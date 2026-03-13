import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/server_state.dart';
import 'dashboard_screen.dart';

/// Parse JSON bundle and deserialize resources off the main isolate.
List<Map<String, dynamic>> _parseBundle(String jsonStr) {
  final bundle = jsonDecode(jsonStr) as Map<String, dynamic>;
  final entries = bundle['entry'] as List? ?? [];
  return entries
      .map((e) => (e as Map<String, dynamic>)['resource'] as Map<String, dynamic>?)
      .whereType<Map<String, dynamic>>()
      .toList();
}

const _onboardingCompleteKey = 'onboarding_complete';

/// Check whether onboarding has been completed.
Future<bool> isOnboardingComplete() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_onboardingCompleteKey) ?? false;
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;
  bool _loadingSampleData = false;
  String? _sampleDataResult;

  static const _pageCount = 3;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingCompleteKey, true);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    }
  }

  Future<void> _loadSampleData() async {
    setState(() {
      _loadingSampleData = true;
      _sampleDataResult = null;
    });

    try {
      final state = context.read<ServerState>();

      // Start server in dev mode if not running
      final wasRunning = state.isRunning;
      if (!wasRunning) {
        state.port = 8080;
        state.devMode = true;
        await state.startServer();
        // Give server a moment to bind
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Parse JSON off the main isolate to avoid ANR
      final jsonStr = await rootBundle.loadString('assets/sample_data.json');
      final resourceJsons = await compute(_parseBundle, jsonStr);

      // Deserialize all resources
      final resources = <Resource>[];
      var errors = 0;
      for (final json in resourceJsons) {
        try {
          resources.add(Resource.fromJson(json));
        } catch (_) {
          errors++;
        }
      }

      if (mounted) {
        setState(() {
          _sampleDataResult =
              'Saving ${resources.length} resources to database...';
        });
      }
      await Future<void>.delayed(Duration.zero);

      // Batch save — single transaction, much faster than individual saves
      final db = state.db;
      await db.saveResources(resources);
      final saved = resources.length;

      // Stop server if we started it
      if (!wasRunning) {
        await state.stopServer();
      }

      setState(() {
        _sampleDataResult = 'Loaded $saved resources'
            '${errors > 0 ? ' ($errors errors)' : ''}';
      });
    } catch (e) {
      setState(() {
        _sampleDataResult = 'Error: $e';
      });
    } finally {
      setState(() {
        _loadingSampleData = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: [
                  _buildWelcomePage(theme),
                  _buildHowItWorksPage(theme),
                  _buildGetStartedPage(theme),
                ],
              ),
            ),
            // Page indicator + navigation
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  // Page dots
                  Row(
                    children: List.generate(_pageCount, (i) {
                      return Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == _currentPage
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline.withValues(alpha: 0.3),
                        ),
                      );
                    }),
                  ),
                  const Spacer(),
                  if (_currentPage < _pageCount - 1)
                    FilledButton(
                      onPressed: () => _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      ),
                      child: const Text('Next'),
                    )
                  else
                    FilledButton(
                      onPressed: _loadingSampleData ? null : _finishOnboarding,
                      child: const Text('Get Started'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomePage(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.dns_rounded,
            size: 80,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'FHIR ANT',
            style: theme.textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Fast Healthcare Interoperability Resources\nAgile Networking Tool',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Text(
            'A complete FHIR R4 server\nrunning on your phone.',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorksPage(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildFeatureRow(
            theme,
            Icons.play_arrow_rounded,
            'Start the server',
            'Tap Start to launch the FHIR server on your device.',
          ),
          const SizedBox(height: 24),
          _buildFeatureRow(
            theme,
            Icons.qr_code_rounded,
            'Connect from any device',
            'Use the QR code or URL to connect from a laptop, '
                'another phone, or any FHIR client.',
          ),
          const SizedBox(height: 24),
          _buildFeatureRow(
            theme,
            Icons.shield_rounded,
            'Dev Mode for testing',
            'Dev Mode skips authentication so you can explore '
                'the API immediately. Turn it off for secure access.',
          ),
          const SizedBox(height: 24),
          _buildFeatureRow(
            theme,
            Icons.backup_rounded,
            'Backup & restore',
            'Export all your data as a FHIR Bundle and restore '
                'it anytime. Your data stays on your device.',
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(
    ThemeData theme,
    IconData icon,
    String title,
    String description,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGetStartedPage(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.dataset_rounded,
            size: 60,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'Load Sample Data?',
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Optionally load a set of sample clinical data '
            '(from MIMIC-IV) to explore the server with '
            'realistic patients, encounters, and observations.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          if (_loadingSampleData)
            const Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading sample data...'),
              ],
            )
          else ...[
            OutlinedButton.icon(
              onPressed: _loadSampleData,
              icon: const Icon(Icons.download_rounded),
              label: const Text('Load Sample Data'),
            ),
            if (_sampleDataResult != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _sampleDataResult!.startsWith('Error')
                      ? theme.colorScheme.errorContainer
                      : theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _sampleDataResult!,
                  style: TextStyle(
                    color: _sampleDataResult!.startsWith('Error')
                        ? theme.colorScheme.onErrorContainer
                        : theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'You can always load or clear data later.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
