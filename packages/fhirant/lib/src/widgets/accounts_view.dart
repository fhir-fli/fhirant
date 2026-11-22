import 'dart:async';

import 'package:fhirant/src/screens/administration_screen.dart';
import 'package:fhirant/src/state/admin_session.dart';
import 'package:fhirant_server/fhirant_server.dart'
    show Account, ConsoleResult, DeviceConsole;
import 'package:material_ui/material_ui.dart';

/// Every account, and what an administrator does with one: create it,
/// approve the password its owner sent, reset it, switch it off or on,
/// change its role or permissions, unlock it. Each action is one of the
/// server's own routes (`DeviceConsole`), so its rules apply: the last
/// administrator cannot be switched off or demoted, and every change is in
/// the audit trail.
class AccountsView extends StatefulWidget {
  const AccountsView({required this.session, super.key});
  final AdminSession session;

  @override
  State<AccountsView> createState() => _AccountsViewState();
}

class _AccountsViewState extends State<AccountsView> {
  List<Account>? _accounts;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final session = widget.session.session;
    if (session == null) return;
    final console = await widget.session.console();
    final result = await console.accounts(session);
    if (!mounted) return;
    if (result.ok) {
      final list = result.value!
        ..sort((a, b) => a.username.compareTo(b.username));
      setState(() {
        _accounts = list;
        _error = null;
      });
    } else if (result.refusal!.status == 401) {
      await handleRefusal(context, widget.session, result);
    } else {
      setState(() => _error = result.refusal!.message);
    }
  }

  /// Runs one action, says how it went, and reloads the list.
  Future<void> _act(
    Future<ConsoleResult<void>> Function(DeviceConsole console) action,
    String done,
  ) async {
    widget.session.touch();
    final console = await widget.session.console();
    final result = await action(console);
    if (!mounted) return;
    if (result.ok) {
      showMessage(context, done);
    } else {
      await handleRefusal(context, widget.session, result);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _accounts;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-account'),
        onPressed: _create,
        icon: const Icon(Icons.person_add),
        label: const Text('New account'),
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : accounts == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 88),
                    children: [
                      for (final a in accounts)
                        ListTile(
                          key: Key('account-${a.username}'),
                          title: Text(a.username),
                          subtitle: Text(_status(a)),
                          trailing: a.passwordSent && a.awaitingOwner
                              ? const Icon(Icons.mark_email_unread)
                              : null,
                          onTap: () => _open(a),
                        ),
                    ],
                  ),
                ),
    );
  }

  Future<void> _create() async {
    final username = TextEditingController();
    final patient = TextEditingController();
    var role = 'clinician';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('New account'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('new-username'),
                  controller: username,
                  decoration: const InputDecoration(labelText: 'Username'),
                  autocorrect: false,
                ),
                DropdownButtonFormField<String>(
                  key: const Key('new-role'),
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: [
                    for (final r in DeviceConsole.roles)
                      DropdownMenuItem(value: r, child: Text(_roleName(r))),
                  ],
                  onChanged: (r) => setState(() => role = r ?? role),
                ),
                TextField(
                  key: const Key('new-patient'),
                  controller: patient,
                  decoration: const InputDecoration(
                    labelText: 'Patient id (optional)',
                    helperText: "For a patient's own account",
                  ),
                  autocorrect: false,
                ),
                const SizedBox(height: 12),
                const Text(
                  'The account waits 12 hours for its owner. They set '
                  'their own password on this screen, with "I have a new '
                  'account", and show you a code to approve.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('new-ok'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final session = widget.session.session;
    if (session == null) return;
    await _act(
      (c) => c.create(
        session,
        username: username.text.trim(),
        role: role,
        patient: patient.text.trim(),
      ),
      'Account ${username.text.trim()} created. It waits for its owner.',
    );
  }

  Future<void> _open(Account a) async {
    final session = widget.session.session;
    if (session == null) return;
    final choice = await showModalBottomSheet<_Action>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(a.username),
              subtitle: Text(_status(a)),
            ),
            if (a.awaitingOwner && a.passwordSent)
              _actionTile(
                context,
                _Action.approve,
                Icons.verified,
                'Approve the password, with their code',
              ),
            if (a.username != session.username)
              _actionTile(
                context,
                _Action.reset,
                Icons.lock_reset,
                'Reset the password',
              ),
            if (a.locked)
              _actionTile(context, _Action.unlock, Icons.lock_open, 'Unlock'),
            _actionTile(
              context,
              a.active ? _Action.off : _Action.on,
              a.active ? Icons.person_off : Icons.person,
              a.active ? 'Switch off' : 'Switch on',
            ),
            _actionTile(context, _Action.role, Icons.badge, 'Change the role'),
            _actionTile(
              context,
              _Action.scopes,
              Icons.tune,
              'Change the permissions',
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case _Action.approve:
        final code = await _ask('Their code', 'The 8 letters they were shown');
        if (code == null) return;
        await _act(
          (c) => c.approve(session, a.id, code),
          'Approved. ${a.username} can sign in.',
        );
      case _Action.reset:
        if (!await confirmAction(
          context,
          'Reset the password of ${a.username}?',
          'Their password stops working and every session of theirs ends. '
              'They set a new one here and show you a code.',
        )) {
          return;
        }
        await _act(
          (c) => c.reset(session, a.id),
          'Reset. ${a.username} waits for its owner.',
        );
      case _Action.unlock:
        await _act((c) => c.unlock(session, a.id), '${a.username} unlocked.');
      case _Action.off:
        if (!await confirmAction(
          context,
          'Switch off ${a.username}?',
          'They cannot sign in, and every session of theirs ends.',
        )) {
          return;
        }
        await _act(
          (c) => c.setActive(session, a.id, active: false),
          '${a.username} switched off.',
        );
      case _Action.on:
        await _act(
          (c) => c.setActive(session, a.id, active: true),
          '${a.username} switched on.',
        );
      case _Action.role:
        final role = await _pickRole(a.role);
        if (role == null || role == a.role) return;
        await _act(
          (c) => c.setRole(session, a.id, role),
          '${a.username} is now ${_roleName(role)}.',
        );
      case _Action.scopes:
        await _editScopes(a);
    }
  }

  Widget _actionTile(
    BuildContext context,
    _Action action,
    IconData icon,
    String label,
  ) =>
      ListTile(
        key: Key('action-${action.name}'),
        leading: Icon(icon),
        title: Text(label),
        onTap: () => Navigator.of(context).pop(action),
      );

  Future<String?> _ask(String title, String hint) {
    final field = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const Key('ask-field'),
          controller: field,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('ask-ok'),
            onPressed: () => Navigator.of(context).pop(field.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<String?> _pickRole(String current) => showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Role'),
          children: [
            for (final r in DeviceConsole.roles)
              SimpleDialogOption(
                key: Key('role-$r'),
                onPressed: () => Navigator.of(context).pop(r),
                child: Text(
                  r == current ? '${_roleName(r)} (now)' : _roleName(r),
                ),
              ),
          ],
        ),
      );

  /// Permissions are SMART scopes, one per line; empty returns the account
  /// to its role's own.
  Future<void> _editScopes(Account a) async {
    final session = widget.session.session;
    if (session == null) return;
    final field = TextEditingController(text: a.scopes.join('\n'));
    final result = await showDialog<List<String>?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Permissions of ${a.username}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'One per line, as SMART scopes (for example '
                "user/Patient.rs). Leave empty for the role's own.",
              ),
              TextField(
                key: const Key('scopes-field'),
                controller: field,
                maxLines: 8,
                autocorrect: false,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('scopes-ok'),
            onPressed: () => Navigator.of(context).pop(
              field.text
                  .split('\n')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList(),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await _act(
      (c) => c.setScopes(session, a.id, result.isEmpty ? null : result),
      'Permissions of ${a.username} changed.',
    );
  }
}

enum _Action { approve, reset, unlock, off, on, role, scopes }

String _roleName(String role) => switch (role) {
      'admin' => 'Administrator',
      'clinician' => 'Clinician',
      'readonly' => 'Read only',
      _ => role,
    };

/// One line: role, and anything that needs attention. Times in 24-hour form
/// on the phone's clock (clinical apps use the 24-hour clock everywhere).
String _status(Account a) {
  final parts = <String>[_roleName(a.role)];
  if (!a.active) parts.add('switched off');
  if (a.locked) parts.add('locked');
  if (a.awaitingOwner) {
    parts.add(
      a.passwordSent
          ? 'password sent, waiting for your approval'
          : 'waiting for its owner until ${clock(a.awaitingOwnerUntil!)}',
    );
  }
  if (a.patient != null) parts.add('patient ${a.patient}');
  return parts.join(' · ');
}

/// `yyyy-MM-dd HH:mm`, local time.
String clock(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} '
      '${two(l.hour)}:${two(l.minute)}';
}
