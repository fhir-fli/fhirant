import 'app_db.dart';

extension AccountTableExtension on Account {
  AccountCompanion asHistory({required int lastUpdated}) {
    return AccountHistory(id: id, lastUpdated: lastUpdated, resource: resource);
  }
}
