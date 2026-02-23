import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/server_state.dart';

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
                                state.stopServer();
                              } else {
                                state.startServer();
                              }
                            },
                      icon: Icon(state.isRunning ? Icons.stop : Icons.play_arrow),
                      label: Text(state.isRunning ? 'Stop' : 'Start'),
                    ),
                  ],
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
