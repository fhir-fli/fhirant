import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import '../screens/resource_browser_screen.dart';
import '../state/server_state.dart';

List<Map<String, dynamic>> _parseBundle(String jsonStr) {
  final bundle = jsonDecode(jsonStr) as Map<String, dynamic>;
  final entries = bundle['entry'] as List? ?? [];
  return entries
      .map((e) => (e as Map<String, dynamic>)['resource'] as Map<String, dynamic>?)
      .whereType<Map<String, dynamic>>()
      .toList();
}

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
      final resourceJsons = await compute(_parseBundle, jsonStr);
      final resources = <Resource>[];
      for (final json in resourceJsons) {
        try {
          resources.add(Resource.fromJson(json));
        } catch (_) {}
      }
      await state.db.saveResources(resources);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Loaded ${resources.length} sample resources')),
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
                    if (counts.isNotEmpty) ...[
                      Text(
                        '${counts.values.fold<int>(0, (a, b) => a + b)} total',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.open_in_new, size: 18),
                        tooltip: 'Browse Resources',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChangeNotifierProvider.value(
                              value: state,
                              child: const ResourceBrowserScreen(),
                            ),
                          ),
                        ),
                      ),
                    ],
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
    final state = context.read<ServerState>();

    return sorted.map((entry) {
      return InkWell(
        onTap: () {
          if (entry.key is R4ResourceType) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChangeNotifierProvider.value(
                  value: state,
                  child: ResourceBrowserScreen(
                    initialType: entry.key as R4ResourceType,
                  ),
                ),
              ),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  entry.key.toString(),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              Text(
                entry.value.toString(),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      );
    }).toList();
  }
}
