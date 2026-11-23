# 06 – Worker gets Permission denied on the reports volume

## Symptom
The worker (running as UID 10001) exits within seconds of starting, when it writes
its first CSV report into the new `reports` named volume.

## Commands and output
~~~
$ docker run -d --name worker --network internal ... -e REPORT_DIR=/reports \
    -v reports:/reports linkly-worker:dev

$ docker ps -a --filter name=worker
CONTAINER ID   IMAGE               COMMAND              CREATED         STATUS                     NAMES
de56d74f4727   linkly-worker:dev   "python worker.py"   6 seconds ago   Exited (1) 4 seconds ago   worker

$ docker logs worker 2>&1 | tail -5
    write_report()
  File "/app/worker.py", line 58, in write_report
    with open(path, "w", newline="") as f:
         ^^^^^^^^^^^^^^^^^^^^^^^^^^^
PermissionError: [Errno 13] Permission denied: '/reports/clicks-2026-11-22.csv'

$ docker run --rm -v reports:/reports busybox:1.36 ls -ld /reports
drwxr-xr-x    2 root     root          4096 Nov 15 15:03 /reports

$ docker run --rm --entrypoint id linkly-worker:dev
uid=10001(app) gid=10001(app) groups=10001(app)
~~~

## Root cause
`/reports` does not exist in the worker image. When Docker mounts a new, empty named
volume, it takes the mount point's ownership from the image; with no such directory
in the image, the volume root is created as `root:root` with mode 755. The worker runs
as UID 10001 (non-root by design), so it can read but not write there.

## Fix
Create the mount point in the image, owned by the app user, before `USER 10001`:

~~~dockerfile
RUN mkdir /reports && chown 10001:10001 /reports
~~~

Rebuild, then recreate the volume so Docker copies the new ownership into it
(the copy only happens for a new, empty volume):

~~~
PASTE: ls -l /reports output after the fix
~~~

We did not fix it with `chmod 777` or by running as root: both would weaken the
least-privilege design.
