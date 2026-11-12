import 'package:auto_route/auto_route.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/community/content_detail_pod.dart';
import 'package:island/community/my_content_screen.dart'
    show myApplicationsProvider, myProjectsProvider, myQuestionsProvider;
import 'package:island/community/user_pod.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/content_api.dart';
import 'package:island/core/api/projects_api.dart';
import 'package:island/core/api/users_api.dart';
import 'package:island/route.gr.dart';
import 'package:island/shared/hooks/material_hooks.dart';
import 'package:island/shared/widgets/alert.dart';
import 'package:island/shared/widgets/app_scaffold.dart';

/// The profile's post/column tabs narrow the unified content read by type.
final _userContentProvider = FutureProvider.autoDispose
    .family<ApiPage<LkmContentItem>, ({String userId, String type})>((
      ref,
      key,
    ) {
      final session = ref.watch(lkmApiSessionProvider);
      return session.run(
        () => ref.watch(contentApiProvider).items(
          authorId: key.userId,
          contentType: key.type,
          pageSize: 50,
        ),
      );
    });

/// Another account's page: profile plus the follow relation.
@RoutePage()
class UserProfileScreen extends HookConsumerWidget {
  const UserProfileScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider(id));

    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text('account'.tr()),
      ),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorView(
          error: error,
          onRetry: () => ref.invalidate(userProfileProvider(id)),
        ),
        data: (profile) => _ProfileBody(profile: profile),
      ),
    );
  }
}

class _ProfileBody extends HookConsumerWidget {
  const _ProfileBody({required this.profile});

  final LkmUserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = useMaterialTabController(initialLength: 4);
    final signedIn = ref.watch(lkmApiSessionProvider).isSignedIn;
    final me = ref.watch(lkmMeProvider).value;
    final isSelf = me != null && me.id == profile.userId;
    final follow = ref.watch(followProvider(profile.userId));
    final followNotifier = ref.read(followProvider(profile.userId).notifier);

    Future<void> toggleFollow() async {
      try {
        await followNotifier.toggle();
      } catch (error) {
        if (context.mounted) showSnackBar('$error');
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          child: Column(
            children: [
              _Avatar(url: profile.avatar, name: profile.displayName),
              const SizedBox(height: 16),
              Text(
                profile.displayName,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Chip(
                label: Text(profile.role),
                visualDensity: VisualDensity.compact,
              ),
              if (signedIn && !isSelf) ...[
                const SizedBox(height: 16),
                follow.isLoading
                    ? const SizedBox(
                        width: 120,
                        child: LinearProgressIndicator(),
                      )
                    : follow.value == true
                    ? OutlinedButton.icon(
                        onPressed: toggleFollow,
                        icon: const Icon(Icons.check),
                        label: Text('following'.tr()),
                      )
                    : FilledButton.icon(
                        onPressed: toggleFollow,
                        icon: const Icon(Icons.person_add_alt),
                        label: Text('follow'.tr()),
                      ),
              ],
            ],
          ),
        ),
        TabBar(
          controller: controller,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: 'authFlow.tabPosts'.tr()),
            Tab(text: 'authFlow.tabProjects'.tr()),
            Tab(text: 'authFlow.tabQuestions'.tr()),
            Tab(text: 'hub.tabColumns'.tr()),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: controller,
            children: [
              _ProfilePosts(userId: profile.userId),
              _ProfileProjects(userId: profile.userId, isSelf: isSelf),
              _ProfileQuestions(userId: profile.userId),
              _ProfileColumns(userId: profile.userId),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfilePosts extends ConsumerWidget {
  const _ProfilePosts({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(
      _userContentProvider((userId: userId, type: 'discussion')),
    );
    return page.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _Message(text: '$error'),
      data: (page) => page.items.isEmpty
          ? _Message(text: 'authFlow.empty'.tr())
          : ListView.builder(
              itemCount: page.items.length,
              itemBuilder: (context, index) {
                final item = page.items[index];
                return ListTile(
                  title: Text(item.title),
                  subtitle: Text(
                    [item.authorName, _formatDate(item.createdAt)].join(' · '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.router.push(
                    ContentDetailRoute(id: item.id),
                  ),
                );
              },
            ),
    );
  }
}

class _ProfileProjects extends ConsumerWidget {
  const _ProfileProjects({required this.userId, required this.isSelf});

  final String userId;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(myProjectsProvider(userId));
    final AsyncValue<List<ProjectApplication>> applications = isSelf
        ? ref.watch(myApplicationsProvider)
        : const AsyncValue.data(<ProjectApplication>[]);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(myProjectsProvider(userId));
        if (isSelf) ref.invalidate(myApplicationsProvider);
      },
      child: ListView(
        children: [
          ...projects.when(
            loading: () => [const _Loading()],
            error: (error, _) => [_Message(text: '$error')],
            data: (items) => items.isEmpty
                ? [_Message(text: 'authFlow.empty'.tr())]
                : [
                    for (final project in items)
                      ListTile(
                        title: Text(project.title),
                        subtitle: Text(project.summary),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.router.push(
                          ProjectDetailRoute(id: project.id),
                        ),
                      ),
                  ],
          ),
          if (isSelf)
            ...applications.when(
              loading: () => [const _Loading()],
              error: (error, _) => [_Message(text: '$error')],
              data: (items) => [
                for (final application in items)
                  if (application.status != 'approved')
                    ListTile(
                    title: Text(application.title),
                    subtitle: Text(
                      '${application.status} · ${application.summary}',
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ProfileQuestions extends ConsumerWidget {
  const _ProfileQuestions({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questions = ref.watch(myQuestionsProvider(userId));
    return questions.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _Message(text: '$error'),
      data: (page) => page.items.isEmpty
          ? _Message(text: 'authFlow.empty'.tr())
          : ListView.builder(
              itemCount: page.items.length,
              itemBuilder: (context, index) {
                final question = page.items[index];
                return ListTile(
                  title: Text(question.title),
                  subtitle: Text(
                    '${question.status} · ${question.answerCount} '
                    '${'authFlow.answers'.tr()}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      context.router.push(QaDetailRoute(id: question.id)),
                );
              },
            ),
    );
  }
}

class _ProfileColumns extends ConsumerWidget {
  const _ProfileColumns({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(
      _userContentProvider((userId: userId, type: 'column_post')),
    );
    return page.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _Message(text: '$error'),
      data: (page) => page.items.isEmpty
          ? _Message(text: 'authFlow.empty'.tr())
          : ListView.builder(
              itemCount: page.items.length,
              itemBuilder: (context, index) {
                final item = page.items[index];
                return ListTile(
                  title: Text(item.title),
                  subtitle: Text(item.columnTitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.router.push(
                    ContentDetailRoute(id: item.id),
                  ),
                );
              },
            ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(24),
    child: Center(child: CircularProgressIndicator()),
  );
}

String _formatDate(DateTime date) {
  final iso = date.toIso8601String();
  return iso.substring(0, 10);
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.name});

  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = name.isEmpty ? '?' : name.characters.first;
    return CircleAvatar(
      radius: 48,
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      foregroundImage: url == null || url!.isEmpty
          ? null
          : CachedNetworkImageProvider(url!),
      child: Text(
        initial,
        style: theme.textTheme.headlineMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'userNotFound'.tr(),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: Text('feedRetry'.tr())),
          ],
        ),
      ),
    );
  }
}
