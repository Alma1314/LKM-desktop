import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

/// Binds the shared authentication surfaces to the host app's client and alert
/// surface.
///
/// The elevation flow never reaches into app state directly: the host owns the
/// authenticated client and how an error is shown, exactly the way the drive
/// takes its client, secret store and task sink through overrides.

/// Authenticated Solar Network client (the host owns auth and construction).
///
/// Only `client.auth` is used today — the elevation challenge — but the seam
/// takes the whole client because the host already builds one for the rest of
/// the app.
final authClientProvider = Provider<SolarNetworkClient>(
  (ref) => throw UnimplementedError(
    'authClientProvider must be overridden by the host app',
  ),
);

/// Surfaces an error to the user (alert, dialog or toast).
typedef AuthErrorReporter = void Function(Object error);

/// Error reporter used when the elevation flow fails.
///
/// Defaults to a no-op so a headless host — or a test — can omit it.
final authErrorReporterProvider = Provider<AuthErrorReporter>(
  (ref) => (error) {},
);
