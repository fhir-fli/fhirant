/// The default authentication posture for a **fresh install**, before the
/// operator has chosen a mode. Once a mode is chosen it is persisted and this
/// value no longer applies to that install.
///
/// ┌──────────────────────────────────────────────────────────────────────┐
/// │  ⚠️  SHIP DEFAULT — THIS IS THE ONE LINE TO FLIP FOR PRODUCTION  ⚠️   │
/// └──────────────────────────────────────────────────────────────────────┘
///
/// While fhirant is pre-release and being tried by beta testers, this is
/// `true` — a fresh install defaults to **Experimentation mode**, where
/// authentication is DISABLED so devices and client apps can be wired together
/// without friction. That mode is for TEST DATA ONLY; it must never hold PHI,
/// and the app shows a standing warning whenever it is active.
///
/// When fhirant is ready for real-world (PHI) deployment, change this to
/// `false`. That single change makes every fresh install default to **Secure
/// mode**: authentication required, an admin account created at setup, and the
/// full server hardening. Operators who have already picked a mode are
/// unaffected — their choice is persisted.
const bool kDefaultAuthDisabled = true;
