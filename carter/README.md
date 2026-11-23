# Carter Consulting — DHIS2 test environment

This directory lives on branch `carter/2.43-test` of Carter's fork of
[dhis2/dhis2-core](https://github.com/dhis2/dhis2-core), based on release tag **2.43.2.1**
(the latest stable release at setup, 2026-11-23). Everything Carter-specific lives in
`carter/`, so upstream patch releases merge cleanly.

> **Test only.** Ports are bound to `127.0.0.1`, the demo DB uses public demo credentials,
> and audit is on for everything. Do not expose this to the internet or load real patient data.

## Quick start

```bash
cd dhis2-carter/carter
cp .env.example .env              # set DB_PASSWORD
./scripts/up.sh                   # DHIS2 + PostGIS 16 + Sierra Leone demo DB
./scripts/wait-ready.sh           # first boot takes 5–15 min
open http://localhost:8080        # login: admin / district
```

With the CompassLink connector and a mock Compass API:

```bash
./scripts/up.sh --compasslink
docker compose logs -f compasslink
```

Stop with `./scripts/down.sh` (`--reset` also wipes the database and the downloaded dump).

## What runs

| Service        | Image                        | Port (localhost) | Notes |
|----------------|------------------------------|------------------|-------|
| `web`          | `dhis2/core:2.43.2.1`        | 8080             | Config: `config/dhis.conf` |
| `db`           | `postgis/postgis:16-3.5`     | 5432             | Data in `db-data` volume |
| `db-dump`      | `busybox`                    | –                | Downloads demo DB once |
| `compass-mock` | built from `../../compasslink` | 4010           | profile `compasslink` |
| `compasslink`  | built from `../../compasslink` | –              | profile `compasslink` |

Swap in a Carter test snapshot or empty database by changing `DHIS2_DB_DUMP_URL`
(then `./scripts/down.sh --reset`).

## Hosting on Railway

`railway/` has Railway services for DHIS2, PostGIS (with first-boot demo load and admin
password hardening) and the CompassLink cron job. See [railway/README.md](railway/README.md).

## Running Carter's own build of DHIS2

The default uses the official release image (identical to this source). To run a build
of this fork with Carter patches (needs JDK 17, Maven 3.9, Docker):

```bash
./carter/scripts/build-local.sh carter/dhis2-core:2.43.2.1-carter
# then in carter/.env:  DHIS2_IMAGE=carter/dhis2-core:2.43.2.1-carter
```

## Keeping the fork current

The clone is shallow (`--depth 1`) and the upstream remote is named `upstream`.

```bash
git fetch --depth 1 upstream tag 2.43.3            # next patch release
git merge 2.43.3                                    # carter/ never conflicts
```

To publish the fork to Carter's GitHub org: create the fork on GitHub
(`gh repo fork dhis2/dhis2-core --org <carter-org> --clone=false`), then
`git remote add origin <url> && git push -u origin carter/2.43-test`.
