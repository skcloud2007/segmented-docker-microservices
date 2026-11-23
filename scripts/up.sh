#!/usr/bin/env bash
# Build and start the whole Linkly stack in dependency order.
set -euo pipefail
cd "$(dirname "$0")/.."                       # always run from the repo root

HUB_USER="sk7528"                            # Docker Hub username
TAG="$(git rev-parse --short HEAD)"           # images are tagged with the git SHA
API_IMG="$HUB_USER/linkly-api:$TAG"
WORKER_IMG="$HUB_USER/linkly-worker:$TAG"
SECRET="$PWD/secrets/db_password"
HARDEN="--cap-drop ALL --security-opt no-new-privileges --read-only"

wait_healthy() {                              # incident 03: never start too early
  for i in $(seq 1 60); do
    if [ "$(docker inspect -f '{{.State.Health.Status}}' "$1")" = "healthy" ]; then
      echo "$1 is healthy"; return 0
    fi
    echo "waiting for $1..."; sleep 2
  done
  echo "ERROR: $1 not healthy"; docker logs --tail 20 "$1"; exit 1
}

echo "== Secret and certificate"
if [ ! -f secrets/db_password ]; then
  mkdir -p secrets
  openssl rand -base64 24 | tr -d '/+=' > secrets/db_password
fi
chmod 644 secrets/db_password
[ -f proxy/certs/tls.crt ] || bash proxy/gen-cert.sh

echo "== Images (tag $TAG)"
docker build -f api/Dockerfile -t "$API_IMG" .
docker build -f worker/Dockerfile -t "$WORKER_IMG" .

echo "== Networks and volumes"
docker network inspect dmz      >/dev/null 2>&1 || docker network create --subnet 172.30.1.0/24 dmz
docker network inspect internal >/dev/null 2>&1 || docker network create --internal --subnet 172.30.2.0/24 internal
docker network inspect admin    >/dev/null 2>&1 || docker network create --internal --subnet 172.30.3.0/24 admin
for v in pgdata redisdata reports; do docker volume create "$v" >/dev/null; done

echo "== Removing old containers (data stays in volumes)"
docker rm -f proxy worker api cache db >/dev/null 2>&1 || true

echo "== db"
docker run -d --name db --network internal --user 70:70 $HARDEN \
  --tmpfs /var/run/postgresql:uid=70,gid=70 --tmpfs /tmp \
  --memory 512m --cpus 1 \
  -e POSTGRES_USER=linkly -e POSTGRES_DB=linkly \
  -e POSTGRES_PASSWORD_FILE=/run/secrets/db_password \
  -v "$SECRET:/run/secrets/db_password:ro" \
  -v pgdata:/var/lib/postgresql/data \
  --health-cmd "pg_isready -U linkly -d linkly" --health-interval 5s --health-retries 5 \
  postgres:16-alpine
docker network connect admin db
wait_healthy db

echo "== cache"
docker run -d --name cache --network internal --user 999:999 $HARDEN \
  --memory 256m --cpus 0.5 \
  -v redisdata:/data \
  --health-cmd "redis-cli ping" --health-interval 5s --health-retries 5 \
  redis:7.4-alpine redis-server --appendonly yes
wait_healthy cache

echo "== api"
docker run -d --name api --network internal $HARDEN --tmpfs /tmp \
  --memory 256m --cpus 0.5 \
  -e DB_HOST=db -e REDIS_HOST=cache -e LOG_FILE=- \
  -e DB_PASSWORD_FILE=/run/secrets/db_password \
  -v "$SECRET:/run/secrets/db_password:ro" \
  "$API_IMG"
docker network connect dmz api
wait_healthy api

echo "== worker"
docker run -d --name worker --network internal $HARDEN --tmpfs /tmp \
  --memory 256m --cpus 0.5 \
  -e DB_HOST=db -e REDIS_HOST=cache -e WEBHOOK_URL= -e REPORT_DIR=/reports \
  -e DB_PASSWORD_FILE=/run/secrets/db_password \
  -v "$SECRET:/run/secrets/db_password:ro" \
  -v reports:/reports \
  "$WORKER_IMG"
wait_healthy worker

echo "== proxy"
docker run -d --name proxy --network dmz -p 80:8080 -p 443:8443 $HARDEN --tmpfs /tmp \
  --memory 128m --cpus 0.5 \
  -v "$PWD/proxy/default.conf:/etc/nginx/conf.d/default.conf:ro" \
  -v "$PWD/proxy/certs:/etc/nginx/certs:ro" \
  --health-cmd "wget -qO- http://127.0.0.1:8080/healthz || exit 1" --health-interval 10s \
  nginxinc/nginx-unprivileged:1.27-alpine
wait_healthy proxy

echo "== Stack is up"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
