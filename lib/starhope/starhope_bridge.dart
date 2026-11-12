import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_session.dart';

/// Only identifies the local namespace; authorization is always done by the API.
String? starHopeUserId(String? token) {
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

String starHopeScope(String server, String userId) => sha256
    .convert(utf8.encode(jsonEncode([normalizeApiBase(server), userId])))
    .toString();

/// Asset-only WebF bridge. No token, arbitrary URL, SQL or filesystem access.
class StarHopeBridge {
  StarHopeBridge({
    required this.session,
    required this.userId,
    required this.isCurrent,
    required this.read,
    required this.save,
    required this.locale,
    required this.dark,
  });

  final ApiSession session;
  final String userId;
  final bool Function() isCurrent;
  final Future<String?> Function() read;
  final Future<void> Function(String) save;
  final String locale;
  final bool dark;
  bool _disposed = false;
  static const entities = {'questions', 'folders', 'sessions'};
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
          data = {'userId': userId, 'locale': locale, 'dark': dark};
        case 'newId':
          data = const Uuid().v4();
        case 'load':
          data = await read();
        case 'save':
          if (arguments.length != 1 || arguments.single is! String) {
            throw const FormatException();
          }
          final payload = arguments.single as String;
          if (utf8.encode(payload).length > maxSnapshotBytes) {
            throw const FormatException();
          }
          final parsed = jsonDecode(payload);
          if (parsed is! Map ||
              parsed['version'] != 1 ||
              parsed['entries'] is! Map ||
              parsed['cursors'] is! Map) {
            throw const FormatException();
          }
          await save(payload);
          data = true;
        case 'pull':
        case 'push':
          if (arguments.isEmpty || !entities.contains(arguments.first)) {
            throw const FormatException();
          }
          final entity = arguments.first as String;
          if (method == 'pull') {
            final since = arguments.length > 1 ? arguments[1] : null;
            if (since != null &&
                (since is! String || DateTime.tryParse(since) == null)) {
              throw const FormatException();
            }
            data = await session.run(() {
              _check();
              return session.client.getObject(
                '/starhope/$entity',
                query: {'since': ?since},
              );
            });
          } else {
            if (arguments.length != 3 ||
                arguments[1] is! List ||
                arguments[2] is! List ||
                (arguments[1] as List).length > 500 ||
                (arguments[2] as List).length > 500) {
              throw const FormatException();
            }
            data = await session.run(() {
              _check();
              return session.client.post(
                '/starhope/$entity/sync',
                body: {'upserts': arguments[1], 'deletes': arguments[2]},
              );
            });
          }
        default:
          throw const FormatException();
      }
      _check();
      return jsonEncode({'ok': true, 'data': data});
    } on SessionExpiredException {
      return jsonEncode({'ok': false, 'error': 'session'});
    } on FormatException {
      return jsonEncode({'ok': false, 'error': 'invalid'});
    } on ApiException catch (error) {
      return jsonEncode({
        'ok': false,
        'error': error.isUnauthenticated ? 'session' : 'sync',
      });
    } on ApiTransportException {
      return jsonEncode({'ok': false, 'error': 'offline'});
    } catch (_) {
      return jsonEncode({'ok': false, 'error': 'storage'});
    }
  }
}
