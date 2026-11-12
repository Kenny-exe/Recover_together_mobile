import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/api/api_client.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:app/realtime/realtime_lifecycle.dart';
import 'package:app/realtime/realtime_service.dart';

import 'support/mock_adapter.dart';

/// SSE headers for a mocked event-stream response.
Map<String, List<String>> get _sseHeaders => {
      Headers.contentTypeHeader: ['text/event-stream'],
    };

void main() {
  testWidgets('paused closes the stream, resumed reopens it, inactive keeps it',
      (tester) async {
    // A stream that stays open, like a real SSE connection. A fresh
    // single-subscription stream per request — a reused one would throw on
    // the second listen.
    final streamController = StreamController<Uint8List>();
    final adapter = MockAdapter((options) async {
      return ResponseBody(streamController.stream, 200, headers: _sseHeaders);
    });
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;

    final storage = InMemoryTokenStorage()
      ..accessToken = 'access-1'
      ..refreshToken = 'refresh-1';
    final auth = AuthController(
      client: ApiClient(storage: storage, baseUrl: 'http://test'),
      storage: storage,
    )..status = AuthStatus.authenticated;

    final realtime = RealtimeService(
      storage: storage,
      baseUrl: 'http://test',
      dioOverride: dio,
    );
    final lifecycle = RealtimeLifecycle(realtime: realtime, auth: auth);
    lifecycle.attach();

    void dispatch(AppLifecycleState state) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }

    int eventsRequests() =>
        adapter.requests.where((r) => r.path.endsWith('/events')).length;

    // Resumed (foreground) opens the stream.
    dispatch(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(eventsRequests(), 1);

    // Inactive (app switcher) keeps the stream — no new connection.
    dispatch(AppLifecycleState.inactive);
    await tester.pump(const Duration(milliseconds: 100));
    expect(eventsRequests(), 1);

    // Paused (background) closes the stream — FCM covers delivery.
    dispatch(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 100));
    expect(eventsRequests(), 1,
        reason: 'disconnect must not open a replacement connection');

    // Back to the foreground reopens it.
    dispatch(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(eventsRequests(), 2);

    // No session → resumed does not reconnect.
    auth.status = AuthStatus.anonymous;
    dispatch(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 100));
    dispatch(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(eventsRequests(), 2,
        reason: 'an anonymous session must not open the stream');

    lifecycle.detach();
    unawaited(streamController.close());
  });

  testWidgets('a reconnect scheduled by a closed stream is cancelled by '
      'backgrounding and replaced by a single fresh connection on resume',
      (tester) async {
    // The 30-minute server cap closes the stream while the app is
    // foregrounded: the service schedules a reconnect (backoff 1 s). If the
    // app is backgrounded before the timer fires, disconnect must cancel it
    // — otherwise resumed would fire the stale reconnect AND a fresh one.
    final controllers = <StreamController<Uint8List>>[];
    final adapter = MockAdapter((options) async {
      final controller = StreamController<Uint8List>();
      controllers.add(controller);
      return ResponseBody(controller.stream, 200, headers: _sseHeaders);
    });
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;

    final storage = InMemoryTokenStorage()
      ..accessToken = 'access-1'
      ..refreshToken = 'refresh-1';
    final auth = AuthController(
      client: ApiClient(storage: storage, baseUrl: 'http://test'),
      storage: storage,
    )..status = AuthStatus.authenticated;
    final realtime = RealtimeService(
      storage: storage,
      baseUrl: 'http://test',
      dioOverride: dio,
    );
    final lifecycle = RealtimeLifecycle(realtime: realtime, auth: auth);
    lifecycle.attach();

    void dispatch(AppLifecycleState state) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }

    int eventsRequests() =>
        adapter.requests.where((r) => r.path.endsWith('/events')).length;

    dispatch(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(eventsRequests(), 1);

    // Server cap: the stream dies while foregrounded → reconnect scheduled.
    await controllers.first.close();
    await tester.pump(const Duration(milliseconds: 100));
    expect(eventsRequests(), 1, reason: 'the 1 s backoff has not fired yet');

    // Background before the timer fires → the pending reconnect is cancelled.
    dispatch(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 5));
    expect(eventsRequests(), 1,
        reason: 'a cancelled reconnect must not fire while backgrounded');

    // Foreground again: exactly one fresh connection.
    dispatch(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(eventsRequests(), 2);

    // End the session cleanly BEFORE closing the live stream — closing a
    // connected stream would schedule a reconnect that stays pending and
    // fails the test's no-pending-timers invariant.
    realtime.disconnect();
    lifecycle.detach();
    for (final controller in controllers) {
      unawaited(controller.close());
    }
  });
}
