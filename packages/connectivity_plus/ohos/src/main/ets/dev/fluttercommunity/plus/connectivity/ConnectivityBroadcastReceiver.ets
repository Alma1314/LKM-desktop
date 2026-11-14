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

import connection from '@ohos.net.connection';
import { StreamHandler, EventSink } from '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';
import { Connectivity } from './Connectivity';

export class ConnectivityBroadcastReceiver implements StreamHandler {
  private connectivity: Connectivity;
  private subscription: connection.NetConnection | null = null;
  private events: EventSink | null = null;

  constructor(connectivity: Connectivity) {
    this.connectivity = connectivity;
  }

  onListen(args: Object, events: EventSink): void {
    this.onCancel();
    const subscription = connection.createNetConnection();
    this.subscription = subscription;
    this.events = events;
    subscription.on('netAvailable', () => this.refresh(subscription));
    subscription.on('netCapabilitiesChange', () => this.refresh(subscription));
    subscription.on('netLost', () => this.refresh(subscription));
    subscription.on('netUnavailable', () => this.refresh(subscription));
    subscription.register((error) => {
      if (this.subscription !== subscription) return;
      if (error) this.events?.error('connectivity_error', error.message, null);
      else this.refresh(subscription);
    });
  }

  onCancel(args?: Object): void {
    const subscription = this.subscription;
    this.subscription = null;
    this.events = null;
    if (subscription !== null) {
      subscription.unregister(() => {});
    }
  }

  private async refresh(subscription: connection.NetConnection): Promise<void> {
    try {
      const types = await this.connectivity.getNetworkType();
      if (this.subscription === subscription) this.events?.success(types);
    } catch (error) {
      if (this.subscription === subscription) {
        this.events?.error('connectivity_error', String(error), null);
      }
    }
  }
}
