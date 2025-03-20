import 'dart:io';
import 'package:fhirant/fhirant.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Assume these providers are defined elsewhere.
final serverManagerProvider = Provider<ServerManager>((ref) {
  throw UnimplementedError('serverManagerProvider not implemented');
});

/// DashboardScreen shows the server status, network details, and quick actions.
class DashboardScreen extends ConsumerStatefulWidget {
  /// Constructor
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String? _ipAddress;
  bool _isLoadingIp = false;

  @override
  void initState() {
    super.initState();
    _loadIpAddress();
  }

  Future<void> _loadIpAddress() async {
    setState(() {
      _isLoadingIp = true;
    });

    final ip = await _getLocalIpAddress();

    if (mounted) {
      setState(() {
        _ipAddress = ip;
        _isLoadingIp = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverManager = ref.watch(serverManagerProvider);
    final isRunning = serverManager.isRunning;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Header
            Text(
              'Server Status',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  isRunning ? Icons.check_circle : Icons.error,
                  color: isRunning ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  isRunning ? 'Server is Running' : 'Server is Stopped',
                  style: const TextStyle(fontSize: 18),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Network Info (only when running)
            if (isRunning) ...[
              Row(
                children: [
                  const Text(
                    'Network Information',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _loadIpAddress,
                    tooltip: 'Refresh IP Address',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_isLoadingIp)
                const Center(child: CircularProgressIndicator())
              else if (_ipAddress != null) ...[
                Text(
                  'Server URL: https://$_ipAddress:${serverManager.port ?? 8080}',
                ),
                const SizedBox(height: 8),
                // Display a QR code for quick access.
                Center(
                  child: QrImageView(
                    data: 'https://$_ipAddress:${serverManager.port ?? 8080}',
                    size: 120,
                    backgroundColor: Colors.white,
                  ),
                ),
              ] else
                const Text('Unable to determine IP address.'),
            ],
            const SizedBox(height: 24),

            // Quick Actions section
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            // Start/Stop Server
            ElevatedButton.icon(
              onPressed: () async {
                if (isRunning) {
                  await serverManager.stop();
                } else {
                  await serverManager.start();
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isRunning
                            ? 'Server stopped'
                            : 'Server started successfully',
                      ),
                    ),
                  );
                }
              },
              icon: Icon(isRunning ? Icons.stop : Icons.play_arrow),
              label: Text(isRunning ? 'Stop Server' : 'Start Server'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 12),

            // Generate Registration Code
            ElevatedButton.icon(
              onPressed: isRunning
                  ? () {
                      final code = serverManager.generateRegistrationCode();
                      setState(() {}); // Refresh UI to show QR code
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Registration Code: $code')),
                      );
                    }
                  : null, // Disable when server is not running
              icon: const Icon(Icons.qr_code),
              label: const Text('Generate Registration Code'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 24),

            // Registration settings
            if (isRunning) ...[
              Text(
                'Registration Settings',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),

              // Toggle for open registration
              SwitchListTile(
                title: const Text('Allow Open Registration'),
                subtitle: const Text('Anyone can register without a code'),
                value: serverManager.isRegistrationOpen,
                onChanged: (value) {
                  if (value) {
                    serverManager.allowGeneralRegistration();
                  } else {
                    serverManager.closeGeneralRegistration();
                  }
                  setState(() {}); // Refresh UI
                },
              ),
              const SizedBox(height: 16),
            ],

            // Show Registration QR Code (if available and server is running)
            if (isRunning && serverManager.registrationCode != null) ...[
              const Divider(),
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Current Registration Code',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.content_copy),
                        onPressed: () {
                          // Add clipboard functionality here
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Code copied to clipboard'),
                            ),
                          );
                        },
                        tooltip: 'Copy to clipboard',
                      ),
                    ],
                  ),
                  Text('Code: ${serverManager.registrationCode}'),
                  const SizedBox(height: 12),
                  const Text('Scan QR Code to Register:'),
                  const SizedBox(height: 8),
                  Center(
                    child: QrImageView(
                      data: serverManager.registrationCode!,
                      size: 150,
                      backgroundColor: Colors.white,
                      errorStateBuilder: (context, error) {
                        return const Center(
                          child: Text(
                            'Error generating QR code',
                            style: TextStyle(color: Colors.red),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This code will expire in 5 minutes.',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Helper method to get the local IPv4 address.
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
      debugPrint('Error retrieving IP address: $e');
    }
    return null;
  }
}
