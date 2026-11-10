import 'package:flutter_test/flutter_test.dart';

import 'package:app/realtime/realtime_service.dart';

void main() {
  late List<(String, String)> events;
  late SseParser parser;

  setUp(() {
    events = [];
    parser = SseParser(
      onEvent: (event, data) => events.add((event, data)),
    );
  });

  test('ignores keepalive comment lines', () {
    parser.addLine(': keepalive');
    parser.addLine('');
    expect(events, isEmpty);
  });

  test('dispatches event + data on the terminating blank line', () {
    parser
      ..addLine('event: message')
      ..addLine('data: {"id":1,"content":"hi"}')
      ..addLine('');

    expect(events, hasLength(1));
    expect(events.single.$1, 'message');
    expect(events.single.$2, '{"id":1,"content":"hi"}');
  });

  test('data without an event name defaults to event "message"', () {
    parser
      ..addLine('data: hello')
      ..addLine('');

    expect(events.single.$1, 'message');
    expect(events.single.$2, 'hello');
  });

  test('strips exactly one leading space from field values', () {
    parser
      ..addLine('event: connected')
      ..addLine('data: {"user":"k@example.com"}')
      ..addLine('');

    expect(events.single.$1, 'connected');
    expect(events.single.$2, '{"user":"k@example.com"}');
  });

  test('joins multi-line data with newlines', () {
    parser
      ..addLine('data: line one')
      ..addLine('data: line two')
      ..addLine('');

    expect(events.single.$2, 'line one\nline two');
  });

  test('buffers partial events until the blank line', () {
    parser
      ..addLine('event: notification')
      ..addLine('data: {"id":9}')
      ..addLine(': keepalive inside an event') // comments never break events
      ..addLine('');

    expect(events, hasLength(1));
    expect(events.single.$1, 'notification');
    expect(events.single.$2, '{"id":9}');
  });

  test('stray blank lines produce nothing', () {
    parser
      ..addLine('')
      ..addLine('')
      ..addLine('event: message')
      ..addLine('');

    expect(events, hasLength(1));
    expect(events.single.$1, 'message');
    expect(events.single.$2, isEmpty);
  });

  test('a second event after the first starts clean', () {
    parser
      ..addLine('event: message')
      ..addLine('data: first')
      ..addLine('')
      ..addLine('event: notification')
      ..addLine('data: second')
      ..addLine('');

    expect(events, hasLength(2));
    expect(events[0].$1, 'message');
    expect(events[0].$2, 'first');
    expect(events[1].$1, 'notification');
    expect(events[1].$2, 'second');
  });
}
