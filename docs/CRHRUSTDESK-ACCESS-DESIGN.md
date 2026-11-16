# CrhRustDesk account access

Plan: ground the current paths, sketch alternatives, implement, verify, minimize the diff.

Grounding: IP connections currently bypass the encrypted identity handshake and carry no account context. `ConnectionMeta` contains capability bits and an audit reference, not an authenticated user. The account API already verifies registered bearer tokens and enabled accounts at `/api/user/info`. Existing connection authorization preserves target 2FA and shows the connection manager.

Two read-only design candidates agree on short-lived, server-signed session permits. Online bearer validation by the target was rejected because it exposes reusable account credentials to a destination. IP-to-ID mapping was considered, but an unverified mapping would obscure which endpoint the user reaches. The chosen path connects to the requested IP and verifies its registered public key through the configured HTTPS service before establishing the existing encrypted key exchange. It refuses plaintext fallback.

The permit sidecar reads the hbbs peer database without writing it. Authenticated controllers can request a registered device public key. The key only establishes device identity; it grants no session permission. The sidecar signs permits using a separate Ed25519 key, after checking the live central account and server-owned username/device policy. Admin accounts receive the configured all-device policy; other accounts require an explicit grant. Clients receive only the permit verification public key.

```rust
async fn connect_direct(address: &str) -> Result<(Stream, Vec<u8>)>;
async fn attach_permit(message: &mut Message, hash: &Hash, peer_key: &[u8], encrypted: bool) -> Result<()>;
fn verify_permit(proof: &[u8], nonce: &str, controller_id: &str) -> Result<String>;
fn local_ipv4() -> String;
```

Permits contain a domain separator, authenticated account name, target device ID and registered public key, controller ID, random 256-bit connection nonce, desktop scope and expiry of at most 60 seconds. Both sides validate the signature and fields. The controller requires the permit device key to match the authenticated transport peer, preventing another registered device from relaying a victim's nonce to obtain a permit. The target checks its own identity and requires an encrypted stream before bypassing click approval. The bearer token stays between controller and HTTPS service. File transfer, camera, terminal and tunnels retain their existing authorization paths. Invalid permits are refused. Accounts without a grant retain local approval.

The local protobuf adds explicit feature fields to `Hash` and `LoginRequest`; no hbb_common submodule change or Flutter bridge regeneration is needed. UI uses a feature-specific key in the existing `main_get_common` interface. Tray and UI enumerate live adapters, filtering loopback and unusable IPv4 addresses.

Rubric: verified account and device identity; no plaintext or credential leakage; scoped nonreplayable permits; thin feature-gated hooks preserving the disabled path; installable artifact with visible connection notification. The two candidates converged on the permit boundary. Synthesis adds authenticated direct key exchange from the second candidate's transport finding. The candidates used the inherited model, so model diversity was reduced and a separate-family cross-judge was unavailable.

Verification must cover real account and policy decisions, signature tampering, device/nonce/controller/scope/expiry mismatch, encrypted direct handshake, normal connection-manager notification, live IP display and the final installer. Build success alone does not establish that a desktop session works on the remote machine.

## Verification and remaining work

Before the user's instruction to stop automatic builds, the three Rust permit tests and three Python account/policy tests passed. The Python tests use a real `AD_USERNAME` login for account verification; the admin policy branch uses an authoritative-role fixture because the saved initial admin password is no longer accepted. No account password was reset. HTTPS identity and permit requests passed certificate validation against the development CA.

The release client at `target/CrhRustDesk-20261114-180340` accepted a real encrypted Direct IP v1 connection on temporary local port 21128. The wire probe received desktop PeerInfo using a live `AD_USERNAME` permit without a click; an altered signature was rejected. The actual native controller also reached the new identity/permit endpoints and opened its remote desktop window. A responding connection-manager window appeared on the controlled side. Video/input, visual IP layout and target 2FA were not fully exercised. Both temporary controller configuration files were restored byte-for-byte after closing the test processes.

The feature-disabled Rust check passed. Dart analysis of the home page reported only three existing deprecation notices. The development DLL was compiled with release optimization, LTO disabled and 16 codegen units, then packaged with `Build.ps1 -SkipCargo`. The normal build script retains the repository's release profile.

The easy installer has not been rebuilt for these changes. Installation and a real LAN session on `172.29.0.52` remain unverified. Further builds, including installer compilation and tests that compile code, must wait for an explicit user instruction under AGENTS.md. Existing native audit posting reports a success-envelope mismatch with the API and retries; this backend compatibility issue was not changed here.

