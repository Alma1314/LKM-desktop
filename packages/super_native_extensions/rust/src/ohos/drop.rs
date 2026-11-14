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

use core::time;
use std::{
    cell::{Cell, RefCell}, collections::HashMap, ffi::{CStr, CString}, ops::Deref, rc::{Rc, Weak}, sync::Arc, time::Duration
};

use irondash_engine_context::EngineContext;
use irondash_message_channel::{IsolateId, Value};
use irondash_run_loop::RunLoop;

use napi_derive::napi;

pub use super::sys::*;
use base64::prelude::*;

use crate::{
    api_model::{DropOperation, Point}, data_provider_manager::DataProviderHandle, drag_manager::DragSessionId, drop_manager::{
        BaseDropEvent, DropEvent, DropItem, DropSessionId, PlatformDropContextDelegate,
        PlatformDropContextId,
    }, error::{NativeExtensionsError, NativeExtensionsResult}, log::OkLog, platform::{PlatformDragContext}, reader_manager::RegisteredDataReader, util::{DropNotifier, NextId}
};

use super::{
    drag_common::{DragAction},
    ContentItem,
    PlatformDataReader,
    data_provider::{MIME_TYPE_TEXT_PLAIN, MIME_TYPE_TEXT_HTML, MIME_TYPE_URI_LIST, MIME_TYPE_FILE_URI}
};

pub struct PlatformDropContext {
    id: PlatformDropContextId,
    engine_handle: i64,
    delegate: Weak<dyn PlatformDropContextDelegate>,
    next_session_id: Cell<i64>,
    current_session: RefCell<Option<Rc<Session>>>,
}

struct Session {
    id: DropSessionId,
    last_operation: Cell<DropOperation>,
}

thread_local! {
    static CONTEXT: RefCell<Option<Weak<PlatformDropContext>>> = RefCell::new(None);
    static CURRENT_POINT: RefCell<Option<Point>> = RefCell::new(None);
}

impl PlatformDropContext {
    pub fn new(
        id: PlatformDropContextId,
        engine_handle: i64,
        delegate: Weak<dyn PlatformDropContextDelegate>,
    ) -> NativeExtensionsResult<Self> {
        Ok(Self {
            id,
            engine_handle,
            delegate,
            next_session_id: Cell::new(0),
            current_session: RefCell::new(None),
        })
    }

    fn _assign_weak_self(&self, weak_self: Weak<Self>) -> NativeExtensionsResult<()> {
        CONTEXT.with(|c| c.replace(Some(weak_self)));
        Ok(())
    }

    pub fn assign_weak_self(&self, weak_self: Weak<Self>) {
        self._assign_weak_self(weak_self).ok_log();
    }

    pub fn register_drop_formats(&self, _formats: &[String]) -> NativeExtensionsResult<()> {
        Ok(())
    }

    pub fn on_drag_enter(&self, event: NativeDragEvent) -> NativeExtensionsResult<()> {
        self.current_session.borrow_mut()
            .get_or_insert_with(|| {
                let id = self.next_session_id.next_id();
                Rc::new(Session {
                    id: id.into(),
                    last_operation: Cell::new(DropOperation::None),
                })
            });
        Ok(())
    }

    pub fn on_drag_move(&self, event: NativeDragEvent) -> NativeExtensionsResult<()> {
        if let Some(delegate) = self.delegate.upgrade() {
            let drag_contexts = delegate.get_platform_drag_contexts();
            let mut session_id = None;
            
            for drag_context in &drag_contexts {
                let drag_session_id = drag_context.on_drop_event(event.clone(), "drag_move".to_string())?;
                if drag_session_id.is_some() {
                    session_id = drag_session_id;
                }
            }

            let current_session = self.current_session.borrow_mut().as_ref().cloned().unwrap();

            let event = Self::translate_drop_event(
                event,
                current_session.id,
                Self::get_local_data(session_id, drag_contexts.clone()),
                Self::get_allowed_operations(session_id, drag_contexts.clone()),
                None, // accepted operation
                None, // reader
            )?;
            let weak_delegate = self.delegate.clone();
            delegate.send_drop_update(
                self.id,
                event,
                Box::new(move |res| {
                    let operation = res.ok_log().unwrap_or(DropOperation::None);
                    if let (Some(session_id), Some(delegate)) = (session_id, weak_delegate.upgrade()) {
                        delegate
                            .get_platform_drag_contexts()
                            .iter()
                            .for_each(|d| d.replace_last_operation(session_id, operation));
                    }
                    current_session.last_operation.replace(operation);
                }),
            );
        }
        Ok(())
    }

    pub fn on_drag_leave(&self, event: NativeDragEvent) -> NativeExtensionsResult<()> {
        if let Some(delegate) = self.delegate.upgrade() {
            let current_session = self.current_session.borrow_mut().as_ref().cloned().unwrap();
            delegate.send_drop_leave(
                self.id,
                BaseDropEvent {
                    session_id: current_session.id,
                },
            );
        }
        Ok(())
    }

