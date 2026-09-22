import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:url_launcher/url_launcher.dart';

/// Tells the user what keeps the server alive while the phone is not in use,
/// and opens the one setting the app can open for them.
///
/// Measured on a OnePlus (Android 16, tool/background_survival/RESULTS.md):
/// unplugged, the phone stopped fhirant 5–7 minutes after the cable came
/// out, battery exemption or not; with the exemption AND the app locked in
/// Recents it ran 69 minutes idle and 36 minutes of ordinary use with no
/// stop.
///
/// The exemption is reached through the settings list
/// (ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS), not the direct prompt: the
/// direct prompt needs REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, and Google Play
/// rejected Syncthing's release for declaring it ("Remove
/// android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS from your
/// manifest", syncthing-android issue 1039, 2018). No Android API reports
/// whether an app is locked in Recents, so that step is instructions only.
Future<void> showKeepRunningDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _KeepRunningDialog(),
  );
}

class _KeepRunningDialog extends StatefulWidget {
  const _KeepRunningDialog();

  @override
  State<_KeepRunningDialog> createState() => _KeepRunningDialogState();
}

class _KeepRunningDialogState extends State<_KeepRunningDialog> {
  bool? _exempt;

  @override
  void initState() {
    super.initState();
    unawaited(_checkExempt());
  }

  Future<void> _checkExempt() async {
    final exempt = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    if (mounted) setState(() => _exempt = exempt);
  }

  Future<void> _openBatterySettings() async {
    await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
    await _checkExempt();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exempt = _exempt;
    return AlertDialog(
      title: const Text('Keep fhirant running'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Phones stop apps they think are idle. On battery, a phone '
              'can stop fhirant within minutes, and other devices lose the '
              'server. Two settings keep it running.',
            ),
            const SizedBox(height: 16),
            Text(
              '1. Turn off battery optimisation',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            if (exempt ?? false)
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Expanded(child: Text('Done: fhirant is not optimised.')),
                ],
              )
            else ...[
              // Wording read off a OnePlus on Android 16 (App battery usage
              // → FHIR ANT → Allow background usage → Unrestricted); older
              // Android's list says Don't optimize (developer.android.com
              // doze-standby: Settings > Battery > Battery Optimization).
              const Text(
                'In the list that opens, find FHIR ANT. Newer phones: tap '
                'Allow background usage, then choose Unrestricted. Older '
                "phones: choose All apps, then set FHIR ANT to Don't "
                'optimize.',
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: exempt == null ? null : _openBatterySettings,
                child: const Text('Open battery settings'),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              '2. Lock fhirant in recent apps',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            const Text(
              'OnePlus: swipe up from the bottom and hold to open recent '
              "apps, tap More on fhirant's card, then tap Lock.",
            ),
            const SizedBox(height: 4),
            TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => unawaited(
                launchUrl(
                  Uri.parse('https://dontkillmyapp.com/'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              child: const Text('Other phones: dontkillmyapp.com'),
            ),
            const SizedBox(height: 8),
            Text(
              'If the phone stops fhirant anyway, the server starts again '
              'by itself within about 20 seconds. Keeping the phone on a '
              'charger also helps.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
