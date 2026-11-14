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

import StandardMessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMessageCodec';
import BasicMessageChannel, { Reply } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BasicMessageChannel';
import { BinaryMessenger, TaskQueue } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import MessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/MessageCodec';
import { ByteBuffer } from '@ohos/flutter_ohos/src/main/ets/util/ByteBuffer';
import { HashMap } from '@kit.ArkTS';

/** Error class for passing custom error details to Flutter via a thrown PlatformException. */
export class FlutterError implements Error {
  /** The error code. */
  public code: string;
  /** The error name. */
  public name: string;
  /** The error message. */
  public message: string;
  /** The error stack. */
  public stack?: string;

  constructor(code: string, name: string, message: string, stack: string) {
    this.code = code;
    this.name = name;
    this.message = message;
    this.stack = stack;
  }
}

function wrapError(error: Error): Array<Object> {
  let errorList: Array<Object> = new Array<Object>(3);
  if (error instanceof FlutterError) {
    let err: FlutterError = error as FlutterError;
    errorList[0] = err.code;
    // Dart 端 messages.g.dart 的 _extractReplyValueOrThrow 按 [code, message, details] 解析，
    // message 位须放真实错误描述（对齐 Android 端 Pigeon 生成代码），details 位放栈信息，
    // 避免 PlatformException.message 恒为 "Error"、真实描述落入 details 的字段错位。
    errorList[1] = err.message;
    errorList[2] = err.stack ?? '';
  } else {
    errorList[0] = error.toString();
    errorList[1] = error.name;
    errorList[2] = "Cause: " + error.message + ", Stacktrace: " + error.stack;
  }
  return errorList;
}

/*
*  Message for toggling the wakelock on the platform side.
* 
*  Generated class from Pigeon that represents data sent in messages.
*/
export class ToggleMessage {
  private enable: boolean;

  getEnable(): boolean {
    return this.enable;
  }

  constructor(enable: boolean) {
    this.enable = enable;
  }

  toList(): Object[] {
    let arr: Object[] = new Array();
    arr.push(this.enable);
    return arr;
  }

  static fromList(message: Object): ToggleMessage {
    let list: Array<Object> = message as Array<Object>;
    // 入口校验：ArkTS 的 as 断言不做运行时检查，畸形消息（null/非数组/首元素非布尔）
    // 须在解码入口抛出明确错误，而不是携带非法值深入到 setWindowKeepScreenOn 才以 401 参数错误兜底。
    let isValid: boolean = message instanceof Array && list.length > 0 && typeof list[0] === 'boolean';
    if (!isValid) {
      throw new Error('Invalid ToggleMessage payload: expected [boolean]');
    }
    return new ToggleMessage(list[0] as boolean);
  }
}

/*
*  Message for reporting the wakelock state from the platform side.
*
*  Generated class from Pigeon that represents data sent in messages.
*/
export class IsEnabledMessage {
  private enabled: boolean;

  getEnabled(): boolean {
    return this.enabled;
  }

  constructor(enabled: boolean) {
    this.enabled = enabled;
  }

  toList(): Array<Object> {
    let result: Array<Object> = [];
    result.push(this.enabled);
    return result;
  }

  static fromList(arr: Object[]): IsEnabledMessage {
    // 入口校验：畸形回包在解码入口抛出明确错误，避免把非法 enabled 值传给上层。
    let isValid: boolean = arr instanceof Array && arr.length > 0 && typeof arr[0] === 'boolean';
    if (!isValid) {
      throw new Error('Invalid IsEnabledMessage payload: expected [boolean]');
    }
    return new IsEnabledMessage(arr[0] as boolean);
  }
}

class WakelockApiCodec extends StandardMessageCodec {
  static INSTANCE: WakelockApiCodec = new WakelockApiCodec();

  getByte(n: number): number {
    let byteArray = new Uint8Array(1);
    byteArray[0] = n;
    return byteArray[0] as number;
  }

  readValueOfType(type: number, buffer: ByteBuffer): ESObject {
    switch (type) {
      case this.getByte(130):
        return IsEnabledMessage.fromList(super.readValue(buffer));
      case this.getByte(129):
        return ToggleMessage.fromList(super.readValue(buffer));
      default:
        return super.readValueOfType(type, buffer);
    }
  }

  writeValue(stream: ByteBuffer, value: ESObject): ESObject {
    if (value instanceof IsEnabledMessage) {
      // 130 超出 Int8 有符号范围，须用无符号写出，与 Dart/Android/iOS 的类型码保持一致。
      stream.writeUint8(this.getByte(130));
      this.writeValue(stream, (value as IsEnabledMessage).toList());
    } else if (value instanceof ToggleMessage) {
      stream.writeUint8(this.getByte(129));
      this.writeValue(stream, (value as ToggleMessage).toList());
    } else {
      super.writeValue(stream, value);
    }
  }
}

/* Generated abstract class from Pigeon that represents a handler of messages from Flutter.*/
export abstract class WakelockApi {
  abstract toggle(msg: ToggleMessage): Promise<void>;

  abstract isEnabled(): Promise<IsEnabledMessage>;

  /** The codec used by WakelockApi. */
  static getCodec(): MessageCodec<Object> {
    return WakelockApiCodec.INSTANCE;
  }

  /*Sets up an instance of `WakelockApi` to handle messages through the `binaryMessenger`.*/
  static setup(binaryMessenger: BinaryMessenger, api: WakelockApi | null): void {
    {
      let channel: BasicMessageChannel<Object> =
        new BasicMessageChannel(
          binaryMessenger, "dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle", WakelockApi.getCodec());
      if (api != null) {
        channel.setMessageHandler({
          async onMessage(message: Object, reply: Reply<Object>) {
            let args: Array<Object> = message as Array<Object>;
            let res: Array<Object> = [];
            try {
              await api!.toggle(args[0] as ToggleMessage);
              res.push(null);
            }
            catch (error) {
              let wrappedError: Array<Object> = wrapError(error);
              res = wrappedError;
            }
            reply.reply(res);
          }
        });
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      let channel: BasicMessageChannel<Object> =
        new BasicMessageChannel(
          binaryMessenger, "dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.isEnabled", WakelockApi.getCodec());
      if (api != null) {
        channel.setMessageHandler({
          async onMessage(message: Object, reply: Reply<Object>) {
            try {
              let output: IsEnabledMessage = await api!.isEnabled();
              // Dart 端 messages.g.dart（Pigeon v26.2.3）按 IsEnabledMessage 对象解包回包（[IsEnabledMessage]），须与之一致。
              let res: Array<Object> = [];
              res.push(output);
              reply.reply(res);
            }
            catch (error) {
              let wrappedError: Array<Object> = wrapError(error);
              reply.reply(wrappedError);
            }
          }
        });
      } else {
        channel.setMessageHandler(null);
      }
    }
  }
}
