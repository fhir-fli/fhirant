import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart';

/// Writes a list of FHIR resources to an NDJSON file (one JSON object per line).
///
/// Uses [IOSink] for streaming writes to avoid materializing the full
/// output in memory.
Future<int> writeNdjsonFile(String filePath, List<Resource> resources) async {
  final file = File(filePath);
  await file.parent.create(recursive: true);
  final sink = file.openWrite();
  try {
    for (final resource in resources) {
      sink.writeln(jsonEncode(resource.toJson()));
    }
    await sink.flush();
  } finally {
    await sink.close();
  }
  return resources.length;
}
