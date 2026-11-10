import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/dto.dart';
import '../api/notification_api.dart';

/// The NotificationType wire names, in display order. SOS_ALERT is always on
/// per the contract (disabling it is a 400).
const _notificationTypes = <(String, String)>[
  ('NEW_MESSAGE', 'New messages'),
  ('SOS_ALERT', 'SOS alerts'),
  ('PARTNER_RELAPSE', 'Partner relapse'),
  ('MISSED_CHECKIN', 'Missed check-in alerts'),
  ('ACHIEVEMENT_UNLOCKED', 'My achievements'),
  ('PARTNER_ACHIEVEMENT', 'Partner achievements'),
  ('DAILY_CHECKIN_REMINDER', 'Daily check-in reminders'),
  ('SUPPORT_REQUEST', 'Support requests'),
];

TimeOfDay? _parseHm(String? value) {
  if (value == null || value.length < 4) return null;
  final parts = value.split(':');
  final h = int.tryParse(parts[0]);
  final m = parts.length > 1 ? int.tryParse(parts[1]) : null;
  if (h == null || m == null) return null;
  return TimeOfDay(hour: h, minute: m);
}

String _formatHm(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

/// Delivery preferences (GET/PUT /notifications/preferences): the global push
/// switch, optional quiet hours on the user's local clock, and per-type push
/// toggles. Push only gates FCM — in-app notifications and SSE always arrive.
class NotificationPrefsScreen extends StatefulWidget {
  const NotificationPrefsScreen({super.key});

  @override
  State<NotificationPrefsScreen> createState() =>
      _NotificationPrefsScreenState();
}

class _NotificationPrefsScreenState extends State<NotificationPrefsScreen> {
  bool _loading = true;
  String? _error;

  bool _pushEnabled = true;
  bool _quietEnabled = false;
  TimeOfDay? _quietStart;
  TimeOfDay? _quietEnd;
  Map<String, bool> _typePrefs = {};

  bool _saving = false;
  bool _dirty = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await context.read<NotificationApi>().preferences();
      if (!mounted) return;
      setState(() {
        _pushEnabled = prefs.pushNotificationsEnabled ?? true;
        _quietEnabled = prefs.quietHoursEnabled ?? false;
        _quietStart = _parseHm(prefs.quietHoursStart);
        _quietEnd = _parseHm(prefs.quietHoursEnd);
        // Keep unknown types so a future backend never loses them on save.
        _typePrefs = {...?prefs.typePreferences};
        _loading = false;
        _dirty = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final initial = isStart ? _quietStart : _quietEnd;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial ?? const TimeOfDay(hour: 22, minute: 0),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _quietStart = picked;
      } else {
        _quietEnd = picked;
      }
      _dirty = true;
      _saveError = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_quietEnabled && (_quietStart == null || _quietEnd == null)) {
      setState(() => _saveError = 'Set both quiet-hours times first');
      return;
    }
    if (_quietEnabled && _quietStart == _quietEnd) {
      setState(() =>
          _saveError = 'Quiet-hours start and end cannot be the same time');
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final saved = await context.read<NotificationApi>().updatePreferences(
            NotificationPreferences(
              pushNotificationsEnabled: _pushEnabled,
              quietHoursEnabled: _quietEnabled,
              quietHoursStart:
                  _quietEnabled && _quietStart != null ? _formatHm(_quietStart!) : null,
              quietHoursEnd:
                  _quietEnabled && _quietEnd != null ? _formatHm(_quietEnd!) : null,
              typePreferences: _typePrefs,
            ),
          );
      if (!mounted) return;
      // Re-sync from the authoritative server response.
      setState(() {
        _pushEnabled = saved.pushNotificationsEnabled ?? true;
        _quietEnabled = saved.quietHoursEnabled ?? false;
        _quietStart = _parseHm(saved.quietHoursStart);
        _quietEnd = _parseHm(saved.quietHoursEnd);
        _typePrefs = {...?saved.typePreferences};
        _saving = false;
        _dirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preferences saved')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Notification settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
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
                else ...[
                  SwitchListTile(
                    title: const Text('Push notifications'),
                    subtitle: const Text(
                        'Deliver notifications to this device while the app '
                        'is in the background'),
                    value: _pushEnabled,
                    onChanged: (v) => setState(() {
                      _pushEnabled = v;
                      _dirty = true;
                    }),
                  ),
                  const Divider(height: 24),
                  SwitchListTile(
                    title: const Text('Quiet hours'),
                    subtitle: const Text(
                        'Mute pushes during these hours (your local clock). '
                        'SOS alerts always come through.'),
                    value: _quietEnabled,
                    onChanged: (v) => setState(() {
                      _quietEnabled = v;
                      _dirty = true;
                      _saveError = null;
                    }),
                  ),
                  if (_quietEnabled) ...[
                    ListTile(
                      leading: const Icon(Icons.bedtime_outlined),
                      title: const Text('Start'),
                      trailing: Text(
                        _quietStart != null
                            ? _quietStart!.format(context)
                            : 'Not set',
                        style: theme.textTheme.titleMedium,
                      ),
                      onTap: () => _pickTime(true),
                    ),
                    ListTile(
                      leading: const Icon(Icons.wb_sunny_outlined),
                      title: const Text('End'),
                      trailing: Text(
                        _quietEnd != null ? _quietEnd!.format(context) : 'Not set',
                        style: theme.textTheme.titleMedium,
                      ),
                      onTap: () => _pickTime(false),
                    ),
                  ],
                  const Divider(height: 24),
                  Text('Notification types', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  for (final (type, label) in _notificationTypes)
                    if (type == 'SOS_ALERT')
                      const SwitchListTile(
                        title: Text('SOS alerts'),
                        subtitle: Text('Always on — cannot be disabled'),
                        value: true,
                        onChanged: null,
                      )
                    else
                      SwitchListTile(
                        title: Text(label),
                        value: _typePrefs[type] ?? true,
                        onChanged: (v) => setState(() {
                          _typePrefs[type] = v;
                          _dirty = true;
                        }),
                      ),
                  if (_saveError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _saveError!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: (_saving || !_dirty) ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: const Text('Save preferences'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'In-app notifications and the live feed always arrive — '
                    'these settings only control pushes to this device.',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
    );
  }
}
