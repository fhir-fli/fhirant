import 'package:fhirant/src/widgets/backup_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Layout guard for the backup card.
///
/// The dashboard smoke test caught this card overflowing by 42 pixels on a
/// 320-wide phone the moment it was added. This pins the card on its own, so a
/// future change to it fails here rather than somewhere further away.
void main() {
  const sizes = <String, Size>{
    'small phone': Size(320, 568),
    'phone': Size(412, 915),
    'tablet': Size(834, 1112),
  };

  for (final entry in sizes.entries) {
    testWidgets('lays out on a ${entry.key}', (tester) async {
      await tester.binding.setSurfaceSize(entry.value);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: BackupCard()),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Backup & restore'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);
      expect(find.text('Restore'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
