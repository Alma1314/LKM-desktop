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

use std::rc::{Rc, Weak};

use irondash_message_channel::IsolateId;

use crate::{
    api_model::{ImageData, Menu, ShowContextMenuRequest, ShowContextMenuResponse},
    error::{NativeExtensionsError, NativeExtensionsResult},
    menu_manager::{PlatformMenuContextDelegate, PlatformMenuContextId, PlatformMenuDelegate},
};

pub struct PlatformMenuContext {}

#[derive(Debug)]
pub struct PlatformMenu {}

impl PlatformMenu {
    pub fn new(
        _isolate: IsolateId,
        _delegate: Weak<dyn PlatformMenuDelegate>,
        _menu: Menu,
    ) -> NativeExtensionsResult<Rc<Self>> {
        Ok(Rc::new(Self {}))
    }
}

impl PlatformMenuContext {
    pub fn new(
        _id: PlatformMenuContextId,
        _engine_handle: i64,
        _delegate: Weak<dyn PlatformMenuContextDelegate>,
    ) -> NativeExtensionsResult<Self> {
        Ok(Self {})
    }

    pub fn update_preview_image(
        &self,
        _configuration_id: i64,
        _image_data: ImageData,
    ) -> NativeExtensionsResult<()> {
        Err(NativeExtensionsError::UnsupportedOperation)
    }

    pub async fn show_context_menu(
        &self,
        _request: ShowContextMenuRequest,
    ) -> NativeExtensionsResult<ShowContextMenuResponse> {
        Err(NativeExtensionsError::UnsupportedOperation)
    }

    pub fn assign_weak_self(&self, _weak_self: Weak<Self>) {}
}
