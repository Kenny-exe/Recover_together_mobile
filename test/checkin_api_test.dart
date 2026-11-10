import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/api/checkin_api.dart';
import 'package:app/api/dto.dart';

import 'support/mock_adapter.dart';

void main() {
  late MockAdapter adapter;
  late CheckInApi api;

  setUp(() {
    adapter = MockAdapter((options) async {
      return jsonBody(const {
        'timestamp': '2026-11-10T10:00:00',
        'status': 404,
        'message': 'Resource not found',
      }, 404);
    });
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = adapter;
    api = CheckInApi(dio);
  });

  test('dashboard parses all contract fields', () async {
    adapter.handler = (options) async => jsonBody(const {
          'currentStreak': 12,
          'bestStreak': 20,
          'totalCheckIns': 45,
          'successCount': 40,
          'relapseCount': 5,
          'successRate': 88.9,
          'unreadMessages': 2,
          'partnerName': 'Sam',
          'partnerCurrentStreak': 7,
          'partnerBestStreak': 15,
          'partnerLastSeen': '2026-11-10T09:30:00',
          'partnerCheckedInToday': true,
          'daysSinceLastCheckIn': 0,
          'achievementCount': 6,
        }, 200);

    final d = await api.dashboard();

    expect(d.currentStreak, 12);
    expect(d.bestStreak, 20);
    expect(d.successRate, 88.9);
    expect(d.unreadMessages, 2);
    expect(d.hasPartner, isTrue);
    expect(d.partnerName, 'Sam');
    expect(d.partnerCurrentStreak, 7);
    expect(d.partnerCheckedInToday, isTrue);
    expect(d.daysSinceLastCheckIn, 0);
    expect(d.achievementCount, 6);
  });

  test('dashboard tolerates a missing partner section', () async {
    adapter.handler = (options) async => jsonBody(const {
          'currentStreak': 0,
          'bestStreak': 0,
          'totalCheckIns': 0,
          'successCount': 0,
          'relapseCount': 0,
          'successRate': 0.0,
          'unreadMessages': 0,
          'achievementCount': 0,
        }, 200);

    final d = await api.dashboard();

    expect(d.hasPartner, isFalse);
    expect(d.partnerName, isNull);
    expect(d.partnerCheckedInToday, isNull);
    expect(d.currentStreak, 0);
    expect(d.achievementCount, 0);
  });

  test('latest returns null on 404 (never checked in)', () async {
    final checkIn = await api.latest();

    expect(checkIn, isNull);
    expect(adapter.requests.single.path.endsWith('/checkin/latest'), isTrue);
  });

  test('latest parses a check-in', () async {
    adapter.handler = (options) async => jsonBody(const {
          'id': 42,
          'date': '2026-11-10',
          'status': 'SUCCESS',
          'note': 'Good day',
          'createdAt': '2026-11-10T08:00:00',
        }, 200);

    final c = await api.latest();

    expect(c, isNotNull);
    expect(c!.id, 42);
    expect(c.date, '2026-11-10');
    expect(c.status, CheckInStatus.success);
    expect(c.note, 'Good day');
  });

  test('latest surfaces non-404 errors as ApiException', () async {
    adapter.handler = (options) async => jsonBody(const {
          'timestamp': '',
          'status': 401,
          'message': 'Invalid or expired token',
        }, 401);

    ApiException? ex;
    try {
      await api.latest();
    } on ApiException catch (e) {
      ex = e;
    }

    expect(ex, isNotNull);
    expect(ex!.status, 401);
  });

  test('submit posts the wire enum and trims the note', () async {
    adapter.handler = (options) async =>
        jsonBody({'message': 'Check-in submitted successfully'}, 200);

    await api.submit(status: CheckInStatus.strongUrge, note: '  rough evening  ');

    final body = adapter.requests.single.data as Map<String, dynamic>;
    expect(body['status'], 'STRONG_URGE');
    expect(body['note'], 'rough evening');
  });

  test('submit omits the note field when blank', () async {
    adapter.handler = (options) async =>
        jsonBody({'message': 'Check-in submitted successfully'}, 200);

    await api.submit(status: CheckInStatus.success, note: '   ');

    final body = adapter.requests.single.data as Map<String, dynamic>;
    expect(body.containsKey('note'), isFalse);
  });

  test('submit surfaces the duplicate envelope message on 400', () async {
    adapter.handler = (options) async => jsonBody(const {
          'timestamp': '2026-11-10T10:00:00',
          'status': 400,
          'message': 'You have already checked in today',
        }, 400);

    ApiException? ex;
    try {
      await api.submit(status: CheckInStatus.success);
    } on ApiException catch (e) {
      ex = e;
    }

    expect(ex, isNotNull);
    expect(ex!.message, 'You have already checked in today');
  });
}
