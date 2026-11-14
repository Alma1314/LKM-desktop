/*
 * Copyright (C) 2025 Huawei Device Co., Ltd.
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

import {
  AbilityAware,
  AbilityPluginBinding,
  FlutterPlugin,
  FlutterPluginBinding,
} from '@ohos/flutter_ohos';
import { FlutterError, IsEnabledMessage, ToggleMessage, WakelockApi } from './WakelockApi';
import window from '@ohos.window';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

/** WakelockPlugin **/
export default class WakelockPlugin extends WakelockApi implements FlutterPlugin, AbilityAware {
  private context: common.Context | null = null;

  constructor() {
    super();
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.context = binding.getAbility().context;
  }

  onDetachedFromAbility(): void {
    this.context = null;
  }

  async toggle(msg: ToggleMessage): Promise<void> {
    // 通过窗口的 keepScreenOn 能力保持屏幕常亮，不需要额外的 runningLock 资源。
    if (this.context == null) {
      // 对齐 Android：无上下文（detached）时抛错而非静默成功，避免调用方误以为常亮已开启。
      throw new FlutterError(
        'no_ability',
        'Error',
        'wakelock requires a foreground ability (context is null / detached)',
        ''
      );
    }
    try {
      // 懒获取窗口：不在 attach 时缓存，避免 windowStage 未就绪时拿到异常窗口。
      const windowClass = await window.getLastWindow(this.context);
      await windowClass.setWindowKeepScreenOn(msg.getEnable());
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      // 不吞异常：转成 FlutterError 上抛，由通道层 wrapError 转为 PlatformException
      // 回传 Flutter，避免调用方误以为切换成功。
      throw new FlutterError(
        `window_error_${e.code}`,
        'Error',
        `setWindowKeepScreenOn(${msg.getEnable()}) failed: ${e.message}`,
        e.stack ?? ''
      );
    }
  }

  async isEnabled(): Promise<IsEnabledMessage> {
    if (this.context == null) {
      // 对齐 Android：无上下文（detached）时抛错而非返回伪造 false，保证"查询失败"与"未开启"可区分。
      throw new FlutterError(
        'no_ability',
        'Error',
        'wakelock requires a foreground ability (context is null / detached)',
        ''
      );
    }
    try {
      const windowClass = await window.getLastWindow(this.context);
      return new IsEnabledMessage(windowClass.getWindowProperties().isKeepScreenOn);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      // 查询失败与“未开启”需要区分：上抛错误由通道层 wrapError 转成 PlatformException 回传。
      throw new FlutterError(
        `window_error_${e.code}`,
        'Error',
        `query isKeepScreenOn failed: ${e.message}`,
        e.stack ?? ''
      );
    }
  }

  getUniqueClassName(): string {
    return "WakelockPlugin";
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    WakelockApi.setup(binding.getBinaryMessenger(), this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    WakelockApi.setup(binding.getBinaryMessenger(), null);
  }
}