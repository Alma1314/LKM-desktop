/*
 * Copyright (C) 2026 Huawei Device Co., Ltd.
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
  AbilityPluginBinding,
  BinaryMessageHandler,
  BinaryMessenger,
  BinaryReply,
  MethodResult,
  NewWantListener,
  OnSaveStateListener,
  TaskQueue,
  TaskQueueOptions,
  WindowFocusChangedListener,
} from '@ohos/flutter_ohos';
// Not exported from the flutter_ohos main entry; the deep import is required.
import SendableBinaryMessageHandler from '@ohos/flutter_ohos/src/main/ets/plugin/common/SendableBinaryMessageHandler';
import UIAbility from '@ohos.app.ability.UIAbility';

/**
 * Test double for the Flutter-side MethodResult: records every callback the
 * plugin makes so tests can assert what was reported back to Flutter.
 */
export class MockMethodResult implements MethodResult {
  isSuccessCalled: boolean = false;
  successValue: ESObject = null;
  isErrorCalled: boolean = false;
  errorCode: string = '';
  errorMessage: string = '';
  isNotImplementedCalled: boolean = false;
  callCount: number = 0;

  success(result: ESObject): void {
    this.callCount++;
    this.isSuccessCalled = true;
    this.successValue = result;
  }

  error(errorCode: string, errorMessage: string, errorDetails: ESObject): void {
    this.callCount++;
    this.isErrorCalled = true;
    this.errorCode = errorCode;
    this.errorMessage = errorMessage;
  }

  notImplemented(): void {
    this.callCount++;
    this.isNotImplementedCalled = true;
  }
}

/**
 * No-op BinaryMessenger that records handler registration so lifecycle tests
 * can assert the plugin registered/cleared its MethodChannel handler.
 */
export class MockBinaryMessenger implements BinaryMessenger {
  handlerChannel: string | null = null;
  handlerRegistered: boolean = false;

  makeBackgroundTaskQueue(options?: TaskQueueOptions): TaskQueue {
    return undefined as ESObject as TaskQueue;
  }

  send(channel: String, message: ArrayBuffer | null, callback?: BinaryReply | null): void {
  }

  setMessageHandler(channel: String, handler: BinaryMessageHandler | SendableBinaryMessageHandler | null,
    taskQueue?: TaskQueue): void {
    this.handlerChannel = channel as ESObject as string;
    this.handlerRegistered = handler != null;
  }
}

/** Structural stand-in for FlutterPluginBinding: only getBinaryMessenger is used by the plugin. */
export class MockFlutterPluginBinding {
  private messenger: BinaryMessenger;

  constructor(messenger: BinaryMessenger) {
    this.messenger = messenger;
  }

  getBinaryMessenger(): BinaryMessenger {
    return this.messenger;
  }
}

/** Minimal stand-in for abilityInfo: only bundleName is read by the plugin. */
export class MockAbilityInfo {
  bundleName: string = 'com.example.demo';
}

/** Structural stand-in for a UIAbilityContext: carries just enough data for the plugin's guards. */
export class MockUIAbilityContext {
  abilityInfo: MockAbilityInfo = new MockAbilityInfo();
}

/** Structural stand-in for a UIAbility: exposes a plain context object. */
export class AbilityStub {
  context: MockUIAbilityContext = new MockUIAbilityContext();
}

/**
 * No-op AbilityPluginBinding. Pass an AbilityStub to simulate an attached
 * ability whose context can be read by the plugin.
 */
export class MockAbilityPluginBinding implements AbilityPluginBinding {
  private ability: UIAbility | null;

  constructor(ability: UIAbility | null) {
    this.ability = ability;
  }

  getAbility(): UIAbility {
    return this.ability as ESObject as UIAbility;
  }

  addOnNewWantListener(listener: NewWantListener): void {
  }

  removeOnNewWantListener(listener: NewWantListener): void {
  }

  addOnWindowFocusChangedListener(listener: WindowFocusChangedListener): void {
  }

  removeOnWindowFocusChangedListener(listener: WindowFocusChangedListener): void {
  }

  addOnSaveStateListener(listener: OnSaveStateListener): void {
  }

  removeOnSaveStateListener(listener: OnSaveStateListener): void {
  }
}
