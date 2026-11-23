# Linkly: Segmented Multi-Network Docker Stack

A URL shortener with click analytics, run as 6 hardened containers on 3 segmented
Docker networks, using plain `docker` CLI (no Compose). The public tier cannot reach
the data tier, and the data tier has no internet access. A script proves it live.

## Architecture

~~~
 client (browser / curl)
    │  HTTPS 443   (HTTP 80 → 301 redirect)
    ▼
┌─ dmz · bridge · 172.30.1.0/24 ──────────────┐
│  proxy  (nginx, TLS termination,            │
│          the ONLY service with host ports)  │
│    │ HTTP :5000                             │
│    ▼                                        │
│  api  (gunicorn) ◄── dual-homed ──┐         │
└───────────────────────────────────┼─────────┘
┌─ internal · --internal · 172.30.2.0/24 ─────┼───────────┐
│                                   api                   │
│                  ┌────────────────┴───┐                 │
│                  ▼                    ▼                 │
│                 db (Postgres)      cache (Redis, AOF)   │
│                  ▲                    ▲                 │
│                  └──── worker ────────┘ (CSV reports)   │
└──────────────────┼──────────────────────────────────────┘
┌─ admin · --internal · 172.30.3.0/24 ─┼─┐
│  backup job (throwaway pg_dump) ──► db │
└────────────────────────────────────────┘
~~~

| Service | Image | Networks | Host ports | Storage |
|---|---|---|---|---|
| proxy | `nginxinc/nginx-unprivileged:1.27-alpine` + `proxy/default.conf` | dmz | 80→8080, 443→8443 | none |
| api | built from `api/` | dmz, internal | none | none |
| worker | built from `worker/` | internal | none | `reports` |
| cache | `redis:7.4-alpine`, AOF on | internal | none | `redisdata` |
| db | `postgres:16-alpine` | internal, admin | none | `pgdata` |
| backup job | `postgres:16-alpine` (throwaway) | admin | none | `./backups` bind mount |

`internal` and `admin` are created with `--internal`: no gateway, no internet.

## Reachability matrix (latest `scripts/netcheck.sh` run)

Each service is tested from inside its own network namespace with a busybox sidecar
(`docker run --rm --network container:<svc> busybox:1.36 nc -zw3 <host> <port>`).
The backup job is tested from a throwaway container on `admin`.

~~~
FROM     TO                 EXPECTED  ACTUAL                           RESULT
proxy    api:5000           Allowed   Allowed                          PASS
proxy    db:5432            Blocked   Blocked (name did not resolve)   PASS
proxy    cache:6379         Blocked   Blocked (name did not resolve)   PASS
proxy    1.1.1.1:443        Allowed   Allowed                          PASS
api      db:5432            Allowed   Allowed                          PASS
api      cache:6379         Allowed   Allowed                          PASS
api      1.1.1.1:443        Allowed   Allowed                          PASS
worker   api:5000           Allowed   Allowed                          PASS
worker   db:5432            Allowed   Allowed                          PASS
worker   cache:6379         Allowed   Allowed                          PASS
worker   1.1.1.1:443        Blocked   Blocked (timed out / no route)   PASS
cache    api:5000           Allowed   Allowed                          PASS
cache    db:5432            Allowed   Allowed                          PASS
cache    1.1.1.1:443        Blocked   Blocked (timed out / no route)   PASS
db       api:5000           Allowed   Allowed                          PASS
db       cache:6379         Allowed   Allowed                          PASS
db       1.1.1.1:443        Blocked   Blocked (timed out / no route)   PASS
backup   api:5000           Blocked   Blocked (name did not resolve)   PASS
backup   db:5432            Allowed   Allowed                          PASS
backup   cache:6379         Blocked   Blocked (name did not resolve)   PASS
backup   1.1.1.1:443        Blocked   Blocked (timed out / no route)   PASS

All 21 checks match the design.
~~~

- **name did not resolve**: the two containers share no network, so Docker's DNS does not know the name.
- **timed out / no route**: `--internal` networks have no route to the internet.

## Why the api is reachable from `internal`

worker, cache and db can open connections to `api:5000` because they share the
`internal` network, and Docker networks do not filter traffic between members.

**Why this is acceptable here:**
- The api only serves the same HTTP endpoints that are already public through the proxy,
  so a data-tier container gains nothing it could not get from the internet.
- `internal` has no route out, so this path cannot be used to exfiltrate data.
- cache and db never initiate connections; the worker only needs db and cache.

**How we would remove it if required:**
- Add a `DOCKER-USER` iptables rule that drops new TCP connections to the api's port
  5000 from the `internal` subnet, while allowing established replies to the api's own
  outbound connections.
