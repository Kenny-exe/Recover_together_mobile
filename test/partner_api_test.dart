import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/api/dto.dart';
import 'package:app/api/partner_api.dart';

import 'support/mock_adapter.dart';

void main() {
  late MockAdapter adapter;
  late PartnerApi api;

  setUp(() {
    adapter = MockAdapter((options) async {
      return jsonBody(const {
        'timestamp': '',
        'status': 404,
        'message': 'Resource not found',
      }, 404);
    });
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = adapter;
    api = PartnerApi(dio);
  });

  test('searchByEmail parses a match and passes the email query', () async {
    adapter.handler = (options) async => jsonBody(const {
          'id': 5,
          'name': 'Sam',
          'email': 'sam@example.com',
          'timezone': 'UTC',
        }, 200);

    final user = await api.searchByEmail('sam@example.com');

    expect(user, isNotNull);
    expect(user!.id, 5);
    expect(user.email, 'sam@example.com');
    final request = adapter.requests.single;
    expect(request.path.endsWith('/users/search'), isTrue);
    expect(request.uri, contains('email=sam%40example.com'));
  });

  test('searchByEmail returns null on 404 (no user matches)', () async {
    final user = await api.searchByEmail('nobody@example.com');
    expect(user, isNull);
  });

  test('current parses the partner', () async {
    adapter.handler = (options) async => jsonBody(const {
          'id': 5,
          'name': 'Sam',
          'email': 'sam@example.com',
        }, 200);

    final partner = await api.current();

    expect(partner, isNotNull);
    expect(partner!.name, 'Sam');
  });

  test('current returns null on 404 (no partner yet)', () async {
    final partner = await api.current();
    expect(partner, isNull);
  });

  test('incomingRequests parses the contract array with status mapping',
      () async {
    adapter.handler = (options) async => jsonBody(const [
          {
            'id': 11,
            'senderName': 'Sam',
            'receiverName': 'Kenny',
            'status': 'PENDING',
            'createdAt': '2026-11-10T09:00:00',
          },
        ], 200);

    final requests = await api.incomingRequests();

    expect(requests, hasLength(1));
    expect(requests.single.id, 11);
    expect(requests.single.senderName, 'Sam');
    expect(requests.single.status, PartnerRequestStatus.pending);
  });

  test('sentRequests parses the receiver-only shape', () async {
    adapter.handler = (options) async => jsonBody(const [
          {'requestId': 12, 'receiverName': 'Alex'},
        ], 200);

    final sent = await api.sentRequests();

    expect(sent, hasLength(1));
    expect(sent.single.requestId, 12);
    expect(sent.single.receiverName, 'Alex');
  });

  test('sendRequest posts to the receiver path', () async {
    adapter.handler = (options) async =>
        jsonBody({'message': 'Partner request sent'}, 200);

    await api.sendRequest(receiverId: 5);

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path.endsWith('/partner/request/5'), isTrue);
  });

  test('accept, reject and unpair hit their contract paths', () async {
    adapter.handler = (options) async =>
        jsonBody({'message': 'Partner request accepted'}, 200);

    await api.accept(11);
    await api.reject(12);
    await api.unpair();

    final paths =
        adapter.requests.map((r) => '${r.method} ${r.path}').toList();
    expect(
      paths.where((p) => p.contains('/partner/')),
      containsAllInOrder([
        endsWith('/partner/accept/11'),
        endsWith('/partner/reject/12'),
        endsWith('/partner/unpair'),
      ]),
    );
  });

  test('sending to an invalid target surfaces the envelope message',
      () async {
    adapter.handler = (options) async => jsonBody(const {
          'timestamp': '',
          'status': 400,
          'message': 'You already have a partner',
        }, 400);

    ApiException? ex;
    try {
      await api.sendRequest(receiverId: 5);
    } on ApiException catch (e) {
      ex = e;
    }

    expect(ex, isNotNull);
    expect(ex!.message, 'You already have a partner');
  });
}
