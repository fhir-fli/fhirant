import 'package:fhirant/app/signaling_server.dart';
import 'package:flutter/material.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: SignalingServerPage(),
    );
  }
}

class SignalingServerPage extends StatefulWidget {
  const SignalingServerPage({super.key});

  @override
  State<SignalingServerPage> createState() => _SignalingServerPageState();
}

class _SignalingServerPageState extends State<SignalingServerPage> {
  final SignalingServer _server = SignalingServer();
  bool _isRunning = false;

  Future<void> _startServer() async {
    await _server.startServer();
    setState(() {
      _isRunning = true;
    });
  }

  Future<void> _stopServer() async {
    await _server.stopServer();
    setState(() {
      _isRunning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signaling Server')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_isRunning ? 'Server is running' : 'Server is stopped'),
            ElevatedButton(
              onPressed: _isRunning ? _stopServer : _startServer,
              child: Text(_isRunning ? 'Stop Server' : 'Start Server'),
            ),
          ],
        ),
      ),
    );
  }
}