## Existing paths changed

* `src/client.rs`: feature-gated IP connection and permit attachment hooks, with one feature-specific authenticated-peer-key field. The key is necessary to prevent cross-device permit relay.
* `src/rendezvous_mediator.rs`: the CrhRustDesk direct listener requests the existing encrypted identity handshake. The disabled feature still passes `false` as before.
* `src/server/connection.rs`: feature-gated nonce preparation, account authorization hook and audit method. Authorization stays after existing access checks and uses the original response and connection-manager paths.
* `libs/base/protos/message.proto`: additive capability and permit fields carry the nonce/device identity and scoped proof. Default fields do not alter old serialized messages.
* `src/flutter_ffi.rs`: a feature-gated key on the existing common getter exposes live adapter addresses without bridge regeneration.
* `flutter/lib/desktop/pages/desktop_home_page.dart`: the CrhRustDesk home page reads and displays IPs using its existing refresh loop.
* `src/tray.rs`: feature-gated IP menu/tooltip and refresh through the existing session-count polling. The disabled feature retains its previous update condition.
* `.github/workflows/flutter-build.yml`: the Windows test job additionally runs the new feature's permit tests.

The remaining runtime implementation is in feature-specific new modules. Build, installer and development-server scripts under `res/crhrustdesk` change only the CrhRustDesk workflow. The earlier branding hooks remain unchanged by this feature work. No submodule was bumped.

## Installation roles and AD follow-up

Source includes a two-role installer and a loopback-only Management page. The Windows installer containing these changes is packaged in `target/CrhRustDesk-Ubuntu-Setup`. Management and the patched API are deployed separately on Ubuntu `172.16.1.83`. AD uses plain LDAP to `172.16.1.10:389` as explicitly requested. A real AD login and current-account lookup passed. LDAP traffic itself is unencrypted.

The installer writes one protected `connection-profile.json` containing role and public server configuration. The feature-specific role module applies the existing incoming/outgoing mode and override settings at process startup. This is needed for operator installations without a receiving service, where writing options to an elevated installer's Windows user profile would not configure the ordinary user's app. The installer verifies the copied profile and reads effective server options back through the existing CLI. It refuses packaging a DLL without role support.

The endpoint role requires a central desktop permit and blocks outgoing connections, including the incoming-mode switch-back exception. The operator role uses existing outgoing-only behavior. An installation role is a local application mode, not a substitute for central account authorization; running another binary on a workstation does not confer central permission.

Management lets administrators enter usernames directly, grant all devices or selected IDs, and revoke grants. It does not require an AD group or grant API administrator privileges to operators. Tokens remain in browser memory. Admin routes enforce administrator role and loopback Host/Origin, and are excluded from the LAN proxy. Policy writes have one service writer; the old CLI now requires the service to be stopped.

The API patch preserves local `admin` as a recovery account, removes LDAP-to-local-password fallback for other users, and checks current AD enabled status when validating tokens. The Ubuntu API was built with this patch and is running. Ubuntu uses a fresh database, JWT secret and signing keys, so no old non-admin tokens were migrated. Existing dev services retain their own data and keys.

Three isolated Python management tests passed: administrator-only edits, per-device grant/revoke, and invalid device IDs. The Rust feature check and five permit/role unit tests also passed. The Windows build succeeded. Installer UI, native role enforcement and ordinary-user operator configuration still require an installation test on the actual endpoints.

Additional existing files changed in this follow-up are `src/crhrustdesk.rs` for profile startup, `src/client.rs` for the endpoint outgoing guard, `src/server/connection.rs` for the required-permit guard, the home-page IP block for operator visibility, and `.github/workflows/flutter-build.yml` to include role tests. Feature-specific installer/build scripts, the permit server, the LAN proxy admin matcher and the offline policy command change only their respective CrhRustDesk workflows. Existing clients without an installation profile retain their previous mode and approval path. No shared signature or submodule changed.

## Ubuntu deployment verification

All five CrhRustDesk services are active and enabled at boot. Recovery admin login, real AD login as a non-admin, admin-only Management access, forged-token rejection and anonymous-permit rejection passed through the live services. HTTPS chain and IP-name verification passed from dev using the exported public CA. LAN requests to admin routes return 403. TCP21115–21117 are reachable from dev; TCP21114,21120,21118,21119 are not reachable. UFW permits only the two configured client IPs for native transport and HTTPS. Reboot, disabled AD accounts, UDP traversal and a real desktop session on `172.29.0.52` remain untested.

