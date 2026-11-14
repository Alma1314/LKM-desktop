// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Based on Flutter code, Copyright 2013 The Flutter Authors.
// BSD-style license: LICENSE_ODID. Based on the CPF-Flutter image_picker backend.
// Local changes: shared channel, serialized requests, and completion on every outcome.
import {
  AbilityAware, AbilityPluginBinding, FlutterPlugin, FlutterPluginBinding,
  MethodCall, MethodCallHandler, MethodChannel, MethodResult,
} from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { camera, cameraPicker } from '@kit.CameraKit';
import { fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import FileUtils from './FileUtils';
import ImageResizer from './ImageResizer';
import ExifDataCopier from './ExifDataCopier';

export default class ImagePickerPlugin implements FlutterPlugin, AbilityAware, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private context: common.UIAbilityContext | null = null;
  private pending: MethodResult | null = null;

  getUniqueClassName(): string { return 'ImagePickerPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'plugins.flutter.io/image_picker');
    this.channel.setMethodCallHandler(this);
  }
  onAttachedToAbility(binding: AbilityPluginBinding): void { this.context = binding.getAbility().context; }
  onDetachedFromAbility(): void {
    this.context = null;
    const pending = this.pending;
    this.pending = null;
    pending?.error('no_ability', 'Image picker ability detached', null);
  }
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.onDetachedFromAbility();
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }
  onMethodCall(call: MethodCall, result: MethodResult): void {
    // Lost-data recovery is Android-only in the shared public contract.
    if (call.method === 'retrieve') { result.success(null); return; }
    if (!['pickImage', 'pickMultiImage', 'pickVideo', 'pickMultiVideo', 'pickMedia'].includes(call.method)) {
      result.notImplemented(); return;
    }
    if (this.context === null) { result.error('no_ability', 'Image picker requires an ability', null); return; }
    if (this.pending !== null) { result.error('already_active', 'Image picker is already active', null); return; }
    this.pending = result;
    this.pick(call, this.context, result).then((paths: string[]) => {
      if (this.pending !== result) return;
      this.pending = null;
      const single = call.method === 'pickImage' || call.method === 'pickVideo';
      result.success(single ? (paths.length === 0 ? null : paths[0]) : paths);
    }).catch((error: BusinessError) => {
      if (this.pending !== result) return;
      this.pending = null;
      result.error('picker_error', error.message, error.code);
    });
  }

  private async pick(call: MethodCall, context: common.UIAbilityContext, request: MethodResult): Promise<string[]> {
    const video = call.method === 'pickVideo' || call.method === 'pickMultiVideo';
    const mixed = call.method === 'pickMedia';
    const multiple = call.method === 'pickMultiImage' || call.method === 'pickMultiVideo' ||
      (mixed && call.argument('allowMultiple') === true);
    const limit = call.argument('limit') as number;
    if (limit != null && (!Number.isInteger(limit) || limit < 2 || !multiple)) {
      throw new Error('A selection limit requires multiple selection and must be at least 2');
    }
    const width = call.argument(mixed ? 'maxImageWidth' : 'maxWidth') as number;
    const height = call.argument(mixed ? 'maxImageHeight' : 'maxHeight') as number;
    const quality = (call.argument('imageQuality') ?? 100) as number;
    if ((width != null && (!Number.isFinite(width) || width <= 0)) ||
      (height != null && (!Number.isFinite(height) || height <= 0)) ||
      !Number.isInteger(quality) || quality < 0 || quality > 100) {
      throw new Error('Invalid image dimensions or quality');
    }
    if (!multiple && !mixed && call.argument('source') === 0) {
      const path = `${context.cacheDir}/${util.generateRandomUUID()}.${video ? 'mp4' : 'jpg'}`;
      const duration = call.argument('maxDuration') as number;
      if (video && duration != null && (!Number.isInteger(duration) || duration <= 0)) {
        throw new Error('Invalid video duration');
      }
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      fs.closeSync(file);
      const profile: cameraPicker.PickerProfile = {
        cameraPosition: call.argument('cameraDevice') === 1 ?
          camera.CameraPosition.CAMERA_POSITION_FRONT : camera.CameraPosition.CAMERA_POSITION_BACK,
        saveUri: fileUri.getUriFromPath(path),
      };
      if (video && duration != null) profile.videoDuration = duration;
      try {
        const captured = await cameraPicker.pick(context,
          [video ? cameraPicker.PickerMediaType.VIDEO : cameraPicker.PickerMediaType.PHOTO], profile);
        if (this.pending !== request) return [];
        const uris = captured.resultCode === 0 ? [captured.resultUri || profile.saveUri!] : [];
        return await this.cacheAndResize(uris, context, video, mixed, width, height, quality);
      } finally {
        try { fs.unlinkSync(path); } catch (_) {}
      }
    }
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.maxSelectNumber = multiple ? Math.min(limit ?? 500, 500) : 1;
    if (!mixed) options.MIMEType = video ? photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE :
      photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    const selection = await new photoAccessHelper.PhotoViewPicker().select(options);
    if (this.pending !== request) return [];
    return this.cacheAndResize(selection.photoUris, context, video, mixed, width, height, quality);
  }

  private async cacheAndResize(uris: string[], context: common.UIAbilityContext, video: boolean,
    mixed: boolean, width: number, height: number, quality: number): Promise<string[]> {
    const paths: string[] = [];
    const resizer = new ImageResizer(context, new ExifDataCopier());
    for (const uri of uris) {
      let path = FileUtils.getPathFromUri(context, uri, video ? 'mp4' : 'jpg');
      const isVideo = video || (mixed && (/\/video\//i.test(uri) || /\.(mp4|3gp|mkv|webm|avi|mov|m4v)$/i.test(path)));
      if (!isVideo) path = await resizer.resizeImageIfNeeded(path, width, height, quality);
      paths.push(path);
    }
    return paths;
  }
}
