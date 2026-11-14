import {
  Any,
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
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import util from '@ohos.util';

const CHANNEL = 'miguelruivo.flutter.plugins.filepicker';

export default class FilePickerPlugin
  implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel: MethodChannel | null = null;
  private context: common.UIAbilityContext | null = null;

  getUniqueClassName(): string {
    return 'FilePickerPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel !== null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
    this.context = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.context = binding.getAbility().context;
  }

  onDetachedFromAbility(): void {
    this.context = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    this.handle(call, result).catch((error: Error) => {
      result.error('file_picker_error', error.message, null);
    });
  }

  private async handle(call: MethodCall, result: MethodResult): Promise<void> {
    switch (call.method) {
      case 'pickFiles': {
        const uris = await this.selectFiles(call);
        const cached: string[] = [];
        for (const uri of uris) cached.push(await this.cacheFile(uri));
        result.success(cached);
        return;
      }
      case 'getDirectoryPath': {
        const uris = await this.selectFiles(call, true);
        result.success(uris.length === 0 ? null : uris[0]);
        return;
      }
      case 'saveFile': {
        result.success(await this.saveFile(call));
        return;
      }
      case 'clearTemporaryFiles': {
        if (this.context !== null) {
          const root = `${this.context.cacheDir}/file_picker`;
          if (fs.accessSync(root)) await fs.rmdir(root, true);
        }
        result.success(null);
        return;
      }
      case 'skipEntitlementsChecks': {
        result.success(null);
        return;
      }
      default:
        result.notImplemented();
    }
  }

  private async selectFiles(
    call: MethodCall,
    directory: boolean = false,
  ): Promise<string[]> {
    if (this.context === null) {
      throw new Error('No UIAbility context is attached');
    }
    const target = new picker.DocumentViewPicker(this.context);
    const options = new picker.DocumentSelectOptions();
    const multiple = directory ? false : Boolean(call.argument('multiple'));
    options.maxSelectNumber = multiple ? 50 : 1;
    if (directory) {
      options.selectMode = picker.DocumentSelectMode.FOLDER;
    }
    const initialDirectory = this.optionalString(call, 'initialDirectory');
    if (initialDirectory.length > 0) {
      options.defaultFilePathUri = this.toUri(initialDirectory);
    }
    const filters = this.suffixFilters(call);
    if (filters.length > 0) {
      options.fileSuffixFilters = filters;
    }
    return await target.select(options);
  }

  private async saveFile(call: MethodCall): Promise<string | null> {
    if (this.context === null) {
      throw new Error('No UIAbility context is attached');
    }
    const fileName = this.stringArgument(call, 'fileName');
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [fileName];
    const initialDirectory = this.optionalString(call, 'initialDirectory');
    if (initialDirectory.length > 0) {
      options.defaultFilePathUri = this.toUri(initialDirectory);
    }
    const suffix = this.fileSuffix(call, fileName);
    if (suffix.length > 0) {
      options.fileSuffixChoices = [suffix];
    }
    const target = new picker.DocumentViewPicker(this.context);
    const uris = await target.save(options);
    if (uris.length === 0) {
      return null;
    }
    const uri = uris[0];
    const bytes = call.argument('bytes') as Uint8Array;
    const file = await fs.open(
      uri,
      fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC,
    );
    try {
      let written = 0;
      while (written < bytes.byteLength) {
        const end = Math.min(written + 65536, bytes.byteLength);
        const chunk = bytes.buffer.slice(bytes.byteOffset + written, bytes.byteOffset + end) as ArrayBuffer;
        const count = await fs.write(file.fd, chunk);
        if (count <= 0) throw new Error('File write made no progress');
        written += count;
      }
    } finally {
      await fs.close(file);
    }
    return uri;
  }

  private suffixFilters(call: MethodCall): string[] {
    const type = Number(call.argument('type'));
    const extensions = this.stringList(call.argument('allowedExtensions'));
    if (type === 5 && extensions.length > 0) {
      return extensions.map((item: string) => this.withDot(item));
    }
    switch (type) {
      case 1:
        return ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.mp4', '.mov', '.mkv', '.webm'];
      case 2:
        return ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'];
      case 3:
        return ['.mp4', '.mov', '.mkv', '.webm', '.avi'];
      case 4:
        return ['.mp3', '.aac', '.flac', '.wav', '.ogg', '.m4a'];
      default:
        return [];
    }
  }

  private fileSuffix(call: MethodCall, fileName: string): string {
    const extensions = this.stringList(call.argument('allowedExtensions'));
    if (extensions.length > 0) {
      return this.withDot(extensions[0]);
    }
    const index = fileName.lastIndexOf('.');
    return index >= 0 ? fileName.substring(index) : '';
  }

  private withDot(value: string): string {
    return value.startsWith('.') ? value : `.${value}`;
  }

  private optionalString(call: MethodCall, key: string): string {
    const value: Any = call.argument(key);
    return value === null || value === undefined ? '' : String(value);
  }

  private stringArgument(call: MethodCall, key: string): string {
    const value = this.optionalString(call, key);
    if (value.length === 0) {
      throw new Error(`${key} is required`);
    }
    return value;
  }

  private stringList(value: Any): string[] {
    if (value === null || value === undefined) {
      return [];
    }
    return (value as Any[]).map((item: Any) => String(item));
  }

  private toUri(path: string): string {
    return path.startsWith('file://') ? path : `file://${path}`;
  }

  private async cacheFile(uri: string): Promise<string> {
    if (this.context === null) throw new Error('No UIAbility context is attached');
    const directory = `${this.context.cacheDir}/file_picker/${util.generateRandomUUID()}`;
    fs.mkdirSync(directory, true);
    const original = new fileUri.FileUri(uri).name;
    const name = original.replace(/[\\/]/g, '_');
    const safeName = name.length === 0 || name === '.' || name === '..' ? 'file' : name;
    const destination = `${directory}/${safeName}`;
    const input = await fs.open(uri, fs.OpenMode.READ_ONLY);
    try {
      await fs.copyFile(input.fd, destination);
    } finally {
      await fs.close(input);
    }
    return fileUri.getUriFromPath(destination);
  }
}
