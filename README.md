# fhirant

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: MIT][license_badge]][license_link]
[![Powered by Dart Frog](https://img.shields.io/endpoint?url=https://tinyurl.com/dartfrog-badge)](https://dartfrog.vgv.dev)

An example application built with dart_frog

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis

🔒 Security & Access Control
✅ Username/Password Authentication → (High Priority)

Implement a secure login system using username/password.
Store credentials securely (flutter_secure_storage).
Use JWT (JSON Web Tokens) for authentication & session management.
Restrict access to FHIR endpoints.
✅ Rate Limiting → (Medium Priority)

Prevent abuse by limiting requests per second per IP.
Can be implemented with a middleware in shelf.
✅ IP Blocking & Malicious Request Handling → (Medium Priority)

Maintain a list of blacklisted IPs.
Automatically block excessive failed logins or suspicious requests.
Can be stored in SQLite or an in-memory list.
✅ CORS Policy → (Medium Priority)

Restrict access to specific origins if needed.
Prevent unauthorized JavaScript-based requests.
✅ Compression (Gzip/Deflate Support) → (Medium Priority)

Reduce response size for large FHIR JSON responses.
📜 Logging & Monitoring
✅ Logging System → (High Priority)

Log all requests, errors, and security events.
Structured logging in JSON format (for easy debugging).
Store logs in SQLite or files.
✅ Access Logs → (Medium Priority)

Track IP addresses, request patterns, and API usage.
Could be useful for detecting abuse or usage trends.
✅ Error Monitoring & Alerts → (Low Priority)

Store error logs and allow for later debugging.
Optionally, send logs remotely when online.
⚙️ Server Execution & Performance
✅ Run the FHIR Server in a Separate Isolate (Background Execution) → (High Priority)

Ensure the server continues running even if the app is minimized.
Use Isolate.spawn() and flutter_background_service.
✅ Optimize Query Performance → (Low Priority)

SQLite is already fast, but indexing commonly queried fields could help.
✅ Compression & Response Optimization → (Medium Priority)

Gzip support for JSON responses.
Can help when syncing larger amounts of data.
✅ WebSockets for Real-time Updates → (Future, Not Needed Now)

Needed later for notifying clients of new data.
✅ Reverse Proxy-Like Features → (As Needed)

We’re already covering the essential ones (security, rate limiting, logging, compression).
🚀 Summary: What’s Next?
Feature	Priority	Action Steps
Authentication (Username/Password + JWT)	High	Secure login, session management, access control
Logging System (Structured Logs, Error Logs, Access Logs)	High	Implement structured JSON logging, store in SQLite
Run Server in Background Isolate	High	Use Isolate.spawn() and flutter_background_service
Rate Limiting & IP Blocking	Medium	Prevent abuse by limiting requests & tracking malicious activity
CORS Policy & Security Enhancements	Medium	Restrict origins if needed, prevent unauthorized API access
Compression (Gzip for JSON Responses)	Medium	Reduce bandwidth for large responses
WebSockets for Real-time Updates	Future	Not needed yet, but will be required later
🔹 What to Work on First?
1️⃣ Authentication (Username/Password + JWT)
2️⃣ Logging System (Requests, Errors, Access Logs)
3️⃣ Run Server in Background Isolate

Which one do you want to start with? 🚀
