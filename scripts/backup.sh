#!/usr/bin/env bash
# Dump the linkly database over the admin network only, into ./backups/<timestamp>.sql.gz
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p backups
FILE="linkly-$(date +%Y%m%d-%H%M%S).sql.gz"

docker run --rm --network admin \
  --user "$(id -u):$(id -g)" \
  --cap-drop ALL --security-opt no-new-privileges --read-only --tmpfs /tmp \
  --memory 256m --cpus 0.5 \
  -v "$PWD/secrets/db_password:/run/secrets/db_password:ro" \
  -v "$PWD/backups:/backups" \
  postgres:16-alpine \
  sh -c 'set -eo pipefail
         PGPASSWORD="$(cat /run/secrets/db_password)" pg_dump -h db -U linkly -d linkly \
           | gzip > /backups/'"$FILE"

echo "Backup written: backups/$FILE"
ls -lh "backups/$FILE"
