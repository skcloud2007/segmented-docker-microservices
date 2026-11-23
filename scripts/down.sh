#!/usr/bin/env bash
# Remove the stack's containers and networks. Volumes (the data) are kept.
set -uo pipefail

docker rm -f proxy worker api cache db 2>/dev/null
docker network rm dmz internal admin 2>/dev/null

echo "Containers and networks removed. Volumes kept:"
docker volume ls --filter name=pgdata --filter name=redisdata --filter name=reports
