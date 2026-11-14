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

use std::rc::Weak;

use crate::{
    error::{NativeExtensionsError, NativeExtensionsResult},
    hot_key_manager::{HotKeyCreateRequest, HotKeyHandle, HotKeyManagerDelegate},
};

pub struct PlatformHotKeyManager {}

impl PlatformHotKeyManager {
    pub fn new(_delegate: Weak<dyn HotKeyManagerDelegate>) -> Self {
        Self {}
    }

    pub fn assign_weak_self(&self, _weak: Weak<PlatformHotKeyManager>) {}

    pub fn create_hot_key(
        &self,
        _handle: HotKeyHandle,
        _request: HotKeyCreateRequest,
    ) -> NativeExtensionsResult<()> {
        Err(NativeExtensionsError::UnsupportedOperation)
    }

    pub fn destroy_hot_key(&self, _handle: HotKeyHandle) -> NativeExtensionsResult<()> {
        Err(NativeExtensionsError::UnsupportedOperation)
    }
}
