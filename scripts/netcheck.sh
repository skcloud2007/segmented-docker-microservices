#!/usr/bin/env bash
# Test every cell of the reachability matrix from inside each service's network
# namespace (busybox sidecar). Prints expected vs actual; exits 1 on any mismatch.
set -uo pipefail

INET=1.1.1.1
FAILS=0
TOTAL=0
FMT="%-8s %-18s %-9s %-32s %s\n"
printf "$FMT" FROM TO EXPECTED ACTUAL RESULT

check() {   # check <from> <host> <port> <Allowed|Blocked>
  local from=$1 host=$2 port=$3 expected=$4 net out actual result
  if [ "$from" = "backup" ]; then net="admin"; else net="container:$from"; fi

  if out=$(docker run --rm --network "$net" busybox:1.36 nc -zw3 "$host" "$port" 2>&1); then
    actual="Allowed"
  elif echo "$out" | grep -q "bad address"; then
    actual="Blocked (name did not resolve)"
  else
    actual="Blocked (timed out / no route)"
  fi

  if [ "${actual%% *}" = "$expected" ]; then result="PASS"; else result="FAIL"; FAILS=$((FAILS+1)); fi
  TOTAL=$((TOTAL+1))
  printf "$FMT" "$from" "$host:$port" "$expected" "$actual" "$result"
}

#     from    to     port  expected
check proxy   api    5000  Allowed
check proxy   db     5432  Blocked
check proxy   cache  6379  Blocked
check proxy   $INET  443   Allowed

check api     db     5432  Allowed
check api     cache  6379  Allowed
check api     $INET  443   Allowed

check worker  api    5000  Allowed
check worker  db     5432  Allowed
check worker  cache  6379  Allowed
check worker  $INET  443   Blocked

check cache   api    5000  Allowed
check cache   db     5432  Allowed
check cache   $INET  443   Blocked

check db      api    5000  Allowed
check db      cache  6379  Allowed
check db      $INET  443   Blocked

check backup  api    5000  Blocked
check backup  db     5432  Allowed
check backup  cache  6379  Blocked
check backup  $INET  443   Blocked

echo
if [ "$FAILS" -eq 0 ]; then
  echo "All $TOTAL checks match the design."
else
  echo "$FAILS of $TOTAL checks do NOT match the design."
  exit 1
fi
