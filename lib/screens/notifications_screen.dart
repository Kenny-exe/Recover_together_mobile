import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/dto.dart';
import '../api/notification_api.dart';
import '../realtime/realtime_service.dart';
import 'notification_prefs_screen.dart';

IconData _iconForType(String? type) => switch (type) {
      'NEW_MESSAGE' => Icons.chat_bubble_outline,
      'SOS_ALERT' => Icons.warning_amber_outlined,
      'PARTNER_RELAPSE' => Icons.restart_alt_outlined,
      'MISSED_CHECKIN' => Icons.event_busy_outlined,
      'ACHIEVEMENT_UNLOCKED' => Icons.emoji_events_outlined,
      'PARTNER_ACHIEVEMENT' => Icons.workspace_premium_outlined,
      'DAILY_CHECKIN_REMINDER' => Icons.notifications_active_outlined,
      'SUPPORT_REQUEST' => Icons.volunteer_activism_outlined,
      _ => Icons.notifications_outlined,
    };

/// The notification inbox: history from GET /notifications (newest-first
/// cursor pages), live arrivals via the SSE `notification` event, and the
/// contract's read/delete actions.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> _items = const []; // newest-first, as served
  int _unread = 0;
  bool _loading = true;
  String? _error;
  bool _loadingMore = false;
  bool _hasMore = false;

  RealtimeService? _realtime;
  void Function(AppNotification)? _previousOnNotification;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    final realtime = _realtime;
    if (realtime != null &&
        realtime.onNotification == _onSseNotification) {
      realtime.onNotification = _previousOnNotification;
    }
    super.dispose();
  }

  void _subscribe() {
    final realtime = context.read<RealtimeService>();
    _realtime = realtime;
    _previousOnNotification = realtime.onNotification;
    realtime.onNotification = _onSseNotification;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<NotificationApi>();
      final itemsFuture = api.list(limit: 20);
      final unreadFuture = api.unreadCount();
      final items = await itemsFuture;
      final unread = await unreadFuture;
      if (!mounted) return;
      setState(() {
        _items = items;
        _unread = unread;
        _hasMore = items.length == 20;
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

  /// SSE `notification` events fire app-wide while the inbox is open — the
  /// same entity can also arrive via FCM push, so deduplicate by id.
  void _onSseNotification(AppNotification notification) {
    if (_items.any((n) => n.id != null && n.id == notification.id)) return;
    if (!mounted) return;
    setState(() {
      _items = [notification, ..._items];
      if (notification.read != true) _unread++;
    });
  }

  Future<void> _markRead(AppNotification notification) async {
    if (notification.read == true || notification.id == null) return;
    try {
      await context.read<NotificationApi>().markRead(notification.id!);
      if (!mounted) return;
      setState(() {
        _items = [
          for (final n in _items)
            if (n.id == notification.id)
              AppNotification(
                id: n.id,
                type: n.type,
                message: n.message,
                read: true,
                createdAt: n.createdAt,
              )
            else
              n,
        ];
        _unread = (_unread - 1).clamp(0, _unread);
      });
    } on ApiException catch (e) {
      _showError(e.message);
    }
  }

  Future<void> _markAllRead() async {
    try {
      await context.read<NotificationApi>().markAllRead();
      if (!mounted) return;
      setState(() {
        _items = [
          for (final n in _items)
            AppNotification(
              id: n.id,
              type: n.type,
              message: n.message,
              read: true,
              createdAt: n.createdAt,
            ),
        ];
        _unread = 0;
      });
    } on ApiException catch (e) {
      _showError(e.message);
    }
  }

  Future<void> _remove(AppNotification notification) async {
    if (notification.id == null) {
      setState(() => _items = _items.where((n) => n != notification).toList());
      return;
    }
    try {
      await context.read<NotificationApi>().remove(notification.id!);
      if (!mounted) return;
      setState(() {
        _items = _items.where((n) => n.id != notification.id).toList();
        if (notification.read != true) {
          _unread = (_unread - 1).clamp(0, _unread);
        }
      });
    } on ApiException catch (e) {
      _showError(e.message);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _items.isEmpty) return;
    // The page is newest-first, so the last item is the oldest loaded one —
    // its id is the exclusive cursor.
    final oldestId = _items.last.id;
    if (oldestId == null) return;
    setState(() => _loadingMore = true);
    try {
      final older =
          await context.read<NotificationApi>().list(limit: 20, beforeId: oldestId);
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...older];
        _hasMore = older.length == 20;
        _loadingMore = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      _showError(e.message);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Notification settings',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const NotificationPrefsScreen()),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                children: [
                  Row(
                    children: [
                      Text(
                        _unread == 0
                            ? 'All caught up'
                            : '$_unread unread',
                        style: theme.textTheme.bodySmall,
                      ),
                      const Spacer(),
                      if (_unread > 0)
                        TextButton.icon(
                          onPressed: _markAllRead,
                          icon: const Icon(Icons.done_all, size: 18),
                          label: const Text('Mark all read'),
                        ),
                    ],
                  ),
                  if (_error != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(_error!),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_items.isEmpty) ...[
                    const SizedBox(height: 48),
                    Icon(Icons.notifications_none,
                        size: 64, color: theme.colorScheme.outline),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        'No notifications yet.',
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        'Check-ins, partner activity and achievements will '
                        'appear here.',
                        style: theme.textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ] else ...[
                    for (final notification in _items)
                      Dismissible(
                        key: ValueKey('notification-${notification.id ?? notification.message}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          color: theme.colorScheme.errorContainer,
                          child: Icon(Icons.delete_outline,
                              color:
                                  theme.colorScheme.onErrorContainer),
                        ),
                        onDismissed: (_) => _remove(notification),
                        child: ListTile(
                          leading: Icon(
                            _iconForType(notification.type),
                            color: notification.type == 'SOS_ALERT'
                                ? theme.colorScheme.error
                                : null,
                          ),
                          title: Text(
                            notification.message,
                            style: notification.read == true
                                ? null
                                : TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                  ),
                          ),
                          subtitle: Text(notification.timestampLabel),
                          trailing: notification.read == true
                              ? null
                              : Container(
                                  key: ValueKey('dot-${notification.id}'),
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                          onTap: () => _markRead(notification),
                        ),
                      ),
                    if (_hasMore)
                      Padding(
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
                                  onPressed: _loadMore,
                                  child: const Text('Load more'),
                                ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}
