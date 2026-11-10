import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/dto.dart';
import '../api/partner_api.dart';

/// Connect with a recovery partner: search by exact email, send/receive
/// requests, accept/reject, and unpair. Data comes from GET /partner/current,
/// /partner/requests and /partner/sent.
class PartnerScreen extends StatefulWidget {
  const PartnerScreen({super.key});

  @override
  State<PartnerScreen> createState() => _PartnerScreenState();
}

class _PartnerScreenState extends State<PartnerScreen> {
  Partner? _partner;
  List<PartnerRequest> _incoming = const [];
  List<SentRequest> _sent = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final api = context.read<PartnerApi>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        api.current(),
        api.incomingRequests(),
        api.sentRequests(),
      ]);
      if (!mounted) return;
      setState(() {
        _partner = results[0] as Partner?;
        _incoming = results[1] as List<PartnerRequest>;
        _sent = results[2] as List<SentRequest>;
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

  Future<void> _unpair() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unpair from partner?'),
        content: const Text(
          'You will no longer see each other\'s check-ins or receive each '
          'other\'s notifications. You can always connect with a new partner '
          'afterwards.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Unpair'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    try {
      await context.read<PartnerApi>().unpair();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
    _refresh();
  }

  Future<void> _answer(PartnerRequest request, {required bool accept}) async {
    final api = context.read<PartnerApi>();
    try {
      if (accept) {
        await api.accept(request.id!);
      } else {
        await api.reject(request.id!);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Partner')),
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
                  else ...[
                    if (_partner != null) ...[
                      Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              _partner!.name.isEmpty
                                  ? '?'
                                  : _partner!.name[0].toUpperCase(),
                            ),
                          ),
                          title: Text(
                            _partner!.name,
                            style: theme.textTheme.titleLarge,
                          ),
                          subtitle: Text(_partner!.email),
                          trailing: IconButton(
                            tooltip: 'Unpair',
                            icon: const Icon(Icons.link_off),
                            onPressed: _unpair,
                          ),
                        ),
                      ),
                    ] else
                      _SearchCard(onSent: _refresh),
                    if (_incoming.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('Incoming requests',
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (final request in _incoming)
                              ListTile(
                                leading: const Icon(Icons.person_add_alt_1),
                                title: Text(request.senderName),
                                subtitle: const Text(
                                    'Wants to be your recovery partner'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton(
                                      onPressed: () =>
                                          _answer(request, accept: false),
                                      child: const Text('Reject'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          _answer(request, accept: true),
                                      child: const Text('Accept'),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (_sent.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('Sent requests',
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (final request in _sent)
                              ListTile(
                                leading: const Icon(Icons.send_outlined),
                                title: Text(request.receiverName),
                                trailing: const Chip(label: Text('Pending')),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
    );
  }
}

/// The no-partner state: search by exact email and invite the match.
class _SearchCard extends StatefulWidget {
  const _SearchCard({required this.onSent});

  final VoidCallback onSent;

  @override
  State<_SearchCard> createState() => _SearchCardState();
}

class _SearchCardState extends State<_SearchCard> {
  final _email = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  UserResponse? _found;
  bool _searching = false;
  bool _sending = false;
  String? _searchError;
  String? _sendError;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (!_formKey.currentState!.validate() || _searching) return;
    setState(() {
      _searching = true;
      _searchError = null;
      _sendError = null;
      _found = null;
    });
    try {
      final user =
          await context.read<PartnerApi>().searchByEmail(_email.text.trim());
      if (!mounted) return;
      setState(() {
        _found = user;
        _searching = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _searchError = e.message;
        _searching = false;
      });
    }
  }

  Future<void> _send() async {
    final found = _found;
    if (found == null || _sending) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await context.read<PartnerApi>().sendRequest(receiverId: found.id);
      if (!mounted) return;
      setState(() {
        _found = null;
        _sending = false;
      });
      _email.clear();
      widget.onSent();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sendError = e.message;
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Connect with a partner',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Recovery partners see each other\'s check-ins and get '
                'notified about relapses, milestones and missed check-ins.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                decoration: InputDecoration(
                  labelText: 'Partner\'s email',
                  prefixIcon: const Icon(Icons.email_outlined),
                  suffixIcon: IconButton(
                    tooltip: 'Search',
                    icon: _searching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.search),
                    onPressed: _search,
                  ),
                ),
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                onFieldSubmitted: (_) => _search(),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'Email is required';
                  final ok =
                      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t);
                  return ok ? null : 'Enter a valid email';
                },
              ),
              if (_searchError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _searchError!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_found != null) ...[
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Text(
                      _found!.name.isEmpty ? '?' : _found!.name[0].toUpperCase(),
                    ),
                  ),
                  title: Text(_found!.name),
                  subtitle: Text(_found!.email),
                ),
                FilledButton.icon(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.person_add_alt_1),
                  label: const Text('Send partner request'),
                ),
                if (_sendError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _sendError!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
