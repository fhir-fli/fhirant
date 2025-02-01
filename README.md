# System Design Goals

## Passkey Control and JWT Authentication

- **Goal:** Enforce passkey-based logins, store user credentials securely, and issue JWT tokens for session management.
- **Approach:**
  - Store the JWT signing `_secretKey` securely, avoiding hardcoding.
  - Expand the `authenticate()` middleware to validate JWT scopes and roles.
  - Consider adding passkey revocation/renewal functionality.
- **Notes:** Since multiple users may register on the same device, consider implementing a more robust user management system if concurrency or multi-tenant usage increases.

---

## Restrict Access to FHIR Endpoints

- **Goal:** Prevent unauthorized or anonymous modifications to resources.
- **Approach:**
  - Use the same JWT middleware to check roles and permissions before allowing certain routes (e.g., POST, PUT, DELETE).
  - Consider role-based or resource-type-level restrictions.

---

## Rate Limiting

- **Goal:** Limit the number of requests per second/minute from a single IP or user.
- **Approach:**
  - Use an in-memory cache or SQLite table to track request counts per IP.
  - Return a 429 (Too Many Requests) response when thresholds are exceeded.
- **Notes:** Helps prevent denial-of-service or brute-force attempts.

---

## IP Blocking & Malicious Request Handling

- **Goal:** Automatically blacklist IPs after excessive failures or suspicious behavior.
- **Approach:**
  - Store blocked IPs in a short-term in-memory list or database.
  - Expire blocks after a certain period or require administrative intervention for unblocking.
- **Notes:** Integrate this with rate-limiting data, potentially associating it with repeated invalid passkey attempts.

---

## CORS Policy

- **Goal:** Restrict requests to known/valid origins to mitigate Cross-Site Request Forgery (CSRF).
- **Approach:**
  - Add a CORS middleware in your `Pipeline()` to handle OPTIONS preflights.
  - Specify allowed Origins, Methods, and Headers.
- **Notes:** For closed ecosystems or mobile-only usage, the policy can be more permissive. For broader usage, tighten the policy.

---

## Compression (Gzip/Deflate Support)

- **Goal:** Reduce bandwidth usage for large FHIR resources or NDJSON responses.
- **Approach:**
  - Add a Shelf middleware such as `shelf_gzip` or implement compression manually.
  - Ensure the client sets `Accept-Encoding: gzip` (many clients do by default).
- **Notes:** Be mindful of CPU usage on mobile devices when compressing very large responses.

---

# Low Priority / Future Enhancements

## Optimize Query Performance

- **Goal:** Speed up large queries or complex searches.
- **Approach:**
  - Create indexes in the SQLite database for common search fields.
  - Adjust batch insertion logic or streaming for NDJSON if performance degrades.
- **Notes:** Typically necessary only as the data grows or for more complex queries (e.g., advanced FHIR search parameters).

---

## WebSockets for Real-Time Updates

- **Goal:** Notify connected clients when new data arrives without the need for repeated polling.
- **Approach:**
  - Add a `shelf_web_socket` route or use a separate library to handle push events.
  - Possibly integrate with an Isolate background server for scalability.
- **Notes:** This is a natural extension for live updates but can be deferred.

---

## Certificate & Key Rotation

- **Goal:** Periodically regenerate self-signed certificates (or use a real certificate) to reduce the risk if a key is compromised.
- **Approach:**
  - Add a process that checks certificate expiration and regenerates automatically or upon admin trigger.
  - For multi-device usage, distribute the new certificate or import an externally signed certificate.
- **Notes:** More relevant if your server operates in varied network environments.

---

## Logs and Auditing

- **Goal:** Track server events without allowing logs to grow unbounded.
- **Approach:**
  - Implement a job to archive or prune old log records.
  - For compliance, store logs encrypted or off-device.
- **Notes:** This is often overshadowed by more immediate tasks but is important for long-term maintenance.

---

# Other Considerations

## Concurrency & Transaction Safety

- **Notes:** If scaling to multiple isolates or devices, ensure SQLite concurrency remains safe. Drift can handle concurrency with a single writer, but you may need a single connection approach or a more robust synchronization strategy.

---

## Real Certificates vs. Self-Signed

- **Notes:** In real-world contexts, it’s better to obtain a legitimate certificate from a Certificate Authority (CA). Self-signed certificates may trigger warnings or rejections unless manually trusted.

---

## User/Role Management

- **Notes:** As the system grows, consider implementing Role-Based Access Control (RBAC) or user-based policies to differentiate FHIR permissions (e.g., read-only, admin).
