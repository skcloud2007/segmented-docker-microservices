# 03 – API crash-loops until Postgres is ready

## Symptom
Starting db and api together, the api crashes and Docker restarts it
(RestartCount > 0) until Postgres finishes initializing.

## Commands and output
$ docker run -d --name db ... postgres:16-alpine
$ docker run -d --name api --restart on-failure:10 ... linkly-api:dev

$ docker logs api 2>&1 | grep -i -E “error|refused|starting up” | head -5
[2026-11-15 15:43:33 +0000] [7] [ERROR] Exception in worker process
psycopg.OperationalError: connection failed: connection to server at “172.30.2.2”, port 5432 failed: Connection refused
[2026-11-15 15:43:33 +0000] [8] [ERROR] Exception in worker process
psycopg.OperationalError: connection failed: connection to server at “172.30.2.2”, port 5432 failed: Connection refused
[2026-11-15 15:43:33 +0000] [1] [ERROR] Worker (pid:8) exited with code 3

$ docker inspect -f ‘RestartCount={{.RestartCount}}’ api
RestartCount=1


After the fix (wait for db healthy, then start api):

PASTE YOUR “waiting for db...” OUTPUT AND RestartCount=0 HERE


## Root cause
The api runs `init_schema()` at import time, so it needs Postgres the moment it starts.
A container being "running" does not mean Postgres accepts connections: on a fresh
volume it first runs initdb and restarts itself. During that window, connections are
refused and the gunicorn worker fails to boot (exit 3).

## Fix
Give db a healthcheck (`pg_isready -U linkly -d linkly`) and start the api only after
`docker inspect -f '{{.State.Health.Status}}' db` returns `healthy`.
`scripts/up.sh` does this for every service in dependency order.
