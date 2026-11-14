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

export class Connectivity {
  async getNetworkType(): Promise<string[]> {
    const net = await connection.getDefaultNet();
    if (net.netId === 0) return ['none'];
    const capabilities = await connection.getNetCapabilities(net);
    return this.hasTransport(capabilities.bearerTypes);
  }

  hasTransport(capabilities: number[]): string[] {
    const types: string[] = [];
    for (const bearer of capabilities) {
      let type = 'other';
      switch (bearer) {
        case connection.NetBearType.BEARER_WIFI: type = 'wifi'; break;
        case connection.NetBearType.BEARER_ETHERNET: type = 'ethernet'; break;
        case connection.NetBearType.BEARER_CELLULAR: type = 'mobile'; break;
        case connection.NetBearType.BEARER_BLUETOOTH: type = 'bluetooth'; break;
        case connection.NetBearType.BEARER_VPN: type = 'vpn'; break;
      }
      if (!types.includes(type)) types.push(type);
    }
    return types.length === 0 ? ['none'] : types;
  }
}
