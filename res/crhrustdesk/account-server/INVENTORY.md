# Client inventory

Open `/_permissions/` on the existing Management listener and sign in as an
administrator. The inventory shows installations that have reported successfully,
including machines that have never received a remote session. It retains offline
machines; an offline entry does not confirm that the software is still installed.

The Windows client reports once per minute after managed installation. Incoming
clients report from the Windows service. Outgoing clients report while the main
application is open; the first enrollment requires account login. Portable runs
do not enroll. Online means a signed report was received in the last 180 seconds.
Dates in the browser use the administrator's local time.

## Report contract

`POST /crhrustdesk/inventory` accepts JSON fields `public_key` (base64 Ed25519
public key) and `report` (base64 signed message, signature followed by UTF-8 JSON).
The signed object contains:

- `domain`: `crhrustdesk-inventory-v1`
- `machine_id`: lowercase SHA-256 of the existing machine UUID
- `id`, `hostname`, `role` (`incoming` or `outgoing`), `version`
- `revision`: positive signed-64-bit release revision from `client-release.json`
- `reported_at`: Unix seconds within 120 seconds of the server clock

Incoming enrollment must match the transport server's registered public key.
Outgoing enrollment requires a valid account bearer token. The first accepted
signing key is pinned to the machine identity. Later reports must use that key;
replaying an old report does not refresh online status. This endpoint grants no
remote permissions and does not change account or unattended-access policy.

Reports are stored in `client-inventory.sqlite3` under the existing permit state
directory. A changed ID updates the existing machine instead of adding a count.
Clearing the device's signing key requires administrator review of its inventory
entry before re-enrollment. Cloned OS machine UUIDs require distinct OS identities.

## Administrator contract

`POST /crhrustdesk/admin/inventory` with `{}` uses the existing administrator
bearer authentication and Management Host/Origin checks. It returns `total`,
`online`, `incoming`, `outgoing`, `online_seconds`, and `devices` ordered by most
recent report. Device rows contain identity, metadata, first/last-seen Unix seconds,
and `online`. Public keys, account tokens, and passwords are never returned.

Deploy `inventory.py` together with `server.py`, `management.py`, and the
`management` assets. Restart only the permit service. No API/transport database
migration or proxy route change is needed. Existing clients and permission routes
keep their previous behavior.

Run `python -B -m unittest test_inventory test_management` from this directory.
