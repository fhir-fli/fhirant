**FHIR ANT turns an Android phone into a complete FHIR R4 server.** It runs
entirely on the device — no internet, no cloud, no external server — so it works
anywhere, including offline and low-resource field settings. Start the server
with one tap and any device on the same Wi-Fi can connect to it over the URL or
QR code the app shows.

This is the first direct release. FHIR ANT is **not on the Google Play Store**;
install it from the APKs below.

## Install

See [INSTALL.md](https://github.com/fhir-fli/fhirant/blob/main/INSTALL.md) for
step-by-step instructions. Short version: download
**`fhirant-1.0.0-arm64-v8a.apk`** (right for essentially every modern phone),
tap it, and allow installation from that source when Android asks.

Requires Android 7.0 (API 24) or newer.

## What it does

- Full FHIR R4 REST API — create, read, update, delete, search, history,
  transaction and batch Bundles
- Bulk Data Export (`$export`) as NDJSON with async job polling
- CQL (`$cql`, `Library/$evaluate`) and FHIRPath (`$fhirpath`)
- Validation (`$validate`) and terminology (`$validate-code`, `$lookup`,
  `$expand`)
- FHIR Mapping Language transforms (`$transform`)
- Immunization forecasting: `$immds-forecast` (CDC schedule, tested against
  CDC's published cases) and `$immds-forecast-who` (WHO schedule, not yet
  validated against any outside answer; treat as a draft)
- Patient `$everything`, `$document` generation, `_history`
- `$backup` / `$restore` of the whole dataset as an encrypted SQLite file (a passphrase-wrapped FHIR Bundle is still accepted on restore)
- Built-in resource browser with JSON/YAML views and clickable references
- Bundled MIMIC-IV demo dataset to load with one tap

Data lives in a local SQLite database encrypted with SQLCipher. In Secure mode
every request requires SMART on FHIR authentication (OAuth 2.0 + PKCE, scoped
access); patient data is kept out of screenshots, screen recordings, and cloud
backups.

## Notes

- **If you already have FHIR ANT from the Play Store**, this installs *alongside*
  it rather than updating it — it's published under a new application ID
  (`dev.fhirfli.fhirant.app`). The two don't share data. Uninstall the old one if
  you don't want both.
- The version resets to 1.0.0 for the same reason; this is not a downgrade from
  the old 1.3.x Play builds.
- The server stops when the app is force-quit or the server is stopped. Android
  keeps it alive in the background via a persistent notification.

## Checksums

```
e3656ec72fe1e9dcb0a1fbb8fced380c2e3b7bdb28563eb8d5689d8bdf769dc2  fhirant-1.0.0-arm64-v8a.apk
03e963b10384da162b5e2c113712d690ebb1d14d4b8595ed8b18fc5f7aa28c4b  fhirant-1.0.0-armeabi-v7a.apk
46a67d70fce2689445b12c3c03eb66a059b3c32b756af67e5515af144e7aca59  fhirant-1.0.0-universal.apk
daece6b8a59cc18a638f78ae03dd289da874f71ac915e193d8dbdbb2ad8a6a4c  fhirant-1.0.0-x86_64.apk
```

Signed with the FHIR-FLI release key, SHA-256 fingerprint
`97:7D:D5:5D:B6:CD:74:24:D8:F4:D9:14:00:39:14:2D:6B:0F:5F:94:7F:7B:EC:5A:12:7D:26:F9:39:3E:AD:28`.
