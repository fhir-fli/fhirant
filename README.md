# fhirant

## ToDo
- Implement passkey control
- Use JWT (JSON Web Tokens) for authentication & session management.
- Restrict access to FHIR endpoints.
- Rate Limiting → (Medium Priority)
- Prevent abuse by limiting requests per second per IP.
- IP Blocking & Malicious Request Handling → (Medium Priority)
- Maintain a list of blacklisted IPs.
- Automatically block excessive failed logins or suspicious requests.
- Can be stored in SQLite or an in-memory list.
- CORS Policy → (Medium Priority)
- Restrict access to specific origins if needed.
- Prevent unauthorized JavaScript-based requests.
- Compression (Gzip/Deflate Support) → (Medium Priority)
- Reduce response size for large FHIR JSON responses.
- Server Execution & Performance
    - Run the FHIR Server in a Separate Isolate (Background Execution) → (High Priority)
- Ensure the server continues running even if the app is minimized.
    - Use Isolate.spawn() and flutter_background_service.
- Optimize Query Performance → (Low Priority)
- Needed later for notifying clients of new data.
Run Server in Background Isolate	High	Use Isolate.spawn() and flutter_background_service
Rate Limiting & IP Blocking	Medium	Prevent abuse by limiting requests & tracking malicious activity
CORS Policy & Security Enhancements	Medium	Restrict origins if needed, prevent unauthorized API access
Compression (Gzip for JSON Responses)	Medium	Reduce bandwidth for large responses
WebSockets for Real-time Updates	Future	Not needed yet, but will be required later
