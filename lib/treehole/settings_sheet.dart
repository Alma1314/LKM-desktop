import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/config.dart';
import 'package:island/treehole/local_store.dart';

class TreeholeSettingsSheet extends HookConsumerWidget {
  const TreeholeSettingsSheet({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = TreeholeLocalStore(
      ref.watch(sharedPreferencesProvider),
      ref.watch(lkmServerUrlProvider),
    );
    final data = useState(store.read());
    final error = useState<String?>(null);
    Future<void> set(String key, Object value) async {
      await store.patch(key, value);
      if (context.mounted) data.value = store.read();
    }

    Future<void> backup(bool importing) async {
      try {
        if (importing) {
          final files = await FilePicker.pickFiles();
          if (files.isEmpty) return;
          if (await files.first.xFile.length() > 1024 * 1024)
            throw const FormatException('Backup too large');
          final text = await files.first.xFile.readAsString();
          if (!context.mounted) return;
          final yes = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              content: Text('migration34.replaceBackup'.tr()),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: Text('cancel'.tr()),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: Text('confirm'.tr()),
                ),
              ],
            ),
          );
          if (yes != true) return;
          await store.import(text);
          if (context.mounted) data.value = store.read();
        } else {
          await FilePicker.saveFile(
            fileName: 'treehole-backup.json',
            bytes: utf8.encode(store.export()),
          );
        }
      } catch (e) {
        if (context.mounted) error.value = '$e';
      }
    }

    return AlertDialog(
      title: Text('settings'.tr()),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: data.value['theme'] as String? ?? 'system',
                decoration: InputDecoration(
                  labelText: 'migration34.theme'.tr(),
                ),
                items: [
                  for (final v in ['system', 'light', 'dark'])
                    DropdownMenuItem(
                      value: v,
                      child: Text('migration34.$v'.tr()),
                    ),
                ],
                onChanged: (v) => set('theme', v!),
              ),
              Text('migration34.fontSize'.tr()),
              Slider(
                value: (data.value['scale'] as num? ?? 1).toDouble(),
                min: 0.8,
                max: 1.6,
                divisions: 8,
                onChanged: (v) => set('scale', v),
              ),
              for (final k in ['contrast', 'mute', 'limit'])
                SwitchListTile(
                  title: Text('migration34.$k'.tr()),
                  value: data.value[k] as bool? ?? (k != 'contrast'),
                  onChanged: (v) => set(k, v),
                ),
              Text('migration34.localPrivacy'.tr()),
              Wrap(
                children: [
                  TextButton(
                    onPressed: () => backup(false),
                    child: Text('migration34.export'.tr()),
                  ),
                  TextButton(
                    onPressed: () => backup(true),
                    child: Text('migration34.import'.tr()),
                  ),
                  TextButton(
                    onPressed: () async {
                      await store.patch('draft', null);
                      if (context.mounted) data.value = store.read();
                    },
                    child: Text('migration34.clearDraft'.tr()),
                  ),
                ],
              ),
              if (error.value != null) Text(error.value!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('close'.tr()),
        ),
      ],
    );
  }
}
