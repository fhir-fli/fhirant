import 'package:fhirant_server/fhirant_server.dart' show RequestLogEntry;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/server_state.dart';

class RequestLogCard extends StatelessWidget {
  const RequestLogCard({super.key});

  Color _statusColor(int code) {
    if (code < 300) return Colors.green;
    if (code < 400) return Colors.blue;
    if (code < 500) return Colors.orange;
    return Colors.red;
  }

  Color _methodColor(String method) {
    return switch (method) {
      'GET' => Colors.blue,
      'POST' => Colors.green,
      'PUT' => Colors.orange,
      'PATCH' => Colors.purple,
      'DELETE' => Colors.red,
      _ => Colors.grey,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ServerState>(
      builder: (context, state, _) {
        final log = state.requestLog;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.list_alt, color: Colors.indigo),
                    const SizedBox(width: 8),
                    Text(
                      'Request Log',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    if (log.isNotEmpty)
                      Text(
                        '${log.length} entries',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (log.isEmpty)
                  Text(
                    state.isRunning
                        ? 'No requests yet'
                        : 'Start the server to see requests',
                    style: TextStyle(color: Colors.grey.shade600),
                  )
                else
                  SizedBox(
                    height: 300,
                    child: ListView.builder(
                      itemCount: log.length,
                      itemBuilder: (context, index) =>
                          _buildLogEntry(context, log[index]),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLogEntry(BuildContext context, RequestLogEntry entry) {
    final time =
        '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
        '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
        '${entry.timestamp.second.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              time,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Container(
            width: 52,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: _methodColor(entry.method).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              entry.method,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _methodColor(entry.method),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              entry.path,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: _statusColor(entry.statusCode).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              entry.statusCode.toString(),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _statusColor(entry.statusCode),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 40,
            child: Text(
              '${entry.durationMs}ms',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
