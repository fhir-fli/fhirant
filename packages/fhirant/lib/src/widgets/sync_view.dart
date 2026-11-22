import 'dart:async';

import 'package:fhirant/src/screens/administration_screen.dart';
import 'package:fhirant/src/state/admin_session.dart';
import 'package:fhirant/src/widgets/accounts_view.dart' show clock;
import 'package:fhirant_server/fhirant_server.dart'
    show SyncState, SyncStatus, SyncedPeer;
import 'package:material_ui/material_ui.dart';

/// Sync with another server: the servers synced with before, a sync
/// running now, and what the last one did. A sync merges the two record
/// sets field by field; nobody decides a clash by hand (CLAUDE.md, `$sync`).
///
/// The operator signs in at the other fhirant server with an account
/// there; that sign-in is ended when the sync does. Only a server that is
/// not fhirant takes a token pasted in. Each action is one of the server's
/// own routes (`DeviceConsole`): `$sync`, `$sync-status` and
/// `admin/sync-peers`. A sync goes on after this screen is signed out of
/// or closed, and only one runs on the phone at a time.
class SyncView extends StatefulWidget {
  const SyncView({
    required this.session,
    this.pollEvery = const Duration(seconds: 2),
    super.key,
  });
  final AdminSession session;

  /// How often a running sync's progress is asked for.
  final Duration pollEvery;

  @override
  State<SyncView> createState() => _SyncViewState();
}

class _SyncViewState extends State<SyncView> {
  List<SyncedPeer>? _peers;
  SyncStatus? _status;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final session = widget.session.session;
    if (session == null) return;
    final console = await widget.session.console();
    final peers = await console.syncPeers(session);
    final status = await console.syncStatus(session);
    if (!mounted) return;
    for (final r in [peers, status]) {
      if (!r.ok) {
        if (r.refusal!.status == 401) {
          await handleRefusal(context, widget.session, r);
        } else {
          setState(() => _error = r.refusal!.message);
        }
        return;
      }
    }
    setState(() {
      _peers = peers.value;
      _status = status.value;
      _error = null;
    });
    _poll?.cancel();
    if (_status!.state == SyncState.running) {
      _poll = Timer(widget.pollEvery, () => unawaited(_load()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final peers = _peers;
    final status = _status;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-sync'),
        onPressed: status?.state == SyncState.running ? null : _start,
        icon: const Icon(Icons.sync),
        label: const Text('Sync with a server'),
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : peers == null || status == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 88),
                    children: [
                      _StatusCard(status: status),
                      if (peers.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                          child: Text(
                            'Synced with before',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                      for (final p in peers)
                        ListTile(
                          key: Key('peer-${p.peer}'),
                          leading: const Icon(Icons.dns),
                          title: Text(p.peer),
                          subtitle: Text(
                            p.lastRun == null
                                ? 'Never completed'
                                : 'Last completed ${clock(p.lastRun!)}',
                          ),
                          onTap: status.state == SyncState.running
                              ? null
                              : () => _start(peer: p.peer),
                        ),
                    ],
                  ),
                ),
    );
  }