The deployment changes only CrhRustDesk paths under `/opt`, `/etc`, `/var/lib`, its five new systemd units and six additive UFW rules. Existing Nginx and the running `chiangrai-fastapi-pq` container were not changed. API source and normalized line endings belong to the external build copy, not the parent repository or submodules.

In this deployment follow-up, `res/crhrustdesk/Build.ps1` adds explicit production permit-key and root-certificate inputs while keeping dev defaults. `account-server/requirements.txt` selects a Python-3.10-compatible pycparser on Ubuntu without changing the Windows selection. `ubuntu/set-ldap-secret.sh` now checks for an existing secret before creating its directory, so re-running it cannot remove the running service user's directory access. Client runtime paths were not changed in this step.

The user explicitly requested the Windows client build afterward. Release compilation used LTO disabled and 16 codegen units, followed by Flutter release and Inno Setup compilation. The fresh native DLL contains the exported Ubuntu transport/permit public keys, the Ubuntu API URL and the role marker; the dev permit key is absent. The bundle DLL matches the fresh build, the exported CA hash matches, no private server files or stale installation profile were found, and native `--version` returns 1.5.3. The executable's extracted icon shows the new transparent logo. These checks do not establish that a remote desktop session or an elevated installation succeeds.

For packaging, `Build-EasySetup.ps1` adds an optional output directory so the Ubuntu installer can be kept separately from dev artifacts. `installer/CrhRustDesk.iss` changes only the displayed CA description and the explanation that unauthorized endpoint connections are rejected. No authorization logic or shared runtime path changed during this build task.

## Management access from LAN

At the user's request, Management is also available at `https://172.16.1.83:21120/_admin/`. Caddy binds the LAN address on TCP21120; Python remains bound to 127.0.0.1:21120. Two additive UFW rules allow Management from the observed Ubuntu subnet 172.16.0.0/16 and controller subnet 172.29.0.0/24. Existing native transport and account API firewall rules remain unchanged.

Regression surface: `account-server/server.py` accepts one optional configured HTTPS Origin while preserving the existing loopback Host check, authentication and default behavior. `ubuntu/crhrustdesk-permit.service` enables that Origin for this deployment. `ubuntu/Caddyfile` adds the Management HTTPS listener, forwards only its page, script and admin-sidecar routes, and rewrites upstream Host to the loopback host. The existing 8443 admin-route block and all account/permit authorization rules remain in place. Documentation adds the LAN URL alongside the existing SSH option. No client runtime changed or client rebuild was needed.

Live verification passed: certificate-verified page and script retrieval from dev, HTTPS admin login, authenticated account-list access, anonymous denial, and untrusted-Origin denial even with a valid admin token. Three existing management policy tests and all five live account verification checks passed. All five services remained active. Root-only backups of the three deployment files were saved before replacing them.

## Full Admin page correction

The LAN /_admin/ URL initially served only the permit-policy sidecar, so it lacked the existing API's user management, logs and password editor. It now proxies to the full API frontend, with the same index bytes as the dev release. The supplemental grant page is at /_permissions/ and is linked from the API's welcome text. It retains its own login and policy behavior.

Regression surface for this correction: `ubuntu/Caddyfile` changes only the 21120 listener's routing, forwarding the grant page and sidecar admin endpoints to Python and other paths to the existing account API. `account-server/server.py` adds static aliases for the new grant page; existing loopback paths still work. `management/index.html` uses a relative script URL for both paths and links to full Admin. `ubuntu/admin-hello.md` provides the grant-page link through the API's existing welcome-file mechanism, and `install-server.sh` copies that file for a fresh installation. Documentation identifies the two URLs. No client paths, authorization rules, user/password records or firewall rules changed.

Validation used the actual HTTPS service: full Admin index matches dev, all index-linked scripts/styles/icons load, the separate grant page loads, full Admin login and user/log reads succeed, anonymous reads are denied, and the password-change endpoint rejects missing required fields without changing the password. Existing policy checks and live account checks remain required. No client or API build was run for this correction; the existing frontend assets and API routes are reused.

## File-transfer account authorization, pending build

