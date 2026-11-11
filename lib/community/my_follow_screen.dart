import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/community/content_detail_pod.dart';
import 'package:island/community/user_pod.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/content_api.dart';
import 'package:island/core/api/users_api.dart';
import 'package:island/route.gr.dart';
import 'package:island/shared/widgets/app_scaffold.dart';

final followingUsersProvider = FutureProvider.autoDispose<List<LkmFollowUser>>((
  ref,
) {
  final session = ref.watch(lkmApiSessionProvider);
  return session.run(() => ref.watch(usersApiProvider).following());
});

final followingBoardsProvider =
    FutureProvider.autoDispose<List<LkmFollowBoard>>((ref) {
      final session = ref.watch(lkmApiSessionProvider);
      return session.run(() => ref.watch(contentApiProvider).followingBoards());
    });

/// The website's `/follow`: followed users and boards in one page.
@RoutePage()
class MyFollowScreen extends ConsumerWidget {
  const MyFollowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(followingUsersProvider);
    final boards = ref.watch(followingBoardsProvider);
    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text('authFlow.myFollowing'.tr()),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(followingUsersProvider);
          ref.invalidate(followingBoardsProvider);
        },
        child: ListView(
          children: [
            _Header(text: 'authFlow.followingUsers'.tr()),
            ...users.when(
              loading: () => [const _Loading()],
              error: (error, _) => [_Error(text: '$error')],
              data: (items) => items.isEmpty
                  ? [_Empty()]
                  : [
                      for (final user in items)
                        ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              user.displayName.isEmpty
                                  ? '?'
                                  : user.displayName.characters.first,
                            ),
                          ),
                          title: Text(user.displayName),
                          trailing: TextButton(
                            onPressed: () async {
                              await ref
                                  .read(usersApiProvider)
                                  .setFollow(user.userId, follow: false);
                              ref.invalidate(followingUsersProvider);
                            },
                            child: Text('authFlow.unfollow'.tr()),
                          ),
                          onTap: () => context.router.push(
                            UserProfileRoute(id: user.userId),
                          ),
                        ),
                    ],
            ),
            _Header(text: 'authFlow.followingBoards'.tr()),
            ...boards.when(
              loading: () => [const _Loading()],
              error: (error, _) => [_Error(text: '$error')],
              data: (items) => items.isEmpty
                  ? [_Empty()]
                  : [
                      for (final board in items)
                        ListTile(
                          leading: const Icon(Icons.forum_outlined),
                          title: Text(board.title),
                          trailing: TextButton(
                            onPressed: () async {
                              await ref
                                  .read(contentApiProvider)
                                  .setBoardFollow(board.boardId, follow: false);
                              ref.invalidate(followingBoardsProvider);
                            },
                            child: Text('authFlow.unfollow'.tr()),
                          ),
                          onTap: () => context.router.push(
                            BoardDetailRoute(id: board.boardId),
                          ),
                        ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(24),
    child: Center(child: CircularProgressIndicator()),
  );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Center(child: Text('authFlow.empty'.tr())),
  );
}

class _Error extends StatelessWidget {
  const _Error({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Center(child: Text(text)),
  );
}
