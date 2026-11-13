import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:island/mini_apps/mini_apps_screen.dart';

/// Preserve existing /starhope links while using the shared mini app host.
@RoutePage()
class StarHopeScreen extends StatelessWidget {
  const StarHopeScreen({super.key});

  @override
  Widget build(BuildContext context) => const MiniAppScreen(appId: 'starhope');
}