- Or split `internal` into narrower networks so each service shares a network only with
  the peers it needs. db and cache would still share a network with the api (it calls
  them), so the firewall rule is the simpler option.

## Setup

Prerequisites: Docker Engine / Docker Desktop, `git`, `openssl`, `bash`.

~~~bash
git clone https://github.com/skcloud2007/segmented-docker-microservices.git
cd segmented-docker-microservices
./scripts/up.sh          # builds images, creates secret, cert, networks, volumes; starts all 5 services in order
./scripts/netcheck.sh    # proves the segmentation; exits 0 when every cell matches
~~~

`up.sh` creates a random DB password in `secrets/db_password` and a self-signed
certificate in `proxy/certs/` on first run. Both are gitignored.

Try the app:

~~~bash
curl -sk -X POST https://localhost/links -H 'Content-Type: application/json' -d '{"url":"https://example.com"}'
curl -sk -o /dev/null -w '%{http_code}\n' https://localhost/<code>     # 302
curl -sk https://localhost/stats/<code>                               # clicks counted by the worker
~~~

Other scripts:

| Script | What it does |
|---|---|
| `scripts/up.sh` | Builds and starts the stack in dependency order, waiting for each service to be healthy |
| `scripts/down.sh` | Removes containers and networks, **keeps volumes** (data survives) |
| `scripts/backup.sh` | Runs `pg_dump` in a throwaway container on `admin` only → `backups/linkly-<timestamp>.sql.gz` |
| `scripts/netcheck.sh` | Tests all 21 cells of the reachability matrix |

## Images

| Image | Docker Hub | Tag (git SHA) | Digest |
|---|---|---|---|
| api | [sk7528/linkly-api](https://hub.docker.com/r/sk7528/linkly-api) | `3047a3c` | `sha256:5391a5510ec540dd891c668b08f5c26e88b2127ac3968fc8477bb44c8b286b1c` |
| worker | [sk7528/linkly-worker](https://hub.docker.com/r/sk7528/linkly-worker) | `3047a3c` | `sha256:852188b4829c9a48ec9f464e7bba8785ec72c2fa729bfb2df82c0912bfb8f5b0` |

- Base `python:3.12-slim-bookworm`; `requirements.txt` installed before the code is copied (layer caching).
- Run as fixed non-root UID **10001**; exec-form `CMD`; gunicorn binds `0.0.0.0:5000`.
- `HEALTHCHECK` on every service (provided `healthcheck.py` for api and worker).
- Trivy `aquasec/trivy:0.56.2` with `--severity CRITICAL --ignore-unfixed --exit-code 1`:
  see `docs/evidence/trivy.txt`.
- **api image size ≈ 192 MB** unpacked (sum of `docker history` layers). Docker Desktop's
  containerd image store reports a larger number because it also counts the compressed copy.
- Images were built on Apple Silicon (**arm64**). `up.sh` always builds from source, so the
  stack runs on any architecture.

## Security

| Control | How |
|---|---|
| Least privilege | Every container: `--cap-drop ALL` (no capabilities added back), `--security-opt no-new-privileges` |
| Non-root | api/worker UID 10001, db UID 70, cache UID 999, proxy UID 101 (unprivileged nginx) |
| Immutable filesystem | `--read-only` everywhere; `--tmpfs` only where a service needs scratch space |
| Resource limits | `--memory` and `--cpus` on every container |
| Secrets | DB password is a file mounted read-only at `/run/secrets/db_password`, passed as `DB_PASSWORD_FILE` / `POSTGRES_PASSWORD_FILE`; never in `docker inspect` env |
| Never used | `--privileged`, `--network host`, Docker socket mounts |

## Incidents

Each write-up has the symptom, commands with real output, root cause and fix.

| # | Incident |
|---|---|
| 01 | [api cannot resolve `db` on the default bridge](docs/incidents/01-api-cannot-resolve-db.md) |
| 02 | [proxy returns 502 with the laptop command](docs/incidents/02-proxy-502-loopback-bind.md) |
| 03 | [api crash-loops until Postgres is ready](docs/incidents/03-api-crash-loop-before-postgres.md) |
| 04 | [worker exits on the webhook from `internal`](docs/incidents/04-worker-exits-on-webhook.md) |
| 05 | [api fails with `--read-only`](docs/incidents/05-api-read-only-filesystem.md) |
| 06 | [Permission denied on a new `reports` volume](docs/incidents/06-reports-volume-permission-denied.md) |

## Evidence

Outputs of real runs in [`docs/evidence/`](docs/evidence/): `up-run.txt` (fresh start, timed),
`netcheck.txt`, `backup.txt`, `trivy.txt`, `checks.txt` (dual-homing, published ports,
process users, hardening, secret exposure, app flow), image histories.
