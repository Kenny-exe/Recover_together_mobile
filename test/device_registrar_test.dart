import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/api/device_api.dart';
import 'package:app/push/device_registrar.dart';

import 'support/mock_adapter.dart';

/// Mutable token source for tests.
class StubTokenSource implements PushTokenSource {
  StubTokenSource(this.token);

  String? token;

  @override
  Future<String?> currentToken() async => token;
}

void main() {
  late MockAdapter adapter;
  late StubTokenSource tokenSource;
  late DeviceRegistrar registrar;

  setUp(() {
    adapter = MockAdapter((options) async => jsonBody(const {
          'id': 1,
          'platform': 'ANDROID',
          'tokenPreview': 'fcm…ken',
          'active': true,
        }, 200));
    tokenSource = StubTokenSource('fcm-token-1');
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    registrar = DeviceRegistrar(
      api: DeviceApi(dio),
      tokenSource: tokenSource,
      deviceName: 'Test device',
    );
  });

  test('registers the current token on first call', () async {
    await registrar.registerIfNeeded();

    final request = adapter.requests.single;
    expect(request.path.endsWith('/users/me/devices'), isTrue);
    final body = request.data as Map<String, dynamic>;
    expect(body['platform'], 'ANDROID');
    expect(body['token'], 'fcm-token-1');
    expect(body['deviceName'], 'Test device');
  });

  test('a null token source registers nothing', () async {
    adapter.handler = (options) async {
      fail('no request should be made without a token');
    };

    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    final noopRegistrar = DeviceRegistrar(
      api: DeviceApi(dio),
      tokenSource: NoopPushTokenSource(),
    );

    await noopRegistrar.registerIfNeeded();
    expect(adapter.requests, isEmpty);
  });

  test('the same token is registered only once per session', () async {
    await registrar.registerIfNeeded();
    await registrar.registerIfNeeded();
    await registrar.registerIfNeeded();

    expect(adapter.requests, hasLength(1),
        reason: 'repeated calls with an unchanged token are no-ops');
  });

  test('a changed token re-registers (FCM refresh handoff)', () async {
    await registrar.registerIfNeeded();

    tokenSource.token = 'fcm-token-2';
    await registrar.registerIfNeeded();

    expect(adapter.requests, hasLength(2));
    expect(
      (adapter.requests.last.data as Map<String, dynamic>)['token'],
      'fcm-token-2',
    );
  });

  test('a failed registration is retried on the next call', () async {
    var failing = true;
    adapter.handler = (options) async {
      if (failing) {
        return jsonBody(const {
          'timestamp': '',
          'status': 500,
          'message': 'Internal error',
        }, 500);
      }
      return jsonBody(const {
        'id': 1,
        'platform': 'ANDROID',
        'active': true,
      }, 200);
    };

    await registrar.registerIfNeeded();
    expect(adapter.requests, hasLength(1));

    failing = false;
    await registrar.registerIfNeeded();
    expect(adapter.requests, hasLength(2),
        reason: 'a failed registration is not remembered as done');
  });

  test('reset() re-registers the same token on the next call', () async {
    await registrar.registerIfNeeded();
    registrar.reset();
    await registrar.registerIfNeeded();

    expect(adapter.requests, hasLength(2),
        reason: 'after logout the next login sends a fresh registration');
  });
}
