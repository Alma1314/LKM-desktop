import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/core/api/treehole_api.dart';
import 'package:island/shared/widgets/alert.dart';
import 'package:island/shared/widgets/layouts/sheet_scaffold.dart';
import 'package:island/treehole/treehole_common.dart';
import 'package:island/treehole/treehole_pod.dart';

/// Writes a new anonymous letter, or edits [letter] when one is supplied.
class TreeholeLetterSheet extends HookConsumerWidget {
  const TreeholeLetterSheet({super.key, this.letter});

  final LkmTreeholeLetter? letter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editing = letter;
    final content = useTextEditingController(text: editing?.content ?? '');
    final codename = useTextEditingController(
      text: editing?.codename ?? randomTreeholeCodename(),
    );
    final category = useState(editing?.category ?? treeholeCategories.first.key);
    final privacy = useState(editing?.privacy ?? 'public');
    final moods = useState<List<String>>(editing?.moods ?? const []);
    final tags = useState<List<String>>(editing?.tags ?? const []);
    final submitting = useState(false);
    final error = useState<String?>(null);
    final theme = Theme.of(context);

    void toggle(List<String> current, String value, ValueChanged<List<String>> set) {
      if (current.contains(value)) {
        set([...current]..remove(value));
      } else if (current.length < 3) {
        set([...current, value]);
      }
    }

    Future<void> submit() async {
      final text = content.text.trim();
      final name = codename.text.trim();
      if (text.isEmpty || name.isEmpty || submitting.value) return;
      submitting.value = true;
      final api = ref.read(treeholeApiProvider);
      final input = LkmLetterInput(
        content: text,
        category: category.value,
        privacy: privacy.value,
        codename: name,
        moods: moods.value,
        tags: tags.value,
      );
      try {
        final result = editing == null
            ? await api.createLetter(input)
            : await api.editLetter(editing.id, input);
        if (context.mounted) Navigator.of(context).pop(result);
      } catch (failure) {
        if (!context.mounted) return;
        error.value = 'treeholeFailed'.tr();
        showSnackBar('$failure');
      } finally {
        submitting.value = false;
      }
    }

    return SheetScaffold(
      heightFactor: 0.9,
      titleText: editing == null
          ? 'treeholeWriteLetter'.tr()
          : 'treeholeEditLetter'.tr(),
      actions: [
        FilledButton(
          onPressed: submitting.value ? null : submit,
          child: Text('treeholePublish'.tr()),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          TextField(
            controller: content,
            maxLines: 8,
            minLines: 4,
            maxLength: 1000,
            decoration: InputDecoration(
              labelText: 'treeholeLetterContent'.tr(),
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: category.value,
            decoration: InputDecoration(
              labelText: 'treeholeCategory'.tr(),
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final item in treeholeCategories)
                DropdownMenuItem(
                  value: item.key,
                  child: Text('${item.emoji} ${item.labelKey.tr()}'),
                ),
            ],
            onChanged: (value) {
              if (value != null) category.value = value;
            },
          ),
          const SizedBox(height: 16),
          Text('treeholePrivacy'.tr(), style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'public',
                label: Text('treeholePrivacyPublic'.tr()),
              ),
              ButtonSegment(
                value: 'self',
                label: Text('treeholePrivacySelf'.tr()),
              ),
              ButtonSegment(
                value: 'random',
                label: Text('treeholePrivacyRandom'.tr()),
              ),
            ],
            selected: {privacy.value},
            onSelectionChanged: (value) => privacy.value = value.first,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: codename,
            maxLength: 80,
            decoration: InputDecoration(
              labelText: 'treeholeCodename'.tr(),
              helperText: 'treeholeCodenameHint'.tr(),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text('treeholeMoods'.tr(), style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final mood in treeholeMoods)
                FilterChip(
                  label: Text(mood),
                  selected: moods.value.contains(mood),
                  onSelected: (_) => toggle(moods.value, mood, (v) => moods.value = v),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('treeholeTags'.tr(), style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final (key, labelKey) in treeholeTags)
                FilterChip(
                  label: Text(labelKey.tr()),
                  selected: tags.value.contains(key),
                  onSelected: (_) => toggle(tags.value, key, (v) => tags.value = v),
                ),
            ],
          ),
          if (error.value != null) ...[
            const SizedBox(height: 12),
            Text(
              error.value!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
