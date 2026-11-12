import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';
import 'package:webf/webf.dart';

import 'package:island/community/user_pod.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/api_session.dart';
import 'package:island/core/database.dart';
import 'package:island/core/webf/webf_module_host.dart';
import 'package:island/starhope/starhope_bridge.dart';

@RoutePage()
class StarHopeScreen extends ConsumerWidget {
  const StarHopeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch login/logout invalidation without blocking local use on /auth/me.
    ref.watch(lkmMeProvider);
    final session = ref.watch(lkmApiSessionProvider);
    final id = starHopeUserId(session.cachedAccessToken);
    return Scaffold(
      appBar: AppBar(title: const Text('StarHope')),
      body: id == null
          ? Center(child: Text('starHope.signIn'.tr()))
          : _StarHopeModule(
              key: ValueKey((
                starHopeScope(session.serverUrl, id),
                ref.watch(databaseProvider),
              )),
              session: session,
              userId: id,
            ),
    );
  }
}

class _StarHopeModule extends ConsumerStatefulWidget {
  const _StarHopeModule({
    super.key,
    required this.session,
    required this.userId,
  });
  final ApiSession session;
  final String userId;
  @override
  ConsumerState<_StarHopeModule> createState() => _StarHopeModuleState();
}

class _StarHopeModuleState extends ConsumerState<_StarHopeModule> {
  final _controllerName = 'starhope-${const Uuid().v4()}';
  final _bundle = WebFBundle.fromUrl(
    'assets:///assets/webf/starhope/index.html',
  );
  StarHopeBridge? _bridge;

  @override
  void dispose() {
    _bridge?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    final scope = starHopeScope(widget.session.serverUrl, widget.userId);
    return WebfModuleHost(
      controllerName: _controllerName,
      bundle: _bundle,
      loadingWidget: const Center(child: CircularProgressIndicator()),
      createController: () {
        final bridge = StarHopeBridge(
          session: widget.session,
          userId: widget.userId,
          isCurrent: () =>
              mounted &&
              identical(ref.read(lkmApiSessionProvider), widget.session) &&
              starHopeUserId(widget.session.cachedAccessToken) == widget.userId,
          read: () => db.readStarHope(scope),
          save: (payload) => db.saveStarHope(scope, payload),
          locale: context.locale.toLanguageTag(),
          dark: Theme.of(context).brightness == Brightness.dark,
        );
        _bridge?.dispose();
        _bridge = bridge;
        final controller = WebFController();
        controller.javascriptChannel.onMethodCall = bridge.call;
        // No navigation delegate: WebF cancels page navigation by default.
        return controller;
      },
    );
  }
}
