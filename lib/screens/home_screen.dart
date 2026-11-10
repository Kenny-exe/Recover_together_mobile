import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/checkin_api.dart';
import '../api/dto.dart';
import '../auth/auth_controller.dart';
import 'chat_screen.dart';
import 'notifications_screen.dart';
import 'partner_screen.dart';
import 'settings_screen.dart';

/// The user's daily home base: streaks, today's check-in, partner status.
/// Data comes from GET /dashboard and GET /checkin/latest.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Dashboard? _dashboard;
  CheckIn? _latest;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final api = context.read<CheckInApi>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results =
          await Future.wait<dynamic>([api.dashboard(), api.latest()]);
      if (!mounted) return;
      setState(() {
        _dashboard = results[0] as Dashboard;
        _latest = results[1] as CheckIn?;
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

  Future<void> _openCheckInSheet() async {
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CheckInSheet(),
    );
    if (submitted == true) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final user = auth.user;
    final dashboard = _dashboard;

    return Scaffold(
      appBar: AppBar(
        title: Text(user == null || user.name.isEmpty
            ? 'RecoverTogether'
            : 'Hi, ${user.name}'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthController>().logout(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
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
                              onPressed: _refresh,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (dashboard != null) ...[
                    _StreakCard(dashboard: dashboard),
                    const SizedBox(height: 12),
                    _TodayCard(latest: _latest, onCheckIn: _openCheckInSheet),
                    const SizedBox(height: 12),
                    _PartnerCard(dashboard: dashboard),
                    const SizedBox(height: 12),
                    _InfoChips(dashboard: dashboard),
                  ],
                ],
              ),
            ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.dashboard});

  final Dashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${dashboard.currentStreak}',
                  style: theme.textTheme.displaySmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('day streak', style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Stat(label: 'Best', value: '${dashboard.bestStreak}'),
                _Stat(
                  label: 'Success rate',
                  value: '${dashboard.successRate.toStringAsFixed(0)}%',
                ),
                _Stat(label: 'Total check-ins', value: '${dashboard.totalCheckIns}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(value, style: theme.textTheme.titleLarge),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.latest, required this.onCheckIn});

  final CheckIn? latest;
  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final checkIn = latest;
    final checkedIn = checkIn != null && checkIn.isToday;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Today', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (checkedIn) ...[
              Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.green),
                  const SizedBox(width: 8),
                  const Text('Checked in today'),
                  const SizedBox(width: 8),
                  Chip(label: Text(checkIn.status?.label ?? '')),
                ],
              ),
              if ((checkIn.note ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    checkIn.note!,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ] else
              FilledButton.icon(
                onPressed: onCheckIn,
                icon: const Icon(Icons.edit_note),
                label: const Text('Check in for today'),
              ),
          ],
        ),
      ),
    );
  }
}

class _PartnerCard extends StatelessWidget {
  const _PartnerCard({required this.dashboard});

  final Dashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.group_outlined),
                const SizedBox(width: 8),
                Text('Partner', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            if (dashboard.hasPartner) ...[
              Text(dashboard.partnerName!,
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('Streak: ${dashboard.partnerCurrentStreak ?? 0}'),
                  const SizedBox(width: 16),
                  if (dashboard.partnerCheckedInToday == true)
                    const Chip(label: Text('Checked in today'))
                  else if ((dashboard.daysSinceLastCheckIn ?? -1) >= 0)
                    Text(
                        '${dashboard.daysSinceLastCheckIn} day(s) since their last check-in'),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ChatScreen()),
                ),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Message partner'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PartnerScreen()),
                ),
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Manage partner'),
              ),
            ] else ...[
              Text(
                'No partner connected yet. Ask your partner to send you a '
                'partner request — you will see their check-ins here.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PartnerScreen()),
                ),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Find a partner'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoChips extends StatelessWidget {
  const _InfoChips({required this.dashboard});

  final Dashboard dashboard;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Chip(
          avatar: const Icon(Icons.forum_outlined, size: 18),
          label: Text('${dashboard.unreadMessages} unread'),
        ),
        Chip(
          avatar: const Icon(Icons.emoji_events_outlined, size: 18),
          label: Text('${dashboard.achievementCount} achievements'),
        ),
      ],
    );
  }
}

IconData _iconFor(CheckInStatus status) => switch (status) {
      CheckInStatus.success => Icons.emoji_events_outlined,
      CheckInStatus.relapse => Icons.restart_alt_outlined,
      CheckInStatus.struggling => Icons.mood_bad_outlined,
      CheckInStatus.strongUrge => Icons.warning_amber_outlined,
      CheckInStatus.needSupport => Icons.volunteer_activism_outlined,
    };

Color _colorFor(CheckInStatus status) => switch (status) {
      CheckInStatus.success => Colors.green.shade600,
      CheckInStatus.relapse => Colors.red.shade600,
      CheckInStatus.struggling => Colors.orange.shade700,
      CheckInStatus.strongUrge => Colors.deepOrange.shade600,
      CheckInStatus.needSupport => Colors.blue.shade600,
    };

/// Bottom sheet for submitting today's check-in. Pops with `true` when a
/// check-in was submitted successfully.
class _CheckInSheet extends StatefulWidget {
  const _CheckInSheet();

  @override
  State<_CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends State<_CheckInSheet> {
  CheckInStatus? _status;
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final status = _status;
    if (status == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<CheckInApi>().submit(status: status, note: _note.text);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('How was today?', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...CheckInStatus.values.map(_buildStatusTile),
          const SizedBox(height: 8),
          TextFormField(
            controller: _note,
            maxLines: 2,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'Anything you want to remember about today',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _status == null || _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Submit check-in'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildStatusTile(CheckInStatus status) {
    final selected = _status == status;
    return ListTile(
      leading: Icon(_iconFor(status), color: _colorFor(status)),
      title: Text(status.label),
      trailing: selected ? const Icon(Icons.check_circle) : null,
      onTap: () => setState(() => _status = status),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tileColor: selected
          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4)
          : null,
    );
  }
}
