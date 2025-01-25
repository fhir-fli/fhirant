import 'dart:io';
import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant/fhirant.dart';
import 'package:flutter/material.dart';

/// PrimaryScreen
class PrimaryScreen extends StatefulWidget {
  /// Constructor
  const PrimaryScreen({super.key});

  @override
  State<PrimaryScreen> createState() => _PrimaryScreenState();
}

class _PrimaryScreenState extends State<PrimaryScreen> {
  // Database service instance
  final DbService dbService = DbService();

  // Server status notifier
  final ValueNotifier<bool> isServerRunning = ValueNotifier<bool>(false);

  // State variables for managing resources
  List<Resource> displayedResources = [];
  List<String> validResourceTypes = [];
  String? selectedResourceType;

  @override
  void initState() {
    super.initState();
    _initializeResources();
  }

  @override
  void dispose() {
    dbService.close(); // Close database connection
    super.dispose();
  }

  Future<void> _initializeResources() async {
    try {
      final validTypes = await dbService.getValidResourceTypes();
      setState(() {
        validResourceTypes = validTypes;
      });
    } catch (e) {
      _showError('Failed to load resource types: $e');
    }
  }

  /// Load FHIR resources from a directory
  Future<void> _loadFhirResources(String directoryPrefix) async {
    try {
      final resources =
          await dbService.loadResourcesFromAssets(directoryPrefix);
      if (resources.isNotEmpty) await _initializeResources();
    } catch (e) {
      _showError('Error loading resources: $e');
    }
  }

  /// Show error in a snackbar
  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  /// Start the server
  Future<void> _startServer() async {
    try {
      await ServerManager().start();
      final ipAddress = await _getLocalIpAddress();
      final port = ServerManager().port;

      if (ipAddress != null && port != null) {
        final serverUrl = 'http://$ipAddress:$port';
        isServerRunning.value = true;
        _showMessage('Server started at $serverUrl');
      } else {
        _showMessage('Could not determine server IP address or port.');
      }
    } catch (e) {
      _showError('Failed to start server: $e');
    }
  }

  /// Stop the server
  Future<void> _stopServer() async {
    try {
      await ServerManager().stop();
      isServerRunning.value = false;
      _showMessage('Server stopped');
    } catch (e) {
      _showError('Failed to stop server: $e');
    }
  }

  /// Get the local IP address
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

  /// Show a success message in a snackbar
  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  /// Display resources of a selected type
  void _showResources() {
    if (selectedResourceType == null) return;
    final resources = dbService.getAllResources(selectedResourceType!);
    setState(() {
      displayedResources = resources;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: FhirantAppBar(isServerRunning),
      drawer: FhirantDrawer(
        onLoadMimicData: () => _loadFhirResources('mimic-fhir'),
        onLoadExampleData: () => _loadFhirResources('fhir-assets'),
        onStartServer: _startServer,
        onStopServer: _stopServer,
        isServerRunning: isServerRunning,
        serverUrl: 'http://localhost:8080',
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            DatabaseOverview(dbService),
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
              items: validResourceTypes.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(type),
                );
              }).toList(),
              onChanged: (type) {
                setState(() {
                  selectedResourceType = type;
                  _showResources();
                });
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ResourceList(displayedResources),
            ),
          ],
        ),
      ),
    );
  }
}
