import 'dart:ffi';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:sqlite3/open.dart';

/// Utility for loading SQLCipher in a platform-agnostic way
class SqlCipherLoader {
  /// Loads the appropriate SQLCipher library for the current platform
  static void load({String? customPath}) {
    final libraryPath = customPath ?? _getDefaultLibraryPath();

    if (!File(libraryPath).existsSync()) {
      throw Exception('SQLCipher library not found at: $libraryPath');
    }

    if (Platform.isLinux) {
      open.overrideFor(
          OperatingSystem.linux, () => DynamicLibrary.open(libraryPath));
    } else if (Platform.isMacOS) {
      open.overrideFor(
          OperatingSystem.macOS, () => DynamicLibrary.open(libraryPath));
    } else if (Platform.isWindows) {
      open.overrideFor(
          OperatingSystem.windows, () => DynamicLibrary.open(libraryPath));
    } else {
      throw UnsupportedError(
          'Unsupported platform: ${Platform.operatingSystem}');
    }
  }

  /// Get the default library path based on the platform
  static String _getDefaultLibraryPath() {
    final rootDir = _findPackageRoot() ?? Directory.current.path;
    final sqlcipherDir = path.join(rootDir, 'lib', 'sqlcipher');

    if (Platform.isLinux) {
      return path.join(sqlcipherDir, 'linux', 'libsqlcipher.so');
    } else if (Platform.isMacOS) {
      return path.join(sqlcipherDir, 'macos', 'libsqlcipher.dylib');
    } else if (Platform.isWindows) {
      return path.join(sqlcipherDir, 'windows', 'sqlcipher.dll');
    } else {
      throw UnsupportedError(
          'Unsupported platform: ${Platform.operatingSystem}');
    }
  }

  /// Find the package root directory
  static String? _findPackageRoot() {
    String currentDir = Directory.current.path;
    while (currentDir.isNotEmpty) {
      if (File(path.join(currentDir, 'pubspec.yaml')).existsSync()) {
        return currentDir;
      }
      final parent = path.dirname(currentDir);
      if (parent == currentDir) {
        return null;
      }
      currentDir = parent;
    }
    return null;
  }
}
