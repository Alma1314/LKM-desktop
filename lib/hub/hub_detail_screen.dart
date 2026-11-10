import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/community/user_pod.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/qa_api.dart';
import 'package:island/hub/hub_pod.dart';
import 'package:island/shared/widgets/alert.dart';
import 'package:island/shared/widgets/app_scaffold.dart';
import 'package:island/shared/widgets/content/markdown.dart';

/// One question: body, answers and the asker's accept/close actions.
@RoutePage()
class QaDetailScreen extends HookConsumerWidget {
  const QaDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final question = ref.watch(qaQuestionProvider(id));
    final signedIn = ref.watch(lkmApiSessionProvider).isSignedIn;
    final myId = ref.watch(lkmMeProvider).value?.id;

    Future<void> mutate(Future<void> Function() action) async {
      try {
        await ref.read(lkmApiSessionProvider).run(action);
        ref.invalidate(qaQuestionProvider(id));
      } catch (err) {
        if (context.mounted) {
          showSnackBar(err is ApiException ? err.message : 'hub.actionFailed'.tr());
        }
      }
    }

    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text('hub.question'.tr()),
      ),
      body: question.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('hub.loadFailed'.tr()),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(qaQuestionProvider(id)),
                child: Text('refresh'.tr()),
              ),
            ],
          ),
        ),
        data: (q) {
          final theme = Theme.of(context);
          final muted = theme.colorScheme.onSurfaceVariant;
          final isAsker = myId != null && myId == q.authorId;
          final acceptedCount = q.answers.where((a) => a.isAccepted).length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _StatusChip(status: q.status),
                  if (q.isOpen && q.urgent)
                    _Chip(
                      text: 'hub.qaUrgent'.tr(),
                      color: theme.colorScheme.error,
                    ),
                  if (q.bountyTotal > 0)
                    _Chip(
                      text: 'hub.qaBounty'.tr(args: ['${q.bountyTotal}']),
                      color: theme.colorScheme.secondary,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                q.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                [
                  q.authorName,
                  _formatDateTime(q.createdAt),
                  'hub.qaAnswers'.tr(args: ['${q.answers.length}']),
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
              if (q.bountyExpiresAt != null) ...[
                const SizedBox(height: 6),
                Text(
                  'hub.bountyExpires'.tr(
                    args: [_formatDateTime(q.bountyExpiresAt!)],
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _SectionBox(child: Text(q.situation)),
              if (q.content.isNotEmpty) ...[
                const SizedBox(height: 8),
                _SectionBox(child: MarkdownTextContent(content: q.content)),
              ],
              if (isAsker && q.isOpen) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: () => mutate(
                      () async => ref.read(qaApiProvider).close(q.id),
                    ),
                    icon: const Icon(Symbols.lock),
                    label: Text('hub.closeQuestion'.tr()),
                  ),
                ),
              ],
              const Divider(height: 32),
              Text(
                'hub.qaAnswers'.tr(args: ['${q.answers.length}']),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              if (q.answers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'hub.noAnswers'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
              for (final answer in q.answers)
                _AnswerCard(
                  answer: answer,
                  canAccept:
                      isAsker &&
                      q.isOpen &&
                      !answer.isAccepted &&
                      answer.authorId != q.authorId &&
                      acceptedCount < q.bountyPeople,
                  onAccept: () => mutate(
                    () async =>
                        ref.read(qaApiProvider).accept(q.id, answer.id),
                  ),
                ),
              if (signedIn && !isAsker && q.isOpen) ...[
                const SizedBox(height: 16),
                _AnswerComposer(
                  onSubmit: (text) => mutate(
                    () async => ref.read(qaApiProvider).answer(q.id, text),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({
    required this.answer,
    required this.canAccept,
    required this.onAccept,
  });

  final QaAnswer answer;
  final bool canAccept;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: answer.isAccepted
          ? theme.colorScheme.tertiaryContainer.withValues(alpha: 0.35)
          : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (answer.isAccepted)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      Symbols.check_circle,
                      size: 16,
                      color: theme.colorScheme.tertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'hub.accepted'.tr(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  ],
                ),
              ),
            Text(answer.content),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${answer.authorName} · ${_formatDateTime(answer.createdAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
                if (canAccept)
                  TextButton(
                    onPressed: onAccept,
                    child: Text('hub.accept'.tr()),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AnswerComposer extends HookWidget {
  const _AnswerComposer({required this.onSubmit});

  final Future<void> Function(String text) onSubmit;

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController();
    final busy = useState(false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TextField(
          controller: controller,
          minLines: 3,
          maxLines: 8,
          decoration: InputDecoration(
            labelText: 'hub.answerPlaceholder'.tr(),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: busy.value
              ? null
              : () async {
                  final text = controller.text.trim();
                  if (text.isEmpty) return;
                  busy.value = true;
                  await onSubmit(text);
                  busy.value = false;
                },
          child: Text('hub.submitAnswer'.tr()),
        ),
      ],
    );
  }
}

/// One column and its published posts.
@RoutePage()
class ColumnDetailScreen extends HookConsumerWidget {
  const ColumnDetailScreen({
    super.key,
    required this.id,
    this.title,
  });

  final String id;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(columnPostsProvider(id));
    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text(title?.isNotEmpty == true ? title! : 'hub.tabColumns'.tr()),
      ),
      body: posts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('hub.loadFailed'.tr()),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(columnPostsProvider(id)),
                child: Text('refresh'.tr()),
              ),
            ],
          ),
        ),
        data: (page) {
          if (page.items.isEmpty) {
            return Center(child: Text('hub.empty'.tr()));
          }
          final theme = Theme.of(context);
          final muted = theme.colorScheme.onSurfaceVariant;
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            itemCount: page.items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final post = page.items[index];
              return Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  title: Text(
                    post.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      [
                        if (post.publishedAt != null)
                          _formatDateTime(post.publishedAt!),
                        'hub.itemViews'.tr(args: ['${post.viewCount}']),
                        'hub.itemLikes'.tr(args: ['${post.likeCount}']),
                        'hub.itemComments'.tr(
                          args: ['${post.commentCount}'],
                        ),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (post.summary.isNotEmpty) ...[
                      Text(
                        post.summary,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    MarkdownTextContent(content: post.content),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// One project's showcase page plus the incubation application.
@RoutePage()
class ProjectDetailScreen extends HookConsumerWidget {
  const ProjectDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectProvider(id));
    final signedIn = ref.watch(lkmApiSessionProvider).isSignedIn;
    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text('hub.projectDetail'.tr()),
        actions: [
          if (signedIn)
            IconButton(
              tooltip: 'hub.applyProject'.tr(),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const _ApplyProjectDialog(),
              ),
              icon: const Icon(Symbols.rocket_launch),
            ),
        ],
      ),
      body: project.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('hub.loadFailed'.tr()),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(projectProvider(id)),
                child: Text('refresh'.tr()),
              ),
            ],
          ),
        ),
        data: (p) {
          final theme = Theme.of(context);
          final muted = theme.colorScheme.onSurfaceVariant;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (p.isIncubated)
                    _Chip(
                      text: 'hub.projectIncubated'.tr(),
                      color: theme.colorScheme.tertiary,
                    ),
                  if (p.isRecruiting)
                    _Chip(
                      text: 'hub.projectRecruiting'.tr(),
                      color: theme.colorScheme.secondary,
                    ),
                  for (final tag in p.tags)
                    _Chip(
                      text: tag,
                      color: theme.colorScheme.primary,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                p.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                p.summary,
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: p.progress.clamp(0, 100) / 100,
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('${p.progress}%'),
                ],
              ),
              const SizedBox(height: 16),
              _TextBlock(title: 'hub.projectBackground', text: p.background),
              _TextBlock(title: 'hub.projectGoals', text: p.goals),
              _TextBlock(title: 'hub.projectDescription', text: p.description),
              _TextBlock(title: 'hub.projectRequirements', text: p.requirements),
              _TextBlock(title: 'hub.projectTeam', text: p.teamIntro),
              if (p.recruitingRoles.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'hub.projectRoles'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final role in p.recruitingRoles)
                      Chip(
                        label: Text(role),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
              if (p.members.isNotEmpty) ...[
                const Divider(height: 32),
                Text(
                  'hub.projectMembersTitle'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                for (final member in p.members)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: CircleAvatar(
                      child: Text(
                        member.displayName.isEmpty
                            ? '?'
                            : member.displayName.characters.first,
                      ),
                    ),
                    title: Text(member.displayName),
                    subtitle: Text(member.roleInProject),
                  ),
              ],
              if (p.reports.isNotEmpty) ...[
                const Divider(height: 32),
                Text(
                  'hub.projectReports'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                for (final report in p.reports)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ExpansionTile(
                      title: Text(report.title),
                      subtitle: Text(report.date),
                      childrenPadding: const EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        16,
                      ),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [Text(report.content)],
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TextBlock extends StatelessWidget {
  const _TextBlock({required this.title, required this.text});

  final String title;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final body = text;
    if (body == null || body.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.tr(),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(body),
        ],
      ),
    );
  }
}

class _ApplyProjectDialog extends HookConsumerWidget {
  const _ApplyProjectDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = useTextEditingController();
    final summary = useTextEditingController();
    final description = useTextEditingController();
    final busy = useState(false);
    final error = useState<String?>(null);

    Future<void> submit() async {
      if (title.text.trim().isEmpty ||
          summary.text.trim().isEmpty ||
          description.text.trim().isEmpty) {
        error.value = 'hub.askRequired'.tr();
        return;
      }
      busy.value = true;
      error.value = null;
      try {
        await ref.read(lkmApiSessionProvider).run(
          () => ref.read(projectsApiProvider).apply(
            title: title.text.trim(),
            summary: summary.text.trim(),
            description: description.text.trim(),
          ),
        );
        if (context.mounted) Navigator.of(context).pop();
      } catch (err) {
        error.value = err is ApiException ? err.message : 'hub.actionFailed'.tr();
        busy.value = false;
      }
    }

    return AlertDialog(
      title: Text('hub.applyProject'.tr()),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: InputDecoration(
                  labelText: 'hub.projectTitle'.tr(),
                ),
                maxLength: 100,
              ),
              TextField(
                controller: summary,
                decoration: InputDecoration(
                  labelText: 'hub.projectSummary'.tr(),
                ),
                maxLines: 2,
                maxLength: 300,
              ),
              TextField(
                controller: description,
                decoration: InputDecoration(
                  labelText: 'hub.projectDescription'.tr(),
                ),
                maxLines: 3,
                maxLength: 500,
              ),
              if (error.value != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    error.value!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy.value ? null : () => Navigator.of(context).pop(),
          child: Text('cancel'.tr()),
        ),
        FilledButton(
          onPressed: busy.value ? null : submit,
          child: Text('hub.submit'.tr()),
        ),
      ],
    );
  }
}

class _SectionBox extends StatelessWidget {
  const _SectionBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: DefaultTextStyle.merge(
        style: theme.textTheme.bodyMedium ?? const TextStyle(),
        child: child,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (text, color) = switch (status) {
      'accepted' => ('hub.qaResolved'.tr(), theme.colorScheme.tertiary),
      'closed' => ('hub.qaClosed'.tr(), theme.colorScheme.onSurfaceVariant),
      _ => ('hub.qaOpen'.tr(), theme.colorScheme.primary),
    };
    return _Chip(text: text, color: color);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

String _formatDateTime(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
