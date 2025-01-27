import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// FhirantDrawer
class FhirantDrawer extends StatelessWidget {
  /// Constructor
  const FhirantDrawer({
    required this.onLoadMimicData,
    required this.onLoadExampleData,
    required this.onStartServer,
    required this.onStopServer,
    required this.isServerRunning,
    required this.serverUrl,
    super.key,
  });

  /// Callback to load MIMIC data
  final VoidCallback onLoadMimicData;

  /// Callback to load example data
  final VoidCallback onLoadExampleData;

  /// Callback to start the server
  final VoidCallback onStartServer;

  /// Callback to stop the server
  final VoidCallback onStopServer;

  /// Server running status notifier
  final ValueNotifier<bool> isServerRunning;

  /// Current server URL
  final String serverUrl;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.indigo, Colors.blueAccent],
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/fhirant_logo.png', height: 80),
                const SizedBox(height: 8),
                const Text(
                  'FHIR ANT',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.download, color: Colors.indigo),
            title: const Text('Load Mimic Data'),
            onTap: () {
              Navigator.pop(context);
              onLoadMimicData();
              _showSnackbar(context, 'MIMIC data loading started...');
            },
          ),
          ListTile(
            leading: const Icon(Icons.cloud_download, color: Colors.indigo),
            title: const Text('Load Example Data'),
            onTap: () {
              Navigator.pop(context);
              onLoadExampleData();
              _showSnackbar(context, 'Loading FHIR Spec examples...');
            },
          ),
          ValueListenableBuilder<bool>(
            valueListenable: isServerRunning,
            builder: (context, running, child) {
              return ListTile(
                leading: Icon(
                  running
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outlined,
                  color: Colors.indigo,
                ),
                title: Text(running ? 'Stop Server' : 'Start Server'),
                onTap: () {
                  Navigator.pop(context);
                  running ? onStopServer() : onStartServer();
                  _showSnackbar(
                    context,
                    running
                        ? 'Stopping the server...'
                        : 'Starting the server...',
                  );
                },
              );
            },
          ),
          const Divider(),
          ValueListenableBuilder<bool>(
            valueListenable: isServerRunning,
            builder: (context, running, child) {
              if (!running) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Server is not running.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }
              return Column(
                children: [
                  ListTile(
                    title: const Text(
                      'Server Address:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      serverUrl,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                  Center(child: QrCodeWidget(serverUrl: serverUrl)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Shows a snackbar with the provided [message].
  void _showSnackbar(BuildContext context, String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

/// QrCodeWidget
class QrCodeWidget extends StatelessWidget {
  /// Constructor
  const QrCodeWidget({required this.serverUrl, super.key});

  /// Server URL
  final String serverUrl;

  @override
  Widget build(BuildContext context) {
    if (serverUrl.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Invalid server URL', style: TextStyle(color: Colors.red)),
      );
    }

    return Tooltip(
      message: 'Scan to access the server URL',
      child: QrImageView(
        data: serverUrl,
        size: 120,
        backgroundColor: Colors.white,
      ),
    );
  }
}
