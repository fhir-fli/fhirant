import 'dart:convert';
import 'dart:math';

import 'package:fhirant/fhirant.dart';
import 'package:flutter_passkey/flutter_passkey.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';

final Logger _logger = Logger('RegisterHandler');

/// Generates a secure random challenge for WebAuthn authentication
String _generateChallenge() {
  final random = Random.secure();
  final values = List<int>.generate(32, (i) => random.nextInt(256));
  return base64Url.encode(values);
}

/// Handler for the register route
Future<Response> registerHandler(Request request) async {
  try {
    final requestData =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;

    if (!requestData.containsKey('username')) {
      _logger.warning('Registration attempt without username');
      return Response(400, body: jsonEncode({'error': 'Username required'}));
    }

    final username = requestData['username'];
    if (username is! String) {
      _logger.warning('Invalid username format: $username');
      return Response(400, body: jsonEncode({'error': 'Invalid username'}));
    }

    _logger.info('Registration attempt for user: $username');
    final challenge = _generateChallenge();

    // Create WebAuthn registration options
    final options = jsonEncode({
      'challenge': challenge,
      'rp': {'name': 'FHIR Server'},
      'user': {
        'id': base64Url.encode(utf8.encode(username)),
        'name': username,
        'displayName': username,
      },
      'pubKeyCredParams': [
        {'type': 'public-key', 'alg': -7}, // ES256
        {'type': 'public-key', 'alg': -257}, // RS256
      ],
      'authenticatorSelection': {
        'requireResidentKey': false,
        'userVerification': 'preferred',
      },
      'timeout': 60000,
    });

    // Call `createCredential` to generate a passkey
    final credential = await FlutterPasskey().createCredential(options);
    if (credential.isEmpty) {
      _logger.warning('Failed to generate passkey for user: $username');
      return Response(
        500,
        body: jsonEncode({'error': 'Passkey generation failed'}),
      );
    }

    // Store the passkey credentials securely
    final storage = SecureStorageService();
    await storage.storePasskey(username, credential);

    _logger.info('User registered successfully: $username');
    return Response.ok(
      jsonEncode({'message': 'User registered', 'challenge': challenge}),
    );
  } catch (e, stackTrace) {
    _logger.severe('Registration failed', e, stackTrace);
    return Response(
      500,
      body: jsonEncode({'error': 'Registration failed: $e'}),
    );
  }
}
