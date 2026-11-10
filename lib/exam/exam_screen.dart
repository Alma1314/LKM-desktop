import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/exam_api.dart';
import 'package:island/exam/exam_pod.dart';
import 'package:island/route.gr.dart';
import 'package:island/shared/hooks/material_hooks.dart';
import 'package:island/shared/widgets/alert.dart';
import 'package:island/shared/widgets/app_scaffold.dart';

/// The website's competition hall, backed by `/exam` instead of mock data:
/// competitions, certification exams and the signed-in user's certificates.
@RoutePage()
class ExamHallScreen extends HookConsumerWidget {
  const ExamHallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useMaterialTabController(initialLength: 3);

    void refreshAll() {
      ref.invalidate(examsProvider);
      ref.invalidate(myCertificatesProvider);
    }

    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text('exam.title'.tr()),
        actions: [
          IconButton(
            tooltip: 'refresh'.tr(),
            onPressed: refreshAll,
            icon: const Icon(Symbols.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          TabBar(
            controller: controller,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(
                icon: const Icon(Symbols.trophy),
                text: 'exam.tabCompetitions'.tr(),
              ),
              Tab(
                icon: const Icon(Symbols.verified),
                text: 'exam.tabCertificates'.tr(),
              ),
              Tab(
                icon: const Icon(Symbols.workspace_premium),
                text: 'exam.tabMine'.tr(),
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: controller,
              children: const [
                _ExamList(type: 'competition'),
                _ExamList(type: 'exam'),
                _MyCertificatesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExamList extends ConsumerWidget {
  const _ExamList({required this.type});

  final String type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(examsProvider(type));

    if (value.hasError) {
      return _RetryHint(onRetry: () => ref.invalidate(examsProvider(type)));
    }
    final page = value.value;
    if (page == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (page.items.isEmpty) {
      return Center(
        child: Text(
          'exam.empty'.tr(),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: page.items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final exam = page.items[index];
        return _ExamCard(
          exam: exam,
          onTap: () => context.router.push(ExamDetailRoute(id: exam.id)),
        );
      },
    );
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.exam, required this.onTap});

  final Exam exam;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _statusOf(exam);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      exam.title,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(status: status),
                ],
              ),
              if ((exam.description ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  exam.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _Meta(
                    icon: Symbols.help,
                    label: 'exam.questions'.tr(args: ['${exam.questionCount}']),
                  ),
                  _Meta(
                    icon: Symbols.timer,
                    label: 'exam.timeLimit'.tr(
                      args: ['${exam.timeLimitMin}'],
                    ),
                  ),
                  _Meta(
                    icon: Symbols.star,
                    label: 'exam.difficulty'.tr(args: ['${exam.difficulty}']),
                  ),
                ],
              ),
              if (exam.startsAt != null || exam.endsAt != null) ...[
                const SizedBox(height: 8),
                Text(
                  _window(exam),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MyCertificatesTab extends ConsumerWidget {
  const _MyCertificatesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(lkmApiSessionProvider);
    if (!session.isSignedIn) {
      return Center(child: Text('exam.signInRequired'.tr()));
    }
    final value = ref.watch(myCertificatesProvider);
    if (value.hasError) {
      return _RetryHint(onRetry: () => ref.invalidate(myCertificatesProvider));
    }
    final certificates = value.value;
    if (certificates == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (certificates.isEmpty) {
      return Center(child: Text('exam.noCertificates'.tr()));
    }
    final theme = Theme.of(context);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: certificates.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final cert = certificates[index];
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: Icon(
              Symbols.workspace_premium,
              color: cert.passed ? Colors.amber : theme.colorScheme.error,
            ),
            title: Text(cert.examTitle.isEmpty ? cert.examId : cert.examTitle),
            subtitle: Text(
              'exam.certificateNo'.tr(args: [cert.certNo]),
            ),
            trailing: Text(
              '${cert.score}',
              style: theme.textTheme.titleMedium,
            ),
          ),
        );
      },
    );
  }
}

@RoutePage()
class ExamDetailScreen extends HookConsumerWidget {
  const ExamDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(examDetailProvider(id));
    final theme = Theme.of(context);

    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text('exam.detail'.tr()),
      ),
      body: Builder(
        builder: (context) {
          if (value.hasError) {
            return _RetryHint(
              onRetry: () => ref.invalidate(examDetailProvider(id)),
            );
          }
          final exam = value.value;
          if (exam == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      exam.title,
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(status: _statusOf(exam)),
                ],
              ),
              if ((exam.description ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(exam.description!, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _Meta(
                    icon: Symbols.help,
                    label: 'exam.questions'.tr(
                      args: ['${exam.questionCount}'],
                    ),
                  ),
                  _Meta(
                    icon: Symbols.timer,
                    label: 'exam.timeLimit'.tr(
                      args: ['${exam.timeLimitMin}'],
                    ),
                  ),
                  _Meta(
                    icon: Symbols.flag,
                    label: 'exam.passScore'.tr(args: ['${exam.passScore}']),
                  ),
                  _Meta(
                    icon: Symbols.star,
                    label: 'exam.difficulty'.tr(args: ['${exam.difficulty}']),
                  ),
                ],
              ),
              if (exam.startsAt != null || exam.endsAt != null) ...[
                const SizedBox(height: 12),
                Text(
                  _window(exam),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (exam.unlocksSomething) ...[
                const SizedBox(height: 12),
                Text(
                  'exam.unlock'.tr(
                    args: [
                      [
                        if ((exam.unlockLevel ?? '').isNotEmpty)
                          exam.unlockLevel!,
                        if ((exam.unlockRole ?? '').isNotEmpty)
                          exam.unlockRole!,
                      ].join(' / '),
                    ],
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _StartExamButton(exam: exam),
              if (exam.isCompetition) ...[
                const SizedBox(height: 24),
                Text('exam.leaderboard'.tr(), style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                _Leaderboard(examId: exam.id),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StartExamButton extends HookConsumerWidget {
  const _StartExamButton({required this.exam});

  final Exam exam;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = useState(false);
    final status = _statusOf(exam);
    final open = status == 'open' || status == 'always';

    return FilledButton.icon(
      onPressed: !open || busy.value
          ? null
          : () async {
              final session = ref.read(lkmApiSessionProvider);
              if (!session.isSignedIn) {
                showSnackBar('exam.signInRequired'.tr());
                return;
              }
              busy.value = true;
              try {
                final attempt = await session.run(
                  () => ref.read(examApiProvider).startAttempt(exam.id),
                );
                if (!context.mounted) return;
                await context.router.push(
                  ExamAttemptRoute(attempt: attempt, title: exam.title),
                );
              } on ApiException catch (err) {
                showSnackBar(err.message);
              } catch (_) {
                showSnackBar('exam.actionFailed'.tr());
              } finally {
                busy.value = false;
              }
            },
      icon: busy.value
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Symbols.play_arrow),
      label: Text(open ? 'exam.startExam'.tr() : 'exam.notOpen'.tr()),
    );
  }
}

class _Leaderboard extends ConsumerWidget {
  const _Leaderboard({required this.examId});

  final String examId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(examLeaderboardProvider(examId));
    final theme = Theme.of(context);

    if (value.hasError) {
      return _RetryHint(
        onRetry: () => ref.invalidate(examLeaderboardProvider(examId)),
      );
    }
    final page = value.value;
    if (page == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (page.items.isEmpty) {
      return Text(
        'exam.noLeaderboard'.tr(),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < page.items.length; i++)
            ListTile(
              dense: true,
              leading: SizedBox(
                width: 28,
                child: Text(
                  '${i + 1}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: i < 3 ? Colors.amber : null,
                  ),
                ),
              ),
              title: Text(page.items[i].displayName),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (page.items[i].certified)
                    const Icon(Symbols.verified, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    '${page.items[i].score}',
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (status) {
      'upcoming' => ('exam.upcoming'.tr(), scheme.tertiary),
      'ended' => ('exam.ended'.tr(), scheme.onSurfaceVariant),
      'open' => ('exam.open'.tr(), scheme.primary),
      _ => ('exam.alwaysOpen'.tr(), scheme.secondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _RetryHint extends StatelessWidget {
  const _RetryHint({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('exam.loadFailed'.tr()),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: Text('refresh'.tr())),
        ],
      ),
    );
  }
}

String _statusOf(Exam exam) {
  final now = DateTime.now();
  final starts = exam.startsAt;
  final ends = exam.endsAt;
  if (starts != null && now.isBefore(starts)) return 'upcoming';
  if (ends != null && now.isAfter(ends)) return 'ended';
  if (starts == null && ends == null) return 'always';
  return 'open';
}

String _window(Exam exam) {
  String fmt(DateTime value) =>
      '${value.year}-${_two(value.month)}-${_two(value.day)} '
      '${_two(value.hour)}:${_two(value.minute)}';
  final starts = exam.startsAt;
  final ends = exam.endsAt;
  if (starts != null && ends != null) return '${fmt(starts)} ~ ${fmt(ends)}';
  if (starts != null) return 'exam.startsAt'.tr(args: [fmt(starts)]);
  return 'exam.endsAt'.tr(args: [fmt(ends!)]);
}

String _two(int value) => value.toString().padLeft(2, '0');
