// Reads free and total bytes through StatvfsDiskSpace for each path given,
// 10,000 times, and prints them with the time per call, to check against
// `df -B1 --output=target,avail,size` (probe.tsv, run 2026-11-02).
//
// Usage: dart run tool/review_2026-10-17/storage_floor/tools/statvfs_probe.dart <path>...
// ignore_for_file: avoid_print
import 'package:fhirant_server/src/services/disk_space.dart';

void main(List<String> paths) {
  final disk = StatvfsDiskSpace();
  for (final path in paths) {
    final watch = Stopwatch()..start();
    DiskUsage? usage;
    for (var i = 0; i < 10000; i++) {
      usage = disk.measure(path);
    }
    final perCall = watch.elapsedMicroseconds / 10000;
    print('$path\t${usage?.free}\t${usage?.total}\t$perCall us/call');
  }
}
