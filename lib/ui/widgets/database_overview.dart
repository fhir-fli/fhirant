import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant_db/db_service.dart';
import 'package:flutter/material.dart';

/// DatabaseOverview
class DatabaseOverview extends StatelessWidget {
  /// Constructor
  const DatabaseOverview(this.dbService, {super.key});

  /// Database Service
  final DbService dbService;

  Future<Map<R4ResourceType, int>> _getResourceCounts() async {
    final counts = <R4ResourceType, int>{};

    for (final resourceType in R4ResourceType.values) {
      final count = await dbService.getResourceCount(resourceType);
      counts[resourceType] = count;
    }

    return counts;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<R4ResourceType, int>>(
      future: _getResourceCounts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Text(
            'Error: ${snapshot.error}',
            style: const TextStyle(color: Colors.red),
          );
        }

        final counts = (snapshot.data ?? {})
          ..removeWhere((key, value) => value == 0);

        if (counts.isEmpty) {
          return const Text(
            'No resources found in database',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          );
        }

        return ExpansionTile(
          title: const Text(
            'Database Overview',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: Scrollbar(
                thumbVisibility: true,
                thickness: 4,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: counts.entries.map<Widget>((entry) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                entry.key.toString(),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${entry.value} resource(s)',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
