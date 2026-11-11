import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/community/content_detail_pod.dart';
import 'package:island/community/user_pod.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/content_api.dart';
import 'package:island/core/api/projects_api.dart';
import 'package:island/core/api/qa_api.dart';
import 'package:island/hub/hub_pod.dart';
import 'package:island/route.gr.dart';
import 'package:island/shared/hooks/material_hooks.dart';
import 'package:island/shared/widgets/app_scaffold.dart';

final myQuestionsProvider = FutureProvider.autoDispose
    .family<ApiPage<QaQuestion>, String>((ref, authorId) {
      final session = ref.watch(lkmApiSessionProvider);
      return session.run(
        () => ref.watch(qaApiProvider).questions(authorId: authorId, limit: 50),
      );
    });

final myPostsProvider = FutureProvider.autoDispose
    .family<ApiPage<LkmContentItem>, String>((ref, authorId) {
      final session = ref.watch(lkmApiSessionProvider);
      return session.run(
        () => ref
            .watch(contentApiProvider)
            .items(authorId: authorId, pageSize: 50),
      );
    });

/// Projects are only exposed as one hall list, so "mine" is filtered locally
/// on `applicant_id`.
final myProjectsProvider = FutureProvider.autoDispose
    .family<List<ProjectSummary>, String>((ref, userId) async {
      final session = ref.watch(lkmApiSessionProvider);
      final projects = await session.run(
        () => ref.watch(projectsApiProvider).projects(),
      );
      return projects
          .where((project) => project.applicantId == userId)
          .toList(growable: false);
    });

final myApplicationsProvider =
    FutureProvider.autoDispose<List<ProjectApplication>>((ref) {
      final session = ref.watch(lkmApiSessionProvider);
      return session.run(() => ref.watch(projectsApiProvider).myApplications());
    });

final myFavoritesProvider = FutureProvider.autoDispose<List<LkmSavedItem>>((
  ref,
) async {
  final session = ref.watch(lkmApiSessionProvider);
  final page = await session.run(
    () => ref.watch(contentApiProvider).favorites(limit: 50),
  );
  return page.items;
});

final myHistoryProvider = FutureProvider.autoDispose<List<LkmSavedItem>>((
  ref,
) async {
  final session = ref.watch(lkmApiSessionProvider);
  final page = await session.run(
    () => ref.watch(contentApiProvider).history(limit: 50),
  );
  return page.items;
});

/// The website's `/my/*`: my questions, posts, projects, applications,
/// favorites and reading history.
@RoutePage()
class MyContentScreen extends HookConsumerWidget {
  const MyContentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(lkmMeProvider);
    final controller = useMaterialTabController(initialLength: 5);

    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text('authFlow.myContent'.tr()),
        bottom: TabBar(
          controller: controller,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: 'authFlow.tabQuestions'.tr()),
            Tab(text: 'authFlow.tabPosts'.tr()),
            Tab(text: 'authFlow.tabProjects'.tr()),
            Tab(text: 'authFlow.tabFavorites'.tr()),
            Tab(text: 'authFlow.tabHistory'.tr()),
          ],
        ),
      ),
      body: me.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Message(text: '$error'),
        data: (account) {
          if (account == null) {
            return _Message(text: 'authFlow.signInRequired'.tr());
          }
          return TabBarView(
            controller: controller,
            children: [
              _QuestionsTab(userId: account.id),
              _PostsTab(userId: account.id),
              _ProjectsTab(userId: account.id),
              _FavoritesTab(),
              _HistoryTab(),
            ],
          );
        },
      ),
    );
  }
}

class _QuestionsTab extends ConsumerWidget {
  const _QuestionsTab({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questions = ref.watch(myQuestionsProvider(userId));
    return questions.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _Message(text: '$error'),
      data: (page) {
        if (page.items.isEmpty) return _Message(text: 'authFlow.empty'.tr());
        return ListView.builder(
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
              onTap: () => context.router.push(QaDetailRoute(id: question.id)),
            );
          },
        );
      },
    );
  }
}

class _PostsTab extends ConsumerWidget {
  const _PostsTab({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(myPostsProvider(userId));
    return posts.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _Message(text: '$error'),
      data: (page) {
        if (page.items.isEmpty) return _Message(text: 'authFlow.empty'.tr());
        return ListView.builder(
          itemCount: page.items.length,
          itemBuilder: (context, index) {
            final item = page.items[index];
            return ListTile(
              title: Text(item.title),
              subtitle: Text(
                '${item.contentType} · ${item.likeCount} · '
                '${item.commentCount}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.router.push(ContentDetailRoute(id: item.id)),
            );
          },
        );
      },
    );
  }
}

class _ProjectsTab extends ConsumerWidget {
  const _ProjectsTab({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(myProjectsProvider(userId));
    final applications = ref.watch(myApplicationsProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(myProjectsProvider(userId));
        ref.invalidate(myApplicationsProvider);
      },
      child: ListView(
        children: [
          _SectionHeader(text: 'authFlow.myProjects'.tr()),
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
          _SectionHeader(text: 'authFlow.myApplications'.tr()),
          ...applications.when(
            loading: () => [const _Loading()],
            error: (error, _) => [_Message(text: '$error')],
            data: (items) => items.isEmpty
                ? [_Message(text: 'authFlow.empty'.tr())]
                : [
                    for (final application in items)
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

class _FavoritesTab extends ConsumerWidget {
  const _FavoritesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _savedTab(ref.watch(myFavoritesProvider), 'authFlow.empty'.tr());
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _savedTab(ref.watch(myHistoryProvider), 'authFlow.empty'.tr());
}

Widget _savedTab(AsyncValue<List<LkmSavedItem>> items, String empty) {
  return items.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (error, _) => _Message(text: '$error'),
    data: (list) {
      if (list.isEmpty) return _Message(text: empty);
      return ListView.builder(
        itemCount: list.length,
        itemBuilder: (context, index) {
          final item = list[index];
          return ListTile(
            title: Text(item.title),
            subtitle: Text(item.contentType),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                context.router.push(ContentDetailRoute(id: item.contentId)),
          );
        },
      );
    },
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(child: Text(text, textAlign: TextAlign.center)),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}
