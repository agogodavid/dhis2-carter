# Carter DHIS2 test environment + CompassLink on Railway

One Railway project, five services. They talk over Railway's private network
(`<service>.railway.internal`), and only DHIS2 gets a public domain.

| Service       | Source                                  | Type            | Volume                      |
|---------------|-----------------------------------------|-----------------|-----------------------------|
| `postgis`     | `dhis2-carter/carter/railway/postgis`   | always on       | `/var/lib/postgresql/data`  |
| `dhis2`       | `dhis2-carter/carter/railway/dhis2`     | always on, public | `/opt/dhis2/files`        |
| `Postgres`    | Railway Postgres template               | always on (small) | managed by Railway        |
| `compasslink` | `compasslink/` (`railway.json`)         | **cron**, hourly | none: state lives in `Postgres` |
| `compass-mock`| `compasslink/` (`railway.mock-compass.json`) | optional, sleeps when idle | none          |

**Deployed instance:** project `carter-dhis2-test` (workspace Teledyne Projects),
DHIS2 at https://dhis2-production.up.railway.app. Generated secrets are in
`.secrets.local` next to this file (git-ignored).

> **Railway CLI caveat (CLI 4.36):** `railway up` applies the *build* section of
> `railway.json` but **not** the *deploy* section (start command, cron schedule, health
> check, restart policy), and `railway environment edit` reported "No changes to apply".
> The images therefore don't rely on start commands. Set these deploy settings in the
> dashboard (*service → Settings*) or through Railway's GraphQL API
> (`serviceInstanceUpdate`). The deployed instance already has the first two:
>
> | Service | Setting |
> |---|---|
> | `compasslink` | Cron Schedule `0 * * * *`, Restart Policy **Never** (set) |
> | `dhis2` | Healthcheck Path `/api/ping`, timeout 600 s (set; applies from the next deploy) |
> | `compass-mock` | Serverless / sleep when idle (optional) |

DHIS2 is an always-on Java server: it needs **≥ 4 GB RAM** on its service, and
background jobs (analytics tables, scheduling) stop if it sleeps. Keep
`sleepApplication` off and one replica. CompassLink is the serverless-shaped part:
it starts on the cron schedule, syncs, and exits.

## 1. Create the project and the database

```bash
railway login
railway init --name carter-dhis2-test
```

Add the **postgis** service: in the dashboard choose *New → Empty service*, name it
`postgis`, add a volume mounted at `/var/lib/postgresql/data`, and set these variables:

```
POSTGRES_USER=dhis
POSTGRES_DB=dhis
POSTGRES_PASSWORD=<random string, 32+ characters>
DHIS2_DB_DUMP_URL=https://databases.dhis2.org/sierra-leone/2.43/dhis2-db-sierra-leone.sql.gz
DHIS2_ADMIN_PASSWORD=<strong password for the DHIS2 admin user>
DHIS2_DISABLE_DEMO_USERS=true
```

Then deploy it:

```bash
cd dhis2-carter/carter/railway/postgis
railway up --service postgis
```

The demo dump is downloaded **at build time** (the PostGIS image's Debian bullseye apt
mirrors are unreliable, so there is no downloader at runtime), so `DHIS2_DB_DUMP_URL`
must be set before the first deploy. On first boot Postgres loads it, then the init script replaces the publicly known
`admin` / `district` password with `DHIS2_ADMIN_PASSWORD`, and disables the other demo
accounts. This only runs while the volume is empty. To start over, delete the volume.
Leave `DHIS2_DB_DUMP_URL` empty to get a blank DHIS2 instead.

## 2. DHIS2

Create an empty service `dhis2`, add a volume at `/opt/dhis2/files`, set the service's
memory to at least 4 GB, and set these variables:

```
DB_HOSTNAME=${{postgis.RAILWAY_PRIVATE_DOMAIN}}
DB_PORT=5432
DB_NAME=${{postgis.POSTGRES_DB}}
DB_USERNAME=${{postgis.POSTGRES_USER}}
DB_PASSWORD=${{postgis.POSTGRES_PASSWORD}}
PORT=8080
DHIS2_PUBLIC_URL=https://${{RAILWAY_PUBLIC_DOMAIN}}
JAVA_TOOL_OPTIONS=-Xms1g -Xmx3g -Dlog4j2.configurationFile=/opt/dhis2/log4j2.xml
RAILWAY_RUN_UID=0
```

`RAILWAY_RUN_UID=0` lets the container write to the Railway volume, which is root-owned.
Deploy it:

```bash
cd dhis2-carter/carter/railway/dhis2
railway up . --path-as-root --service dhis2
```

Wait for the health check at `/api/ping` to pass. The first boot runs database migrations
and can take 10 minutes or more. Then generate a public domain under *Settings → Networking*.
**Check the hardening right away:** `admin` / `district` must be rejected, and `admin`
with `DHIS2_ADMIN_PASSWORD` must work. If the postgis logs showed
`userinfo.password not found`, change the admin password in the DHIS2 UI immediately.

## 3. CompassLink

1. Add Railway's **Postgres** template, keeping the default name `Postgres`. It stores
   CompassLink's sync watermark and run history, separate from the DHIS2 database.
