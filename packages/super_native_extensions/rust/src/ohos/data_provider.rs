/*
 * Copyright (C) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

use std::{
    cell::{Cell, RefCell}, collections::HashMap, ffi::{CStr, CString}, os::raw::c_void, ptr::{self, null, null_mut}, rc::{Rc, Weak}, sync::{Arc, Mutex}
};

use irondash_message_channel::{IsolateId, Late, Value};
use irondash_run_loop::{util::Capsule, RunLoop, RunLoopSender};

use once_cell::sync::Lazy;
use url::Url;

use crate::{
    api_model::{DataProvider, DataRepresentation},
    context::Context,
    drag_manager::GetDragManager,
    data_provider_manager::{DataProviderHandle, PlatformDataProviderDelegate},
    error::{NativeExtensionsError, NativeExtensionsResult},
    util::NextId,
    value_coerce::{CoerceToData, StringFormat},
    value_promise::{ValuePromise, ValuePromiseResult}
};
use super::sys::*;
use base64::prelude::*;

struct DataProviderRecord {
    data: DataProvider,
    delegate: Capsule<Weak<dyn PlatformDataProviderDelegate>>,
    isolate_id: IsolateId,
    sender: RunLoopSender,
}

#[derive(Clone)]
struct SingleData {
    format: String,
    data: Vec<u8>,
}

#[derive(Clone)]
struct RawData {
    formats: Vec<String>,
    data: Vec<SingleData>,
}

static DATA_PROVIDERS: Lazy<Mutex<HashMap<i64, DataProviderRecord>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

thread_local! {
    static NEXT_ID: Cell<i64> = Cell::new(1);
}

pub struct PlatformDataProvider {
    weak_self: Late<Weak<Self>>,
    data_provider_id: i64,
}

pub fn platform_stream_write(_handle: i32, _data: &[u8]) -> i32 {
    1
}

pub fn platform_stream_close(_handle: i32, _delete: bool) {}

pub const MIME_TYPE_TEXT_PLAIN: &str = "general.plain-text";
pub const MIME_TYPE_TEXT_HTML: &str = "general.html";
pub const MIME_TYPE_URI_LIST: &str = "general.hyperlink";
pub const MIME_TYPE_FILE_URI: &str = "general.file";

fn contains(l: &[String], s: &str) -> bool {
    l.iter().any(|v| v == s)
}

impl PlatformDataProvider {
    pub fn new(
        delegate: Weak<dyn PlatformDataProviderDelegate>,
        isolate_id: IsolateId,
        data: DataProvider,
    ) -> Self {
        let id = NEXT_ID.with(|f| f.next_id());
        let mut data_providers = DATA_PROVIDERS.lock().unwrap();
        let sender = RunLoop::current().new_sender();
        data_providers.insert(
            id,
            DataProviderRecord {
                data,
                delegate: Capsule::new_with_sender(delegate, sender.clone()),
                isolate_id,
                sender,
            },
        );
        Self {
            data_provider_id: id,
            weak_self: Late::new(),
        }
    }

    pub fn assign_weak_self(&self, weak_self: Weak<Self>) {
        self.weak_self.set(weak_self);
        let drag_contexts = Context::get().drag_manager().get_platform_drag_contexts();
        for drag_context in &drag_contexts {
            drag_context.drag_session_did_end();
        }
    }

    pub async fn create_clip_data_for_data_providers (
        providers: Vec<Rc<PlatformDataProvider>>,
    ) -> NativeExtensionsResult<*mut OH_UdmfData> {
        let data_providers = DATA_PROVIDERS.lock().unwrap();
        let providers: Vec<_> = providers
            .iter()
            .map(|provider| {
                (
                    provider.data_provider_id,
                    &data_providers[&provider.data_provider_id].data,
                    &data_providers[&provider.data_provider_id],
                )
            })
            .collect();
        Self::_create_clip_data_for_data_providers(providers).await
    }

    async fn _create_clip_data_for_data_providers(
        providers: Vec<(i64, &DataProvider, &DataProviderRecord)>,
    ) -> NativeExtensionsResult<*mut OH_UdmfData> {
        let mut udmf_data = unsafe { OH_UdmfData_Create() };
        for (provider_id, provider, data_provider_record) in providers.iter() {
            Self::add_record_item_from_data_provider(
                udmf_data,
                *provider_id,
                provider,
                data_provider_record,
            ).await;
        }
        Ok(udmf_data)
    }

    async fn add_record_item_from_data_provider (
        udmf_data: *mut OH_UdmfData,
        data_provider_id: i64,
        data_provider: &DataProvider,
        data_provider_record: &DataProviderRecord,
    ) {
        let raw_data = Self::get_raw_data_from_provider(
            data_provider_id,
            data_provider,
            data_provider_record,
        ).await;
        for single_data in raw_data.data.clone() {
            let udmf_record = unsafe { OH_UdmfRecord_Create() };
            let data_cstring = unsafe { CString::from_vec_unchecked(single_data.data) };
            let len = data_cstring.as_bytes().len();
            let data_ptr = data_cstring.as_ptr();
            match single_data.format.as_str() {
                MIME_TYPE_TEXT_PLAIN => {
                    let uds_plain_text = unsafe { OH_UdsPlainText_Create() };
                    let ret = unsafe { OH_UdsPlainText_SetContent(uds_plain_text, data_ptr) };
                    let ret = unsafe { OH_UdmfRecord_AddPlainText(udmf_record, uds_plain_text) };
                    let ret = unsafe { OH_UdmfData_AddRecord(udmf_data, udmf_record) };
                    unsafe { OH_UdsPlainText_Destroy(uds_plain_text); };
                },
                MIME_TYPE_TEXT_HTML => {
                    let uds_html_text = unsafe { OH_UdsHtml_Create() };
                    let ret = unsafe { OH_UdsHtml_SetContent(uds_html_text, data_ptr) };
                    let ret = unsafe { OH_UdmfRecord_AddHtml(udmf_record, uds_html_text) };
                    let ret = unsafe { OH_UdmfData_AddRecord(udmf_data, udmf_record) };
                    unsafe { OH_UdsHtml_Destroy(uds_html_text); };
                },
                MIME_TYPE_URI_LIST => {
                    let uds_hyperlink = unsafe { OH_UdsHyperlink_Create() };
                    let ret = unsafe { OH_UdsHyperlink_SetUrl(uds_hyperlink, data_ptr) };
                    let ret = unsafe { OH_UdmfRecord_AddHyperlink(udmf_record, uds_hyperlink) };
                    let ret = unsafe { OH_UdmfData_AddRecord(udmf_data, udmf_record) };
                    unsafe { OH_UdsHyperlink_Destroy(uds_hyperlink) };
                },
                other_type => {
                    let file_type = MIME_TYPE_FILE_URI;
                    let file_type = file_type.as_bytes().to_vec();
                    let file_type = unsafe { CString::from_vec_unchecked(file_type) };
                    let file_type = file_type.as_ptr();
                    let uds_uri_list = unsafe { OH_UdsFileUri_Create() };
                    let ret = unsafe { OH_UdsFileUri_SetFileUri(uds_uri_list, data_ptr) };
                    let ret = unsafe { OH_UdsFileUri_SetFileType(uds_uri_list, file_type) };
                    let ret = unsafe { OH_UdmfRecord_AddFileUri(udmf_record, uds_uri_list) };
                    let ret = unsafe { OH_UdmfData_AddRecord(udmf_data, udmf_record) };
                    unsafe { OH_UdsFileUri_Destroy(uds_uri_list) };
                }
            }
            unsafe { OH_UdmfRecord_Destroy(udmf_record) };
        }
        ()
    }

    async fn get_raw_data_from_provider(
        data_provider_id: i64,
        data_provider: &DataProvider,
        data_provider_record: &DataProviderRecord,
    ) -> Arc<RawData> {
        let mut formats: Vec<String> = Vec::new();
        let mut data_array: Vec<SingleData> = Vec::new();
        for repr in &data_provider.representations {
            match repr {
                DataRepresentation::Simple { format, data } => {
                    if let Some(data) = data.coerce_to_data(StringFormat::Utf8) {
                        let single_data = SingleData {
                            format: format.to_string(),
                            data,
                        };
                        data_array.push(single_data.clone());
                        if !formats.contains(format) {
                            formats.push(format.clone());
                        }
                    } else {

                    }
                }
                DataRepresentation::Lazy { format, id } => {
                    let delegate = data_provider_record.delegate.clone();
                    let isolate_id = data_provider_record.isolate_id;
                    let id = *id;
                    if let Some(delegate) = delegate.get_ref().unwrap().upgrade() {
                        let res = delegate.get_lazy_data_async(isolate_id, id).await;
                        match res {
                            ValuePromiseResult::Ok { value } => {
                                if let Some(data) = value.coerce_to_data(StringFormat::Utf8) {
                                    let single_data = SingleData {
                                        format: format.to_string(),
                                        data,
                                    };
                                    data_array.push(single_data.clone());
                                    if !formats.contains(format) {
                                        formats.push(format.clone());
                                    }
                                }
                            }
                            ValuePromiseResult::Cancelled => {},
                        }
                    }
                },
                _ => {},
            }
        }
        let raw_data = RawData {
            formats,
            data: data_array,
        };
        let data_ref = Arc::new(raw_data);
        data_ref
    }

    pub async fn write_to_clipboard(
        providers: Vec<(Rc<PlatformDataProvider>, Arc<DataProviderHandle>)>,
    ) -> NativeExtensionsResult<()> {
        let handles: Vec<_> = providers.iter().map(|p| p.1.clone()).collect();
        let providers: Vec<_> = providers.into_iter().map(|p| p.0).collect();

        thread_local! {
            static CURRENT_CLIP: RefCell<Vec<Arc<DataProviderHandle>>> = RefCell::new(Vec::new());
        }
        // ClipManager doesn't provide any lifetime management for clip so just
        // keep the data awake until the clip is replaced.
        CURRENT_CLIP.with(|r| r.replace(handles));

        Ok(())
    }
}

impl Drop for PlatformDataProvider {
    fn drop(&mut self) {
        let mut data_providers = DATA_PROVIDERS.lock().unwrap();
        data_providers.remove(&self.data_provider_id);
    }
}

#[derive(Debug)]
struct UriInfo {
    data_provider_id: i64,
}
