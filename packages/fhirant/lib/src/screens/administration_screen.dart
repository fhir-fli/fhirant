import 'dart:async';

import 'package:fhirant/src/state/admin_session.dart';
import 'package:fhirant/src/widgets/accounts_view.dart';
import 'package:fhirant/src/widgets/apps_view.dart';
import 'package:fhirant_server/fhirant_server.dart'
    show ConsoleResult, DeviceConsole;
import 'package:material_ui/material_ui.dart';

/// The Administration section: everything an operator does with accounts
/// and the apps allowed to sign people in, on the phone itself (Grey
/// 2026-11-21: "anything requiring the command line is wrong for this
/// app"). Shown in Secure mode only.
///
/// It opens on a sign-in. An administrator gets the accounts; anyone else
/// may change their own password here. The owner of a new or reset account
/// sets their password from here too, without signing in, and is shown the
/// code to give the administrator.
class AdministrationScreen extends StatefulWidget {
  const AdministrationScreen({
    required this.openConsole,
    this.idleLimit = const Duration(hours: 1),
    super.key,
  });

  final Future<DeviceConsole> Function() openConsole;
  final Duration idleLimit;

  @override
  State<AdministrationScreen> createState() => _AdministrationScreenState();
}

class _AdministrationScreenState extends State<AdministrationScreen> {
  late final AdminSession _session =
      AdminSession(widget.openConsole, idleLimit: widget.idleLimit);

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        final session = _session.session;
        return Listener(
          // Any touch counts as use for the idle limit.
          onPointerDown: (_) => _session.touch(),
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Administration'),
              actions: [
                if (session != null) ...[
                  IconButton(
                    tooltip: 'Change my password',
                    icon: const Icon(Icons.password),
                    onPressed: () => _changeOwnPassword(context),
                  ),
                  IconButton(
                    tooltip: 'Sign out',
                    icon: const Icon(Icons.logout),
                    onPressed: () => unawaited(_session.end()),
                  ),
                ],
              ],
            ),
            body: SafeArea(
              child: session == null
                  ? _SignIn(session: _session)
                  : session.isAdmin
                      ? _AdminTabs(session: _session)
                      : _NotAdmin(username: session.username),
            ),
          ),
        );
      },
    );
  }

  Future<void> _changeOwnPassword(BuildContext context) async {
    final session = _session.session;
    if (session == null) return;
    final fields = await showPasswordFields(
      context,
      title: 'Change my password',
      askCurrent: true,
    );
    if (fields == null || !mounted) return;
    final console = await _session.console();
    final result =
        await console.changeOwnPassword(session, fields.current, fields.next);
    if (!context.mounted) return;
    if (result.ok) {
      _session.replace(result.value!);
      showMessage(context, 'Password changed.');
    } else {
      await handleRefusal(context, _session, result);
    }
  }
}

/// What an administrator manages: the accounts, and the apps allowed to
/// sign people in.
class _AdminTabs extends StatelessWidget {
  const _AdminTabs({required this.session});
  final AdminSession session;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(key: Key('tab-accounts'), text: 'Accounts'),
                Tab(key: Key('tab-apps'), text: 'Apps'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  AccountsView(session: session),
                  AppsView(session: session),
                ],
              ),
            ),
          ],
        ),
      );
}

class _NotAdmin extends StatelessWidget {
  const _NotAdmin({required this.username});
  final String username;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Signed in as $username.\n\nOnly an administrator can manage '
            'accounts. You can change your own password with the key button '
            'above.',
            textAlign: TextAlign.center,
          ),
        ),
      );
}

class _SignIn extends StatefulWidget {
  const _SignIn({required this.session});
  final AdminSession session;

  @override
  State<_SignIn> createState() => _SignInState();
}

