import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import '../state/server_state.dart';

class ResourceCountsCard extends StatefulWidget {
  const ResourceCountsCard({super.key});

  @override
  State<ResourceCountsCard> createState() => _ResourceCountsCardState();
}

class _ResourceCountsCardState extends State<ResourceCountsCard> {
  bool _loading = false;

  Future<void> _loadSampleData(ServerState state) async {
    setState(() => _loading = true);
    try {
      final jsonStr = await rootBundle.loadString('assets/sample_data.json');
      final bundle = jsonDecode(jsonStr) as Map<String, dynamic>;
      final entries = bundle['entry'] as List? ?? [];
      var saved = 0;
      for (final entry in entries) {
        try {
          final resourceJson = entry['resource'] as Map<String, dynamic>?;
          if (resourceJson != null) {
            final resource = Resource.fromJson(resourceJson);
            await state.db.saveResource(resource);
            saved++;
          }
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Loaded $saved sample resources')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading sample data: $e')),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

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
                if (counts.isEmpty && state.isRunning) ...[
                  Text(
                    'No resources stored yet',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  if (_loading)
                    const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () => _loadSampleData(state),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Load Sample Data'),
                    ),
                ] else if (counts.isEmpty)
                  Text(
                    'Start the server to view resources',
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
