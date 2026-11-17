# Separate Windows installations

Usage: run the role-selecting Setup twice, once per role. Incoming keeps the
existing CrhRustDesk identity; outgoing uses CrhRustDeskIT.exe and the
CrhRustDeskIT identity. Each launches and uninstalls independently. Incoming
authorization continues to require the existing Management permit.

## Design

Startup selects APP_NAME from the executable before configuration access.
Existing config, IPC, registry, shortcuts and window dispatch already derive
their namespace from APP_NAME. The separate IT executable is always outgoing,
including when its profile is missing or invalid. Its inventory machine hash
adds an IT suffix because the server pins one signing key per machine hash.
The existing endpoint hash stays unchanged.

Windows receiver cleanup owns the shared privacy broker and display/printer
drivers. A feature-specific Windows module gives IT its own uninstall commands
and registry lookup. IT skips receiver service and printer setup, leaves the
endpoint update task intact, and disables only its own inbound firewall rule.

## Alternatives and synthesis

Compared two designs with independent read-only agents: two fixed-role Setup
outputs versus one role-selecting Setup with separate installed identities.
Selected the latter: the signed manifest and publishing tools require one
CrhRustDesk-Setup.exe URL. Two fixed-role outputs would also need a new update
distribution contract. No protocol or server changes are necessary here.

The runtime review added receiver cleanup and inventory isolation to the base
installer design. Legacy IT migration is explicit; credentials and keys are
never automatically copied. A dedicated cross-judge was not used.

## Validation and regression surface

Non-compiling checks passed: full diff and whitespace review, PowerShell parsing
of the three changed scripts, and Test-ClientUpdateRoles.ps1 with mocked task
writes. The new task-preservation assertion fails against the HEAD updater and
passes with this change. Rust identity tests are added but must wait for an
explicitly authorized build/test run. Read-only runtime and installer reviews
found no blocking issue.

Existing files and paths affected:

- src/crhrustdesk.rs and role.rs: Windows startup identity and outgoing policy.
- src/crhrustdesk/inventory.rs: only the new IT machine hash changes.
- src/platform/windows.rs: thin IT hooks for registry, service, printer and
  uninstall paths; existing receiver cleanup stays in its original path.
- installer/CrhRustDesk.iss: IT payload rename, role-specific paths/firewall;
  managed updates remain restricted to the existing incoming installation.
- updater/Register-AutoUpdate.ps1: the new IT leaves endpoint tasks untouched;
  legacy outgoing cleanup remains available.
- Build-EasySetup.ps1: rejects bundles missing separate identity support.
- Flutter common.dart and desktop home/settings pages: recognize the IT name
  for account login gating, updates, permissions link, local IP and icon.

Actual installation, concurrent sessions, restart, update and removal require
Windows validation after a separately authorized build. See
ENDPOINT-INSTALL-TH.md for the manual sequence and legacy migration.
