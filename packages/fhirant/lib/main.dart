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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FhirantStartup());
}

/// Shown while the app initializes (database, logging, etc.).
class FhirantStartup extends StatefulWidget {
  const FhirantStartup({super.key});

  @override
  State<FhirantStartup> createState() => _FhirantStartupState();
}

class _FhirantStartupState extends State<FhirantStartup> {
  late Future<_InitResult> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _initialize();
  }

  Future<_InitResult> _initialize() async {
    // Initialize logging
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
          channelDescription:
              'Keeps the FHIR server running in the background',
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

    return _InitResult(
      dbService: dbService,
      serverService: serverService,
      showOnboarding: showOnboarding,
    );
  }

  @override
  Widget build(BuildContext context) {
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
      home: FutureBuilder<_InitResult>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorScreen(
              error: snapshot.error!,
              onRetry: () => setState(() => _initFuture = _initialize()),
            );
          }
          if (!snapshot.hasData) {
            return const _LoadingScreen();
          }
          final result = snapshot.data!;
          return ChangeNotifierProvider(
            create: (_) => ServerState(
              dbService: result.dbService,
              serverService: result.serverService,
            ),
            child: _AppShell(showOnboarding: result.showOnboarding),
          );
        },
      ),
    );
  }
}

class _InitResult {
  final DatabaseService dbService;
  final ServerService serverService;
  final bool showOnboarding;

  _InitResult({
    required this.dbService,
    required this.serverService,
    required this.showOnboarding,
  });
}

class _AppShell extends StatefulWidget {
  final bool showOnboarding;

  const _AppShell({required this.showOnboarding});

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> with WidgetsBindingObserver {
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
      context.read<ServerState>().stopServer();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget home = widget.showOnboarding
        ? const OnboardingScreen()
        : const DashboardScreen();
    if (Platform.isAndroid) {
      home = WithForegroundTask(child: home);
    }
    return home;
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dns_rounded,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'FHIR ANT',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Initializing...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _ErrorScreen({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 24),
              Text(
                'Failed to start',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                error.toString(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