class _SignInState extends State<_SignIn> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result =
        await widget.session.signIn(_username.text.trim(), _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!result.ok) _error = result.refusal!.message;
    });
    _password.clear();
  }

  Future<void> _setMyPassword() async {
    final fields = await showPasswordFields(
      context,
      title: 'Set the password of my new account',
      askUsername: true,
    );
    if (fields == null || !mounted) return;
    final console = await widget.session.console();
    final result = await console.claim(fields.username, fields.next);
    if (!mounted) return;
    if (!result.ok) {
      showMessage(context, result.refusal!.message);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Show this code to your administrator'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(
              result.value!,
              key: const Key('claim-code'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            const Text(
              'Your password works once they approve it with this code. '
              'Sending a password again replaces this one and gives a new '
              'code.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ended = widget.session.endedBecause;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (ended != null) ...[
          Text(ended, key: const Key('ended-because')),
          const SizedBox(height: 16),
        ],
        TextField(
          key: const Key('sign-in-username'),
          controller: _username,
          decoration: const InputDecoration(labelText: 'Username'),
          autocorrect: false,
        ),
        TextField(
          key: const Key('sign-in-password'),
          controller: _password,
          decoration: const InputDecoration(labelText: 'Password'),
          obscureText: true,
          onSubmitted: (_) => _busy ? null : _signIn(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('sign-in'),
          onPressed: _busy ? null : _signIn,
          child: const Text('Sign in'),
        ),
        const SizedBox(height: 24),
        TextButton(
          key: const Key('set-my-password'),
          onPressed: _setMyPassword,
          child: const Text('I have a new account: set my password'),
        ),
      ],
    );
  }
}

/// Shows [text] at the foot of the screen.
void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Shows a refusal; a 401 means the sign-in ended (it ran out, or the
/// account changed), so the person signs in again.
Future<void> handleRefusal(
  BuildContext context,
  AdminSession session,
  ConsoleResult<Object?> result,
) async {
  final refusal = result.refusal!;
  if (refusal.status == 401) {
    await session.end('Your sign-in has ended. Sign in again.');
    return;
  }
  if (context.mounted) showMessage(context, refusal.message);
}

/// Asks before an action that cannot be taken back with one tap.
Future<bool> confirmAction(
  BuildContext context,
  String title,
  String body,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-ok'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    ) ??
    false;

/// What [showPasswordFields] collected.
class PasswordFields {
  const PasswordFields(this.username, this.current, this.next);
  final String username;
  final String current;
  final String next;
}

/// Asks for a new password twice, with the current one or a username when
/// asked. Null when cancelled.
Future<PasswordFields?> showPasswordFields(
  BuildContext context, {
  required String title,
  bool askCurrent = false,
  bool askUsername = false,
}) {
  final username = TextEditingController();
  final current = TextEditingController();
  final next = TextEditingController();
  final again = TextEditingController();
  return showDialog<PasswordFields>(
    context: context,
    builder: (context) {
      String? error;
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (askUsername)
                  TextField(
                    key: const Key('fields-username'),
                    controller: username,
                    decoration: const InputDecoration(labelText: 'Username'),
                    autocorrect: false,
                  ),
                if (askCurrent)
                  TextField(
                    key: const Key('fields-current'),
                    controller: current,
                    decoration:
                        const InputDecoration(labelText: 'Current password'),
                    obscureText: true,
                  ),
                TextField(
                  key: const Key('fields-new'),
                  controller: next,
                  decoration: const InputDecoration(
                    labelText: 'New password',
                    helperText: 'At least 12 characters',
                  ),
                  obscureText: true,
                ),
                TextField(
                  key: const Key('fields-again'),
                  controller: again,
                  decoration:
                      const InputDecoration(labelText: 'New password again'),
                  obscureText: true,
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('fields-ok'),
              onPressed: () {
                if (next.text != again.text) {
                  setState(() => error = 'The two new passwords differ.');
                  return;
                }
                Navigator.of(context).pop(
                  PasswordFields(username.text.trim(), current.text, next.text),
                );
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    },
  );
}
