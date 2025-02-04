import 'dart:io';
import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant/fhirant.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// PrimaryScreen as a ConsumerStatefulWidget to allow provider access.
class PrimaryScreen extends ConsumerStatefulWidget {
  /// Constructor
  const PrimaryScreen({super.key});

  @override
  ConsumerState<PrimaryScreen> createState() => _PrimaryScreenState();
}

class _PrimaryScreenState extends ConsumerState<PrimaryScreen> {
  // Instead of creating our own _dbService and _serverManager,
  // we will read them from Riverpod providers.
  // Other state remains unchanged.

  // Server status notifier
  final ValueNotifier<bool> isServerRunning = ValueNotifier<bool>(false);

  // State variables for managing resources
  List<Resource> displayedResources = [];
  List<String> validResourceTypes = [];
  String? selectedResourceType;

  // Store the server URL
  String? serverUrl;

  @override
  void initState() {
    super.initState();
    // We want to initialize the resource types after the first frame is built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeResources();
    });
  }

  /// Initialize valid resource types and update the UI.
  Future<void> _initializeResources() async {
    try {
      // Read the DbService from the provider.
      final dbService = ref.read(dbServiceProvider);
      final validTypes = await dbService.getValidResourceTypes();
      if (!mounted) return;
      setState(() {
        validResourceTypes =
            validTypes.map((validType) => validType.toString()).toList();
      });
    } catch (e) {
      _showError('Failed to load resource types: $e');
    }
  }

  /// Load FHIR resources from a directory and update the UI.
  Future<void> _loadFhirResources(String directoryPrefix) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final dbService = ref.read(dbServiceProvider);
      final resources = await dbService.loadResourcesFromAssets(
        directoryPrefix,
      );
      if (!mounted) return;
      if (resources.isEmpty) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('No resources found in $directoryPrefix')),
        );
      } else {
        await _initializeResources(); // Refresh the resource types.
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              'Resources successfully loaded from $directoryPrefix',
            ),
          ),
        );
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Error loading resources: $e')),
      );
    }
  }

  /// Start the FHIR server and provide feedback to the user.
  Future<void> _startServer() async {
    try {
      final serverManager = ref.read(serverManagerProvider);
      await serverManager.start();
      final ipAddress = await _getLocalIpAddress();
      final port = serverManager.port;
      if (ipAddress != null && port != null) {
        setState(() {
          serverUrl = 'http://$ipAddress:$port';
        });
        isServerRunning.value = true;
        _showMessage('Server started at $serverUrl');
      } else {
        _showMessage('Could not determine server IP address or port.');
      }
    } catch (e) {
      _showError('Failed to start server: $e');
    }
  }

  /// Stop the FHIR server and provide feedback to the user.
  Future<void> _stopServer() async {
    try {
      final serverManager = ref.read(serverManagerProvider);
      await serverManager.stop();
      setState(() {
        serverUrl = null;
      });
      isServerRunning.value = false;
      _showMessage('Server stopped');
    } catch (e) {
      _showError('Failed to stop server: $e');
    }
  }

  /// Get the local IP address.
  Future<String?> _getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback) return address.address;
        }
      }
    } catch (e) {
      _showError('Error retrieving local IP address: $e');
    }
    return null;
  }

  /// Show an error message in a snackbar.
  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Show a success message in a snackbar.
  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Display resources of a selected type.
  Future<void> _showResources() async {
    if (selectedResourceType == null) return;
    final resourceType = R4ResourceType.fromString(selectedResourceType!);
    if (resourceType == null) return;
    final dbService = ref.read(dbServiceProvider);
    final resources = await dbService.getAllResources(resourceType);
    setState(() {
      displayedResources = resources;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Optionally, if you want to rebuild on serverManager changes, 
    // use ref.watch.
    return Scaffold(
      appBar: FhirantAppBar(isServerRunning),
      drawer: FhirantDrawer(
        onLoadMimicData: () => _loadFhirResources('assets/mimic'),
        onLoadExampleData: () => _loadFhirResources('assets/fhir_spec'),
        onStartServer: _startServer,
        onStopServer: _stopServer,
        serverUrl: serverUrl ?? 'Server not running',
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            // Pass the DbService from the provider to DatabaseOverview.
            DatabaseOverview(ref.read(dbServiceProvider)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedResourceType,
              hint: const Text('Select Resource Type'),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              items:
                  validResourceTypes.map((type) {
                    return DropdownMenuItem(value: type, child: Text(type));
                  }).toList(),
              onChanged: (type) async {
                selectedResourceType = type;
                await _showResources();
              },
            ),
            const SizedBox(height: 16),
            Expanded(child: ResourceList(displayedResources)),
          ],
        ),
      ),
    );
  }
}
