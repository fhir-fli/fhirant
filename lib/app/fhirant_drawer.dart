import 'package:flutter/material.dart';

/// FhirantDrawer
class FhirantDrawer extends StatelessWidget {
  /// Constructor
  const FhirantDrawer({
    required this.onLoadMimicData,
    required this.onLoadExampleData,
    required this.onStartServer,
    required this.onStopServer,
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
                Image.asset(
                  'assets/fhirant_logo.png',
                  height: 80, // Adjust size as needed
                ),
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
            },
          ),
          ListTile(
            leading: const Icon(Icons.cloud_download, color: Colors.indigo),
            title: const Text('Load Example Data'),
            onTap: () {
              Navigator.pop(context);
              onLoadExampleData();
            },
          ),
          ListTile(
            leading:
                const Icon(Icons.play_circle_outlined, color: Colors.indigo),
            title: const Text('Start Server'),
            onTap: () {
              Navigator.pop(context);
              onStartServer();
            },
          ),
          ListTile(
            leading:
                const Icon(Icons.stop_circle_outlined, color: Colors.indigo),
            title: const Text('Stop Server'),
            onTap: () {
              Navigator.pop(context);
              onStopServer();
            },
          ),
        ],
      ),
    );
  }
}