  Future<void> _start({String? peer}) async {
    widget.session.touch();
    final address = TextEditingController(text: peer);
    final username = TextEditingController();
    final password = TextEditingController();
    final token = TextEditingController();
    var notFhirant = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Sync with a server'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('sync-address'),
                  controller: address,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  onChanged: (_) => setDialog(() {}),
                  decoration: const InputDecoration(
                    labelText: "The other server's address",
                    hintText: 'http://192.168.1.20:8080',
                  ),
                ),
                // OWASP ASVS 5.0.0 V12.3.1 (fhirant REVIEW-2026-10-17: a
                // FINDING, `$sync` over plain HTTP): said where it applies.
                if (address.text.trim().toLowerCase().startsWith('http:'))
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'This address is not encrypted (http, not https): '
                      'your password there and the records go over the '
                      'network readable by anyone on it.',
                      key: Key('sync-unencrypted'),
                    ),
                  ),
                SwitchListTile(
                  key: const Key('sync-not-fhirant'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('The other server is not fhirant'),
                  value: notFhirant,
                  onChanged: (v) => setDialog(() => notFhirant = v),
                ),
                if (notFhirant)
                  TextField(
                    key: const Key('sync-token'),
                    controller: token,
                    autocorrect: false,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Its access token (blank for none)',
                    ),
                  )
                else ...[
                  TextField(
                    key: const Key('sync-username'),
                    controller: username,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Your account there',
                    ),
                  ),
                  TextField(
                    key: const Key('sync-password'),
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Its password',
                      helperText: 'Used to sign in there for this sync only',
                      helperMaxLines: 2,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('sync-ok'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Sync'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final session = widget.session.session;
    if (session == null) return;
    final console = await widget.session.console();
    final result = notFhirant
        ? await console.startSync(
            session,
            address.text,
            token: token.text.trim().isEmpty ? null : token.text.trim(),
          )
        : await console.startSync(
            session,
            address.text,
            username: username.text.trim(),
            password: password.text,
          );
    if (!mounted) return;
    if (result.ok) {
      showMessage(context, 'Sync started.');
    } else {
      await handleRefusal(context, widget.session, result);
    }
    await _load();
  }
}

/// What the sync is doing, or what the last one did.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});
  final SyncStatus status;

  /// The route's instants on the phone's 24-hour clock.
  static String _clocked(String text) => text.replaceAllMapped(
        RegExp(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+)?Z?'),
        (m) {
          final t = DateTime.tryParse(m[0]!);
          return t == null ? m[0]! : clock(t);
        },
      );

  @override
  Widget build(BuildContext context) {
    final lines = <Widget>[];
    String n(String key) => '${status.counts[key] ?? 0}';
    switch (status.state) {
      case SyncState.none:
        lines.add(
          const Text(
            'No sync has run since the app started.',
            key: Key('sync-none'),
          ),
        );
      case SyncState.running:
        lines.add(
          Row(
            children: [
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _clocked(status.progress!),
                  key: const Key('sync-running'),
                ),
              ),
            ],
          ),
        );
      case SyncState.failed:
        lines
          ..add(
            const Text(
              'The last sync stopped early. The next sync starts from '
              'where the last complete one ended.',
              key: Key('sync-failed'),
            ),
          )
          ..add(Text(_clocked(status.error!)));
      case SyncState.done:
        lines.addAll([
          Text(
            'Last sync with ${status.peer ?? 'unknown'}',
            key: const Key('sync-done'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (status.started != null && status.finished != null)
            Text(
              '${clock(status.started!)} to ${clock(status.finished!)}',
            ),
          const SizedBox(height: 8),
          Text(
            '${n('considered')} changed on either side since the sync '
            'before; ${n('unchanged')} of them already the same.',
          ),
          Text(
            '${n('writtenToPeer')} written to the other server, '
            '${n('writtenHere')} written here.',
            key: const Key('sync-written'),
          ),
          Text(
            '${n('deletedOnPeer')} deleted on the other server, '
            '${n('deletedHere')} deleted here.',
          ),
        ]);
        if (status.conflicts.isNotEmpty) {
          lines.add(
            _Listed(
              key: const Key('sync-conflicts'),
              title: '${status.conflicts.length} changed on both sides: '
                  'the later save was kept',
              items: status.conflicts,
            ),
          );
        }
        if (status.retryLater.isNotEmpty) {
          lines.add(
            _Listed(
              title: '${status.retryLater.length} changed during the sync: '
                  'the next sync takes them up',
              items: status.retryLater,
            ),
          );
        }
        if (status.failures.isNotEmpty) {
          lines.add(
            _Listed(
              key: const Key('sync-failures'),
              title: '${status.failures.length} not written: the next sync '
                  'tries them again',
              items: status.failures,
            ),
          );
        }
    }
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lines,
        ),
      ),
    );
  }
}

class _Listed extends StatelessWidget {
  const _Listed({required this.title, required this.items, super.key});
  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(title),
        children: [
          for (final item in items)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: SelectableText(_StatusCard._clocked(item)),
              ),
            ),
        ],
      );
}
