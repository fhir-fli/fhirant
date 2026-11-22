import 'dart:async';

import 'package:fhirant/src/screens/administration_screen.dart';
import 'package:fhirant/src/state/admin_session.dart';
import 'package:fhirant/src/widgets/accounts_view.dart' show clock;
import 'package:fhirant_server/fhirant_server.dart'
    show ConsoleResult, DeviceConsole, RegisteredApp;
import 'package:material_ui/material_ui.dart';

/// The apps allowed to sign people in to this server, and the addresses
/// each may be sent back to after sign-in. An app not here gets no
/// sign-in: OWASP ASVS 5.0.0 V10.4.1 asks for "a client-specific allowlist
/// of pre-registered URIs" (0x19-V10-OAuth-and-OIDC.md at tag v5.0.0,
/// read 2026-11-22). Each action is one of the server's own routes
/// (`DeviceConsole`), so its checks and the audit trail apply.
class AppsView extends StatefulWidget {
  const AppsView({required this.session, super.key});
  final AdminSession session;

  @override
  State<AppsView> createState() => _AppsViewState();
}

class _AppsViewState extends State<AppsView> {
  List<RegisteredApp>? _apps;
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
    final result = await console.apps(session);
    if (!mounted) return;
    if (result.ok) {
      setState(() {
        _apps = result.value;
        _error = null;
      });
    } else if (result.refusal!.status == 401) {
      await handleRefusal(context, widget.session, result);
    } else {
      setState(() => _error = result.refusal!.message);
    }
  }

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
    final apps = _apps;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-app'),
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add_link),
        label: const Text('Register an app'),
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : apps == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 88),
                    children: [
                      if (apps.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No app is registered. An app must be '
                            'registered here, with its sign-in return '
                            'addresses, before anyone can sign in to it.',
                            key: Key('no-apps'),
                          ),
                        ),
                      for (final a in apps)
                        ListTile(
                          key: Key('app-${a.clientId}'),
                          title: Text(a.name.isEmpty ? a.clientId : a.name),
                          subtitle: Text(
                            [
                              a.clientId,
                              ...a.redirectUris,
                              'registered ${clock(a.registered)}',
                            ].join('\n'),
                          ),
                          isThreeLine: true,
                          onTap: () => _open(a),
                        ),
                    ],
                  ),
                ),
    );
  }

  Future<void> _open(RegisteredApp a) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(a.name.isEmpty ? a.clientId : a.name),
              subtitle: Text(a.clientId),
            ),
            ListTile(
              key: const Key('app-change'),
              leading: const Icon(Icons.edit),
              title: const Text('Change the name or addresses'),
              onTap: () => Navigator.of(context).pop('change'),
            ),
            ListTile(
              key: const Key('app-remove'),
              leading: const Icon(Icons.link_off),
              title: const Text('Remove'),
              onTap: () => Navigator.of(context).pop('remove'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'change') return _edit(a);
    if (!await confirmAction(
      context,
      'Remove ${a.name.isEmpty ? a.clientId : a.name}?',
      'Everyone signed in through it is signed out now, and it cannot sign '
          'anyone in until it is registered again.',
    )) {
      return;
    }
    final session = widget.session.session;
    if (session == null) return;
    await _act(
      (c) => c.removeApp(session, a.clientId),
      '${a.clientId} removed.',
    );
  }

  /// Registers a new app ([existing] null) or changes one.
  Future<void> _edit(RegisteredApp? existing) async {
    final clientId = TextEditingController(text: existing?.clientId);
    final name = TextEditingController(text: existing?.name);
    final addresses =
        TextEditingController(text: existing?.redirectUris.join('\n'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Register an app' : 'Change the app'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('app-client-id'),
                controller: clientId,
                enabled: existing == null,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Client id',
                  helperText: "Exactly as the app's settings give it",
                ),
              ),
              TextField(
                key: const Key('app-name'),
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                key: const Key('app-addresses'),
                controller: addresses,
                autocorrect: false,
                maxLines: 5,
                minLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Return addresses, one per line',
                  helperText: 'Where the app is sent back after sign-in '
                      '(its redirect URI). An address on this device '
                      '(127.0.0.1, localhost) may use any port.',
                  helperMaxLines: 4,
                ),
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
            key: const Key('app-ok'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final session = widget.session.session;
    if (session == null) return;
    final id = clientId.text.trim();
    final uris = addresses.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    await _act(
      (c) => c.putApp(session, id, name: name.text.trim(), redirectUris: uris),
      existing == null ? '$id registered.' : '$id changed.',
    );
  }
}
