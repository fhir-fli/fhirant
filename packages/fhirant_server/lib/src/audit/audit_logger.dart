import 'dart:convert';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';

/// HIPAA-compliant audit logger for tracking all PHI access and security events
class AuditLogger {
  final FuegoDbInterface _db;

  AuditLogger(this._db);

  /// Log PHI access event (read, create, update, patch, search, history)
  Future<void> logPhiAccess({
    required String userId,
    required String action, // read, create, update, patch, search, history
    String? resourceType,
    String? resourceId,
    required String clientIp,
    String? userAgent,
    String? sessionId,
    String? purposeOfUse,
    required bool success,
    String? method,
    String? url,
    int? statusCode,
    int? responseTime,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      await _db.insertAuditLog(
        level: success ? 'INFO' : 'WARNING',
        message: 'PHI access: $action on ${resourceType ?? 'unknown'}${resourceId != null ? '/$resourceId' : ''}',
        eventType: 'phi_access',
        method: method,
        url: url,
        statusCode: statusCode,
        responseTime: responseTime,
        clientIp: clientIp,
        user: userId,
        resourceType: resourceType,
        resourceId: resourceId,
        action: action,
        userAgent: userAgent,
        sessionId: sessionId,
        purposeOfUse: purposeOfUse,
        outcome: success ? 'success' : 'failure',
        additionalData: additionalData != null ? jsonEncode(additionalData) : null,
      );

      FhirantLogging().logInfo(
        'Audit log: PHI access - $action by $userId on ${resourceType ?? 'unknown'}',
      );
    } catch (e, stackTrace) {
      FhirantLogging().logError(
        'Failed to write audit log for PHI access',
        e,
        stackTrace,
      );
    }
  }

  /// Log authentication event (login, logout, token_refresh)
  Future<void> logAuthentication({
    required String userId,
    required String eventType, // login, logout, token_refresh
    required String clientIp,
    String? userAgent,
    required bool success,
    String? failureReason,
    String? sessionId,
    String? method,
    String? url,
    int? statusCode,
  }) async {
    try {
      await _db.insertAuditLog(
        level: success ? 'INFO' : 'WARNING',
        message: 'Authentication: $eventType by $userId - ${success ? 'success' : 'failed: ${failureReason ?? 'unknown'}'}',
        eventType: 'authentication',
        method: method,
        url: url,
        statusCode: statusCode,
        clientIp: clientIp,
        user: userId,
        action: eventType,
        userAgent: userAgent,
        sessionId: sessionId,
        outcome: success ? 'success' : 'failure',
        additionalData: failureReason != null ? jsonEncode({'failureReason': failureReason}) : null,
      );

      FhirantLogging().logInfo(
        'Audit log: Authentication - $eventType by $userId - ${success ? 'success' : 'failed'}',
      );
    } catch (e, stackTrace) {
      FhirantLogging().logError(
        'Failed to write audit log for authentication',
        e,
        stackTrace,
      );
    }
  }

  /// Log security event (unauthorized_access, rate_limit, suspicious_activity)
  Future<void> logSecurityEvent({
    required String eventType, // unauthorized_access, rate_limit, suspicious_activity
    String? userId,
    required String clientIp,
    String? userAgent,
    required String description,
    String? method,
    String? url,
    int? statusCode,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      await _db.insertAuditLog(
        level: 'WARNING',
        message: 'Security event: $eventType - $description',
        eventType: 'security',
        method: method,
        url: url,
        statusCode: statusCode,
        clientIp: clientIp,
        user: userId,
        action: eventType,
        userAgent: userAgent,
        outcome: 'failure',
        additionalData: additionalData != null ? jsonEncode(additionalData) : null,
      );

      FhirantLogging().logWarning(
        'Audit log: Security event - $eventType from $clientIp',
      );
    } catch (e, stackTrace) {
      FhirantLogging().logError(
        'Failed to write audit log for security event',
        e,
        stackTrace,
      );
    }
  }

  /// Log system event (validation, server_error, config_change)
  Future<void> logSystemEvent({
    required String eventType, // validation, server_error, config_change
    required String message,
    String? userId,
    String? clientIp,
    String? method,
    String? url,
    int? statusCode,
    String? stackTrace,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      await _db.insertAuditLog(
        level: 'INFO',
        message: message,
        eventType: 'system',
        method: method,
        url: url,
        statusCode: statusCode,
        clientIp: clientIp,
        user: userId,
        action: eventType,
        stackTrace: stackTrace,
        outcome: 'success',
        additionalData: additionalData != null ? jsonEncode(additionalData) : null,
      );

      FhirantLogging().logInfo('Audit log: System event - $eventType');
    } catch (e, stackTrace) {
      FhirantLogging().logError(
        'Failed to write audit log for system event',
        e,
        stackTrace,
      );
    }
  }
}
