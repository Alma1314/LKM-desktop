import 'package:auto_route/auto_route.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/community/user_pod.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/users_api.dart';
import 'package:island/shared/widgets/alert.dart';
import 'package:island/shared/widgets/app_scaffold.dart';

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

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.profile});

  final LkmUserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
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

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: _Avatar(url: profile.avatar, name: profile.displayName),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            profile.displayName,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Chip(
            label: Text(profile.role),
            visualDensity: VisualDensity.compact,
          ),
        ),
        if (signedIn && !isSelf) ...[
          const SizedBox(height: 20),
          Center(
            child: follow.isLoading
                ? const SizedBox(width: 120, child: LinearProgressIndicator())
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
          ),
        ],
      ],
    );
  }
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
