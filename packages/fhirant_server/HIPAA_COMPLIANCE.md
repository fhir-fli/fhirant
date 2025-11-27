# HIPAA Compliance Requirements for FHIR Server

## Overview

This FHIR server handles Protected Health Information (PHI) and must comply with HIPAA regulations. This document outlines the audit logging and tracking requirements.

## Required Audit Logging

### 1. User Authentication & Session Tracking

**Required Events:**
- User login (success/failure)
- User logout
- Session creation/termination
- Authentication method used
- Failed login attempts (with reason)

**Data to Log:**
- User ID/username
- Timestamp
- Client IP address
- User agent
- Authentication method
- Success/failure status
- Failure reason (if applicable)

### 2. PHI Access Logging

**Required Events:**
- Resource read (GET)
- Resource creation (POST)
- Resource update (PUT/PATCH)
- Resource deletion (DELETE)
- Resource search (GET with query params)
- FHIRPath queries
- Resource transformations/mappings

**Data to Log:**
- User ID/username
- Resource type
- Resource ID
- Action performed
- Timestamp
- Client IP
- Outcome (success/failure)
- Purpose of use (if applicable)

### 3. Security Events

**Required Events:**
- Unauthorized access attempts
- Rate limit violations
- Invalid authentication tokens
- Suspicious activity patterns

### 4. System Events

**Required Events:**
- Validation requests
- Server errors
- Configuration changes
- Database operations

## Implementation Status

### ✅ Completed
- Basic logging infrastructure (`logs_table.dart`)
- Audit logger class structure (`lib/src/audit/audit_logger.dart`)
- Handler structure for audit logging

### ⚠️ Needs Implementation

1. **Database Schema Extensions**
   - Add `audit_logs` table with HIPAA-specific fields:
     - `purpose_of_use` (text)
     - `event_type` (text)
     - `user_agent` (text)
     - `session_id` (text)
     - `additional_data` (JSON/text)
   
2. **Database Interface Methods**
   - `insertAuditLog()` method in `FuegoDbInterface`
   - Query methods for audit log retrieval
   - Retention policy implementation

3. **Handler Integration**
   - Update all resource handlers to call `AuditLogger.logPhiAccess()`
   - Add authentication tracking in login/logout handlers
   - Add unauthorized access logging in auth middleware

4. **Session Management**
   - Track active user sessions
   - Session timeout handling
   - Session invalidation on logout

5. **Retention & Archival**
   - Log retention policy (HIPAA requires 6 years minimum)
   - Secure log archival
   - Log encryption at rest

## Next Steps

1. Extend `fhirant_db` with audit logging methods
2. Update all handlers to use `AuditLogger`
3. Implement session management
4. Add log retention and archival
5. Add audit log query endpoints (with proper authorization)

## Compliance Checklist

- [ ] All PHI access is logged
- [ ] User authentication is tracked
- [ ] Failed access attempts are logged
- [ ] Logs are tamper-proof (immutable)
- [ ] Logs are encrypted at rest
- [ ] Log retention meets HIPAA requirements (6 years)
- [ ] Audit logs are queryable for compliance audits
- [ ] User sessions are tracked and managed
- [ ] Unauthorized access attempts trigger alerts
