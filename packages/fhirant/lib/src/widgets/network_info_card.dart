import 'dart:async';
import 'dart:convert';

import 'package:fhirant/src/state/server_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

class NetworkInfoCard extends StatelessWidget {
  const NetworkInfoCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ServerState>(
      builder: (context, state, _) {
        final url = state.serverUrl;
        final fingerprint = state.certificateFingerprint;

        if (!state.isRunning) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.wifi_off, color: Colors.grey.shade400),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Start the server to see network info',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.wifi, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      'Network',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (url != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          url,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        tooltip: 'Copy URL',
                        onPressed: () {
                          unawaited(
                            Clipboard.setData(ClipboardData(text: url)),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('URL copied to clipboard'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  if (fingerprint != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Certificate fingerprint (SHA-256)',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 2),
                    // The connection is TLS with a self-signed certificate, so
                    // a joining device cannot check it by name. It checks this
                    // instead — which means the operator has to be able to
                    // read it out, and the QR carries it so they usually will
                    // not have to.
                    SelectableText(
                      fingerprint,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Center(
                    child: QrImageView(
                      // Address and fingerprint together: scanning is what
                      // pairs a device, and pairing without the fingerprint
                      // would mean trusting whatever certificate answered.
                      data: fingerprint == null
                          ? url
                          : jsonEncode({'url': url, 'sha256': fingerprint}),
                      size: 180,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ] else ...[
                  Text(
                    'Unable to detect WiFi IP address.\n'
                    'Connect to a WiFi network to share.',
                    style: TextStyle(color: Colors.orange.shade700),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
