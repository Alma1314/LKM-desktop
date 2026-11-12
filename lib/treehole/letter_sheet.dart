import 'package:island/treehole/local_store.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/config.dart';
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
    final local = TreeholeLocalStore(
      ref.watch(sharedPreferencesProvider),
      ref.watch(lkmServerUrlProvider),
    );
    final draft = useMemoized(
      () => editing == null
          ? Map<String, dynamic>.from(local.read()['draft'] as Map? ?? {})
          : <String, dynamic>{},
      [],
    );
    final scheduled = useState<DateTime?>(
      editing?.scheduledAt ?? DateTime.tryParse('${draft['scheduled'] ?? ''}'),
    );
    final sealed = useState<DateTime?>(
      editing?.sealUntil ?? DateTime.tryParse('${draft['sealed'] ?? ''}'),
    );
    final content = useTextEditingController(
      text: editing?.content ?? draft['content'] as String? ?? '',
    );
    final codename = useTextEditingController(
      text:
          editing?.codename ??
          draft['codename'] as String? ??
          randomTreeholeCodename(),
    );
    final category = useState(
      editing?.category ??
          draft['category'] as String? ??
          treeholeCategories.first.key,
    );
    final privacy = useState(
      editing?.privacy ?? draft['privacy'] as String? ?? 'public',
    );
    final moods = useState<List<String>>(
      editing?.moods ?? (draft['moods'] as List?)?.cast<String>() ?? const [],
    );
    final tags = useState<List<String>>(
      editing?.tags ?? (draft['tags'] as List?)?.cast<String>() ?? const [],
    );
    final submitting = useState(false);
    final error = useState<String?>(null);
    final theme = Theme.of(context);

    Future<void> saveDraft() async {
      if (editing != null) return;
      await local.patch('draft', {
        'content': content.text,
        'codename': codename.text,
        'category': category.value,
        'privacy': privacy.value,
        'moods': moods.value,
        'tags': tags.value,
        'scheduled': scheduled.value?.toIso8601String(),
        'sealed': sealed.value?.toIso8601String(),
      });
    }

    useEffect(() {
      content.addListener(saveDraft);
      codename.addListener(saveDraft);
      return () {
        content.removeListener(saveDraft);
        codename.removeListener(saveDraft);
      };
    }, []);
    useEffect(
      () {
        saveDraft();
        return null;
      },
      [
        category.value,
        privacy.value,
        moods.value,
        tags.value,
        scheduled.value,
        sealed.value,
      ],
    );
    Future<void> pickDate(bool schedule) async {
      final now = DateTime.now();
      final date = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: now,
        lastDate: now.add(const Duration(days: 365)),
      );
      if (date == null || !context.mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (time == null || !context.mounted) return;
      final value = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (schedule) {
        scheduled.value = value;
      } else {
        sealed.value = value;
      }
    }

    void toggle(
      List<String> current,
      String value,
      ValueChanged<List<String>> set,
    ) {
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
      if ((scheduled.value != null &&
              !scheduled.value!.isAfter(DateTime.now())) ||
          (sealed.value != null &&
              !sealed.value!.isAfter(scheduled.value ?? DateTime.now()))) {
        error.value = 'migration34.futureTime'.tr();
        return;
      }
      if (local.read()['limit'] != false &&
          DateTime.now().millisecondsSinceEpoch -
                  (local.read()['lastSent'] as int? ?? 0) <
              30000) {
        error.value = 'migration34.cooldown'.tr();
        return;
      }
      submitting.value = true;
      final api = ref.read(treeholeApiProvider);
      final input = LkmLetterInput(
        content: text,
        category: category.value,
        privacy: privacy.value,
        codename: name,
        moods: moods.value,
        tags: tags.value,
        scheduledAt: scheduled.value,
        sealUntil: sealed.value,
      );
      try {
        final result = editing == null
            ? await api.createLetter(input)
            : await api.editLetter(editing.id, input);
        await local.patch('lastSent', DateTime.now().millisecondsSinceEpoch);
        if (editing == null) await local.patch('draft', null);
        if (context.mounted) Navigator.of(context).pop(result);
      } catch (failure) {
        if (!context.mounted) return;
        error.value = 'treeholeFailed'.tr();
        showSnackBar('$failure');
      } finally {
        if (context.mounted) submitting.value = false;
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
          for (final item in [(true, scheduled.value), (false, sealed.value)])
            ListTile(
              title: Text(
                (item.$1 ? 'migration34.scheduled' : 'migration34.sealed').tr(),
              ),
              subtitle: Text(item.$2?.toString() ?? '—'),
              onTap: () => pickDate(item.$1),
              trailing: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  if (item.$1) {
                    scheduled.value = null;
                  } else {
                    sealed.value = null;
                  }
                },
              ),
            ),
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
                  onSelected: (_) =>
                      toggle(moods.value, mood, (v) => moods.value = v),
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
                  onSelected: (_) =>
                      toggle(tags.value, key, (v) => tags.value = v),
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
