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
    required this.isRegistrationOpen,
    required this.registrationCode,
    required this.generateRegistrationCode,
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

  /// Registration open status
  final bool isRegistrationOpen;

  /// Registration code
  final String? registrationCode; // Registration code to display

  /// Callback to generate a new registration code
  final VoidCallback generateRegistrationCode;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Drawer header with logo and title
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
          // List tile to load MIMIC data
          ListTile(
            leading: const Icon(Icons.download, color: Colors.indigo),
            title: const Text('Load Mimic Data'),
            onTap: () {
              Navigator.pop(context);
              onLoadMimicData();
              _showSnackbar(context, 'MIMIC data loading started...');
            },
          ),
          // List tile to load example data
          ListTile(
            leading: const Icon(Icons.cloud_download, color: Colors.indigo),
            title: const Text('Load Example Data'),
            onTap: () {
              Navigator.pop(context);
              onLoadExampleData();
              _showSnackbar(context, 'Loading FHIR Spec examples...');
            },
          ),
          // List tile to start/stop the server
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
          // Show QR code only if registration is open
          if (isRegistrationOpen && registrationCode != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text(
                    'Scan this QR Code to Register:',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  QrCodeWidget(
                    serverUrl: registrationCode!,
                  ), // Display QR code with registration code
                  const SizedBox(height: 10),
                  const Text(
                    'Scan the code using the registration app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          // Button to generate a new registration code
          if (isRegistrationOpen)
            ListTile(
              leading: const Icon(Icons.qr_code, color: Colors.indigo),
              title: const Text('Generate New Registration Code'),
              onTap: () {
                generateRegistrationCode();
                _showSnackbar(context, 'New registration code generated.');
              },
            ),
          // Show server details when it's running
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

  /// Server URL to display
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
