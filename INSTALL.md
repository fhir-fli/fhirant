# Installing FHIR ANT on Android

FHIR ANT is distributed as a signed APK from the
[GitHub releases page](https://github.com/fhir-fli/fhirant/releases). It is not
on the Google Play Store, so you install it directly.

**Requirements:** Android 7.0 (API 24) or newer. About 250 MB of free space —
the app bundles the FHIR R4 specification, terminology, and a sample dataset.

## 1. Pick a file

| File | Who it's for |
|---|---|
| `fhirant-<version>-arm64-v8a.apk` | **Almost everyone.** Every Android phone or tablet sold in the last several years. |
| `fhirant-<version>-x86_64.apk` | Emulators and x86 Chromebooks. |
| `fhirant-<version>-armeabi-v7a.apk` | Older 32-bit-only devices. |
| `fhirant-<version>-universal.apk` | Works on anything, but ~3× the download. Use this if one of the above says *"App not installed"*. |

Download it on the phone itself, or copy it across with a cable.

## 2. Install it

1. Tap the downloaded `.apk` (in Chrome's Downloads, or your Files app).
2. Android will say the app can't be installed from this source. Tap
   **Settings** → turn on **Allow from this source** → go back.
   You are granting this to the app you downloaded *with* (Chrome, Files), not
   to the whole system, and you can turn it back off afterwards.
3. Tap **Install**, then **Open**.

Play Protect may show a "scan this app?" prompt because the app didn't come
from the Play Store. That's expected for any directly installed app.

## 3. Verify the download (optional)

Every release lists SHA-256 checksums in `SHA256SUMS.txt`:

```bash
sha256sum -c SHA256SUMS.txt --ignore-missing
```

All official builds are signed with the FHIR-FLI release key:

```
SHA-256: 97:7D:D5:5D:B6:CD:74:24:D8:F4:D9:14:00:39:14:2D:6B:0F:5F:94:7F:7B:EC:5A:12:7D:26:F9:39:3E:AD:28
```

Check any APK against it with `apksigner verify --print-certs <file.apk>`
(from the Android SDK build-tools).

## 4. First run

Onboarding introduces the app and offers to load the bundled sample dataset
(MIMIC-IV demo data — example patients to poke at). You can skip it and load
data later.

On the dashboard, tap **Start** on the server card. It then shows a URL and a QR
code; any device on the same Wi-Fi can point a FHIR client at that address. Data
is stored in an encrypted database on the device and never leaves it.

The same card has an **Experimentation / Secure** switch:

- **Experimentation** (the default) — no authentication, for quick testing with
  sample data. Don't put real patient data in it.
- **Secure** — every request requires SMART on FHIR authentication. Flipping the
  switch prompts you to create an admin account, and only takes effect once one
  exists.

On Android the server keeps running when you background the app (there's a
persistent notification). Stopping the server or force-quitting the app stops it.

## Updating

Download the newer APK and install it over the top — your data is kept.

Stay on the **same variant** you installed the first time (arm64-v8a → arm64-v8a).
The per-architecture builds carry different internal version codes, so switching
from, say, `arm64-v8a` to `universal` can be rejected as a downgrade. If that
happens, uninstall first — **which erases the app's database.**

## Uninstalling

Uninstalling removes the encrypted database along with the app. If you want to
keep the data, export it first with the server's `$backup` operation
(`POST /$backup`, admin-only in Secure mode), which returns your whole dataset
as a FHIR Bundle.
