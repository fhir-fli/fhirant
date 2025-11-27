# fhirant_db

Just in case we wanted to use these again. These providers are used in the fhirant server package.

```dart
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
```
