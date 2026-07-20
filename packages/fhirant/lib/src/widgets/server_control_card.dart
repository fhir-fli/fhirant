import 'dart:async';

import 'package:fhirant/src/state/server_state.dart';
import 'package:fhirant/src/widgets/admin_setup_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ServerControlCard extends StatefulWidget {
  const ServerControlCard({super.key});

  @override
  State<ServerControlCard> createState() => _ServerControlCardState();
}

class _ServerControlCardState extends State<ServerControlCard> {
  late TextEditingController _portController;

  @override
  void initState() {
    super.initState();
    _portController = TextEditingController(
      text: context.read<ServerState>().port.toString(),
    );
  }

  @override
  void dispose() {
    _portController.dispose();
    super.dispose();
  }

  /// Handles the Experimentation/Secure switch. Switching to Secure requires an
  /// admin account to exist first — otherwise the server would enforce auth
  /// with no valid credentials, and the first-user bootstrap would let anyone
  /// claim admin. Prompts to create one when none exists; the switch only
  /// completes if an admin then exists.
  Future<void> _onModeChanged(ServerState state, bool experimentation) async {
    if (experimentation) {
      state.devMode = true;
      return;
    }

    final userCount = await state.db.getUserCount();
    if (userCount == 0) {
      if (!mounted) return;
      final created = await showAdminSetupDialog(context, state.db);
      if (created != true) return; // no admin created — stay in Experimentation
    }
    state.devMode = false;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ServerState>(
      builder: (context, state, _) {
        final color = switch (state.status) {
          ServerStatus.running => Colors.green,
          ServerStatus.starting || ServerStatus.stopping => Colors.orange,
          ServerStatus.error => Colors.red,
          ServerStatus.stopped => Colors.grey,
        };

        final statusLabel = switch (state.status) {
          ServerStatus.running => 'Running',
          ServerStatus.starting => 'Starting...',
          ServerStatus.stopping => 'Stopping...',
          ServerStatus.error => 'Error',
          ServerStatus.stopped => 'Stopped',
        };

        final isBusy = state.status == ServerStatus.starting ||
            state.status == ServerStatus.stopping;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.dns, color: color),
                    const SizedBox(width: 8),
                    Text(
                      'FHIR Server',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _portController,
                        enabled: state.status == ServerStatus.stopped ||
                            state.status == ServerStatus.error,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Port',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (value) {
                          final port = int.tryParse(value);
                          if (port != null && port > 0 && port <= 65535) {
                            state.port = port;
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    FilledButton.icon(
                      onPressed: isBusy
                          ? null
                          : () {
                              if (state.isRunning) {
                                unawaited(state.stopServer());
                              } else {
                                unawaited(state.startServer());
                              }
                            },
                      icon:
                          Icon(state.isRunning ? Icons.stop : Icons.play_arrow),
                      label: Text(state.isRunning ? 'Stop' : 'Start'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Authentication',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      state.devMode ? 'Experimentation' : 'Secure',
                      style: TextStyle(
                        fontSize: 12,
                        color: state.devMode
                            ? Colors.orange.shade700
                            : Colors.green.shade700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      // On = Experimentation (no auth); off = Secure.
                      value: state.devMode,
                      onChanged: state.status == ServerStatus.stopped ||
                              state.status == ServerStatus.error
                          ? (value) => unawaited(_onModeChanged(state, value))
                          : null,
                    ),
                  ],
                ),
                if (state.devMode)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber,
                          size: 16,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Authentication is disabled. TEST DATA ONLY — do '
                            'not store real patient data (PHI) in this mode.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (state.errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    state.errorMessage!,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
