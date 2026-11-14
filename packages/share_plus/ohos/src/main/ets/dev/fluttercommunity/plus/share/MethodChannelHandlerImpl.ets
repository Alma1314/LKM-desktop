/* Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
 * Licensed under the Apache License, Version 2.0; see LICENSE-OHOS.
 * Local change: dispatch the current unified share protocol and propagate failures.
 */
import { MethodCall, MethodCallHandler, MethodResult } from '@ohos/flutter_ohos';
import Share from './Share';

export default class MethodChannelHandlerImpl implements MethodCallHandler {
  private share: Share;
  constructor(share: Share) { this.share = share; }
  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method !== 'share') { result.notImplemented(); return; }
    this.share.share(call, result);
  }
}
