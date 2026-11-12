import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';
import 'package:island/community/user_pod.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/points_api.dart';
import 'package:island/core/config.dart';
import 'package:island/hub/hub_pod.dart';

/// Persist the acknowledged question and per-image IDs so image retries reuse
/// the question and idempotent upload IDs, including after restarting the app.
class AskQuestionDialog extends ConsumerWidget {
  const AskQuestionDialog({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(lkmMeProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AlertDialog(
          content: Text('$e'),
          actions: [
            TextButton(
              onPressed: () => ref.invalidate(lkmMeProvider),
              child: Text('retry'.tr()),
            ),
          ],
        ),
        data: (user) => user == null
            ? AlertDialog(content: Text('seriesEditor.signIn'.tr()))
            : _QuestionDraft(
                key: ValueKey('${ref.watch(lkmServerUrlProvider)}:${user.id}'),
                userId: user.id,
              ),
      );
}

class _QuestionDraft extends HookConsumerWidget {
  const _QuestionDraft({super.key, required this.userId});
  final String userId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(sharedPreferencesProvider);
    final key = 'qa-draft:${ref.watch(lkmServerUrlProvider)}:$userId';
    final initial = useMemoized(() {
      try {
        return Map<String, dynamic>.from(
          jsonDecode(prefs.getString(key) ?? '{}') as Map,
        );
      } catch (_) {
        return <String, dynamic>{};
      }
    }, [key]);
    final title = useTextEditingController(text: initial['title'] as String?);
    final situation = useTextEditingController(
      text: initial['situation'] as String?,
    );
    final content = useTextEditingController(
      text: initial['content'] as String?,
    );
    final bounty = useTextEditingController(text: '${initial['bounty'] ?? 0}');
    final people = useState((initial['people'] as int?) ?? 1);
    final days = useState((initial['days'] as int?) ?? 7);
    final category = useState((initial['category'] as String?) ?? 'help');
    final urgent = useState(initial['urgent'] == true);
    final images = useState<List<Map<String, dynamic>>>(
      (initial['images'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
    final questionId = useState(initial['questionId'] as String?);
    final busy = useState(false);
    final error = useState<String?>(null);
    final session = ref.watch(lkmApiSessionProvider);
    final balance = useFuture(
      useMemoized(
        () => session.run(() => PointsApi(session.client).balance()),
        [session],
      ),
    );
    useListenable(bounty);
    Future<void> save() => prefs
        .setString(
          key,
          jsonEncode({
            'title': title.text,
            'situation': situation.text,
            'content': content.text,
            'bounty': bounty.text,
            'people': people.value,
            'days': days.value,
            'category': category.value,
            'urgent': urgent.value,
            'images': images.value,
            'questionId': questionId.value,
          }),
        )
        .then<void>((_) {});
    useEffect(() {
      for (final c in [title, situation, content, bounty]) {
        c.addListener(save);
      }
      return () {
        for (final c in [title, situation, content, bounty]) {
          c.removeListener(save);
        }
      };
    }, [key]);
    useEffect(
      () {
        save();
        return null;
      },
      [
        people.value,
        days.value,
        category.value,
        urgent.value,
        images.value,
        questionId.value,
      ],
    );
    Future<void> pick() async {
      try {
        final files = await FilePicker.pickFiles(type: FileType.image);
        if (!context.mounted) return;
        if (images.value.length + files.length > 6)
          throw StateError('migration34.sixImages'.tr());
        for (final file in files) {
          if (await file.xFile.length() > 20 * 1024 * 1024)
            throw StateError('migration34.imageSize'.tr());
        }
        if (!context.mounted) return;
        images.value = [
          ...images.value,
          for (final f in files)
            {
              'path': f.xFile.path,
              'name': f.name,
              'id': const Uuid().v4(),
              'done': false,
            },
        ];
      } catch (e) {
        if (context.mounted) error.value = '$e';
      }
    }

    Future<void> submit() async {
      if (busy.value) return;
      busy.value = true;
      error.value = null;
      try {
        if (questionId.value == null) {
          final amount = int.tryParse(bounty.text);
          if (title.text.trim().isEmpty ||
              situation.text.trim().isEmpty ||
              content.text.trim().isEmpty ||
              amount == null ||
              amount < 0 ||
              amount * people.value > 1000 ||
              (urgent.value && (amount == 0 || days.value != 7)))
            throw StateError('migration34.invalidBounty'.tr());
          final available = await session.run(
            () => PointsApi(session.client).balance(),
          );
          if (amount * people.value > available.balance)
            throw StateError('migration34.balanceLow'.tr());
          final q = await session.run(
            () => ref
                .read(qaApiProvider)
                .ask(
                  title: title.text.trim(),
                  situation: situation.text.trim(),
                  content: content.text.trim(),
                  category: category.value,
                  bountyPeople: people.value,
                  bountyPerPerson: amount,
                  bountyDays: days.value,
                  urgent: urgent.value,
                ),
          );
          questionId.value = q.id;
          await save();
        }
        for (final image in images.value) {
          if (image['done'] == true) continue;
          final bytes = await File(image['path'] as String).readAsBytes();
          await session.run(
            () => ref
                .read(qaApiProvider)
                .uploadImage(
                  questionId.value!,
                  imageId: image['id'] as String,
                  bytes: bytes,
                  filename: image['name'] as String,
                ),
          );
          image['done'] = true;
          await save();
        }
        await prefs.remove(key);
        if (context.mounted) Navigator.pop(context, true);
      } catch (e) {
        if (context.mounted) error.value = '$e';
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    Widget field(
      TextEditingController c,
      String label, {
      int lines = 1,
      int? max,
    }) => TextField(
      controller: c,
      enabled: !busy.value && questionId.value == null,
      maxLines: lines,
      maxLength: max,
      decoration: InputDecoration(labelText: label),
    );
    return PopScope(
      canPop: !busy.value,
      child: AlertDialog(
        title: Text('hub.askQuestion'.tr()),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (questionId.value != null)
                  Text('migration34.resumeImages'.tr()),
                IgnorePointer(
                  ignoring: busy.value || questionId.value != null,
                  child: Column(
                    children: [
                      field(title, 'hub.askTitle'.tr(), max: 200),
                      field(
                        situation,
                        'hub.askSituation'.tr(),
                        lines: 2,
                        max: 5000,
                      ),
                      field(
                        content,
                        'hub.askContent'.tr(),
                        lines: 5,
                        max: 20000,
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: category.value,
                        items: [
                          for (final c in ['help', 'volunteer'])
                            DropdownMenuItem(
                              value: c,
                              child: Text(
                                (c == 'help' ? 'hub.qaHelp' : 'hub.qaVolunteer')
                                    .tr(),
                              ),
                            ),
                        ],
                        onChanged: (v) => category.value = v!,
                      ),
                      field(bounty, 'hub.bountyPerPerson'.tr()),
                      DropdownButtonFormField<int>(
                        initialValue: people.value,
                        decoration: InputDecoration(
                          labelText: 'migration34.people'.tr(),
                        ),
                        items: [
                          for (var n = 1; n <= 10; n++)
                            DropdownMenuItem(value: n, child: Text('$n')),
                        ],
                        onChanged: (v) => people.value = v!,
                      ),
                      DropdownButtonFormField<int>(
                        initialValue: days.value,
                        decoration: InputDecoration(
                          labelText: 'migration34.days'.tr(),
                        ),
                        items: [
                          for (final n in [7, 14, 30, 90])
                            DropdownMenuItem(value: n, child: Text('$n')),
                        ],
                        onChanged: (v) => days.value = v!,
                      ),
                      Text(
                        '${'migration34.total'.tr()}: ${(int.tryParse(bounty.text) ?? 0) * people.value} / ${'migration34.balance'.tr()}: ${balance.data?.balance ?? '—'}',
                      ),
                      SwitchListTile(
                        title: Text('hub.askUrgent'.tr()),
                        value: urgent.value,
                        onChanged: (v) {
                          urgent.value = v;
                          if (v) days.value = 7;
                        },
                      ),
                    ],
                  ),
                ),
                for (final image in images.value)
                  ListTile(
                    title: Text(image['name'] as String),
                    leading: Icon(
                      image['done'] == true ? Icons.check : Icons.image,
                    ),
                    trailing: image['done'] != true
                        ? IconButton(
                            onPressed: busy.value
                                ? null
                                : () =>
                                      images.value = [...images.value]
                                        ..remove(image),
                            icon: const Icon(Icons.close),
                          )
                        : null,
                  ),
                TextButton.icon(
                  onPressed: busy.value || images.value.length >= 6
                      ? null
                      : pick,
                  icon: const Icon(Icons.add_photo_alternate),
                  label: Text('migration34.sixImages'.tr()),
                ),
                if (error.value != null)
                  Text(
                    error.value!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy.value ? null : () => Navigator.pop(context, false),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            onPressed: busy.value ? null : submit,
            child: Text('hub.submit'.tr()),
          ),
        ],
      ),
    );
  }
}
