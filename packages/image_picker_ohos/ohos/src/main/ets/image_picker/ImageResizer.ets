// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on ImageResizer.java originally written by
// Copyright 2013 The Flutter Authors.

// Local changes: preserve aspect ratio, use private JPEG paths and handle partial writes.
import util from '@ohos.util';
import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import common from '@ohos.app.ability.common';
import ExifDataCopier from './ExifDataCopier'
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';

const TAG: string = "ImageResizer";

export default class ImageResizer {
  private readonly context: common.Context;
  private readonly exifDataCopier: ExifDataCopier;

  constructor(context: common.Context, exifDataCopier: ExifDataCopier) {
    this.context = context;
    this.exifDataCopier = exifDataCopier;
  }

  async resizeImageIfNeeded(imagePath: string, maxWidth: number, maxHeight: number, imageQuality: number):
    Promise<string> {
    if (imagePath == null) {
      Log.e(TAG, "imagePath is null");
      return imagePath;
    }

    let shouldScale: boolean = (maxWidth != null || maxHeight != null || imageQuality < 100);
    if (!shouldScale) {
      return imagePath;
    }

    let imageFile: fs.File | null = null;
    let imageSource: image.ImageSource | null = null;
    let imagePixelMap: image.PixelMap | null = null;
    try {
      imageFile = fs.openSync(imagePath);
      imageSource = image.createImageSource(imageFile.fd);
      let imageInfo: image.ImageInfo = await imageSource.getImageInfo();
      if (imageInfo.size.width == -1 || imageInfo.size.height == -1) {
        return imagePath;
      }

      let targetSize: image.Size = this.calculateTargetSize(imageInfo.size.width, imageInfo.size.height, maxWidth,
        maxHeight);
      Log.d(TAG, "Start scale image, origin w:" + imageInfo.size.width + " origin h:" + imageInfo.size.width +
        " target w:" + targetSize.width + " target h:" + targetSize.height);

      let parts: string[] = imagePath.split('/', -1);
      let imageName: string = parts[parts.length - 1];
      imagePixelMap = await imageSource.createPixelMap({
        desiredSize: targetSize
      });

      let outFileName = await this.createImageOnExternalDirectory(imagePixelMap, imageName, imageQuality);
      await this.exifDataCopier.copyExif(imagePath, outFileName);
      return outFileName;
    } catch (e) {
      Log.e(TAG, "Resize image failed " + imagePath + " err " + e);
      return imagePath;
    } finally {
      if (imageFile != null) {
        try {
          fs.closeSync(imageFile);
        } catch (e) {
          Log.e(TAG, "Close image failed failed " + e);
        }
      }
      if (imageSource != null) {
        await imageSource.release();
      }
      if (imagePixelMap != null) {
        await imagePixelMap.release();
      }
    }
  }

  private calculateTargetSize(originalWidth: number, originalHeight: number, maxWidth: number,
                              maxHeight: number): image.Size {
    const ratio = Math.min(1, maxWidth == null ? 1 : maxWidth / originalWidth,
      maxHeight == null ? 1 : maxHeight / originalHeight);
    return { width: Math.max(1, Math.floor(originalWidth * ratio)),
      height: Math.max(1, Math.floor(originalHeight * ratio)) };
  }

  private async createImageOnExternalDirectory(imagePixelMap: image.PixelMap, imageName: string, imageQuality: number):
    Promise<string> {
    let imagePackerApi: image.ImagePacker | null = null;
    let outFile: fs.File | null = null;
    let outFileName: string = `${this.context.cacheDir}/scaled_${util.generateRandomUUID()}.jpg`;

    try {
      imagePackerApi = image.createImagePacker();
      let bufferData = await imagePackerApi.packing(imagePixelMap, {
        format: "image/jpeg", quality: imageQuality, needsPackProperties: true
      });

      outFile = fs.openSync(outFileName, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      let written = 0;
      while (written < bufferData.byteLength) {
        const chunk = bufferData.slice(written, Math.min(written + 65536, bufferData.byteLength));
        const count = fs.writeSync(outFile.fd, chunk);
        if (count <= 0) throw new Error('Image output write made no progress');
        written += count;
      }
    } finally {
      if (imagePackerApi != null) {
        await imagePackerApi.release();
      }
      if (outFile != null) {
        try {
          fs.closeSync(outFile);
        } catch (e) {
          Log.w(TAG, "Close out file failed");
        }
      }
    }
    return outFileName;
  }
}