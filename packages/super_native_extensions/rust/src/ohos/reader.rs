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
    collections::HashMap,ops::Deref, path::PathBuf,
    ptr,
    rc::Rc,
    sync::Arc,
};

use irondash_message_channel::{Value};
use irondash_run_loop::{util::FutureCompleter, RunLoop};

use url::Url;

use crate::{
    error::{NativeExtensionsError, NativeExtensionsResult},
    reader_manager::{ReadProgress, VirtualFileReader},
    util::DropNotifier,
};

use super::MIME_TYPE_URI_LIST;

#[derive(Clone)]
pub struct ContentItem {
    format: String,
    content_format: String,
    content: Value,
}

impl ContentItem {
    pub fn from_event(
        format2: String,
        content_format2: String,
        content2: Value,
    ) -> NativeExtensionsResult<Rc<Self>> {
        Ok(Rc::new(Self {
            format: format2,
            content_format: content_format2,
            content: content2,
        }))
    }
}

pub struct PlatformDataReader {
    items: Option<Arc<Vec<Rc<ContentItem>>>>,
    size: i64,
    // If needed enhance life of local data source
    _source_drop_notifier: Option<Arc<DropNotifier>>,
}

impl PlatformDataReader {
    pub async fn get_item_format_for_uri(
       &self,
        _item: i64,
    ) -> NativeExtensionsResult<Option<String>> {
        Ok(None)
    }

    pub fn get_items_sync(&self) -> NativeExtensionsResult<Vec<i64>> {
        Ok((0..self.size).collect())
    }

    pub async fn get_items(&self) -> NativeExtensionsResult<Vec<i64>> {
        self.get_items_sync()
    }

    pub fn get_formats_for_item_sync(&self, item: i64) -> NativeExtensionsResult<Vec<String>> {
        let mut formats = Vec::new();
        if let Some(items) = self.items.clone() {
            formats.push(items[item as usize].format.clone());
        }
        Ok(formats)
    }

    pub async fn get_suggested_name_for_item(
        &self,
        item: i64,
    ) -> NativeExtensionsResult<Option<String>> {
        let formats = self.get_formats_for_item_sync(item)?;
        if formats.iter().any(|s| s == MIME_TYPE_URI_LIST) {
            let uri = self
                .get_data_for_item(item, MIME_TYPE_URI_LIST.to_owned(), None)
                .await?;
            if let Value::String(url) = uri {
                if let Ok(url) = Url::parse(&url) {
                    if let Some(segments) = url.path_segments() {
                        let last: Option<&str> = segments.last().filter(|s| !s.is_empty());
                        return Ok(last.map(|f| f.to_owned()));
                    }
                }
            }
        }
        Ok(None)
    }

    pub async fn get_formats_for_item(&self, item: i64) -> NativeExtensionsResult<Vec<String>> {
        self.get_formats_for_item_sync(item)
    }

    thread_local! {
        static NEXT_HANDLE: Cell<i64> = Cell::new(1);
        static PENDING:
            RefCell<HashMap<i64,irondash_run_loop::util::FutureCompleter<NativeExtensionsResult<Value>>>> = RefCell::new(HashMap::new());
    }

    pub async fn get_data_for_item(
        &self,
        item: i64,
        format: String,
        _progress: Option<Arc<ReadProgress>>,
    ) -> NativeExtensionsResult<Value> {
        if let Some(items) = self.items.clone() {
            let content = items[item as usize].content.clone();
            Ok(Value::from(content))
        } else {
            Ok(Value::Null)
        }
    }

    pub fn from_clip_data (
        content_items: Option<Arc<Vec<Rc<ContentItem>>>>,
        size: i64,
        source_drop_notifier: Option<Arc<DropNotifier>>
    ) -> NativeExtensionsResult<Rc<Self>> {

        Ok(Rc::new(Self {
            items: content_items,
            size: size,
            _source_drop_notifier: source_drop_notifier,
        }))
    }

    pub fn new_clipboard_reader() -> NativeExtensionsResult<Rc<Self>> {
        Ok(Rc::new(Self {
            items: None,
            size: 0,
            _source_drop_notifier: None,
        }))
    }

    pub fn item_format_is_synthesized(
        &self,
        _item: i64,
        _format: &str,
    ) -> NativeExtensionsResult<bool> {
        Ok(false)
    }

    pub async fn can_read_virtual_file_for_item(
        &self,
        _item: i64,
        _format: &str,
    ) -> NativeExtensionsResult<bool> {
        Ok(false)
    }

    pub async fn can_copy_virtual_file_for_item(
        &self,
        _item: i64,
        _format: &str,
    ) -> NativeExtensionsResult<bool> {
        Ok(false)
    }

    pub async fn create_virtual_file_reader_for_item(
        &self,
        _item: i64,
        _format: &str,
        _progress: Arc<ReadProgress>,
    ) -> NativeExtensionsResult<Option<Rc<dyn VirtualFileReader>>> {
        Ok(None)
    }

    pub async fn copy_virtual_file_for_item(
        &self,
        _item: i64,
        _format: &str,
        _target_folder: PathBuf,
        _progress: Arc<ReadProgress>,
    ) -> NativeExtensionsResult<PathBuf> {
        Err(NativeExtensionsError::UnsupportedOperation)
    }
}
