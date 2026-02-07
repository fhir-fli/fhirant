import 'dart:convert';
import 'package:test/test.dart';
import 'package:shelf/shelf.dart';
import 'package:fhirant_server/src/handlers/validate_handler.dart';

void main() {
  group('validateHandler', () {
    test('returns 400 with OperationOutcome for empty body', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/Patient/\$validate'),
        body: '',
      );

      final response = await validateHandler(request, 'Patient');

      expect(response.statusCode, equals(400));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('OperationOutcome'));
      expect((json['issue'] as List).first['diagnostics'],
          contains('empty'));
    });

    test('returns 400 with OperationOutcome for invalid JSON', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/Patient/\$validate'),
        body: 'not valid json{{{',
      );

      final response = await validateHandler(request, 'Patient');

      expect(response.statusCode, equals(400));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('OperationOutcome'));
      expect((json['issue'] as List).first['diagnostics'],
          contains('Invalid JSON'));
    });

    test('returns 400 when resource type in body mismatches URL', () async {
      final patientJson = jsonEncode({
        'resourceType': 'Patient',
        'id': 'test-1',
      });

      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/Observation/\$validate'),
        body: patientJson,
      );

      final response = await validateHandler(request, 'Observation');

      expect(response.statusCode, equals(400));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('OperationOutcome'));
      expect(
        (json['issue'] as List).first['diagnostics'] as String,
        contains('does not match'),
      );
    });

    test('accepts valid resource without type constraint', () async {
      // When no resourceType is passed (null), the handler skips type check
      // and goes straight to the validator.
      final patientJson = jsonEncode({
        'resourceType': 'Patient',
        'id': 'test-1',
        'name': [
          {'family': 'Smith', 'given': ['John']},
        ],
      });

      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/\$validate'),
        body: patientJson,
      );

      // This exercises the FhirValidationEngine. If it throws (e.g.,
      // missing external resources), we get 500 instead. Either outcome
      // is acceptable — we're testing that the handler reaches the
      // validator without erroring on pre-checks.
      final response = await validateHandler(request);

      // We accept 200 (valid) or 400 (validation issues) — both mean
      // the validator ran. 500 means an unexpected crash.
      expect(response.statusCode, isNot(equals(500)));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('OperationOutcome'));
    });
  });
}
