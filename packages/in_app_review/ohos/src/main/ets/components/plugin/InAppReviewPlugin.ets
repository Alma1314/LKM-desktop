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
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { commentManager } from '@kit.AppGalleryKit';
import { deviceInfo } from '@kit.BasicServicesKit';

// Local changes: check API availability and preserve SDK errors; encode listing identifiers.
/** InAppReviewPlugin **/
export default class InAppReviewPlugin implements FlutterPlugin, MethodCallHandler,AbilityAware {

  private channel: MethodChannel | null = null;
  private context:  common.UIAbilityContext | null = null;

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.context = binding.getAbility().context;
  }

  onDetachedFromAbility(): void {
    this.context = null;
  }

  getUniqueClassName(): string {
    return 'InAppReviewPlugin'
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'dev.britannio.in_app_review');
    this.channel.setMethodCallHandler(this)
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null)
      // Release the channel reference so it can be garbage collected.
      this.channel = null;
    }
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      if (call.method == 'isAvailable') {
        this.isAvailable(result);
      } else if (call.method == 'requestReview') {
        this.requestReview(result);
      } else if (call.method == 'openStoreListing') {
        let appId: string | null = call.argument('ohos_id');
        this.openStoreListing(result, appId);
      } else {
        result.notImplemented()
      }
    } catch (error) {
      // Ensure an unexpected failure still replies to Flutter instead of leaving it waiting.
      result.error(
        'error',
        'An error occurred while handling the method call',
        null
      );
    }
  }

  public isAvailable(result: MethodResult) {
    const context = this.context;
    if (context == null) {
      // Without a context the review dialog cannot be shown, so report the feature as unavailable.
      result.success(false);
      return;
    }
    result.success(deviceInfo.sdkApiVersion >= 20);
  }

  public requestReview(result: MethodResult) {
    const context = this.context;
    if (deviceInfo.sdkApiVersion < 20) {
      result.error(
        'error',
        'This feature requires API 20, But API is unavailable',
        null
      );
      return;
    }
    if (context == null) {
      result.error(
        'error',
        'ohos context not available',
        null
      );
      return;
    }
    try {
      commentManager.showCommentDialog(context).then(() => {
        // The API does not indicate whether the user reviewed or if the dialog was shown.
        result.success(null);
      }).catch((error: BusinessError<Object>) => {
        result.error(
          'error',
          error.message,
          error.code
        );
      });
    } catch (error) {
      // Catch synchronous failures, e.g. an invalid context rejected by the dialog API.
      result.error(
        'error',
        'An error occurred during the requestReview',
        null
      );
    }
  }

  public openStoreListing(result: MethodResult, appId: string | null) {
    const context = this.context;
    if (context == null) {
      result.error(
        'error',
        'ohos context not available',
        null
      );
      return;
    }
    try {
      // Fall back to the current application bundle name when appId is missing, empty, or not a string.
      let bundleName: string;
      if (typeof appId === 'string' && appId.length > 0) {
        bundleName = appId;
      } else {
        bundleName = context.abilityInfo.bundleName;
      }
      let link: string = 'https://appgallery.huawei.com/app/detail?id=' + encodeURIComponent(bundleName);
      context.openLink(link, { appLinkingOnly: false })
        .then(() => {
          // Match the Android/iOS contract: Dart expects void, so reply with null.
          result.success(null);
        })
        .catch((error: BusinessError) => {
          result.error(
            'error',
            error.message,
            error.code
          );
        });
    } catch (error) {
      // Catch synchronous failures while building or launching the store link.
      result.error(
        'error',
        'An error occurred while opening AppGallery',
        null
      );
    }
  }
}
