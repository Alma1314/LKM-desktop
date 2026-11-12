import 'package:island/hub/ask_question_dialog.dart';
import 'package:island/hub/hub_detail_screen.dart' show ApplyProjectDialog;
import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/community/compose_sheet.dart';
import 'package:island/community/content_detail_pod.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/columns_api.dart';
import 'package:island/core/api/content_api.dart';
import 'package:island/core/api/projects_api.dart';
import 'package:island/core/api/qa_api.dart';
import 'package:island/hub/hub_pod.dart';
import 'package:island/route.gr.dart';
import 'package:island/shared/hooks/material_hooks.dart';
import 'package:island/shared/widgets/alert.dart';
import 'package:island/shared/widgets/app_scaffold.dart';

/// Content hub aligned with the website's forum sidebar: questions, columns,
/// projects and boards in one place.
@RoutePage()
class HubScreen extends HookConsumerWidget {
  const HubScreen({super.key, @QueryParam('tab') this.initialTab = 0});
  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useMaterialTabController(
      initialLength: 4,
      initialIndex: initialTab.clamp(0, 3),
    );

    void refreshAll() {
      ref.invalidate(qaQuestionsProvider);
      ref.invalidate(columnsProvider);
      ref.invalidate(projectsProvider);
      ref.invalidate(contentBoardsProvider);
    }

    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text('hub.title'.tr()),
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
                icon: const Icon(Symbols.help_center),
                text: 'hub.tabQa'.tr(),
              ),
              Tab(
                icon: const Icon(Symbols.article),
                text: 'hub.tabColumns'.tr(),
              ),
              Tab(
                icon: const Icon(Symbols.rocket_launch),
                text: 'hub.tabProjects'.tr(),
              ),
              Tab(icon: const Icon(Symbols.forum), text: 'hub.tabBoards'.tr()),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: controller,
              children: const [
                _QaTab(),
                _ColumnsTab(),
                _ProjectsTab(),
                _BoardsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AsyncList<T> extends StatelessWidget {
  const _AsyncList({
    required this.value,
    required this.builder,
    required this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (value.hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('hub.loadFailed'.tr()),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: Text('refresh'.tr())),
          ],
        ),
      );
    }
    final data = value.value;
    if (data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return builder(data);
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'hub.empty'.tr(),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- QA

class _QaTab extends HookConsumerWidget {
  const _QaTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = useState<String?>(null);
    final sort = useState('newest');
    final questions = ref.watch(
      qaQuestionsProvider((category: category.value, sort: sort.value)),
    );
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 12, 4),
          child: Row(
            children: [
              SegmentedButton<String?>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: null, label: Text('hub.qaAll'.tr())),
                  ButtonSegment(value: 'help', label: Text('hub.qaHelp'.tr())),
                  ButtonSegment(
                    value: 'volunteer',
                    label: Text('hub.qaVolunteer'.tr()),
                  ),
                ],
                selected: {category.value},
                onSelectionChanged: (value) => category.value = value.first,
              ),
              const Spacer(),
              DropdownButton<String>(
                value: sort.value,
                underline: const SizedBox.shrink(),
                items: [
                  DropdownMenuItem(
                    value: 'newest',
                    child: Text('hub.sortNewest'.tr()),
                  ),
                  DropdownMenuItem(
                    value: 'bounty',
                    child: Text('hub.sortBounty'.tr()),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) sort.value = value;
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'hub.qaHint'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _showAskQuestion(context, ref),
                icon: const Icon(Symbols.add),
                label: Text('hub.askQuestion'.tr()),
              ),
            ],
          ),
        ),
        Expanded(
          child: _AsyncList(
            value: questions,
            onRetry: () => ref.invalidate(
              qaQuestionsProvider((category: category.value, sort: sort.value)),
            ),
            builder: (page) {
              if (page.items.isEmpty) return const _EmptyHint();
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                itemCount: page.items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final q = page.items[index];
                  return _QuestionCard(
                    question: q,
                    onTap: () => context.router.push(QaDetailRoute(id: q.id)),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.question, required this.onTap});

  final QaQuestion question;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final statusColor = switch (question.status) {
      'accepted' => theme.colorScheme.tertiary,
      'closed' => muted,
      _ => theme.colorScheme.primary,
    };
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Badge(
                    text: switch (question.status) {
                      'accepted' => 'hub.qaResolved'.tr(),
                      'closed' => 'hub.qaClosed'.tr(),
                      _ => 'hub.qaOpen'.tr(),
                    },
                    color: statusColor,
                  ),
                  if (question.isOpen && question.urgent)
                    _Badge(
                      text: 'hub.qaUrgent'.tr(),
                      color: theme.colorScheme.error,
                    ),
                  if (question.bountyTotal > 0)
                    _Badge(
                      text: 'hub.qaBounty'.tr(
                        args: ['${question.bountyTotal}'],
                      ),
                      color: theme.colorScheme.secondary,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                question.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${question.authorName} · ${_formatDate(question.createdAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    'hub.qaAnswers'.tr(args: ['${question.answerCount}']),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Columns

class _ColumnsTab extends ConsumerWidget {
  const _ColumnsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final columns = ref.watch(columnsProvider);
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 0),
            child: TextButton.icon(
              onPressed: () => _showApplyColumn(context, ref),
              icon: const Icon(Symbols.draw),
              label: Text('hub.applyColumn'.tr()),
            ),
          ),
        ),
        Expanded(
          child: _AsyncList(
            value: columns,
            onRetry: () => ref.invalidate(columnsProvider),
            builder: (page) {
              if (page.items.isEmpty) return const _EmptyHint();
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                itemCount: page.items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final column = page.items[index];
                  return _ColumnCard(
                    column: column,
                    onTap: () => context.router.push(
                      ColumnDetailRoute(id: column.id, title: column.title),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ColumnCard extends StatelessWidget {
  const _ColumnCard({required this.column, required this.onTap});

  final ColumnSummary column;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.secondaryContainer,
                child: const Icon(Symbols.article),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            column.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (column.isVerified) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Symbols.verified,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      column.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        column.authorName,
                        'hub.columnArticles'.tr(
                          args: ['${column.articleCount}'],
                        ),
                        'hub.columnFollowers'.tr(
                          args: ['${column.followerCount}'],
                        ),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Projects

class _ProjectsTab extends ConsumerWidget {
  const _ProjectsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider);
    return Column(
      children: [
        if (ref.watch(lkmApiSessionProvider).isSignedIn)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const ApplyProjectDialog(),
              ),
              icon: const Icon(Icons.add),
              label: Text('hub.applyProject'.tr()),
            ),
          ),
        Expanded(
          child: _AsyncList(
            value: projects,
            onRetry: () => ref.invalidate(projectsProvider),
            builder: (items) {
              if (items.isEmpty) return const _EmptyHint();
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final project = items[index];
                  return _ProjectCard(
                    project: project,
                    onTap: () =>
                        context.router.push(ProjectDetailRoute(id: project.id)),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onTap});

  final ProjectSummary project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (project.isPinned)
                    _Badge(
                      text: 'hub.projectPinned'.tr(),
                      color: theme.colorScheme.primary,
                    ),
                  if (project.isIncubated)
                    _Badge(
                      text: 'hub.projectIncubated'.tr(),
                      color: theme.colorScheme.tertiary,
                    ),
                  if (project.isRecruiting)
                    _Badge(
                      text: 'hub.projectRecruiting'.tr(),
                      color: theme.colorScheme.secondary,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                project.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                project.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: project.progress.clamp(0, 100) / 100,
                        minHeight: 6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${project.progress}%',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [
                  if (project.applicantName.isNotEmpty) project.applicantName,
                  'hub.projectMembers'.tr(args: ['${project.members.length}']),
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Boards

class _BoardsTab extends ConsumerWidget {
  const _BoardsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boards = ref.watch(contentBoardsProvider);
    return _AsyncList(
      value: boards,
      onRetry: () => ref.invalidate(contentBoardsProvider),
      builder: (items) {
        final visible = items.where((b) => b.isPublic).toList(growable: false);
        if (visible.isEmpty) return const _EmptyHint();
        final byParent = <String?, List<LkmBoard>>{};
        for (final board in visible) {
          byParent.putIfAbsent(board.parentId, () => []).add(board);
        }
        final rows = <({LkmBoard board, int depth})>[];
        void addChildren(String? parentId, int depth) {
          final children = byParent[parentId] ?? const <LkmBoard>[];
          for (final board in children) {
            if (rows.any((r) => r.board.id == board.id)) continue;
            rows.add((board: board, depth: depth));
            addChildren(board.id, depth + 1);
          }
        }

        addChildren(null, 0);
        for (final board in visible) {
          if (!rows.any((r) => r.board.id == board.id)) {
            rows.add((board: board, depth: 0));
          }
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final row = rows[index];
            return Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                contentPadding: EdgeInsets.only(
                  left: 16 + row.depth * 20.0,
                  right: 16,
                ),
                leading: Icon(
                  row.depth == 0
                      ? Symbols.forum
                      : Symbols.subdirectory_arrow_right,
                ),
                title: Text(row.board.title),
                subtitle: row.board.status == 'active'
                    ? null
                    : Text('hub.boardClosed'.tr()),
                trailing: const Icon(Symbols.chevron_right),
                onTap: () => context.router.push(
                  BoardDetailRoute(id: row.board.id, title: row.board.title),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------- Board detail

/// Posts inside one board: sub-board links, 最新/热门 ordering and the
/// follow/compose actions the website's board page offers.
@RoutePage()
class BoardDetailScreen extends HookConsumerWidget {
  const BoardDetailScreen({super.key, required this.id, this.title = ''});

  final String id;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(boardFeedProvider(id));
    final boards = ref.watch(contentBoardsProvider).value ?? const <LkmBoard>[];
    LkmBoard? board;
    for (final candidate in boards) {
      if (candidate.id == id) {
        board = candidate;
        break;
      }
    }
    final children = boards
        .where((entry) => entry.parentId == id)
        .toList(growable: false);
    final signedIn = ref.watch(lkmApiSessionProvider).isSignedIn;
    final following = ref.watch(followingBoardsProvider);
    final isFollowing =
        following.value?.any((entry) => entry.boardId == id) == true;
    final hot = useState(false);
    final toggling = useState(false);
    final theme = Theme.of(context);

    Future<void> toggleFollow() async {
      toggling.value = true;
      try {
        await ref
            .read(lkmApiSessionProvider)
            .run(
              () => ref
                  .read(contentApiProvider)
                  .setBoardFollow(id, follow: !isFollowing),
            );
        ref.invalidate(followingBoardsProvider);
      } catch (error) {
        if (context.mounted) showSnackBar('$error');
      } finally {
        if (context.mounted) toggling.value = false;
      }
    }

    Future<void> compose() async {
      final created = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (_) => LkmComposeSheet(initialBoardId: id),
      );
      if (created == null || !context.mounted) return;
      ref.invalidate(boardFeedProvider(id));
      context.router.push(ContentDetailRoute(id: created));
    }

    final heading = title?.isNotEmpty == true
        ? title!
        : board?.title.isNotEmpty == true
        ? board!.title
        : 'hub.tabBoards'.tr();

    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text(heading),
        actions: [
          if (signedIn)
            IconButton(
              tooltip: isFollowing
                  ? 'hub.boardFollowing'.tr()
                  : 'hub.boardFollow'.tr(),
              onPressed: toggling.value ? null : toggleFollow,
              icon: Icon(
                isFollowing ? Symbols.star : Symbols.star_border,
                color: isFollowing ? theme.colorScheme.primary : null,
              ),
            ),
          if (signedIn)
            IconButton(
              tooltip: 'lkmComposeTitle'.tr(),
              onPressed: compose,
              icon: const Icon(Symbols.edit_square),
            ),
        ],
      ),
      body: Column(
        children: [
          if (children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final child in children)
                      ActionChip(
                        avatar: const Icon(
                          Symbols.subdirectory_arrow_right,
                          size: 18,
                        ),
                        label: Text(child.title),
                        onPressed: () => context.router.push(
                          BoardDetailRoute(id: child.id, title: child.title),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text('hub.sortNewest'.tr()),
                  ),
                  ButtonSegment(value: true, label: Text('feedHot'.tr())),
                ],
                selected: {hot.value},
                onSelectionChanged: (selection) => hot.value = selection.first,
              ),
            ),
          ),
          Expanded(
            child: feed.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('hub.loadFailed'.tr()),
                    const SizedBox(height: 8),
                    Text(
                      '$error',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(boardFeedProvider(id)),
                      child: Text('refresh'.tr()),
                    ),
                  ],
                ),
              ),
              data: (items) {
                if (items.isEmpty) return const _EmptyHint();
                final ordered = orderBoardItems(items, hot: hot.value);
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(boardFeedProvider(id));
                    await ref.read(boardFeedProvider(id).future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                    itemCount: ordered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = ordered[index];
                      return Card(
                        margin: EdgeInsets.zero,
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          title: Row(
                            children: [
                              if (item.isPinned)
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    end: 6,
                                  ),
                                  child: Icon(
                                    Symbols.push_pin,
                                    size: 16,
                                    color: theme.colorScheme.primary,
                                  ),
                                )
                              else if (item.isFeatured)
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    end: 6,
                                  ),
                                  child: Icon(
                                    Symbols.workspace_premium,
                                    size: 16,
                                    color: theme.colorScheme.tertiary,
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  item.title,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              [
                                item.authorName,
                                _formatDate(item.createdAt),
                                'hub.itemComments'.tr(
                                  args: ['${item.commentCount}'],
                                ),
                                'hub.itemViews'.tr(args: ['${item.viewCount}']),
                              ].join(' · '),
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          onTap: () => context.router.push(
                            ContentDetailRoute(id: item.id),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Dialog forms

Future<void> _showAskQuestion(BuildContext context, WidgetRef ref) async {
  final created = await showDialog<bool>(
    context: context,
    builder: (_) => const AskQuestionDialog(),
  );
  if (created == true) {
    ref.invalidate(qaQuestionsProvider);
  }
}

Future<void> _showApplyColumn(BuildContext context, WidgetRef ref) async {
  final applied = await showDialog<bool>(
    context: context,
    builder: (_) => const _ApplyColumnDialog(),
  );
  if (applied == true && context.mounted) {
    showSnackBar('hub.columnApplied'.tr());
  }
}

class _ApplyColumnDialog extends HookConsumerWidget {
  const _ApplyColumnDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = useTextEditingController();
    final description = useTextEditingController();
    final reason = useTextEditingController();
    final busy = useState(false);
    final error = useState<String?>(null);

    Future<void> submit() async {
      if (title.text.trim().isEmpty ||
          description.text.trim().isEmpty ||
          reason.text.trim().isEmpty) {
        error.value = 'hub.askRequired'.tr();
        return;
      }
      busy.value = true;
      error.value = null;
      try {
        await ref
            .read(lkmApiSessionProvider)
            .run(
              () => ref
                  .read(columnsApiProvider)
                  .apply(
                    title: title.text.trim(),
                    description: description.text.trim(),
                    reason: reason.text.trim(),
                  ),
            );
        if (context.mounted) Navigator.of(context).pop(true);
      } catch (err) {
        error.value = err is ApiException
            ? err.message
            : 'hub.actionFailed'.tr();
        busy.value = false;
      }
    }

    return AlertDialog(
      title: Text('hub.applyColumn'.tr()),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: InputDecoration(labelText: 'hub.columnTitle'.tr()),
                maxLength: 80,
              ),
              TextField(
                controller: description,
                decoration: InputDecoration(
                  labelText: 'hub.columnDescription'.tr(),
                ),
                maxLines: 2,
                maxLength: 300,
              ),
              TextField(
                controller: reason,
                decoration: InputDecoration(labelText: 'hub.columnReason'.tr()),
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
          onPressed: busy.value ? null : () => Navigator.of(context).pop(false),
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

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

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

String _formatDate(DateTime date) => date.toIso8601String().substring(0, 10);