2. Create the integration user and its token:

   ```bash
   S=dhis2-carter/carter/railway/.secrets.local; URL=https://dhis2-production.up.railway.app
   python3 dhis2-carter/carter/railway/provision-compasslink-user.py $S $URL user
   python3 dhis2-carter/carter/railway/provision-compasslink-user.py $S $URL sharing
   python3 dhis2-carter/carter/railway/provision-compasslink-user.py $S $URL token
   ```

   This creates the user group, role (`F_DATAVALUE_ADD` only) and user `compasslink`, scoped
   to Bo district. It gives the group data-write sharing (`r-rw----`) on the Reproductive
   Health data set and the inpatient program and stage, then creates a personal access token
   while signed in as `compasslink`, because DHIS2 tokens belong to the user who creates them.
3. Create an empty service `compasslink` and set these variables:

   ```
   COMPASSLINK_CONFIG=config/compasslink.railway.yml
   DATABASE_URL=${{Postgres.DATABASE_URL}}
   DHIS2_BASE_URL=http://${{dhis2.RAILWAY_PRIVATE_DOMAIN}}:8080
   DHIS2_API_TOKEN=<the PAT>
   COMPASS_BASE_URL=<Compass API URL>     # or http://${{compass-mock.RAILWAY_PRIVATE_DOMAIN}}:${{compass-mock.PORT}}
   COMPASS_API_TOKEN=<Compass token>
   ```

   Set `DHIS2_API_TOKEN` with `railway variables --service compasslink --set … >/dev/null`.
   The CLI echoes variable values, so discard its output.

4. Deploy it, then set the cron schedule (see the caveat above):

   ```bash
   cd compasslink
   railway up . --path-as-root --service compasslink
   ```

   Without `--path-as-root`, the CLI uploads the whole linked project folder and the
   build fails.

The image's default command is `compasslink sync`. With the cron schedule set it runs every
hour at :00 UTC (Railway allows intervals of 5 minutes or more) and exits. A deploy does
**not** start a run. To run one now, use *Run now* on the cron service in the dashboard, or
the GraphQL mutation `deploymentInstanceExecutionCreate(input: {serviceInstanceId})`. A run that ends with DHIS2 conflicts exits with code 2 and shows as
failed in Railway. The command is chosen with variables:

| Variable | Effect |
|---|---|
| `COMPASSLINK_ARGS="sync --dry-run"` | one validation-only run |
| `COMPASSLINK_ARGS="sync --every 60"` | always-on worker instead of cron |
| `COMPASSLINK_ENTRY=scripts/mock-compass.js` | run the mock Compass API |

Edit `compasslink/config/compasslink.railway.yml` to change the mappings, then redeploy.
It has no secrets of its own: every `${VAR}` comes from the service's variables.

### Optional: mock Compass

Create a service `compass-mock`, set `PORT=4010` and
`COMPASSLINK_ENTRY=scripts/mock-compass.js`, and deploy the `compasslink/` directory to it
(`railway up . --path-as-root --service compass-mock`). Point `COMPASS_BASE_URL` at it as
shown above. It serves a deterministic demo dataset: 10 Bo district facilities, a rolling
13 months, about 8,300 ANC/maternal tallies and 1,850 inpatient discharges. The dataset is
described in [`compasslink/docs/data-model.md`](https://github.com/agogodavid/compasslink/blob/main/docs/data-model.md) (private repo).

## 4. Analytics

DHIS2 dashboards, Data Visualizer and Maps read **analytics tables**, not raw data. On a
fresh instance they don't exist yet, so every dashboard shows *"There's a problem with the
generated analytics"*. Generate them under *Data Administration → Analytics Tables*, or:

```bash
curl -u admin:… -X POST "https://dhis2-production.up.railway.app/api/resourceTables/analytics?lastYears=2"
```

A run takes about 5 minutes on this instance. Data CompassLink writes appears on dashboards
only after the next generation.

**The nightly rebuild exists but is switched off**, because this is a demo instance. In the
*Scheduler* app it's called **CompassLink - nightly analytics refresh (OFF - enable when
developing CompassLink)** (job `cQd8Sl75tiB`). It runs daily at 02:15 UTC, after the 02:00
sync, and rebuilds the last 2 years. Enable it while developing CompassLink and disable it
afterwards.

## Notes

- **Verified IDs:** the example mapping's DHIS2 IDs were checked against this
  2.43.2.1 instance. Ngelehun CHC and Baomahun CHC are assigned to both the data set and the
  program; Bo district is not assigned to the program. For any other instance, check them
  with `compasslink inspect <uid>`.
- **Verified sync, 2026-11-23 (demo dataset):** 10,132 Compass records produced 1,680
  monthly data values and 1,852 inpatient events, with 531 current-month tallies held back,
  2 deliberate bad rows reported as mapping issues, and 0 DHIS2 conflicts.
- **Totals include the demo DB's own values:** the Sierra Leone database also has ANC
  values for these facilities under other category option combos (age bands). Analytics
  totals are demo plus Compass data. Filter on *Fixed/Outreach* to see CompassLink's part.
- **Not production-grade:** this is test infrastructure. For production DHIS2, use managed
  backups for `postgis`, plan memory and analytics capacity, and follow
  [dhis2/docker-deployment](https://github.com/dhis2/docker-deployment).
