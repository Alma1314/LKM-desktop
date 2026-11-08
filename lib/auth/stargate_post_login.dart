import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:island/accounts/account_pod.dart';
import 'package:island/core/network.dart';
import 'package:island/core/services/notify.dart';
import 'package:island/core/websocket.dart';

/// Post-login tasks for a **Solian** session: refresh user info, subscribe to
/// push notifications, connect the websocket, close the login dialog.
///
/// Kept out of `login_content.dart` (which now hosts the LKM challenge login)
/// because only the stargate web-sign-in deep link still calls it; it goes away
/// with the rest of the Solian auth surface.
Future<void> performPostLogin(BuildContext context, WidgetRef ref) async {
  final userNotifier = ref.read(userInfoProvider.notifier);
  await userNotifier.fetchUser();
  if (!context.mounted) return;
  final client = ref.read(solarNetworkClientProvider);
  final wsNotifier = ref.read(websocketStateProvider.notifier);
  await subscribePushNotification(client.dio, context: context);
  wsNotifier.connect();
  if (context.mounted && Navigator.canPop(context)) {
    Navigator.pop(context, true);
  }
}
