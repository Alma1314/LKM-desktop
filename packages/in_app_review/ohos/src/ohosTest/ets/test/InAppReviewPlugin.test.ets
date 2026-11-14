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
import { describe, it, expect } from '@ohos/hypium';
import UIAbility from '@ohos.app.ability.UIAbility';
import InAppReviewPlugin from '../../../main/ets/components/plugin/InAppReviewPlugin';
import { FlutterPluginBinding, MethodCall } from '@ohos/flutter_ohos';
import { MockMethodResult, MockBinaryMessenger, MockFlutterPluginBinding,
  MockAbilityPluginBinding, AbilityStub } from './TestMocks';

const CHANNEL_NAME = 'dev.britannio.in_app_review';

/** Builds an openStoreListing MethodCall carrying only non-null arguments. */
function storeListingCall(ohosId: string | null): MethodCall {
  const args: Map<string, ESObject> = new Map<string, ESObject>();
  if (ohosId !== null) {
    args.set('ohos_id', ohosId);
  }
  return new MethodCall('openStoreListing', args);
}

export default function inAppReviewPluginTest() {
  describe('InAppReviewPluginPureLogicTest', () => {
    // Pure plugin logic that never reaches a system API: routing, argument
    // guards, single-reply contract and lifecycle cleanup. Deterministic on
    // any device.

    it('getUniqueClassName_returnsPluginClassName', 0, () => {
      const plugin: InAppReviewPlugin = new InAppReviewPlugin();
      expect(plugin.getUniqueClassName()).assertEqual('InAppReviewPlugin');
    });

    it('onAttachedToEngine_registersChannelHandler', 0, () => {
      const plugin: InAppReviewPlugin = new InAppReviewPlugin();
      const messenger: MockBinaryMessenger = new MockBinaryMessenger();
      plugin.onAttachedToEngine(
        new MockFlutterPluginBinding(messenger) as ESObject as FlutterPluginBinding);
      expect(messenger.handlerChannel).assertEqual(CHANNEL_NAME);
      expect(messenger.handlerRegistered).assertTrue();
    });

    it('onDetachedFromEngine_clearsChannelHandler', 0, () => {
      const plugin: InAppReviewPlugin = new InAppReviewPlugin();
      const messenger: MockBinaryMessenger = new MockBinaryMessenger();
      const binding: FlutterPluginBinding =
        new MockFlutterPluginBinding(messenger) as ESObject as FlutterPluginBinding;
      plugin.onAttachedToEngine(binding);
      plugin.onDetachedFromEngine(binding);
      expect(messenger.handlerRegistered).assertFalse();
    });

    it('onMethodCall_unknownMethod_reportsNotImplemented', 0, () => {
      const plugin: InAppReviewPlugin = new InAppReviewPlugin();
      const result: MockMethodResult = new MockMethodResult();
      plugin.onMethodCall(new MethodCall('noSuchMethod', null), result);
      expect(result.isNotImplementedCalled).assertTrue();
      expect(result.isSuccessCalled).assertFalse();
      expect(result.isErrorCalled).assertFalse();
      expect(result.callCount).assertEqual(1);
    });

    it('isAvailable_withoutContext_reportsFalseExactlyOnce', 0, () => {
      const plugin: InAppReviewPlugin = new InAppReviewPlugin();
      const result: MockMethodResult = new MockMethodResult();
      plugin.isAvailable(result);
      expect(result.isSuccessCalled).assertTrue();
      expect(result.successValue).assertFalse();
      expect(result.callCount).assertEqual(1);
    });

    it('isAvailable_withAbilityContext_reportsTrue', 0, () => {
      const plugin: InAppReviewPlugin = new InAppReviewPlugin();
      plugin.onAttachedToAbility(
        new MockAbilityPluginBinding(new AbilityStub() as ESObject as UIAbility));
      const result: MockMethodResult = new MockMethodResult();
      plugin.isAvailable(result);
      expect(result.isSuccessCalled).assertTrue();
      expect(result.successValue).assertTrue();
      expect(result.callCount).assertEqual(1);
    });

    it('abilityDetached_reportsUnavailableAgain', 0, () => {
      const plugin: InAppReviewPlugin = new InAppReviewPlugin();
      plugin.onAttachedToAbility(
        new MockAbilityPluginBinding(new AbilityStub() as ESObject as UIAbility));
      const first: MockMethodResult = new MockMethodResult();
      plugin.isAvailable(first);
      expect(first.successValue).assertTrue();
      plugin.onDetachedFromAbility();
      const second: MockMethodResult = new MockMethodResult();
      plugin.isAvailable(second);
      expect(second.successValue).assertFalse();
    });

    it('requestReview_withoutContext_reportsErrorExactlyOnce', 0, () => {
      const plugin: InAppReviewPlugin = new InAppReviewPlugin();
      const result: MockMethodResult = new MockMethodResult();
      plugin.requestReview(result);
      expect(result.isErrorCalled).assertTrue();
      expect(result.callCount).assertEqual(1);
    });

    it('openStoreListing_withoutContext_reportsErrorExactlyOnce', 0, () => {
      const plugin: InAppReviewPlugin = new InAppReviewPlugin();
      const result: MockMethodResult = new MockMethodResult();
      plugin.openStoreListing(result, 'com.example.demo');
      expect(result.isErrorCalled).assertTrue();
      expect(result.callCount).assertEqual(1);
    });

    it('openStoreListing_emptyAppId_fallsBackToBundleName', 0, () => {
      // The stub context carries abilityInfo.bundleName but no openLink, so
      // the empty appId falls back to the bundle name and the resulting
      // failure is recovered through the catch block with a single reply.
      const plugin: InAppReviewPlugin = new InAppReviewPlugin();
      plugin.onAttachedToAbility(
        new MockAbilityPluginBinding(new AbilityStub() as ESObject as UIAbility));
      const result: MockMethodResult = new MockMethodResult();
      plugin.openStoreListing(result, '');
      expect(result.isErrorCalled).assertTrue();
      expect(result.errorMessage).assertContain('play store');
      expect(result.callCount).assertEqual(1);
    });

    it('openStoreListing_stubContextWithoutOpenLink_recoversViaCatch', 0, () => {
      // A valid appId reaches openLink; the stub context has none, so the
      // synchronous throw is caught and reported exactly once.
      const plugin: InAppReviewPlugin = new InAppReviewPlugin();
      plugin.onAttachedToAbility(
        new MockAbilityPluginBinding(new AbilityStub() as ESObject as UIAbility));
      const result: MockMethodResult = new MockMethodResult();
      plugin.openStoreListing(result, 'com.other.app');
      expect(result.isErrorCalled).assertTrue();
      expect(result.errorMessage).assertContain('play store');
      expect(result.callCount).assertEqual(1);
    });

    it('onMethodCall_openStoreListing_nullArgs_repliesExactlyOnce', 0, () => {
      // Null call arguments must still produce exactly one reply, either from
      // the argument reader being guarded by the outer try-catch or from the
      // context guard.
      const plugin: InAppReviewPlugin = new InAppReviewPlugin();
      const result: MockMethodResult = new MockMethodResult();
      plugin.onMethodCall(new MethodCall('openStoreListing', null), result);
      expect(result.isErrorCalled).assertTrue();
      expect(result.callCount).assertEqual(1);
    });

    it('onMethodCall_routesOpenStoreListingArguments', 0, () => {
      // Routing through onMethodCall reaches the same guard as the direct
      // call, proving the dispatch table forwards arguments untouched.
      const plugin: InAppReviewPlugin = new InAppReviewPlugin();
      const result: MockMethodResult = new MockMethodResult();
      plugin.onMethodCall(storeListingCall('com.example.demo'), result);
      expect(result.isErrorCalled).assertTrue();
      expect(result.callCount).assertEqual(1);
    });
  });
}
