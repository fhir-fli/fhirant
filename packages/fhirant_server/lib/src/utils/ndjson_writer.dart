import 'dart:io';

/// Writes [lines] to an NDJSON file at [filePath], one line each, as they
/// arrive, and returns how many were written. The lines are the stored JSON
/// of each resource, so nothing is decoded or re-encoded on the way; the
/// file holds one page of the source at a time however large the type is.
Future<int> writeNdjsonFile(String filePath, Stream<String> lines) async {
  final file = File(filePath);
  await file.parent.create(recursive: true);
  final sink = file.openWrite();
  var count = 0;
  try {
    await for (final line in lines) {
      sink.writeln(line);
      count++;
      // Let the sink drain every page so the file, not the heap, holds the
      // output.
      if (count % 500 == 0) await sink.flush();
    }
    await sink.flush();
  } finally {
    await sink.close();
  }
  return count;
}
