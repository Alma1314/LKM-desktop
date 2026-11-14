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

#include "DragDropHelper.h"
#include <bits/alltypes.h>
#include <arkui/native_type.h>
#include <arkui/native_node.h>
#include <arkui/native_interface.h>
#include <arkui/drag_and_drop.h>
#include <multimedia/image_framework/image/pixelmap_native.h>
#include <database/udmf/udmf.h>
#include <cmath>
#include <hilog/log.h>

#define ARKUI_SUCCEED_CODE 0

#define PIXEL_BYTE_NUM 4

void ArkUICallCheck(int32_t ret, char* func)
{
    if (ret != ARKUI_SUCCEED_CODE) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "drag",
            "call arkui func %{public}s failed, ret = %{public}d", func, ret);
    }
}

void trainsformPixelRGBA2BGRA(uint8_t *data, size_t dataSize)
{
    int swapIndex = 2;
    for (int i = 2; i < dataSize; i += PIXEL_BYTE_NUM) {
        uint8_t temp = data[i];
        data[i] = data[i - swapIndex];
        data[i - swapIndex] = temp;
    }
}

OH_PixelmapNative* getPixelMap(uint8_t *data, size_t dataSize, int32_t width, int32_t height, int32_t rowStride)
{
    trainsformPixelRGBA2BGRA(data, dataSize);

    OH_Pixelmap_InitializationOptions *createOpts;
    ArkUICallCheck(OH_PixelmapInitializationOptions_Create(&createOpts),
        "create OH_Pixelmap_InitializationOptions");
    OH_PixelmapInitializationOptions_SetWidth(createOpts, width);
    OH_PixelmapInitializationOptions_SetHeight(createOpts, height);
    OH_PixelmapInitializationOptions_SetRowStride(createOpts, rowStride);
    OH_PixelmapInitializationOptions_SetPixelFormat(createOpts, PIXEL_FORMAT_BGRA_8888);
    OH_PixelmapInitializationOptions_SetAlphaType(createOpts, PIXELMAP_ALPHA_TYPE_UNKNOWN);

    OH_PixelmapNative *pixelmap = nullptr;
    ArkUICallCheck(OH_PixelmapNative_CreatePixelmap(data, dataSize, createOpts, &pixelmap),
        "create OH_PixelmapNative");
    OH_PixelmapInitializationOptions_Release(createOpts);
    OH_PixelmapNative_Scale(pixelmap, 1.0, 1.0);
    return pixelmap;
}

void releasePixelMap(OH_PixelmapNative* pixelmap)
{
    OH_PixelmapNative_Release(pixelmap);
}

void startDrag(OH_UdmfData *data, OH_PixelmapNative *pixelmap, int touchPointX, int touchPointY)
{
    ArkUI_NativeNodeAPI_1 *nodeAPI = nullptr;
    OH_ArkUI_GetModuleInterface(ARKUI_NATIVE_NODE, ArkUI_NativeNodeAPI_1, nodeAPI);
    ArkUI_NodeHandle node = nodeAPI->createNode(ARKUI_NODE_CUSTOM);
    if (node == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "drag", "create node failed");
        return;
    }
    ArkUI_DragAction *action = OH_ArkUI_CreateDragActionWithNode(node);
    if (action == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "drag", "create drag action failed");
        nodeAPI->disposeNode(node);
        return;
    }
    OH_PixelmapNative* pixelmapArray[] = {pixelmap};
    OH_ArkUI_DragAction_SetPixelMaps(action, pixelmapArray, 1);
    OH_ArkUI_DragAction_SetPointerId(action, 0);
    OH_ArkUI_DragAction_SetTouchPointX(action, touchPointX);
    OH_ArkUI_DragAction_SetTouchPointY(action, touchPointY);
    ArkUICallCheck(OH_ArkUI_DragAction_RegisterStatusListener(action, nullptr,
        [](ArkUI_DragAndDropInfo *info, void *data) -> void {
            ArkUI_DragStatus status = OH_ArkUI_DragAndDropInfo_GetDragStatus(info);
            ArkUI_DragEvent *event = OH_ArkUI_DragAndDropInfo_GetDragEvent(info);
            float x = OH_ArkUI_DragEvent_GetTouchPointXToWindow(event);
            float y = OH_ArkUI_DragEvent_GetTouchPointYToWindow(event);
            ArkUI_DragResult result;
            OH_ArkUI_DragEvent_GetDragResult(event, &result);
            FFiDragEvent dragEvent = {static_cast<long>(round(x)), static_cast<long>(round(y)),
                result == ARKUI_DRAG_RESULT_SUCCESSFUL};
            if (status == ARKUI_DRAG_STATUS_ENDED) {
                OnDragEnd(dragEvent);
            }
        }), "register drag status listener");
    OH_ArkUI_DragAction_SetData(action, data);
    ArkUICallCheck(OH_ArkUI_StartDrag(action), "ArkUI start to drag");
    OH_ArkUI_DragAction_Dispose(action);
    nodeAPI->disposeNode(node);
}