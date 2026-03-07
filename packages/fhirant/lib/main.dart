import 'dart:io';

import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'src/screens/dashboard_screen.dart';
import 'src/screens/onboarding_screen.dart';
import 'src/services/database_service.dart';
import 'src/services/server_service.dart';
import 'src/state/server_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize logging — write to app docs dir on mobile, or skip file logging
  String? logFilePath;
  try {
    final docsDir = await getApplicationDocumentsDirectory();
    logFilePath = '${docsDir.path}/fhirant_server_logs.json';
  } catch (_) {
    // path_provider may fail on some platforms — skip file logging
  }
  FhirantLogging().initialize(logFilePath: logFilePath);

  // Initialize foreground task for Android
  if (Platform.isAndroid) {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'fhirant_server',
        channelName: 'FHIR ANT Server',
        channelDescription: 'Keeps the FHIR server running in the background',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  // Initialize database
  final dbService = DatabaseService();
  await dbService.initialize();

  // Create server service
  final serverService = ServerService(dbService);

  // Check if onboarding has been completed
  final showOnboarding = !await isOnboardingComplete();

  runApp(
    ChangeNotifierProvider(
      create: (_) => ServerState(
        dbService: dbService,
        serverService: serverService,
      ),
      child: FhirantApp(showOnboarding: showOnboarding),
    ),
  );
}

class FhirantApp extends StatefulWidget {
  final bool showOnboarding;

  const FhirantApp({super.key, this.showOnboarding = false});

  @override
  State<FhirantApp> createState() => _FhirantAppState();
}

class _FhirantAppState extends State<FhirantApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (Platform.isIOS && state == AppLifecycleState.paused) {
      // Stop the server when the app goes to the background on iOS
      context.read<ServerState>().stopServer();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show onboarding on first launch, otherwise dashboard
    Widget home = widget.showOnboarding
        ? const OnboardingScreen()
        : const DashboardScreen();
    if (Platform.isAndroid) {
      home = WithForegroundTask(child: home);
    }

    return MaterialApp(
      title: 'FHIR ANT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: home,
    );
  }
}
