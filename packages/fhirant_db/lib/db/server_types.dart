// ignore_for_file: lines_longer_than_80_chars

/// Manual data classes for server-specific tables (Users, ExportJobs).
///
/// These replace Drift-generated classes so that FhirAntDb can extend FhirDb
/// without needing its own @DriftDatabase annotation or code generation.
/// Field names match the previous Drift-generated classes exactly.

import 'package:drift/drift.dart';

/// A user account in the FHIR server.
class User {
  final int id;
  final String username;
  final String passwordHash;
  final String salt;
  final String role;
  final bool active;
  final DateTime createdAt;
  final DateTime? lastLogin;
  final String? scopes;

  const User({
    required this.id,
    required this.username,
    required this.passwordHash,
    required this.salt,
    required this.role,
    required this.active,
    required this.createdAt,
    this.lastLogin,
    this.scopes,
  });

  factory User.fromRow(QueryRow row) {
    return User(
      id: row.read<int>('id'),
      username: row.read<String>('username'),
      passwordHash: row.read<String>('password_hash'),
      salt: row.read<String>('salt'),
      role: row.read<String>('role'),
      active: row.read<bool>('active'),
      createdAt: row.read<DateTime>('created_at'),
      lastLogin: row.readNullable<DateTime>('last_login'),
      scopes: row.readNullable<String>('scopes'),
    );
  }

  @override
  String toString() =>
      'User(id: $id, username: $username, role: $role, active: $active)';
}

/// A bulk export job tracked by the FHIR server.
class ExportJob {
  final String jobId;
  final String status;
  final String requestUrl;
  final DateTime transactionTime;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? outputJson;
  final String? errorJson;
  final String? resourceTypes;
  final DateTime? since;
  final String exportLevel;
  final String? patientId;
  final String? groupId;
  final String? typeFilters;
  final String? requestedBy;

  const ExportJob({
    required this.jobId,
    required this.status,
    required this.requestUrl,
    required this.transactionTime,
    required this.createdAt,
    this.completedAt,
    this.outputJson,
    this.errorJson,
    this.resourceTypes,
    this.since,
    required this.exportLevel,
    this.patientId,
    this.groupId,
    this.typeFilters,
    this.requestedBy,
  });

  factory ExportJob.fromRow(QueryRow row) {
    return ExportJob(
      jobId: row.read<String>('job_id'),
      status: row.read<String>('status'),
      requestUrl: row.read<String>('request_url'),
      transactionTime: row.read<DateTime>('transaction_time'),
      createdAt: row.read<DateTime>('created_at'),
      completedAt: row.readNullable<DateTime>('completed_at'),
      outputJson: row.readNullable<String>('output_json'),
      errorJson: row.readNullable<String>('error_json'),
      resourceTypes: row.readNullable<String>('resource_types'),
      since: row.readNullable<DateTime>('since'),
      exportLevel: row.read<String>('export_level'),
      patientId: row.readNullable<String>('patient_id'),
      groupId: row.readNullable<String>('group_id'),
      typeFilters: row.readNullable<String>('type_filters'),
      requestedBy: row.readNullable<String>('requested_by'),
    );
  }

  @override
  String toString() =>
      'ExportJob(jobId: $jobId, status: $status, exportLevel: $exportLevel)';
}