    pub fn on_drop(&self, event: NativeDragEvent) -> NativeExtensionsResult<()> {
        if let Some(delegate) = self.delegate.upgrade() {
            let drag_contexts = delegate.get_platform_drag_contexts();
            let mut session_id = None;
            for drag_context in &drag_contexts {
                let drag_session_id = drag_context.on_drop_event(event.clone(), "drop".to_string())?;
                if drag_session_id.is_some() {
                    session_id = drag_session_id;
                }
            }
            let current_session = self.current_session.borrow_mut().as_ref().cloned().unwrap();
            let accepted_operation = current_session.last_operation.get();
            if accepted_operation != DropOperation::None
                && accepted_operation != DropOperation::UserCancelled
                && accepted_operation != DropOperation::Forbidden {
                let local_data = Self::get_local_data(session_id, drag_contexts.clone());
                let reader = {
                    let data_provider_handles = Self::get_data_provider_handles(session_id, drag_contexts.clone());
                    let local_event = event.clone();
                    let mut content_items: Vec<Rc<ContentItem>> = Vec::new();
                    let num = local_event.formats.len();
                    for i in 0..num {
                        let format = local_event.formats[i].clone();
                        let content_format = String::new();
                        let mut decoded_content = Value::from("");
                        let format_temp = format.clone();
                        if format_temp.eq(MIME_TYPE_TEXT_PLAIN) || format_temp.eq(MIME_TYPE_TEXT_HTML) || format_temp.eq(MIME_TYPE_URI_LIST) || format_temp.eq(MIME_TYPE_FILE_URI) {
                            let content = local_event.contents[i].clone();
                            decoded_content = Value::from(content);
                        } else {
                            let content = BASE64_STANDARD.decode(local_event.contents[i].clone()).unwrap();
                            decoded_content = Value::from(content);     
                        }
                        let item = ContentItem::from_event(
                            format,
                            content_format,
                            decoded_content,
                        )?;
                        content_items.push(item);
                    }
                    let reader = PlatformDataReader::from_clip_data(
                        Some(Arc::new(content_items)),
                        num as i64,
                        Some(Arc::new(DropNotifier::new(move || {
                            let _data_provider_handles = data_provider_handles; }))),
                    )?;
                    let registered_reader =
                        delegate.register_platform_reader(self.id, reader.clone());
                    Some((reader, registered_reader))
                };

                let event = Self::translate_drop_event(
                    event,
                    current_session.id,
                    local_data,
                    Self::get_allowed_operations(session_id, drag_contexts.clone()),
                    Some(accepted_operation),
                    reader,
                )?;
                let done = Rc::new(Cell::new(false));
                let done_clone = done.clone();
                delegate.send_perform_drop(
                    self.id,
                    event,
                    Box::new(move |r| {
                        r.ok_log();
                        done_clone.set(true);
                    }),
                );
                delegate.send_drop_ended(
                    self.id,
                    BaseDropEvent {
                        session_id: current_session.id,
                    },
                );
                self.current_session.replace(None);
            } else {
                
            }
        }
        Ok(())
    }

    pub fn on_drag_end(&self, event: NativeDragEvent) -> NativeExtensionsResult<()> {
        if let Some(delegate) = self.delegate.upgrade() {
            let drag_contexts = delegate.get_platform_drag_contexts();
            let mut session_id = None;
            
            for drag_context in &drag_contexts {
                let drag_session_id = drag_context.on_drop_event(event.clone(), "drag_end".to_string())?;
                if drag_session_id.is_some() {
                    session_id = drag_session_id;
                }
            }
        }
        Ok(())
    }

    fn get_local_data(
        session_id: Option<DragSessionId>,
        drag_contexts: Vec<Rc<PlatformDragContext>>,
    ) -> Vec<Value> {
        session_id
            .and_then(|session_id| {
                drag_contexts
                    .iter()
                    .filter_map(|c| c.get_local_data_for_session_id(session_id).ok())
                    .next()
            })
            .unwrap_or_default()
    }

    fn get_allowed_operations(
        session_id: Option<DragSessionId>,
        drag_contexts: Vec<Rc<PlatformDragContext>>,
    ) -> Vec<DropOperation> {
        session_id
            .and_then(|session_id| {
                drag_contexts
                    .iter()
                    .filter_map(|c| c.get_allowed_operations(session_id))
                    .next()
            })
            .unwrap_or_else(|| vec![DropOperation::Copy])
    }

    fn get_data_provider_handles(
        session_id: Option<DragSessionId>,
        drag_contexts: Vec<Rc<PlatformDragContext>>,
    ) -> Vec<Arc<DataProviderHandle>> {
        session_id
        .and_then(|session_id| {
            drag_contexts
                .iter()
                .filter_map(|c| c.get_data_provider_handles(session_id))
                .next()
        })
        .unwrap_or_default()
    }

