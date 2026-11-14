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

#ifndef DRAG_DROP_HELPER_H_
#define DRAG_DROP_HELPER_H_

#include <bits/alltypes.h>
#include <arkui/native_type.h>
#include <arkui/native_node.h>
#include <multimedia/image_framework/image/pixelmap_native.h>
#include <database/udmf/udmf.h>

#include <ffrt/type_def.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    long x;
    long y;
    bool result;
} FFiDragEvent;

extern void OnDragEnd(FFiDragEvent event);

OH_PixelmapNative* getPixelMap(uint8_t *data, size_t dataSize, int32_t width, int32_t height, int32_t rowStride);

void releasePixelMap(OH_PixelmapNative* pixelmap);

void startDrag(OH_UdmfData *data, OH_PixelmapNative *pixelmap, int touchPointX, int touchPointY);

#if defined(__cplusplus)
} // extern "C"
#endif

#endif