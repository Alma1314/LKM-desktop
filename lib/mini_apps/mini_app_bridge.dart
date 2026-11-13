import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_session.dart';
import 'package:island/mini_apps/mini_app_manifest.dart';

/// Only identifies the local namespace; the service authorizes requests.
String? miniAppUserId(String? token) {
  if (token == null) return null;
  try {
    final body = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
    );
    final id = body['user_id'] ?? body['sub'];
    return id is String && id.isNotEmpty ? id : null;
  } catch (_) {
    return null;
  }
}

String miniAppAccountScope(String server, String userId) => sha256
    .convert(utf8.encode(jsonEncode([normalizeApiBase(server), userId])))
    .toString();

/// Official bundled apps receive scoped storage and named, allowlisted requests.
/// Credentials, raw URLs, SQL, and filesystem access are never exposed.
class MiniAppBridge {
  MiniAppBridge({
    required this.app,
    required this.session,
    required this.userId,
    required this.isCurrent,
    required this.read,
    required this.save,
    required this.locale,
    required this.dark,
  });

  final MiniAppManifest app;
  final ApiSession session;
  final String userId;
  final bool Function() isCurrent;
  final Future<String?> Function() read;
  final Future<void> Function(String) save;
  final String locale;
  final bool dark;
  bool _disposed = false;
  static const maxSnapshotBytes = 16 * 1024 * 1024;

  void dispose() => _disposed = true;

  void _check() {
    if (_disposed || !isCurrent()) throw const SessionExpiredException();
  }

  Future<String> call(String method, dynamic arguments) async {
    try {
      _check();
      if (arguments is! List) throw const FormatException();
      Object? data;
      switch (method) {
        case 'context':
          if (arguments.isNotEmpty) throw const FormatException();
          data = {
            'apiVersion': miniAppApiVersion,
            'appId': app.id,
            'version': app.version,
            'userId': userId,
            'locale': locale,
            'dark': dark,
          };
        case 'newId':
          if (arguments.isNotEmpty) throw const FormatException();
          data = const Uuid().v4();
        case 'load':
          if (arguments.isNotEmpty) throw const FormatException();
          data = await read();
        case 'save':
          if (arguments.length != 1 || arguments.single is! String) {
            throw const FormatException();
          }
          final payload = arguments.single as String;
          if (utf8.encode(payload).length > maxSnapshotBytes) {
            throw const FormatException();
          }
          jsonDecode(payload);
          await save(payload);
          data = true;
        case 'request':
          if (arguments.length != 2 ||
              arguments[0] is! String ||
              arguments[1] is! Map) {
            throw const FormatException();
          }
          final endpoint = app.requests[arguments[0]];
          if (endpoint == null) return _error('forbidden');
          final options = Map<String, dynamic>.from(arguments[1] as Map);
          if (options.keys.any((key) => key != 'query' && key != 'body') ||
              (options['query'] != null && options['query'] is! Map)) {
            throw const FormatException();
          }
          final query = options['query'] == null
              ? null
              : Map<String, dynamic>.from(options['query'] as Map);
          final body = options['body'];
          data = await session.run(() {
            _check();
            final client = session.client;
            return switch (endpoint.method) {
              'GET' => client.get(endpoint.path, query: query),
              'POST' => client.post(endpoint.path, body: body, query: query),
              'PUT' => client.put(endpoint.path, body: body, query: query),
              'PATCH' => client.patch(endpoint.path, body: body, query: query),
              'DELETE' => client.delete(
                endpoint.path,
                body: body,
                query: query,
              ),
              _ => throw const FormatException(),
            };
          });
        default:
          throw const FormatException();
      }
      _check();
      return jsonEncode({'ok': true, 'data': data});
    } on SessionExpiredException {
      return _error('session');
    } on FormatException {
      return _error('invalid');
    } on ApiException catch (error) {
      return _error(error.isUnauthenticated ? 'session' : 'sync');
    } on ApiTransportException {
      return _error('offline');
    } catch (_) {
      return _error('storage');
    }
  }

  String _error(String code) => jsonEncode({'ok': false, 'error': code});
}
