import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/auth/login_controller.dart';
import 'package:island/community/user_pod.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/shared/widgets/app_scaffold.dart';

const _identityTags = [
  'student',
  'developer',
  'creator',
  'researcher',
  'other',
];
const _newcomerTasks = ['taskProfile', 'taskFollow', 'taskPost', 'taskRead'];

/// Four-step post-registration wizard, persisted step by step through
/// `/auth/onboarding`. The server only treats "skip" as completed, so the last
/// step saves its data and then calls skip.
@RoutePage()
class OnboardingScreen extends HookConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = useState(1);
    final busy = useState(true);
    final error = useState<String?>(null);
    final info = useState<String?>(null);
    final tags = useState(<String>{});
    final answer = useState<int?>(null);
    final tasks = useState(<String>{});
    final followName = useTextEditingController();
    final loaded = useRef(false);

    useEffect(() {
      if (loaded.value) return null;
      loaded.value = true;
      Future.microtask(() async {
        try {
          final state = await ref.read(authApiProvider).onboarding();
          if (!context.mounted) return;
          if (state.completed) {
            Navigator.of(context).pop();
            return;
          }
          step.value = state.step.clamp(1, 4).toInt();
          final data = state.data;
          final first = data?['1'];
          if (first is Map && first['tags'] is List) {
            tags.value = (first['tags'] as List).whereType<String>().toSet();
          }
          final third = data?['3'];
          if (third is Map && third['answer'] is int)
            answer.value = third['answer'] as int;
          final fourth = data?['4'];
          if (fourth is Map && fourth['tasks'] is List) {
            tasks.value = (fourth['tasks'] as List).whereType<String>().toSet();
          }
        } catch (failure) {
          if (context.mounted) error.value = _describe(failure);
        } finally {
          if (context.mounted) busy.value = false;
        }
      });
      return null;
    }, const []);

    Future<void> run(Future<void> Function() action) async {
      if (busy.value) return;
      busy.value = true;
      error.value = null;
      info.value = null;
      try {
        await action();
      } catch (failure) {
        if (context.mounted) error.value = _describe(failure);
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    Map<String, dynamic> dataFor(int at) => switch (at) {
      1 => {'tags': tags.value.toList()},
      3 => {'answer': answer.value},
      4 => {'tasks': tasks.value.toList()},
      _ => const {},
    };

    Future<void> next() => run(() async {
      final at = step.value;
      await ref.read(authApiProvider).setOnboardingStep(at, dataFor(at));
      if (at >= 4) {
        await ref.read(authApiProvider).skipOnboarding();
        if (context.mounted) Navigator.of(context).pop(true);
        return;
      }
      if (context.mounted) step.value = at + 1;
    });

    Future<void> skip() => run(() async {
      await ref.read(authApiProvider).skipOnboarding();
      if (context.mounted) Navigator.of(context).pop(true);
    });

    Future<void> follow() => run(() async {
      final name = followName.text.trim();
      if (name.isEmpty) return;
      final api = ref.read(usersApiProvider);
      final user = await api.profileByUsername(name);
      await api.setFollow(user.userId, follow: true);
      if (context.mounted) {
        info.value = 'authFlow.followedUser'.tr(args: [user.displayName]);
        followName.clear();
      }
    });

    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text('authFlow.onboardingTitle'.tr()),
        actions: [
          TextButton(
            onPressed: busy.value ? null : skip,
            child: Text('authFlow.skip'.tr()),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(value: step.value / 4),
                const SizedBox(height: 20),
                Text(
                  'authFlow.stepOf'.tr(args: ['${step.value}']),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 12),
                if (step.value == 1)
                  _tagsStep(tags)
                else if (step.value == 2)
                  _followStep(followName, busy.value)
                else if (step.value == 3)
                  _quizStep(answer)
                else
                  _tasksStep(tasks),
                if (info.value != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    info.value!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
                if (error.value != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error.value!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    if (step.value > 1)
                      OutlinedButton(
                        onPressed: busy.value ? null : () => step.value -= 1,
                        child: Text('back'.tr()),
                      ),
                    const Spacer(),
                    if (step.value == 2)
                      OutlinedButton(
                        onPressed: busy.value ? null : follow,
                        child: Text('authFlow.follow'.tr()),
                      ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: busy.value ? null : next,
                      child: Text(
                        (step.value == 4 ? 'authFlow.finish' : 'authFlow.next')
                            .tr(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tagsStep(ValueNotifier<Set<String>> tags) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final tag in _identityTags)
          FilterChip(
            label: Text('authFlow.tag.$tag'.tr()),
            selected: tags.value.contains(tag),
            onSelected: (selected) {
              final next = {...tags.value};
              selected ? next.add(tag) : next.remove(tag);
              tags.value = next;
            },
          ),
      ],
    );
  }

  Widget _followStep(TextEditingController controller, bool busy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('authFlow.followHint'.tr()),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          enabled: !busy,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'authFlow.username'.tr(),
            prefixIcon: const Icon(Icons.person_add_alt_1),
          ),
        ),
      ],
    );
  }

  Widget _quizStep(ValueNotifier<int?> answer) {
    final options = ['polite', 'report', 'ignore'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('authFlow.quizQuestion'.tr()),
        const SizedBox(height: 8),
        for (var i = 0; i < options.length; i++)
          RadioListTile<int>(
            value: i,
            groupValue: answer.value,
            onChanged: (value) => answer.value = value,
            title: Text('authFlow.quiz.$i'.tr()),
          ),
      ],
    );
  }

  Widget _tasksStep(ValueNotifier<Set<String>> tasks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final task in _newcomerTasks)
          CheckboxListTile(
            value: tasks.value.contains(task),
            onChanged: (checked) {
              final next = {...tasks.value};
              (checked ?? false) ? next.add(task) : next.remove(task);
              tasks.value = next;
            },
            title: Text('authFlow.$task'.tr()),
          ),
      ],
    );
  }

  String _describe(Object failure) {
    if (failure is ApiException) return failure.message;
    if (failure is ApiTransportException) return failure.message;
    return '$failure';
  }
}
