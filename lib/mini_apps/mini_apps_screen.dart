import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import 'package:island/community/user_pod.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/api_session.dart';
import 'package:island/core/database.dart';
import 'package:island/mini_apps/host/mini_app_host.dart';
import 'package:island/mini_apps/mini_app_bridge.dart';
import 'package:island/mini_apps/mini_app_manifest.dart';

class MiniAppsScreen extends ConsumerWidget {
  const MiniAppsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = context.locale.toLanguageTag();
    return Scaffold(
      appBar: AppBar(title: Text('miniApps.title'.tr())),
      body: ref
          .watch(miniAppCatalogProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => _CatalogError(
              onRetry: () => ref.invalidate(miniAppCatalogProvider),
            ),
            data: (apps) => apps.isEmpty
                ? Center(child: Text('miniApps.empty'.tr()))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: apps.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final app = apps[index];
                      return Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: Text(
                            app.icon,
                            style: const TextStyle(fontSize: 32),
                          ),
                          title: Text(app.name(locale)),
                          subtitle: Text(app.description(locale)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              context.router.pushPath('/mini-apps/${app.id}'),
                        ),
                      );
                    },
                  ),
          ),
    );
  }
}

class MiniAppScreen extends ConsumerWidget {
  const MiniAppScreen({super.key, required this.appId});
  final String appId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(lkmMeProvider);
    final session = ref.watch(lkmApiSessionProvider);
    final userId = miniAppUserId(session.cachedAccessToken);
    final catalog = ref.watch(miniAppCatalogProvider);
    final app = catalog.asData?.value.where((a) => a.id == appId).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          app?.name(context.locale.toLanguageTag()) ?? 'miniApps.title'.tr(),
        ),
      ),
      body: catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _CatalogError(
          onRetry: () => ref.invalidate(miniAppCatalogProvider),
        ),
        data: (_) => app == null
            ? Center(child: Text('miniApps.notFound'.tr()))
            : userId == null
            ? Center(child: Text('miniApps.signIn'.tr()))
            : _MiniAppModule(
                key: ValueKey((
                  app.id,
                  miniAppAccountScope(session.serverUrl, userId),
                  ref.watch(databaseProvider),
                )),
                app: app,
                session: session,
                userId: userId,
              ),
      ),
    );
  }
}

class _CatalogError extends StatelessWidget {
  const _CatalogError({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('miniApps.loadFailed'.tr()),
        TextButton(onPressed: onRetry, child: Text('miniApps.retry'.tr())),
      ],
    ),
  );
}

class _MiniAppModule extends ConsumerStatefulWidget {
  const _MiniAppModule({
    super.key,
    required this.app,
    required this.session,
    required this.userId,
  });
  final MiniAppManifest app;
  final ApiSession session;
  final String userId;
  @override
  ConsumerState<_MiniAppModule> createState() => _MiniAppModuleState();
}

class _MiniAppModuleState extends ConsumerState<_MiniAppModule> {
  late final _controllerName = '${widget.app.id}-${const Uuid().v4()}';
  MiniAppBridge? _bridge;

  @override
  void dispose() {
    _bridge?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    final scope = miniAppAccountScope(widget.session.serverUrl, widget.userId);
    final bridge = _bridge ??= MiniAppBridge(
      app: widget.app,
      session: widget.session,
      userId: widget.userId,
      isCurrent: () =>
          mounted &&
          identical(ref.read(lkmApiSessionProvider), widget.session) &&
          miniAppUserId(widget.session.cachedAccessToken) == widget.userId,
      read: () => db.readMiniApp(widget.app.id, scope),
      save: (payload) => db.saveMiniApp(widget.app.id, scope, payload),
      locale: context.locale.toLanguageTag(),
      dark: Theme.of(context).brightness == Brightness.dark,
    );
    return MiniAppHost(
      controllerName: _controllerName,
      asset: widget.app.asset,
      onMethodCall: bridge.call,
      loadingWidget: const Center(child: CircularProgressIndicator()),
    );
  }
}