The user reported that a separate file-transfer session is rejected even though account-authorized desktop access works. The current client deliberately skips permits for every non-desktop login, the signer always issues desktop scope, and the target only accepts desktop permits. The source fix adds a distinct file_transfer scope using the same username-to-device grants. Both peers verify that the signed scope matches the actual login session type. Unsupported session types still receive no account permit. Existing target file-transfer permissions, encryption, 2FA, session-scope checks and connection-manager notifications remain in their original paths.

Machine remote-access passwords are not required for an authorized central-account session, whether a machine has a local remote-access password configured or not. Windows sign-in and lock-screen credentials remain Windows authentication and are not removed or bypassed by this change.

Regression surface is limited to three feature-specific runtime files. `src/crhrustdesk.rs` requests and verifies a permit for the selected desktop or file-transfer login type; its private verifier carries the expected scope to prevent cross-session reuse. `src/server/connection/crhrustdesk.rs` accepts the supported file-transfer scope through its existing central-account authorization hook. `res/crhrustdesk/account-server/server.py` signs only desktop or file_transfer scope after the existing grant check, defaulting omitted scope to desktop for current clients. No shared core hooks, protobuf fields, Windows credentials or device passwords changed.

One Python regression test checks signed file-transfer scope, unsupported-scope rejection and grant removal. It and the three existing management tests passed. Two Rust tests cover desktop/file-transfer isolation and login-type selection but have not been run because compilation needs a fresh explicit build instruction. No client or installer was built, no server patch was deployed and no real file transfer was performed for this fix. The installed clients still have the reported limitation. Completion requires updating the permit service, building and updating both controller and target clients, then testing send/receive and unauthorized-account denial on the real target.

## Managed Windows updates, pending client build

The requested automatic updater is implemented in source as a SYSTEM scheduled task installed by the interactive bootstrap installer. It checks on startup and daily at 03:00, verifies an RSA-3072/SHA-256 signed manifest, restricts artifacts to the configured HTTPS origin, bounds downloads, checks installer size/hash, and advances an administrator-protected revision only after verifying the installed DLL and release metadata. Signing keys are separate from account/transport keys and remain outside the repository and server; only the public key is packaged.

Incoming endpoints query existing authenticated IPC through their own executable for the original updater's idle state. Operator installations wait until their app processes are closed. Idle is checked before and after downloading, not held as an exclusive session-start lock. A session could start between the final check and installation; this remains a limitation of the check-based approach and needs real maintenance-window testing. No new session counters, cache expiry state or Tokio runtimes were added.

The silent managed-install path accepts only an existing exact role/server profile with unchanged CA and update public key. It uses the native update path and keeps the existing task and firewall rules. Interactive installation provisions the task and private cache. Artifact metadata and payload publication on Ubuntu use immutable revision directories and replace latest.json after copying; a publish lock serializes concurrent publishers. Clients are responsible for RSA validation; the root deployment tool checks metadata and file hashes but does not verify RSA. The server contains no signing private key.

Regression surface: `src/crhrustdesk.rs` adds the Windows-specific update module. `src/core_main.rs` adds a feature-gated readiness CLI hook so the existing authenticated IPC accepts the caller's own executable. `src/ipc.rs` adds a feature-gated read-only readiness query without persisting it. `src/updater.rs` bypasses the public RustDesk native updater only for installed CrhRustDesk Windows clients, which now use the managed channel. Other builds retain their existing paths. These three shared hooks are necessary for readiness and preventing public releases from replacing managed clients.

Build-specific changes are confined to `Build.ps1` for public-key/script packaging, `Build-EasySetup.ps1` for monotonic release metadata and the new native capability check, and `installer/CrhRustDesk.iss` for bootstrap registration and guarded silent updates. `.github/workflows/flutter-build.yml` adds the non-build PowerShell protocol checks to Windows CI. `ubuntu/Caddyfile` adds a static update path ahead of the existing permit proxy on port8443; no other account, Management or remote-session route changed. Most implementation is in new updater/publisher scripts and the new feature module.

Three PowerShell protocol tests passed: signed new/already-applied revisions, forged signatures, and invalid signed origin/expiry/size. Script parsing, Python AST and whitespace checks passed. The Ubuntu static route was deployed after Caddy validation and its TLS/caching behavior was tested with a temporary non-release file that was removed. The existing API, full Admin and grant page remained reachable, and all five services stayed active. No latest.json or executable release was published. No client/installer was built or task registered on a workstation. Native readiness, silent installation, role preservation and two-version updates still require explicit build authorization and real Windows tests before operational use.
