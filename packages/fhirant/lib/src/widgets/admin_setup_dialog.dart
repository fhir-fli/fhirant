import 'package:fhirant_db/fhirant_db.dart' show FhirAntDb;
import 'package:fhirant_server/fhirant_server.dart'
    show AdminProvisioning, AdminSetupStatus;
import 'package:flutter/material.dart';

/// Shows the admin-account setup dialog. Returns `true` if an admin account
/// now exists (freshly created, or already present), `false`/`null` if the
/// operator cancelled without one.
Future<bool?> showAdminSetupDialog(BuildContext context, FhirAntDb db) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AdminSetupDialog(db: db),
  );
}

class _AdminSetupDialog extends StatefulWidget {
  const _AdminSetupDialog({required this.db});

  final FhirAntDb db;

  @override
  State<_AdminSetupDialog> createState() => _AdminSetupDialogState();
}

class _AdminSetupDialogState extends State<_AdminSetupDialog> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text;
    final password = _passwordController.text;

    if (password != _confirmController.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await AdminProvisioning.createInitialAdmin(
      widget.db,
      username,
      password,
    );
    if (!mounted) return;

    switch (result.status) {
      case AdminSetupStatus.created:
      case AdminSetupStatus.alreadyExists:
        // Either outcome means an admin account now exists.
        Navigator.of(context).pop(true);
      case AdminSetupStatus.invalid:
        setState(() {
          _submitting = false;
          _error = result.message ?? 'Could not create the admin account.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Create admin account'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Secure mode requires an administrator account. Client apps and '
              'devices use these credentials to authenticate with the server.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _usernameController,
              enabled: !_submitting,
              autofillHints: const [AutofillHints.username],
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              enabled: !_submitting,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: 'At least 12 characters.',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmController,
              enabled: !_submitting,
              obscureText: _obscure,
              decoration: const InputDecoration(
                labelText: 'Confirm password',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}
