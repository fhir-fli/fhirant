import 'package:fhirant/app/app.dart';
import 'package:fhirant/app/initialize_service.dart';
import 'package:fhirant/app/signaling_server.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Only initialize the background service for mobile platforms
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    await initializeService();
  }

  // For Linux (and other platforms), start the server directly in development 
  // mode
  if (defaultTargetPlatform == TargetPlatform.linux || !kIsWeb) {
    final signalingServer = SignalingServer();
    await signalingServer.startServer();
    // ignore: avoid_print
    print('Signaling server started on Linux.');
  }

  runApp(const App());
}
