import 'package:island/core/api/auth_api.dart';

/// GitHub OAuth needs a loopback HTTP listener; the web build does not have
/// one, so it is not supported there.
Future<LkmAuthResult> runGithubLogin(AuthApi api) =>
    throw UnsupportedError('GitHub OAuth is desktop-only');

Future<bool> runGithubBind(AuthApi api) =>
    throw UnsupportedError('GitHub OAuth is desktop-only');
