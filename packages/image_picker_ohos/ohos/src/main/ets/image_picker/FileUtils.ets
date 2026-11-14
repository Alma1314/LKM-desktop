// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Based on Flutter code, Copyright 2013 The Flutter Authors.
// BSD-style license: LICENSE_ODID. Local changes: safe names, close FDs once, propagate failures.
import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import util from '@ohos.util';

export default class FileUtils {
  static getPathFromUri(context: common.Context, uri: string, extension: string = 'jpg'): string {
    let name = uri.slice(uri.lastIndexOf('/') + 1).split('?')[0];
    try { name = decodeURIComponent(name); } catch (_) {}
    name = name.replace(/[\\/\u0000]/g, '_');
    if (!name || name === '.' || name === '..') name = 'image_picker';
    if (!name.includes('.')) name += `.${extension}`;
    const directory = `${context.cacheDir}/${util.generateRandomUUID()}`;
    fs.mkdirSync(directory);
    const path = `${directory}/${name}`;
    const input = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      fs.copyFileSync(input.fd, path);
      return path;
    } finally {
      fs.closeSync(input);
    }
  }
}
