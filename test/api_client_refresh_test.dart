import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/api/api_client.dart';

import 'support/mock_adapter.dart';

void main() {
  late InMemoryTokenStorage storage;
  late ApiClient client;
  late MockAdapter adapter;

  setUp(() {
    storage = InMemoryTokenStorage()
      ..accessToken = 'stale-access'
      ..refreshToken = 'valid-refresh';
    client = ApiClient(storage: storage, baseUrl: 'http://test');
    adapter = MockAdapter((options) async {
      if (options.method == 'POST' && options.path.endsWith('/auth/refresh')) {
        return jsonBody(const {
          'token': 'new-access',
          'refreshToken': 'new-refresh',
          'tokenType': 'Bearer',
        }, 200);
      }
      if (options.method == 'GET' && options.path.endsWith('/users/me')) {
        final auth = options.headers['Authorization'];
        if (auth == 'Bearer new-access') {
          return jsonBody(const {
            'id': 7,
            'name': 'Kenny',
            'email': 'kenny@example.com',
            'timezone': 'UTC',
            'createdAt': '2026-11-10T10:00:00',
          }, 200);
        }
        return jsonBody(const {
          'timestamp': '2026-11-10T10:00:00',
          'status': 401,
          'message': 'Invalid or expired token',
        }, 401);
      }
      return jsonBody(const {
        'timestamp': '',
        'status': 404,
        'message': 'Resource not found',
      }, 404);
    });
    client.auth.httpClientAdapter = adapter;
    client.api.httpClientAdapter = adapter;
  });

  test('a 401 triggers one silent refresh and replays with the new token',
      () async {
    final res = await client.api.get<dynamic>('/users/me');

    expect(res.statusCode, 200);
    expect(storage.accessToken, 'new-access');
    expect(storage.refreshToken, 'new-refresh');

    final gets =
        adapter.requests.where((r) => r.method == 'GET').toList(growable: false);
    expect(gets.length, 2, reason: 'original request + exactly one replay');
    expect(gets[0].headers['Authorization'], 'Bearer stale-access');
    expect(gets[1].headers['Authorization'], 'Bearer new-access');
  });

  test('a failed silent refresh drops the session and does not replay',
      () async {
    adapter.handler = (options) async {
      if (options.method == 'POST' && options.path.endsWith('/auth/refresh')) {
        return jsonBody(const {
          'timestamp': '',
          'status': 401,
          'message': 'Invalid or expired token',
        }, 401);
      }
      return jsonBody(const {
        'timestamp': '',
        'status': 401,
        'message': 'Invalid or expired token',
      }, 401);
    };

    var sessionExpired = false;
    client.onSessionExpired = () => sessionExpired = true;

    await expectLater(
      client.api.get<dynamic>('/users/me'),
      throwsA(isA<DioException>()),
    );

    expect(sessionExpired, isTrue, reason: 'UI must drop to the login screen');
    expect(storage.accessToken, isNull, reason: 'dead pair must be cleared');
    expect(storage.refreshToken, isNull);
    expect(adapter.requests.length, 2,
        reason: 'original request + refresh attempt, no replay');
  });

  test('a request that already went through one refresh is not retried again',
      () async {
    // Refresh succeeds but the replayed request 401s again — the loop must
    // stop instead of spinning forever.
    adapter.handler = (options) async {
      if (options.method == 'POST' && options.path.endsWith('/auth/refresh')) {
        return jsonBody(const {
          'token': 'new-access',
          'refreshToken': 'new-refresh',
          'tokenType': 'Bearer',
        }, 200);
      }
      return jsonBody(const {
        'timestamp': '',
        'status': 401,
        'message': 'Invalid or expired token',
      }, 401);
    };

    await expectLater(
      client.api.get<dynamic>('/users/me'),
      throwsA(isA<DioException>()),
    );

    final gets =
        adapter.requests.where((r) => r.method == 'GET').toList(growable: false);
    expect(gets.length, 2, reason: 'original + one replay, never a third');
  });
}
