import 'dart:io';

import 'package:fhirant/src/state/server_state.dart';
import 'package:fhirant_server/fhirant_server.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

/// Export and import of the encrypted record.
///
/// This is the device-to-device path. The database is encrypted at rest under
/// a key sealed in platform secure storage, so the key cannot travel with the
/// data; a passphrase-wrapped export is the only way the record survives the
/// phone holding it. Until this existed the export could only be triggered by
/// an HTTP call, which is no use to a clinician holding a dying handset.
///
/// It works on the database directly rather than through the server, so it
/// does not require the server to be running, a network, or a login.
class BackupCard extends StatefulWidget {
  const BackupCard({super.key});

  @override
  State<BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends State<BackupCard> {
  /// Below this the two icon buttons cannot sit side by side: measured at 42
  /// pixels of overflow on the smallest phone the dashboard smoke test covers.
  static const _sideBySideWidth = 340.0;

  bool _busy = false;

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
                Icon(Icons.backup_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                // Flexible so the title wraps on a narrow handset instead of
                // running off the card: it overflowed by 10 pixels at 320.
                Flexible(
                  child: Text(
                    'Backup & restore',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Export every record to an encrypted file you can move to '
              'another device. The passphrase you choose is the only thing '
              'that can open it, and it is not stored anywhere.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (_busy)
              const Center(child: CircularProgressIndicator())
            else
              // Side by side where they fit, stacked where they do not. An
              // icon and a label each need real width, and the dashboard is
              // read on whatever handset is to hand.
              LayoutBuilder(
                builder: (context, constraints) {
                  final export = FilledButton.icon(
                    onPressed: _export,
                    icon: const Icon(Icons.upload_file_rounded),
                    label: const Text('Export'),
                  );
                  final restore = OutlinedButton.icon(
                    onPressed: _import,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Restore'),
                  );
                  if (constraints.maxWidth < _sideBySideWidth) {
                    return Column(
                      children: [
                        SizedBox(width: double.infinity, child: export),
                        const SizedBox(height: 8),
                        SizedBox(width: double.infinity, child: restore),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: export),
                      const SizedBox(width: 12),
                      Expanded(child: restore),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _export() async {
    final passphrase = await showDialog<String>(
      context: context,
      builder: (_) => const _PassphraseDialog(confirming: true),
    );
    if (passphrase == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final db = context.read<ServerState>().db;
      final envelope = await BackupService.create(db, passphrase);

      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file = File(
        '${(await getTemporaryDirectory()).path}/fhirant-backup-$stamp.json',
      );
      await file.writeAsString(envelope);

      // The share sheet is what makes the file reach anywhere useful: another
      // phone, an SD card, a laptop. Writing to app storage alone would leave
      // it on the device that is failing.
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'FHIRant backup',
      );
      _say('Backup created. Keep the passphrase safe: without it the file '
          'cannot be opened.');
    } catch (e) {
      _say('Backup failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;

    final payload = await File(path).readAsString();
    if (!mounted) return;

    // Only ask for a passphrase when the file actually needs one: a plain
    // FHIR Bundle produced elsewhere restores without it.
    String? passphrase;
    if (BackupService.isEncrypted(payload)) {
      passphrase = await showDialog<String>(
        context: context,
        builder: (_) => const _PassphraseDialog(confirming: false),
      );
      if (passphrase == null || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      final db = context.read<ServerState>().db;
      final result = await BackupService.restore(
        db,
        payload,
        passphrase: passphrase,
      );
      _say(
        result.failed == 0
            ? 'Restored ${result.saved} records.'
            : 'Restored ${result.saved} records, ${result.failed} could not '
                'be read.',
        error: result.failed > 0,
      );
    } on BackupDecryptionException {
      _say(
        'That passphrase does not open this file, or the file has been '
        'altered.',
        error: true,
      );
    } on BackupPassphraseRequired catch (e) {
      _say(e.message, error: true);
    } on FormatException catch (e) {
      _say('That file is not a FHIR backup: ${e.message}', error: true);
    } catch (e) {
      _say('Restore failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            error ? Theme.of(context).colorScheme.errorContainer : null,
        duration: const Duration(seconds: 6),
      ),
    );
  }
}

/// Asks for the passphrase, confirming it when one is being chosen.
///
/// A mistyped passphrase on export produces a file nobody can ever open, and
/// nothing later can detect that, so export confirms and restore does not.
class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog({required this.confirming});

  final bool confirming;

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  bool _obscure = true;
  String? _error;

  /// Short enough to guess offline, where an attacker holding the file can try
  /// without limit. Length is what helps; a rule about symbols mostly produces
  /// passphrases people cannot recall when the device they wrote it on is gone.
  static const _minimumLength = 12;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _first.text;
    if (widget.confirming) {
      if (value.length < _minimumLength) {
        setState(() => _error = 'Use at least $_minimumLength characters.');
        return;
      }
      if (value != _second.text) {
        setState(() => _error = 'The two entries do not match.');
        return;
      }
    } else if (value.isEmpty) {
      setState(() => _error = 'Enter the passphrase this file was made with.');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.confirming ? 'Choose a passphrase' : 'Passphrase'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.confirming)
            const Text(
              'This passphrase is the only thing that can open the backup. '
              'It is not stored, and it cannot be recovered or reset.',
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _first,
            obscureText: _obscure,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Passphrase',
              errorText: _error,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
                tooltip: _obscure ? 'Show' : 'Hide',
              ),
            ),
            onSubmitted: (_) => widget.confirming ? null : _submit(),
          ),
          if (widget.confirming) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _second,
              obscureText: _obscure,
              decoration: const InputDecoration(labelText: 'Enter it again'),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.confirming ? 'Export' : 'Restore'),
        ),
      ],
    );
  }
}
