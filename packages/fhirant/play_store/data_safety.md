# FHIR ANT — Play Data Safety form (draft answers)

⚠️ REVIEW CAREFULLY BEFORE SUBMITTING. The Data safety declaration is legally
binding and app-specific. These drafts reflect how fhirant works as built; you
must confirm each answer matches your actual intended distribution and any
changes you make.

## The key distinction Google uses
- **"Collected"** = data transmitted OFF the user's device by your app.
- **"Shared"** = data transferred to a THIRD PARTY (another company/developer).

fhirant is an on-device server. It does NOT send any data to you (the developer)
or to any third party. It stores the operator's own FHIR data locally, encrypted,
and — as its core function — serves that data to OTHER DEVICES ON THE OPERATOR'S
OWN LOCAL NETWORK that the operator explicitly connects. That is user-directed
local transfer, not collection-by-the-developer and not third-party sharing.

## Recommended answers

### Does your app collect or share any of the required user data types?
Answer: **No** — with the reasoning above (no data leaves the device to the
developer or a third party; all processing is on-device; the operator's own LAN
clients are not "third parties").

> NOTE: This is the defensible reading for a purely local server. If you are
> uneasy, the conservative alternative is to answer **Yes** and declare Health
> info + Personal info as "collected" but NOT "shared", processed on-device,
> not sent to the developer. Either can be justified; pick one and be consistent.
> Do NOT claim "not collected" if you later add any cloud sync/telemetry.

### Is all user data encrypted in transit?
- At rest: **Yes** — the local database is encrypted (SQLite + SQLCipher).
- In transit (on the LAN): fhirant serves over HTTP by default, or self-signed
  HTTPS. In an offline field LAN there is no certificate authority. If you
  answer the in-transit question, answer honestly: transit encryption is
  **optional / operator-configured**, not guaranteed by default. Do not claim
  "all data encrypted in transit" unless you enforce TLS.

### Do you provide a way for users to request that their data is deleted?
Answer: **Yes** — users can delete individual resources, clear all data in-app,
or uninstall the app (which removes the local encrypted database).

### Data types (only if you answer "Yes" to collection)
- Health and fitness → Health info (FHIR clinical resources)
- Personal info → Name, Date of birth, other identifiers (in Patient resources)
- App activity / other → the request log (local only)
- Account: username + a salted password HASH (never the plaintext), local only
Purpose for each: **App functionality** (running the server). NOT for
analytics, advertising, or personalization.

## Additional Play sections tied to this
- **Sensitive/health permissions**: none of the special health permissions are
  requested. Permissions used: INTERNET, ACCESS_WIFI_STATE, CHANGE_NETWORK_STATE
  (to run/advertise the LAN server), FOREGROUND_SERVICE +
  FOREGROUND_SERVICE_CONNECTED_DEVICE (keep the server alive in the background).
- **Foreground service declaration**: type `connectedDevice`. Justification: the
  app runs a local network server that other devices connect to; the foreground
  service keeps that server reachable while the app is backgrounded. (Same
  declaration that was accepted for the previous v1.3.0 listing.)
- **Content rating questionnaire**: no objectionable content; it's a
  developer/health tool.
- **Target audience**: adults / professionals (not directed at children).
- **Government / health apps policy**: it handles health data but does not claim
  to be a medical device or provide diagnosis; describe it as developer/interop
  tooling to avoid medical-device policy scope.
