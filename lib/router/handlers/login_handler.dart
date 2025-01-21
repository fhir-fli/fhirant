import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:shelf/shelf.dart';

const _secretKey = 'your-very-secure-secret';
// Replace with a database in production.
const _users = {'admin': 'password123'};

/// Handler for the login route
Future<Response> loginHandler(Request request) async {
  if (request.method != 'POST') {
    return Response(405, body: 'Method Not Allowed');
  }

  final body = await request.readAsString();
  final credentials = jsonDecode(body) as Map<String, dynamic>;
  final username = credentials['username'];
  final password = credentials['password'];

  if (_users[username] == password) {
    final token = JWT({'username': username}).sign(SecretKey(_secretKey));
    return Response.ok(jsonEncode({'token': token}),
        headers: {'Content-Type': 'application/json'},);
  }

  return Response(401,
      body: jsonEncode({'error': 'Invalid credentials'}),
      headers: {'Content-Type': 'application/json'},);
}
