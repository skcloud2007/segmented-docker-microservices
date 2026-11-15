# 01 – API cannot resolve `db`

## Symptom
The `api` container exits a second after starting. It never reaches the database
because the hostname `db` cannot be resolved.

## Commands and output

Started `db` and `api` without `--network` (Docker's default bridge):
$ docker run -d --name db ... postgres:16-alpine
$ docker run -d --name api -e DB_HOST=db ... linkly-api:dev

$ docker ps -a --filter name=api
CONTAINER ID IMAGE COMMAND STATUS
57d82beeb2c2 linkly-api:dev “gunicorn --bind 0.0…” Exited (3)

$ docker logs api 2>&1 | tail -5
psycopg.OperationalError: [Errno -2] Name or service not known
[2026-11-15 15:21:24 +0000] [8] [INFO] Worker exiting (pid: 8)
[2026-11-15 15:21:24 +0000] [1] [ERROR] Worker (pid:7) exited with code 3
[2026-11-15 15:21:24 +0000] [1] [ERROR] Shutting down: Master
[2026-11-15 15:21:24 +0000] [1] [ERROR] Reason: Worker failed to boot.


Name lookup from a container on the default bridge:

$ docker run --rm busybox:1.36 nslookup db
PASTE YOUR OUTPUT HERE


Same lookup from a container on a user-defined network (`internal`), after attaching `db` to it:

$ docker network connect internal db
$ docker run --rm --network internal busybox:1.36 nslookup db
PASTE YOUR OUTPUT HERE


## Root cause
Without `--network`, containers join Docker's **default bridge**. The default bridge
has no DNS for container names; containers there can only reach each other by IP.
The api's `init_schema()` runs at startup, tries to connect to host `db`, the lookup
fails (`Errno -2 Name or service not known`), the gunicorn worker fails to boot and
the container exits with code 3.

## Fix
Run every service on a **user-defined network**. Docker gives these networks an
embedded DNS server (`127.0.0.11`) that resolves container names to IPs.
In this project `api` and `db` share the `internal` network, so `DB_HOST=db` resolves.
`scripts/up.sh` always passes `--network`, and no script uses IP addresses.

## Lesson
Never rely on the default bridge. Service discovery by name only works on
user-defined networks.