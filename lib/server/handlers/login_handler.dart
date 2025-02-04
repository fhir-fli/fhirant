import 'dart:convert';
import 'dart:math';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:fhirant/fhirant.dart';
import 'package:flutter_passkey/flutter_passkey.dart';
import 'package:shelf/shelf.dart';

const _secretKey = 'your-very-secure-secret';

/// Generates a secure random challenge for WebAuthn authentication
String _generateChallenge() {
  final random = Random.secure();
  final values = List<int>.generate(32, (i) => random.nextInt(256));
  return base64Url.encode(values);
}

/// Updated handler for the login route with challenge storage and verification.
Future<Response> loginHandler(Request request) async {
  try {
    if (request.method != 'POST') {
      FhirAntLoggingService().logWarning(
        'Invalid request method: ${request.method}',
      );
      return Response(405, body: jsonEncode({'error': 'Method Not Allowed'}));
    }

    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    if (!body.containsKey('username')) {
      FhirAntLoggingService().logWarning('Login attempt without username');
      return Response(400, body: jsonEncode({'error': 'Username required'}));
    }

    final username = body['username'];
    if (username is! String) {
      FhirAntLoggingService().logWarning('Invalid username format: $username');
      return Response(400, body: jsonEncode({'error': 'Invalid username'}));
    }

    FhirAntLoggingService().logInfo('Login attempt for user: $username');

    // Retrieve stored passkey credential.
    final storage = SecureStorageService();
    final storedCredential = await storage.getPasskey(username);

    if (storedCredential == null) {
      FhirAntLoggingService().logWarning('User not registered: $username');
      return Response(401, body: jsonEncode({'error': 'User not registered'}));
    }

    // Generate a secure challenge for authentication and store it.
    final challenge = _generateChallenge();
    pendingLoginChallenges[username] = challenge;

    // Create WebAuthn authentication options.
    final options = jsonEncode({
      'challenge': challenge,
      'rpId': 'fhirserver.local',
      'allowCredentials': [
        {
          'type': 'public-key',
          'id': storedCredential,
          'transports': ['internal'],
        },
      ],
      'timeout': 60000,
      'userVerification': 'preferred',
    });

    // Call getCredential to trigger passkey authentication.
    final authResponse = await FlutterPasskey().getCredential(options);

    if (authResponse.isEmpty) {
      FhirAntLoggingService().logWarning(
        'Authentication failed for user: $username',
      );
      pendingLoginChallenges.remove(username);
      return Response(
        401,
        body: jsonEncode({'error': 'Authentication failed'}),
      );
    }

    // Decode the assertion response.
    final assertion = jsonDecode(authResponse) as Map<String, dynamic>;
    final clientDataJSONBase64 = assertion['clientDataJSON'] as String;
    final clientDataJSONStr = utf8.decode(
      base64Url.decode(clientDataJSONBase64),
    );
    final clientData = jsonDecode(clientDataJSONStr) as Map<String, dynamic>;

    // Verify that the challenge matches the one stored.
    if (clientData['challenge'] != challenge) {
      FhirAntLoggingService().logWarning(
        'Challenge mismatch during login for user: $username',
      );
      pendingLoginChallenges.remove(username);
      return Response(400, body: jsonEncode({'error': 'Challenge mismatch'}));
    }

    // Remove the stored challenge.
    pendingLoginChallenges.remove(username);

    // Generate JWT token with the expiration expressed in seconds.
    final token = JWT({
      'username': username,
      'exp':
          DateTime.now().add(const Duration(days: 90)).millisecondsSinceEpoch ~/
          1000,
    }).sign(SecretKey(_secretKey));

    FhirAntLoggingService().logInfo(
      'User authenticated successfully: $username',
    );

    return Response.ok(
      jsonEncode({'token': token}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirAntLoggingService().logError('Login failed', e, stackTrace);
    return Response(
      500,
      body: jsonEncode({'error': 'Login failed: $e'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
