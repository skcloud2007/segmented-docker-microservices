# 02 – Proxy returns 502 with the README's laptop command

## Symptom
With the api started using the README's command (`gunicorn app:app`), every request
through the proxy returns **502 Bad Gateway**.

## Commands and output
$ docker run -d --name api --network internal ... linkly-api:dev gunicorn app:app
$ docker network connect dmz api

$ curl -sk -o /dev/null -w '%{http_code}\n' https://localhost/health
502

$ docker logs proxy 2>&1 | grep -i upstream | tail -2
2026/11/22 17:11:40 [error] 22#22: *6 connect() failed (111: Connection refused) while connecting to upstream, client: 192.168.65.1, server: , request: "GET /health HTTP/1.1", upstream: "http://172.30.1.2:5000/health", host: "localhost"

$ docker logs api 2>&1 | grep -i listen
[2026-11-22 17:10:06 +0000] [1] [INFO] Listening at: http://127.0.0.1:8000 (1)


## Root cause
gunicorn's defaults are `127.0.0.1:8000`. Inside a container, 127.0.0.1 is the
container's own loopback, unreachable from other containers. nginx connects to the
api's dmz address on port 5000 (`proxy_pass http://api:5000`), so it is refused on
both counts: wrong interface and wrong port. nginx reports this as 502.

## Fix
Use the image's exec-form CMD, which binds `0.0.0.0:5000`. Restart the proxy
afterwards: nginx resolves `api` only once at startup, so a recreated api container
with a new IP is not picked up until nginx restarts.

$ docker rm -f api
$ docker run -d --name api --network internal ... linkly-api:dev
$ docker network connect dmz api
$ docker restart proxy
$ curl -sk -o /dev/null -w '%{http_code}\n' https://localhost/health
200
$ curl -sk -X POST https://localhost/links -H 'Content-Type: application/json' -d '{"url":"https://example.com"}'
{"code":"H0M3SC","url":"https://example.com"}
$ curl -sk -o /dev/null -w '%{http_code}\n' https://localhost/H0M3SC
302

