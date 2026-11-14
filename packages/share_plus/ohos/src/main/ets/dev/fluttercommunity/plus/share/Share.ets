/* Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
 * Licensed under the Apache License, Version 2.0; see LICENSE-OHOS.
 * Local changes: current API map, awaited copies, private cache, one reply and native failures.
 */
import { MethodCall, MethodResult } from '@ohos/flutter_ohos';
import common from '@ohos.app.ability.common';
import UIAbility from '@ohos.app.ability.UIAbility';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileUri } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import systemShare from '@hms.collaboration.systemShare';
import utd from '@ohos.data.uniformTypeDescriptor';

export default class Share {
  private ability: UIAbility | null = null;
  private pending: MethodResult | null = null;
  private controller: systemShare.ShareController | null = null;
  private dismissed: (() => void) | null = null;
  private context: common.Context;
  constructor(context: common.Context) { this.context = context; }

  setAbility(ability: UIAbility | null): void {
    this.ability = ability;
    if (ability === null && this.pending !== null) {
      const result = this.pending;
      this.clear();
      result.error('no_ability', 'Share ability detached', null);
    }
  }
  share(call: MethodCall, result: MethodResult): void {
    if (this.ability === null) { result.error('no_ability', 'Share requires a foreground ability', null); return; }
    if (this.pending !== null) { result.error('already_active', 'A share sheet is already active', null); return; }
    this.pending = result;
    const ability = this.ability;
    this.buildData(call).then(async (data: systemShare.SharedData) => {
      if (this.pending !== result) return;
      const controller = new systemShare.ShareController(data);
      this.controller = controller;
      this.dismissed = () => {
        if (this.pending !== result) return;
        this.clear();
        // Closing a panel alone does not confirm selection or delivery.
        result.success('dev.fluttercommunity.plus/share/unavailable');
      };
      controller.on('dismiss', this.dismissed);
      await controller.show(ability.context, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE,
      });
    }).catch((error: BusinessError) => {
      if (this.pending !== result) return;
      this.clear();
      result.error('share_error', error.message, error.code);
    });
  }

  private clear(): void {
    const controller = this.controller;
    const dismissed = this.dismissed;
    this.pending = null;
    this.controller = null;
    this.dismissed = null;
    if (controller !== null && dismissed !== null) { try { controller.off('dismiss', dismissed); } catch (_) {} }
  }

  private async buildData(call: MethodCall): Promise<systemShare.SharedData> {
    const text = call.argument('text') as string;
    const uri = call.argument('uri') as string;
    const title = (call.argument('title') ?? call.argument('subject')) as string;
    const paths = call.argument('paths') as string[];
    const mimeTypes = call.argument('mimeTypes') as string[];
    const records: systemShare.SharedRecord[] = [];
    if (text != null) records.push({ utd: utd.UniformDataType.PLAIN_TEXT, content: text });
    if (uri != null) records.push({ utd: utd.UniformDataType.HYPERLINK, content: uri });
    if (paths != null) {
      if (!Array.isArray(paths) || !Array.isArray(mimeTypes) || paths.length !== mimeTypes.length) {
        throw new Error('File paths and MIME types must be matching lists');
      }
      for (let i = 0; i < paths.length; i++) {
        if (typeof paths[i] !== 'string' || !paths[i] || typeof mimeTypes[i] !== 'string') {
          throw new Error('Invalid file path or MIME type');
        }
        const cached = await this.copyFile(paths[i]);
        const extension = cached.slice(cached.lastIndexOf('.'));
        const type = mimeTypes[i] === 'application/octet-stream' ?
          utd.getUniformDataTypeByFilenameExtension(extension) : utd.getUniformDataTypeByMIMEType(mimeTypes[i]);
        records.push({ utd: type || utd.UniformDataType.FILE, uri: fileUri.getUriFromPath(cached) });
      }
    }
    if (records.length === 0) throw new Error('No content to share');
    if (title != null) { for (const record of records) record.title = title; }
    const data = new systemShare.SharedData(records[0]);
    for (let i = 1; i < records.length; i++) data.addRecord(records[i]);
    return data;
  }

  private async copyFile(path: string): Promise<string> {
    const source = await fs.open(path, fs.OpenMode.READ_ONLY);
    try {
      let name = source.name.replace(/[\\/\u0000]/g, '_');
      if (!name || name === '.' || name === '..') name = 'file';
      const directory = `${this.context.cacheDir}/share_plus/${util.generateRandomUUID()}`;
      fs.mkdirSync(directory, true);
      const target = `${directory}/${name}`;
      await fs.copyFile(source.fd, target);
      // ponytail: retain OS-managed cache so asynchronous receivers can still read the files.
      return target;
    } finally {
      await fs.close(source);
    }
  }
}