    fn translate_drop_event(
        event: NativeDragEvent,
        session_id: DropSessionId,
        mut local_data: Vec<Value>,
        allowed_operations: Vec<DropOperation>,
        accepted_operation: Option<DropOperation>,
        reader: Option<(Rc<PlatformDataReader>, RegisteredDataReader)>,
    ) -> NativeExtensionsResult<DropEvent> {
        let items = match reader.as_ref() {
            Some((reader, _)) => {
                let mut items = Vec::new();
                for (index, item) in reader.get_items_sync()?.iter().enumerate() {
                    items.push(DropItem {
                        item_id: (index as i64).into(),
                        formats: reader.get_formats_for_item_sync(*item)?,
                        local_data: local_data.get(index).cloned().unwrap_or(Value::Null),
                    });
                }
                items
            }
            None => {
                let mime_types = event.formats; // TODO：getMimeType

                if local_data.is_empty() {
                    local_data.push(Value::Null);
                }
                local_data
                    .into_iter()
                    .enumerate()
                    .map(|(index, local_data)| DropItem {
                        item_id: (index as i64).into(),
                        formats: mime_types.clone(),
                        local_data,
                    })
                    .collect()
            }
        };

        Ok(DropEvent {
            session_id,
            location_in_view: Point {
                x: event.x as f64,
                y: event.y as f64,
            },
            allowed_operations,
            items,
            accepted_operation,
            reader: reader.map(|r| r.1),
        })
    }

}

impl Drop for PlatformDropContext {
    fn drop(&mut self) {
        
    }
}

#[napi(constructor)]
#[derive(Clone)]
pub struct NativeDragEvent {
    pub x: i32,
    pub y: i32,
    pub result: bool,
    pub formats: Vec<String>,
    pub contents: Vec<String>,
}

#[repr(C)]
#[derive(Clone)]
pub struct FFiDragEvent {
    pub x: i32,
    pub y: i32,
    pub result: bool,
}

#[no_mangle]
pub extern "C" fn OnDragEnd(event: FFiDragEvent) {
    let sender = RunLoop::current().new_sender();
    sender.send(move || {
        let context = CONTEXT
            .with(|c| c.borrow_mut().as_ref().cloned().unwrap()).upgrade();
        match context {
            Some(context) => {
                context.on_drag_end(NativeDragEvent {
                    x: event.x,
                    y: event.y,
                    result: event.result,
                    formats: Vec::new(),
                    contents: Vec::new(),
                });
            }
            None => {
                
            }
        }
    });
    CURRENT_POINT.with(|p| p.replace(None));
}

#[napi]
impl NativeDragEvent {
    #[napi]
    pub fn on_drag_enter(&self) {
        let sender = RunLoop::current().new_sender();
        let mut event_clone = self.clone();
        sender.send(move || {
            let context = CONTEXT
                .with(|c| c.borrow_mut().as_ref().cloned().unwrap()).upgrade();
            match context {
                Some(context) => {
                    context.on_drag_enter(event_clone);
                }
                None => {
                    
                }
            }
        });
    }

    #[napi]
    pub fn on_drag_move(&self) {
        let point = Point {
            x: self.x as f64,
            y: self.y as f64,
        };

        let current_point = CURRENT_POINT.with(|p| p.borrow_mut().as_ref().cloned());
        if current_point.is_some() && current_point.unwrap() == point {
            // Point does not move.
            return ();
        }

        let sender = RunLoop::current().new_sender();
        let mut event_clone = self.clone();
        sender.send(move || {
            let context = CONTEXT
                .with(|c| c.borrow_mut().as_ref().cloned().unwrap()).upgrade();
            match context {
                Some(context) => {
                    context.on_drag_move(event_clone);
                }
                None => {

                }
            }
        });
        CURRENT_POINT.with(|p| p.replace(Some(point)));
    }

    #[napi]
    pub fn on_drag_leave(&self) {
        let sender = RunLoop::current().new_sender();
        let mut event_clone = self.clone();
        sender.send(move || {
            let context = CONTEXT
                .with(|c| c.borrow_mut().as_ref().cloned().unwrap()).upgrade();
            match context {
                Some(context) => {
                    context.on_drag_leave(event_clone);
                }
                None => {
                    
                }
            }
        });
    }

    #[napi]
    pub fn on_drop(&self) {
        let sender = RunLoop::current().new_sender();
        let mut event_clone = self.clone();
        sender.send(move || {
            let context = CONTEXT
                .with(|c| c.borrow_mut().as_ref().cloned().unwrap()).upgrade();
            match context {
                Some(context) => {
                    context.on_drop(event_clone);
                }
                None => {
                    
                }
            }
        });
    }
}