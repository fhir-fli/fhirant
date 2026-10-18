import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

/// Found on the phone run of fhirant REVIEW-2026-10-17 (2026-10-18). The
/// manifest set `android:allowBackup="false"` and nothing else. Android 12
/// behaviour changes page (read 2026-10-18, verbatim): "On devices from some
/// device manufacturers, specifying android:allowBackup="false" does disable
/// backups to Google Drive, but doesn't disable D2D transfers for the app."
/// The app's private files hold the patient record and the server log, so
/// both backup modes exclude every private directory.
///
/// The check reads the source files the build merges; the shipped APK's
/// merged manifest was read with `aapt2 dump xmltree` when this landed.
void main() {
  const android = 'http://schemas.android.com/apk/res/android';

  XmlElement application() => XmlDocument.parse(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      ).rootElement.getElement('application')!;

  test('cloud backup stays off', () {
    expect(
      application().getAttribute('allowBackup', namespace: android),
      'false',
    );
  });

  test('the manifest names data extraction rules', () {
    expect(
      application().getAttribute('dataExtractionRules', namespace: android),
      '@xml/data_extraction_rules',
    );
  });

  for (final mode in ['cloud-backup', 'device-transfer']) {
    test('$mode excludes every private directory and includes nothing', () {
      final file =
          File('android/app/src/main/res/xml/data_extraction_rules.xml');
      expect(file.existsSync(), isTrue);
      final section =
          XmlDocument.parse(file.readAsStringSync()).rootElement.getElement(
                mode,
              );
      expect(section, isNotNull);
      expect(section!.findElements('include'), isEmpty);
      final excluded = {
        for (final e in section.findElements('exclude'))
          if (e.getAttribute('path') == '.') e.getAttribute('domain'),
      };
      expect(excluded, containsAll(['root', 'device_root', 'external']));
    });
  }
}
