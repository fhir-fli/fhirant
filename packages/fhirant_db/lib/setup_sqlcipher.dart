import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';

/// Configure SQLCipher for Android and other platforms
Future<void> setupSqlCipher() async {
  // Apply Android-specific setup to ensure SQLCipher works on older devices
  await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();

  // Override the open behavior for Android to use SQLCipher
  open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
}
