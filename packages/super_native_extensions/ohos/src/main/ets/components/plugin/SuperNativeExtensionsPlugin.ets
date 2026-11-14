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

import {
  FlutterPlugin,
  FlutterPluginBinding,
  FlutterManager,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  DragDropCallback,
  Log,
} from '@ohos/flutter_ohos';

import rustNapi from 'libsuper_native_extensions.so';
import uniformTypeDescriptor from '@ohos.data.uniformTypeDescriptor';
import UDC from '@ohos.data.unifiedDataChannel';
import { BusinessError } from '@ohos.base';
import fs from '@ohos.file.fs';
import util from '@ohos.util';

/** SuperNativeExtensionsPlugin **/
export default class SuperNativeExtensionsPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;

  private dragEnterCbId: number = -1;
  private dragMoveCbId: number = -1;
  private dragLeaveCbId: number = -1;
  private dropCbId: number = -1;

  constructor() {
  }

  getUniqueClassName(): string {
    return "SuperNativeExtensionsPlugin"
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "super_native_extensions");
    this.channel.setMethodCallHandler(this);
    rustNapi.ohosNativeExtensionsInit();
    this.dragEnterCbId = FlutterManager.getInstance().addDragEnterCb(new DragEnterCallback());
    this.dragMoveCbId = FlutterManager.getInstance().addDragMoveCb(new DragMoveCallback());
    this.dragLeaveCbId = FlutterManager.getInstance().addDragLeaveCb(new DragLeaveCallback());
    this.dropCbId = FlutterManager.getInstance().addDropCb(new DropCallback());
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null)
    }
    FlutterManager.getInstance().removeDragEnterCb(this.dragEnterCbId);
    FlutterManager.getInstance().removeDragMoveCb(this.dragMoveCbId);
    FlutterManager.getInstance().removeDragLeaveCb(this.dragLeaveCbId);
    FlutterManager.getInstance().removeDropCb(this.dropCbId);
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method == "dataPreprocess") {
      let format: string = call.argument('format');
      if (format == 'general.plain-text' || format == 'general.html' || format == 'general.hyperlink') {
        result.success(call.argument('data'))
      }
      let fileUri: string = 'file://' + getContext(this).applicationInfo.name + getContext(this).cacheDir + '/' + Date.now().toString() + '.' + format;
      this.writeFile(call.argument('data').buffer, fileUri);
      result.success(fileUri)
    } else {
      result.notImplemented()
    }
  }

  async writeFile(buffer: ArrayBuffer, fileUri: string) {
    let file: fs.File = fs.openSync(fileUri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
    await fs.write(file.fd, buffer);
    fs.closeSync(file);
  }
}

export class DragEnterCallback implements DragDropCallback {
  do(event: DragEvent, extraParams: string) {
    let nativeEvent: rustNapi.NativeDragEvent = new rustNapi.NativeDragEvent(event.getWindowX(), event.getWindowY(), 
      event.getResult() == DragResult.DRAG_SUCCESSFUL, [], []);
    nativeEvent.onDragEnter();
    Log.d('Drag', "plugin onDragEnter " + event.getWindowX() + ", " + event.getWindowY());
  }
}

export class DragMoveCallback implements DragDropCallback {
  do(event: DragEvent, extraParams: string) {
    let formats: Array<string> = [];
    try {
      let summarys = event.getSummary().summary as object;
      (summarys as Array<object>).forEach(su => {
        formats.push(su[0]);
      });
    } catch(err) {
      Log.w('Drag', "Failed to get formats.");
    }
    let nativeEvent: rustNapi.NativeDragEvent = new rustNapi.NativeDragEvent(event.getWindowX(), event.getWindowY(), 
      event.getResult() == DragResult.DRAG_SUCCESSFUL, formats, []);
    nativeEvent.onDragMove();
    Log.d('Drag', "plugin onDragMove " + event.getWindowX() + ", " + event.getWindowY());
  }
}

export class DragLeaveCallback implements DragDropCallback {
  do(event: DragEvent, extraParams: string) {
    let nativeEvent: rustNapi.NativeDragEvent = new rustNapi.NativeDragEvent(event.getWindowX(), event.getWindowY(), 
      event.getResult() == DragResult.DRAG_SUCCESSFUL, [], []);
    nativeEvent.onDragLeave();
    Log.d('Drag', "plugin onDragLeave " + event.getWindowX() + ", " + event.getWindowY());
  }
}

export class DropCallback implements DragDropCallback {
  do(event: DragEvent, extraParams: string) {
    try {
      let records: Array<UDC.UnifiedRecord> = event.getData().getRecords();
      let formats: Array<string> = [];
      let contents: Array<string> = [];
      records.forEach(record => {
        let type: string = record.getType();
        if (type == 'general.plain-text') {
          formats.push('general.plain-text');
          contents.push((record as UDC.PlainText).textContent);
        } else if (type == 'general.html') {
          formats.push('general.html');
          contents.push((record as UDC.HTML).htmlContent);
        } else if (type == 'general.hyperlink') {
          formats.push('general.hyperlink');
          contents.push((record as UDC.Hyperlink).url);
        } else {
          let fileUri: string = (record as UDC.File).uri;
          if (fileUri != undefined) {
            let formatIndex = fileUri.lastIndexOf('.');
            if (formatIndex != -1) {
              let format: string = fileUri.substring(formatIndex + 1);
              formats.push(format);
              let file = fs.openSync(fileUri);
              let stream = fs.fdopenStreamSync(file.fd, "r");
              let stat = fs.statSync(file.fd);
              let size = stat.size;
              let buffer = new ArrayBuffer(size);
              stream.readSync(buffer, {offset: 0, length: size});
              let byteArray = new Uint8Array(buffer);
              contents.push(new util.Base64Helper().encodeToStringSync(byteArray));
              fs.closeSync(file.fd);
            }
          }
        }
      });
      let nativeEvent: rustNapi.NativeDragEvent = new rustNapi.NativeDragEvent(event.getWindowX(), event.getWindowY(), 
        event.getResult() == DragResult.DRAG_SUCCESSFUL, formats, contents);
      nativeEvent.onDrop();
    } catch(err) {
      Log.w('Drag', "Failed to drop.");
    }
  }
}