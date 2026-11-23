# 04 – Worker exits when it posts its first report

## Symptom
On the `internal` network only, the worker writes its first CSV report successfully,
then exits with code 1 when it posts the summary to the webhook.

## Commands and output
~~~
$ docker run -d --name worker --network internal ... -e REPORT_DIR=/reports \
    -v reports:/reports linkly-worker:dev

$ docker ps -a --filter name=worker
CONTAINER ID   IMAGE               COMMAND              CREATED          STATUS                     NAMES
f91cc4d00ace   linkly-worker:dev   "python worker.py"   15 seconds ago   Exited (1) 9 seconds ago   worker

$ docker run --rm -v reports:/reports busybox:1.36 ls -la /reports
total 12
drwxr-xr-x    2 10001    10001         4096 Nov 23 13:14 .
drwxr-xr-x    1 root     root          4096 Nov 23 13:14 ..
-rw-r--r--    1 10001    10001           23 Nov 23 13:14 clicks-2026-11-23.csv

$ docker logs worker 2>&1 | tail -3
  File "/usr/local/lib/python3.12/site-packages/requests/adapters.py", line 700, in send
    raise ConnectionError(e, request=request)
requests.exceptions.ConnectionError: HTTPSConnectionPool(host='httpbin.org', port=443): Max retries exceeded with url: /post (Caused by NameResolutionError("HTTPSConnection(host='httpbin.org', port=443): Failed to resolve 'httpbin.org' ([Errno -3] Temporary failure in name resolution)"))
~~~
The CSV exists, so the report was written; the crash happened on the next step, the webhook post.

## Root cause
After writing the report, the worker posts a summary to `WEBHOOK_URL`, which defaults
to `https://httpbin.org/post`. The `internal` network is created with `--internal`:
no gateway and no external DNS. Docker's embedded DNS resolves container names but
not internet names, so the lookup fails, `requests` raises `ConnectionError`, the code
does not catch it, and the process exits.

## Fix
Set `WEBHOOK_URL=` (empty). The README states an empty value disables the webhook.

~~~
$ docker run -d --name worker --network internal ... -e WEBHOOK_URL= linkly-worker:dev

$ docker ps --filter name=worker
CONTAINER ID   IMAGE               COMMAND              CREATED         STATUS                   NAMES
bb01edf6deac   linkly-worker:dev   "python worker.py"   7 minutes ago   Up 7 minutes (healthy)   worker

$ docker logs worker 2>&1 | grep -E "worker started|report written"
worker started
report written: /reports/clicks-2026-11-23.csv (1 codes)

$ curl -sk https://localhost/stats/H0M3SC
{"clicks":1,"code":"H0M3SC"}
~~~
The click made through the proxy was queued in Redis, moved to Postgres by the worker,
and is now counted by `/stats`.

We did **not** attach the worker to `dmz`: the reachability matrix requires
worker → Internet to be **Blocked**. A data-tier service with internet access is an
exfiltration path. In production, webhooks would go through a controlled egress proxy
with an allow-list.
