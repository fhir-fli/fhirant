import 'dart:convert';
import 'dart:math';
import 'package:fhirant/fhirant.dart';
import 'package:flutter_passkey/flutter_passkey.dart';
import 'package:shelf/shelf.dart';

/// Generates a secure random challenge for WebAuthn authentication
String _generateChallenge() {
  final random = Random.secure();
  final values = List<int>.generate(32, (i) => random.nextInt(256));
  return base64Url.encode(values);
}

/// Updated handler for the register route with challenge storage and verification.
Future<Response> registerHandler(
  Request request,
  String? registrationCode,
  // ignore: avoid_positional_boolean_parameters
  bool isRegistrationOpen,
) async {
  try {
    final requestData =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;

    if (!requestData.containsKey('username')) {
      FhirAntLoggingService().logWarning(
        'Registration attempt without username',
      );
      return Response(400, body: jsonEncode({'error': 'Username required'}));
    }

    final username = requestData['username'];
    if (username is! String) {
      FhirAntLoggingService().logWarning('Invalid username format: $username');
      return Response(400, body: jsonEncode({'error': 'Invalid username'}));
    }

    FhirAntLoggingService().logInfo('Registration attempt for user: $username');

    // Generate a secure challenge and store it temporarily.
    final challenge = _generateChallenge();
    pendingRegistrationChallenges[username] = challenge;

    // Create WebAuthn registration options.
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

    // Call `createCredential` to generate a passkey.
    final credential = await FlutterPasskey().createCredential(options);
    if (credential.isEmpty) {
      FhirAntLoggingService().logWarning(
        'Failed to generate passkey for user: $username',
      );
      pendingRegistrationChallenges.remove(username);
      return Response(
        500,
        body: jsonEncode({'error': 'Passkey generation failed'}),
      );
    }

    // Decode the attestation response (assuming it’s a JSON string)
    final attestation = jsonDecode(credential) as Map<String, dynamic>;
    final clientDataJSONBase64 = attestation['clientDataJSON'] as String;
    final clientDataJSONStr = utf8.decode(
      base64Url.decode(clientDataJSONBase64),
    );
    final clientData = jsonDecode(clientDataJSONStr) as Map<String, dynamic>;

    // Verify that the challenge matches what was generated.
    if (clientData['challenge'] != challenge) {
      FhirAntLoggingService().logWarning(
        'Challenge mismatch during registration for user: $username',
      );
      pendingRegistrationChallenges.remove(username);
      return Response(400, body: jsonEncode({'error': 'Challenge mismatch'}));
    }

    // Store the passkey credentials securely.
    final storage = SecureStorageService();
    await storage.storePasskey(username, credential);

    // Remove the stored challenge as it is no longer needed.
    pendingRegistrationChallenges.remove(username);

    FhirAntLoggingService().logInfo('User registered successfully: $username');
    return Response.ok(
      jsonEncode({'message': 'User registered', 'challenge': challenge}),
    );
  } catch (e, stackTrace) {
    FhirAntLoggingService().logError('Registration failed', e, stackTrace);
    return Response(
      500,
      body: jsonEncode({'error': 'Registration failed: $e'}),
    );
  }
}
