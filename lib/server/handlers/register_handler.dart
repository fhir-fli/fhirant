import 'dart:convert';
import 'dart:math';
import 'package:fhirant/fhirant.dart';
import 'package:flutter_passkey/flutter_passkey.dart';
import 'package:shelf/shelf.dart';

/// Generates a secure random challenge for WebAuthn
String _generateChallenge() {
  final random = Random.secure();
  final values = List<int>.generate(32, (i) => random.nextInt(256));
  return base64Url.encode(values);
}

/// Register a new user
Future<Response> registerHandler(Request request) async {
  try {
    final requestData =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;

    if (!requestData.containsKey('username')) {
      return Response(400, body: jsonEncode({'error': 'Username required'}));
    }

    final username = requestData['username'];
    if (username is! String) {
      return Response(400, body: jsonEncode({'error': 'Invalid username'}));
    }
    final challenge = _generateChallenge();

    // Create WebAuthn registration options
    final options = jsonEncode({
      'challenge': challenge,
      'rp': {'name': 'FHIR Server'},
      'user': {
        'id': base64Url.encode(
          utf8.encode(username),
        ), // WebAuthn requires encoding
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

    // Store the passkey credentials securely
    final storage = SecureStorageService();
    await storage.storePasskey(username, credential);

    return Response.ok(
      jsonEncode({
        'message': 'User registered',
        'challenge': challenge, // The client may need to verify this
      }),
    );
  } catch (e) {
    return Response(
      500,
      body: jsonEncode({'error': 'Registration failed: $e'}),
    );
  }
}
