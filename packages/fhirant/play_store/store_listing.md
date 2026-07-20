# FHIR ANT — Play Store listing (draft)

Draft copy for the Google Play Console listing. Review/edit before submitting.

## App name
FHIR ANT

## Short description (max 80 chars)
A complete FHIR R4 server that runs on your phone — offline and encrypted.
<!-- 79 chars. Alternatives:
"On-device FHIR R4 server: run, connect, and share health data — fully offline."
"Run a full FHIR R4 server on your phone. Offline, encrypted, no cloud needed."
-->

## Full description (max 4000 chars)
FHIR ANT turns your phone into a complete FHIR R4 server. It runs entirely on
your device — no internet, no cloud, no external servers required — so it works
anywhere, including low-resource and offline field settings.

Start the server with one tap and other devices on the same network — a laptop,
another phone, or any FHIR client app — can connect to it over Wi‑Fi using the
shown URL or QR code. Everything stays on your device.

WHAT IT DOES
• Full FHIR R4 REST API: create, read, update, delete, search, history
• Transaction and batch Bundles
• Bulk Data Export ($export) as NDJSON, with async job polling
• Clinical Quality Language ($cql, Library/$evaluate) and FHIRPath ($fhirpath)
• Resource validation ($validate) and terminology operations
  ($validate-code, $lookup, $expand)
• FHIR Mapping Language transforms ($transform)
• Immunization forecasting ($immds-forecast — CDC and WHO schedules)
• Patient $everything, $document generation, and _history
• Backup and restore your whole dataset as a FHIR Bundle

BUILT FOR SECURITY
• All data is stored locally in an encrypted database (SQLite + SQLCipher)
• SMART on FHIR authentication with OAuth 2.0 + PKCE and scoped access
• Strong password hashing and pinned JWT verification
• On Android, patient data is kept out of screenshots, screen recordings, and
  cloud backups
• Two clear modes: an Experimentation mode (no auth, for testing with sample
  data only) and a Secure mode (an admin account and full authentication for
  real use)

WHO IT'S FOR
FHIR developers, health-IT integrators, students, and anyone who needs a real,
standards-compliant FHIR server that is portable, private, and works without a
connection.

FHIR ANT is part of the open-source FHIR-FLI toolset.

<!-- ~1,500 chars. Trim/expand as desired. -->

## Category
Tools  (alternative: Medical — but "Tools" avoids extra medical-app review
requirements; confirm which fits your intent.)

## Tags / keywords
FHIR, HL7, healthcare, interoperability, server, R4, SMART on FHIR, offline

## Contact
- Email: grey@fhirfli.dev
- Website: https://fhir-fli.github.io/fhir_fli_documentation/
- Privacy policy: https://fhir-fli.github.io/fhir_fli_documentation/docs/fhirant/fhirant_privacy_policy

## Assets needed in Console (sizes)
- App icon: 512×512 PNG (already in the app: android/app/src/main/res/mipmap-*)
- Feature graphic: 1024×500 PNG (NOT yet created — needed for the listing)
- Phone screenshots: 2–8, PNG/JPEG, 16:9 or 9:16, min 320px (see the
  screenshots/ folder captured from the emulator)
