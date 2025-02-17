import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider for the database service
final dbServiceProvider = Provider<DbService>((ref) {
  final dbService = DbService(AppDatabase());
  ref.onDispose(dbService.close);
  return dbService;
});

/// Provider when testing an instance of DbService
final testDbServiceProvider = Provider<DbService>((ref) {
  final dbService = DbService(AppDatabase.forTesting(NativeDatabase.memory()));
  ref.onDispose(dbService.close);
  return dbService;
});
