import 'package:fhirant/fhirant.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Updated FhirantDrawer as a ConsumerWidget that reads server state from
/// a provider.
class FhirantDrawer extends ConsumerWidget {
  /// Constructor – only the UI callbacks are passed in.
  const FhirantDrawer({
    required this.onLoadMimicData,
    required this.onLoadExampleData,
    required this.onStartServer,
    required this.onStopServer,
    this.serverUrl = 'Server is not running',
    super.key,
  });

  /// Callback to load MIMIC data.
  final VoidCallback onLoadMimicData;

  /// Callback to load example data.
  final VoidCallback onLoadExampleData;

  /// Callback to start the server.
  final VoidCallback onStartServer;

  /// Callback to stop the server.
  final VoidCallback onStopServer;

  /// Server URL to display in the drawer.
  final String serverUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Read server state from the provider.
    final serverManager = ref.watch(serverManagerProvider);
    String? registrationCode;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Drawer header with logo and title.
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
          // List tile to load MIMIC data.
          ListTile(
            leading: const Icon(Icons.download, color: Colors.indigo),
            title: const Text('Load Mimic Data'),
            onTap: () {
              Navigator.pop(context);
              onLoadMimicData();
              _showSnackbar(context, 'MIMIC data loading started...');
            },
          ),
          const Divider(),
          // List tile to load example data.
          ListTile(
            leading: const Icon(Icons.cloud_download, color: Colors.indigo),
            title: const Text('Load FHIR Spec'),
            onTap: () {
              Navigator.pop(context);
              onLoadExampleData();
              _showSnackbar(context, 'Loading FHIR Spec examples...');
            },
          ),
          const Divider(),
          // List tile to start/stop the server.
          ListTile(
            leading: Icon(
              serverManager.isRunning
                  ? Icons.stop_circle_outlined
                  : Icons.play_circle_outlined,
              color: Colors.indigo,
            ),
            title: Text(
              serverManager.isRunning ? 'Stop Server' : 'Start Server',
            ),
            onTap: () {
              Navigator.pop(context);
              serverManager.isRunning ? onStopServer() : onStartServer();
              _showSnackbar(
                context,
                serverManager.isRunning
                    ? 'Stopping the server...'
                    : 'Starting the server...',
              );
            },
          ),
          const Divider(),
          if (serverManager.isRunning)
            ListTile(
              leading: Icon(
                serverManager.isRegistrationOpen
                    ? Icons.lock_outline
                    : Icons.lock_open_outlined,
                color: Colors.indigo,
              ),
              title: Text(
                serverManager.isRegistrationOpen
                    ? 'Close Registration'
                    : 'Open Registration',
              ),
              onTap: () {
                Navigator.pop(context);
                serverManager.isRegistrationOpen
                    ? serverManager.closeGeneralRegistration()
                    : serverManager.allowGeneralRegistration();
              },
            ),
          if (serverManager.isRunning) const Divider(),
          // Button to generate a new registration code.
          if (serverManager.isRunning)
            ListTile(
              leading: const Icon(Icons.qr_code, color: Colors.indigo),
              title: const Text('Generate New Registration Code'),
              onTap: () {
                registrationCode = serverManager.generateRegistrationCode();
              },
            ),
          // Show QR code for registration if registration is open.
          if (registrationCode != null)
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
                    qrString: serverManager.registrationCode!,
                    errorMessage: 'Invalid registration code',
                    message: 'Scan to register',
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Scan the code using the registration app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),

          // Show server details when it's running.
          if (serverManager.isRunning)
            Column(
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
                Center(
                  child: QrCodeWidget(
                    qrString: serverUrl,
                    errorMessage: 'Invalid server URL',
                    message: 'Scan to access the server URL',
                  ),
                ),
              ],
            )
          else
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Server is not running.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  /// Shows a snackbar with the provided message.
  void _showSnackbar(BuildContext context, String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

/// A widget to display a QR code for the server URL.
class QrCodeWidget extends StatelessWidget {
  /// Constructor – the server URL is required.
  const QrCodeWidget({
    required this.qrString,
    this.errorMessage,
    this.message,
    super.key,
  });

  /// Server URL to display as a QR code.
  final String qrString;

  /// Error message to display if the String is empty.
  final String? errorMessage;

  /// Message to display below the QR code.
  final String? message;

  @override
  Widget build(BuildContext context) {
    if (qrString.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          errorMessage ?? 'Empty String',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
    return Tooltip(
      message: message,
      child: QrImageView(
        data: qrString,
        size: 120,
        backgroundColor: Colors.white,
      ),
    );
  }
}
