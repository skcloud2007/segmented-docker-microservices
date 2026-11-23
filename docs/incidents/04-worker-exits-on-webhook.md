# 04 – Worker exits when it posts its first report

## Symptom
On the `internal` network only, the worker writes its first CSV report successfully,
then exits with code 1 when it posts the summary to the webhook.

## Commands and output
~~~
$ docker run -d --name worker --network internal ... linkly-worker:dev

$ docker ps -a --filter name=worker
CONTAINER ID   IMAGE               COMMAND              CREATED          STATUS                     NAMES
f91cc4d00ace   linkly-worker:dev   "python worker.py"   15 seconds ago   Exited (1) 9 seconds ago   worker

$ docker logs worker 2>&1 | grep -E "worker started|report written"
PASTE YOUR OUTPUT HERE

$ docker logs worker 2>&1 | tail -3
  File "/usr/local/lib/python3.12/site-packages/requests/adapters.py", line 700, in send
    raise ConnectionError(e, request=request)
requests.exceptions.ConnectionError: HTTPSConnectionPool(host='httpbin.org', port=443): Max retries exceeded with url: /post (Caused by NameResolutionError("HTTPSConnection(host='httpbin.org', port=443): Failed to resolve 'httpbin.org' ([Errno -3] Temporary failure in name resolution)"))
~~~

## Root cause
After writing the report, the worker posts a summary to `WEBHOOK_URL`, which defaults
to `https://httpbin.org/post`. The `internal` network is created with `--internal`:
no gateway and no external DNS. Docker's embedded DNS resolves container names but
not internet names, so the lookup fails, `requests` raises `ConnectionError`, the code
does not catch it, and the process exits.

## Fix
Set `WEBHOOK_URL=` (empty). The README states an empty value disables the webhook.

~~~
PASTE: docker ps showing worker Up (healthy)
PASTE: curl /stats/<code> showing clicks >= 1
~~~

We did **not** attach the worker to `dmz`: the reachability matrix requires
worker → Internet to be **Blocked**. A data-tier service with internet access is an
exfiltration path. In production, webhooks would go through a controlled egress proxy
with an allow-list.
