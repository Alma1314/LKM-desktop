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
    cell::{Cell, RefCell},
    collections::HashMap,
    rc::{Rc, Weak},
    sync::Arc,
    ptr::{self, null, null_mut},
};

use irondash_engine_context::EngineContext;
use irondash_message_channel::Value;

use super::sys::*;

use crate::{
    api_model::{DataProviderId, DragConfiguration, DragRequest, DropOperation, ImageData, Point},
    data_provider_manager::DataProviderHandle,
    drag_manager::{
        DataProviderEntry, DragSessionId, PlatformDragContextDelegate, PlatformDragContextId,
    },
    error::{NativeExtensionsError, NativeExtensionsResult},
};

use super::{
    drag_common::{DragAction},
    PlatformDataProvider,
    NativeDragEvent,
};

pub struct PlatformDragContext {
    id: PlatformDragContextId,
    engine_handle: i64,
    delegate: Weak<dyn PlatformDragContextDelegate>,
    sessions: RefCell<HashMap<DragSessionId, DragSession>>,
    current_session_id: RefCell<Option<Rc<DragSessionId>>>,
}

struct DragSession {
    platform_context_id: PlatformDragContextId,
    configuration: DragConfiguration,
    platform_context_delegate: Weak<dyn PlatformDragContextDelegate>,
    data_providers: Vec<Arc<DataProviderHandle>>,
    last_drop_operation: Cell<Option<DropOperation>>,
}

thread_local! {
    static CONTEXTS: RefCell<HashMap<PlatformDragContextId, Weak<PlatformDragContext>>> = RefCell::new(HashMap::new());
}

#[repr(C)]
#[derive(Debug, Copy, Clone)]
pub struct OH_PixelmapNative {
    _unused: [u8; 0],
}
// #[repr(C)]
// #[derive(Debug, Copy, Clone)]
// pub struct OH_UdmfData {
//     _unused: [u8; 0],
// }

#[link(name = "DragDropHelper", kind = "static")]
extern "C" {
    pub fn getPixelMap(
        data: *mut u8,
        dataSize: usize,
        width: i32,
        height: i32,
        rowStride: i32,
    ) -> *mut OH_PixelmapNative;
    pub fn releasePixelMap(
        pixelmap: *mut OH_PixelmapNative,
    );
    pub fn startDrag(
        data: *mut OH_UdmfData,
        pixelmap: *mut OH_PixelmapNative,
        touchPointX: ::std::os::raw::c_int,
        touchPointY: ::std::os::raw::c_int,
    );
}

impl PlatformDragContext {
    pub fn new(
        id: PlatformDragContextId,
        engine_handle: i64,
        delegate: Weak<dyn PlatformDragContextDelegate>,
    ) -> NativeExtensionsResult<Self> {
        Ok(Self {
            id,
            engine_handle,
            delegate,
            sessions: RefCell::new(HashMap::new()),
            current_session_id: RefCell::new(None),
        })
    }

    pub fn assign_weak_self(&self, weak_self: Weak<Self>) {
        CONTEXTS.with(|c| c.borrow_mut().insert(self.id, weak_self));
    }

    pub fn needs_combined_drag_image() -> bool {
        true
    }

    pub async fn start_drag(
        &self,
        request: DragRequest,
        providers: HashMap<DataProviderId, DataProviderEntry>,
        session_id: DragSessionId,
    ) -> NativeExtensionsResult<()> {
        let provider_handles: Vec<_> = providers.iter().map(|p| p.1.handle.clone()).collect();

        let providers: Vec<_> = request
            .configuration
            .items
            .iter()
            .map(|item| providers[&item.data_provider_id].provider.clone())
            .collect();

        let image = &request.combined_drag_image.ok_or_else(|| {
            NativeExtensionsError::OtherError("Missing combined drag image".into())
        })?;

        let device_pixel_ratio = image.image_data.device_pixel_ratio.unwrap_or(1.0);
        let point_in_rect = Point {
            x: (image.rect.width / 2.0 + 4.0) * device_pixel_ratio,
            y: (image.rect.height / 2.0 + 4.0) * device_pixel_ratio,
        };

        let mut sessions = self.sessions.borrow_mut();
        sessions.insert(
            session_id,
            DragSession {
                configuration: request.configuration,
                platform_context_id: self.id,
                platform_context_delegate: self.delegate.clone(),
                data_providers: provider_handles,
                last_drop_operation: Cell::new(None),
            },
        );

        self.current_session_id
            .borrow_mut()
            .get_or_insert_with(|| {
                Rc::new(session_id)
            });

        unsafe {
            let mut tmp = Vec::<u8>::new();

            tmp.resize(image.image_data.data.len() as usize, 0);
            for i in 0..image.image_data.data.len() as usize {
                tmp[i] = image.image_data.data[i];
            }

            let pixelmap: *mut OH_PixelmapNative = getPixelMap(tmp.as_mut_ptr(), tmp.len().into(), 
                image.image_data.width, image.image_data.height, image.image_data.bytes_per_row);

            let mut udmf_data: *mut OH_UdmfData = ptr::null_mut::<OH_UdmfData>();
            if let Ok(data) = PlatformDataProvider::create_clip_data_for_data_providers(providers).await {
                udmf_data = data;
            }
            startDrag(udmf_data, pixelmap,
                (point_in_rect.x.round() as i32).into(),
                (point_in_rect.y.round() as i32).into());
            releasePixelMap(pixelmap);
        }

        Ok(())
    }

