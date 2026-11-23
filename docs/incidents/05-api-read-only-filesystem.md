# 05 – API fails on its first write with --read-only

## Symptom
Adding `--read-only` to the api makes it exit immediately. It fails twice, on two
different writes, before it can start.

## Commands and output

Try 1: `--read-only` only, README defaults:
~~~
$ docker run -d --name api-ro-test --network internal \
    --cap-drop ALL --security-opt no-new-privileges --read-only \
    ... linkly-api:dev

$ docker ps -a --filter name=api-ro-test
CONTAINER ID   IMAGE            COMMAND                  CREATED         STATUS                       NAMES
0886b7563c5e   linkly-api:dev   "gunicorn --bind 0.0…"   5 seconds ago   Exited (255) 4 seconds ago   api-ro-test

$ docker logs api-ro-test 2>&1 | tail -3
  File "/usr/local/lib/python3.12/tempfile.py", line 224, in _get_default_tempdir
    raise FileNotFoundError(_errno.ENOENT,
FileNotFoundError: [Errno 2] No usable temporary directory found in ['/tmp', '/var/tmp', '/usr/tmp', '/app']
~~~

Try 2: add `--tmpfs /tmp`, still the default `LOG_FILE=logs/api.log`:
~~~
$ docker run -d --name api-ro-test --network internal \
    --cap-drop ALL --security-opt no-new-privileges --read-only --tmpfs /tmp \
    ... linkly-api:dev

$ docker ps -a --filter name=api-ro-test
CONTAINER ID   IMAGE            COMMAND                  CREATED         STATUS                     NAMES
9939ed25d8e8   linkly-api:dev   "gunicorn --bind 0.0…"   5 seconds ago   Exited (1) 4 seconds ago   api-ro-test

$ docker logs api-ro-test 2>&1 | tail -1
gunicorn.errors.HaltServer: <HaltServer 'Worker failed to boot.' 3>

$ docker logs api-ro-test 2>&1 | grep -i -E "errno|read-only" | head -3
OSError: [Errno 30] Read-only file system: 'logs'
OSError: [Errno 30] Read-only file system: 'logs'
~~~
(The error appears twice because gunicorn runs two workers, and both fail.)

## Root cause
`--read-only` makes the whole container filesystem unwritable. The api has two writes:

1. **gunicorn's worker heartbeat files.** gunicorn creates temp files through Python's
   `tempfile`, which tries `/tmp`, `/var/tmp`, `/usr/tmp` and the working dir. All are
   read-only, so the master process fails (exit 255).
2. **The application log file.** The README default `LOG_FILE=logs/api.log` makes
   `app.py` create `/app/logs/` at import time. The worker fails with `Errno 30`.

Note: `tail` only showed gunicorn's summary (`Worker failed to boot`); the real cause
was found by searching the full log for `Errno`.

## Fix
Each write gets the fix that matches its kind of data:

| Write | Fix | Why |
|---|---|---|
| gunicorn temp files | `--tmpfs /tmp` | Scratch data: RAM-backed, lost on restart, which is fine |
| app log file | `-e LOG_FILE=-` (stdout) | Logs must outlive the container and be visible to `docker logs`; a tmpfs would hide them and lose them on restart |

~~~
$ docker run -d --name api --network internal \
    --cap-drop ALL --security-opt no-new-privileges \
    --read-only --tmpfs /tmp --memory 256m --cpus 0.5 \
    -e LOG_FILE=- ... linkly-api:dev
$ docker network connect dmz api
$ docker restart proxy

$ docker ps --format 'table {{.Names}}\t{{.Status}}'
NAMES     STATUS
api       Up 15 seconds (healthy)
worker    Up 3 minutes (healthy)
proxy     Up 15 seconds (healthy)
cache     Up 20 hours (healthy)
db        Up 20 hours (healthy)

$ curl -sk -o /dev/null -w '%{http_code}\n' https://localhost/health
200

$ docker inspect -f 'ReadonlyRootfs={{.HostConfig.ReadonlyRootfs}} CapDrop={{.HostConfig.CapDrop}}' api
ReadonlyRootfs=true CapDrop=[ALL]
~~~

We did not drop `--read-only`. The filesystem stays immutable; only `/tmp` (RAM) is writable.
