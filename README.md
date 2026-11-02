# FHIR ANT

**A complete FHIR R4 server that runs on an Android phone or any computer, with no internet.**

FHIR ANT stores health records in an encrypted database on the device itself and serves them over the standard FHIR REST API. Other devices on the same Wi-Fi connect to it by URL or QR code. It is built for clinics and field settings where there is no reliable connection, and for developers who want a real FHIR server they can carry in a pocket or start with one command.

## Try it on a phone (Android 7.0 or newer)

1. Download `fhirant-<version>-arm64-v8a.apk` from the [releases page](https://github.com/fhir-fli/fhirant/releases) on the phone.
2. Tap it and allow installation from that source when Android asks. [INSTALL.md](INSTALL.md) walks through every screen and how to check the download.
3. Open the app, load the sample data (a small MIMIC-IV demo set) and tap **Start**.
4. From a laptop on the same Wi-Fi, ask it for patients. Use the URL the app shows:

```bash
curl -k https://192.168.1.42:8080/Patient
```

`-k` skips the certificate check because the app uses a self-signed certificate. A real client should pin the fingerprint the app shows.

The app is not on the Google Play Store.

## Try it on a computer

You need the [Dart SDK](https://dart.dev/get-dart) (3.x).

```bash
git clone https://github.com/fhir-fli/fhirant.git
cd fhirant/packages/fhirant_server
dart pub get
dart run bin/server.dart --dev-mode --db-path /tmp/fhirant-try --spec-path assets/fhir_spec
```

The first start takes about a minute: Dart compiles the server, then loads the FHIR specification that validation and terminology need. Then, in another terminal:

```bash
curl http://localhost:8080/metadata
curl -X POST http://localhost:8080/Patient \
  -H "Content-Type: application/fhir+json" \
  -d '{"resourceType":"Patient","name":[{"family":"Smith","given":["Ana"]}]}'
curl "http://localhost:8080/Patient?name=smith"
```

`--dev-mode` turns off login and uses a publicly known database key. Use it with test data only. For real use, set `FHIRANT_ENCRYPTION_KEY` and leave authentication on; the [CLI guide](https://fhir-fli.github.io/fhir_fli_documentation/docs/fhirant/fhirant_cli) shows how, and how to run it in Docker.

## What it does

- The FHIR R4 REST API: create, read, update, delete, search (including chained search and `_include`), history, and transaction and batch Bundles.
- SMART on FHIR login with scoped access, or an open mode for test data.
- Bulk export (`$export`), CQL and FHIRPath evaluation, validation, terminology operations, FHIR Mapping Language transforms, Patient `$everything`, and immunization forecasting for the CDC schedule (tested against CDC's published cases) and the WHO schedule (not yet validated; treat as a draft).
- Encrypted backup and restore of the whole store.

## Status

- **Conformance:** passed 1056 of 1056 tests in the AEGIS Touchstone FHIR 4.0.1 server suite on 2026-03-17. That run was against an earlier build on a server that no longer exists, and has not been repeated.
- Version 1.0.0. Pre-release: expect changes.

## Documentation

- [Getting started](https://fhir-fli.github.io/fhir_fli_documentation/docs/fhirant/fhirant_getting_started): first launch, logins and users, common requests.
- [Capabilities](https://fhir-fli.github.io/fhir_fli_documentation/docs/fhirant/fhirant_capabilities) and [API reference](https://fhir-fli.github.io/fhir_fli_documentation/docs/fhirant/fhirant_api_reference).
- [Security](https://fhir-fli.github.io/fhir_fli_documentation/docs/fhirant/fhirant_security) and [privacy policy](https://fhir-fli.github.io/fhir_fli_documentation/docs/fhirant/fhirant_privacy_policy).
- [TESTING.md](TESTING.md): how to run the test suites.

## Repository layout

| Folder | What it is |
|---|---|
| `packages/fhirant` | The Android app (Flutter) |
| `packages/fhirant_server` | The server, also runnable on its own from the command line |
| `packages/fhirant_db` | The encrypted database layer |
| `packages/fhirant_secure_storage`, `packages/fhirant_logging` | Key storage and logging |

## License and contact

MIT. Built by [FHIR-FLI](https://fhir-fli.github.io/fhir_fli_documentation/). Questions and bug reports: [GitHub issues](https://github.com/fhir-fli/fhirant/issues) or grey@fhirfli.dev.