    pub fn on_drop_event<'a>(
        &self,
        event: NativeDragEvent,
        action: String,
    ) -> NativeExtensionsResult<Option<DragSessionId>> {
        let session_id = self.current_session_id.borrow().as_ref().cloned();
        match session_id {
            Some(session_id) => {
                let session_id = *(session_id.clone());
                let mut sessions = self.sessions.borrow_mut();
                if let Some(session) = sessions.get(&session_id) {
                    if session.handle_event(session_id, event, action)? == HandleEventResult::RemoveSession {
                        sessions.remove(&session_id);
                        self.current_session_id.replace(None);
                    }
                }
                Ok(Some(session_id))
            },
            None => Ok(None)
        }
    }

    pub fn drag_session_did_end<'a>(
        &self,
    ) -> NativeExtensionsResult<(Option<DragSessionId>)> {
        let session_id = self.current_session_id.borrow().as_ref().cloned();
        match session_id {
            Some(session_id) => {
                let session_id = *(session_id.clone());
                let mut sessions = self.sessions.borrow_mut();
                if let Some(session) = sessions.get(&session_id) {
                    if let Some(delegate) = session.platform_context_delegate.upgrade() {
                        delegate.drag_session_did_end_with_operation(
                            session.platform_context_id,
                            session_id,
                            DropOperation::None,
                        );
                    }
                    sessions.remove(&session_id);
                    self.current_session_id.replace(None);
                }
                Ok(Some(session_id))
            },
            None => Ok(None)
        }
    }

    pub fn get_allowed_operations(&self, session_id: DragSessionId) -> Option<Vec<DropOperation>> {
        let sessions = self.sessions.borrow();
        let session = sessions.get(&session_id);
        session.map(|s| s.configuration.allowed_operations.clone())
    }

    pub fn replace_last_operation(&self, session_id: DragSessionId, operation: DropOperation) {
        let sessions = self.sessions.borrow();
        let session = sessions.get(&session_id);
        if let Some(session) = session {
            session.last_drop_operation.replace(Some(operation));
        }
    }

    pub fn get_local_data_for_session_id(
        &self,
        session_id: DragSessionId,
    ) -> NativeExtensionsResult<Vec<Value>> {
        let sessions = self.sessions.borrow();
        let session = sessions
            .get(&session_id)
            .ok_or(NativeExtensionsError::DragSessionNotFound)?;
        Ok(session.configuration.get_local_data())
    }

    pub fn get_data_provider_handles(
        &self,
        session_id: DragSessionId,
    ) -> Option<Vec<Arc<DataProviderHandle>>> {
        let sessions = self.sessions.borrow();
        let session = sessions.get(&session_id);
        session.map(|s| s.data_providers.clone())
    }
}

#[derive(PartialEq)]
enum HandleEventResult {
    KeepSession,
    RemoveSession,
}

impl DragSession {
    fn handle_event(
        &self,
        session_id: DragSessionId,
        event: NativeDragEvent,
        action: String,
    ) -> NativeExtensionsResult<HandleEventResult> {
        match action.as_str() {
            "drag_move" => {
                if let Some(delegate) = self.platform_context_delegate.upgrade() {
                    delegate.drag_session_did_move_to_location(
                        self.platform_context_id,
                        session_id,
                        Point {
                            x: event.x as f64,
                            y: event.y as f64,
                        },
                    );
                }
                Ok(HandleEventResult::KeepSession)
            },
            "drag_end" => {
                if let Some(delegate) = self.platform_context_delegate.upgrade() {
                    let result = event.result;
                    let operation = match result {
                        true => self
                            .last_drop_operation
                            .get()
                            .unwrap_or(DropOperation::Copy),
                        false => DropOperation::None,
                    };
                    delegate.drag_session_did_end_with_operation(
                        self.platform_context_id,
                        session_id,
                        operation,
                    );
                }
                Ok(HandleEventResult::RemoveSession)
            },
            _ => Ok(HandleEventResult::KeepSession),
        }
        
    }
}

impl Drop for PlatformDragContext {
    fn drop(&mut self) {
        CONTEXTS.with(|c| c.borrow_mut().remove(&self.id));
    }
}
