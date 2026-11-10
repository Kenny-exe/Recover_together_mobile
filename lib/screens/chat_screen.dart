import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/dto.dart';
import '../api/message_api.dart';
import '../api/partner_api.dart';
import '../auth/auth_controller.dart';
import '../realtime/realtime_service.dart';

/// The 1:1 conversation with the connected partner. History loads from
/// GET /messages/conversation/{partnerId} (one cursor page), live messages
/// arrive via the SSE `message` event, and sent messages re-sync from the
/// server because the send endpoint returns only a confirmation.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  Partner? _partner;
  List<ChatMessage> _messages = const []; // newest-first
  bool _loading = true;
  String? _error;
  bool _loadingMore = false;
  bool _hasMore = false;
  final _input = TextEditingController();
  bool _sending = false;

  RealtimeService? _realtime;
  void Function(ChatMessage)? _previousOnMessage;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    final realtime = _realtime;
    if (realtime != null && realtime.onMessage == _onSseMessage) {
      realtime.onMessage = _previousOnMessage;
    }
    _input.dispose();
    super.dispose();
  }

  void _subscribe() {
    final realtime = context.read<RealtimeService>();
    _realtime = realtime;
    _previousOnMessage = realtime.onMessage;
    realtime.onMessage = _onSseMessage;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final partnerApi = context.read<PartnerApi>();
      final messageApi = context.read<MessageApi>();

      final partner = await partnerApi.current();
      if (partner == null) {
        if (!mounted) return;
        setState(() {
          _partner = null;
          _messages = const [];
          _loading = false;
        });
        return;
      }

      final messages =
          await messageApi.conversation(partner.id!, limit: 50);
      if (!mounted) return;
      setState(() {
        _partner = partner;
        _messages = messages.reversed.toList(); // chronological → newest-first
        _hasMore = messages.length == 50;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  /// SSE `message` events are published to the receiver only, so any event
  /// that arrives while this screen is open belongs to this thread.
  void _onSseMessage(ChatMessage message) {
    // Deduplicate by entity id, per the contract's realtime conventions.
    if (_messages.any((m) => m.id != null && m.id == message.id)) return;
    if (!mounted) return;
    setState(() => _messages = [message, ..._messages]);
  }

  Future<void> _loadOlder() async {
    final partner = _partner;
    if (partner == null || _loadingMore || !_hasMore) return;
    final oldestId = _messages
        .map((m) => m.id)
        .whereType<int>()
        .fold<int?>(null, (a, b) => a == null || b < a ? b : a);
    if (oldestId == null) return;

    setState(() => _loadingMore = true);
    try {
      final messageApi = context.read<MessageApi>();
      final older = await messageApi.conversation(
        partner.id!,
        limit: 50,
        beforeId: oldestId,
      );
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, ...older.reversed];
        _hasMore = older.length == 50;
        _loadingMore = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _send() async {
    final partner = _partner;
    final content = _input.text.trim();
    if (partner == null || content.isEmpty || _sending) return;
    if (content.length > 1000) return; // contract cap; field also enforces

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final messageApi = context.read<MessageApi>();
      await messageApi.send(partnerId: partner.id!, content: content);
      _input.clear();
      // The send response carries no message body, and the sender receives no
      // SSE echo — re-sync the thread from the server.
      final messages = await messageApi.conversation(partner.id!, limit: 50);
      if (!mounted) return;
      setState(() {
        _messages = messages.reversed.toList();
        _hasMore = messages.length == 50;
        _sending = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final myName = context.watch<AuthController>().user?.name ?? '';
    final partner = _partner;

    return Scaffold(
      appBar: AppBar(
        title: Text(_loading ? 'Chat' : partner?.name ?? 'Chat'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : partner == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Connect with a partner first — their chat opens here '
                      'once you are paired.',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Column(
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(child: Text(_error!)),
                            TextButton(
                              onPressed: _load,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        reverse: true, // index 0 = newest, pinned to the bottom
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (_hasMore && index == _messages.length) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Center(
                                child: _loadingMore
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : OutlinedButton(
                                        onPressed: _loadOlder,
                                        child: const Text('Load older'),
                                      ),
                              ),
                            );
                          }
                          final message = _messages[index];
                          final isMine = message.senderName == myName;
                          final time = message.timeLabel;
                          return Align(
                            alignment: isMine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.75,
                              ),
                              decoration: BoxDecoration(
                                color: isMine
                                    ? theme.colorScheme.primaryContainer
                                    : theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(14),
                                  topRight: const Radius.circular(14),
                                  bottomLeft: Radius.circular(isMine
                                      ? 14
                                      : 2), // tail on the sender's side
                                  bottomRight: Radius.circular(
                                      isMine ? 2 : 14),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(message.content),
                                  if (time.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        time,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _input,
                                maxLength: 1000, // contract cap
                                minLines: 1,
                                maxLines: 4,
                                decoration: const InputDecoration(
                                  hintText: 'Message your partner…',
                                  border: InputBorder.none,
                                  counterText: '',
                                ),
                                onSubmitted: (_) => _send(),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Send',
                              icon: _sending
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.send),
                              onPressed: _sending ? null : _send,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
