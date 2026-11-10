import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/api/auth_api.dart';
import 'package:app/api/dto.dart';

import 'support/mock_adapter.dart';

void main() {
  late MockAdapter adapter;
  late AuthApi api;

  setUp(() {
    adapter = MockAdapter((options) async {
      return jsonBody(const {
        'timestamp': '2026-11-10T10:00:00',
        'status': 401,
        'message': 'Invalid email or password',
      }, 401);
    });
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = adapter;
    api = AuthApi(dio);
  });

  test('login parses the contract LoginResponse', () async {
    adapter.handler = (options) async => jsonBody(const {
          'token': 'access-1',
          'refreshToken': 'refresh-1',
          'tokenType': 'Bearer',
        }, 200);

    final res = await api.login(email: 'kenny@example.com', password: 'Secret1!');

    expect(res.token, 'access-1');
    expect(res.refreshToken, 'refresh-1');
    expect(res.tokenType, 'Bearer');

    final body = adapter.requests.single.data as Map<String, dynamic>;
    expect(body['email'], 'kenny@example.com');
    expect(body['password'], 'Secret1!');
  });

  test('login surfaces the contract error envelope message on 401', () async {
    ApiException? ex;
    try {
      await api.login(email: 'kenny@example.com', password: 'wrong');
    } on ApiException catch (e) {
      ex = e;
    }

    expect(ex, isNotNull);
    expect(ex!.status, 401);
    expect(ex.message, 'Invalid email or password');
  });

  test('register posts the RegisterRequest fields and parses UserResponse',
      () async {
    adapter.handler = (options) async => jsonBody(const {
          'id': 7,
          'name': 'Kenny',
          'email': 'kenny@example.com',
          'timezone': 'UTC',
          'createdAt': '2026-11-10T10:00:00',
        }, 200);

    final user = await api.register(
      name: 'Kenny',
      email: 'kenny@example.com',
      password: 'Secret1!',
    );

    expect(user.id, 7);
    expect(user.name, 'Kenny');
    expect(user.email, 'kenny@example.com');
    expect(user.timezone, 'UTC');

    final body = adapter.requests.single.data as Map<String, dynamic>;
    expect(body.keys, containsAll(['name', 'email', 'password']));
  });
}
