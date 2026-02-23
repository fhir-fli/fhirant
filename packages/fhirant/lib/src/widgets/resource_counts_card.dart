import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/server_state.dart';

class ResourceCountsCard extends StatelessWidget {
  const ResourceCountsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ServerState>(
      builder: (context, state, _) {
        final counts = state.resourceCounts;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.storage, color: Colors.teal),
                    const SizedBox(width: 8),
                    Text(
                      'Resources',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    if (counts.isNotEmpty)
                      Text(
                        '${counts.values.fold<int>(0, (a, b) => a + b)} total',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (counts.isEmpty)
                  Text(
                    state.isRunning
                        ? 'No resources stored yet'
                        : 'Start the server to view resources',
                    style: TextStyle(color: Colors.grey.shade600),
                  )
                else
                  ..._buildCountRows(counts),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildCountRows(Map<dynamic, int> counts) {
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.map((entry) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                entry.key.toString(),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
            Text(
              entry.value.toString(),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}
