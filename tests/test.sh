#!/usr/bin/env bash
# Integration test: builds the add-on for the previous and current PostgreSQL
# major, checks a fresh install, then upgrades the same /data to the current
# major and checks the data survived.
set -euo pipefail
cd "$(dirname "$0")/.."

dockerfile=timescaledb/Dockerfile
image=$(sed -nE 's/^ARG PG_IMAGE=(.*)$/\1/p' "$dockerfile")
prev_image=$(sed -nE 's/^ARG PG_PREV_IMAGE=(.*)$/\1/p' "$dockerfile")
prev_major=${prev_image##*-pg}
prev_prev_image=${prev_image%-pg*}-pg$((prev_major - 1))

name=addon-test
data=$(mktemp -d)
dirs=("$data")
cleanup() {
    docker rm -f "$name" >/dev/null 2>&1 || true
    sudo rm -rf "${dirs[@]}" 2>/dev/null || rm -rf "${dirs[@]}"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; docker logs "$name" 2>&1 | tail -n 80 >&2 || true; exit 1; }

echo "== Building $prev_image and $image variants"
docker build -q -t "$name:prev" --build-arg PG_IMAGE="$prev_image" --build-arg PG_PREV_IMAGE="$prev_prev_image" timescaledb >/dev/null
docker build -q -t "$name:current" timescaledb >/dev/null

write_options() {
    cat >"$data/options.json" <<EOF
{
  "databases": [{ "name": "homeassistant", "owner": "homeassistant", "timescaledb": true }],
  "users": [{ "name": "homeassistant", "password": "$1" }],
  "external_access": ${2:-false},
  "pg_hba": [
    { "type": "local", "database": "all", "user": "postgres", "method": "trust" },
    { "type": "host", "database": "all", "user": "all", "address": "127.0.0.1/32", "method": "scram-sha-256" }
  ],
  "max_connections": 50,
  "tune": true,
  "memory": "256MB",
  "postgresql_config": ["work_mem = 8MB"],
  "telemetry": false
}
EOF
}

# Not `docker logs | grep -q`: grep exits early and pipefail reports SIGPIPE.
logged() { grep -qF "$1" <<<"$(docker logs "$name" 2>&1)"; }

start() {
    docker rm -f "$name" >/dev/null 2>&1 || true
    docker run -d --name "$name" -v "$data:/data" "$name:$1" >/dev/null
    for _ in $(seq 180); do
        logged 'Users and databases are up to date' && return
        [ "$(docker inspect -f '{{.State.Running}}' "$name")" = true ] || fail "container exited"
        sleep 1
    done
    fail "add-on did not become ready"
}

# psql over TCP as the application user, so scram auth and pg_hba are exercised.
pw=s3cret
q() { docker exec -e PGPASSWORD="$pw" "$name" psql -X -At -v ON_ERROR_STOP=1 -h 127.0.0.1 -U homeassistant -d homeassistant -c "$1"; }

stop() {
    local t0=$SECONDS
    docker stop -t 60 "$name" >/dev/null
    [ $((SECONDS - t0)) -lt 30 ] || fail "shutdown took $((SECONDS - t0))s"
}

echo "== Empty password is rejected"
write_options ""
docker run --rm -v "$data:/data" "$name:current" >/tmp/out.log 2>&1 && fail "started without a password"
grep -q 'Set a password for user(s): homeassistant' /tmp/out.log || { cat /tmp/out.log; fail "missing password error"; }

echo "== Fresh install on PostgreSQL $prev_major"
write_options s3cret
start prev
[ "$(q 'SHOW server_version_num' | cut -c1-2)" = "$prev_major" ] || fail "wrong server version"
q "CREATE TABLE m (t timestamptz NOT NULL, v double precision);
   SELECT create_hypertable('m', by_range('t'));
   INSERT INTO m SELECT g, random() FROM generate_series(now() - interval '10 days', now(), interval '1 minute') g;" >/dev/null
rows=$(q 'SELECT count(*) FROM m')
grep -qE '^host +all all 0\.0\.0\.0/0 reject$' "$data/pg_hba.conf" || fail "external access not rejected by default"
[ "$(q 'SHOW work_mem')" = 8MB ] || fail "postgresql_config not applied"
[ "$(q 'SHOW max_connections')" = 50 ] || fail "max_connections not applied"
stop

echo "== Upgrade to $image"
start current
current_major=$(q 'SHOW server_version_num' | cut -c1-2)
[ "$current_major" -gt "$prev_major" ] || fail "server was not upgraded"
[ "$(q 'SELECT count(*) FROM m')" = "$rows" ] || fail "row count changed"
[ "$(q "SELECT count(*) FROM timescaledb_information.hypertables WHERE hypertable_name = 'm'")" = 1 ] || fail "hypertable missing"
[ ! -e "$data/postgres.upgrade" ] || fail "upgrade dir left behind"
stop

echo "== Restart is idempotent and picks up new options"
write_options n3w-pass true
pw=n3w-pass
start current
docker exec -e PGPASSWORD=n3w-pass "$name" psql -X -At -h 127.0.0.1 -U homeassistant -d homeassistant -c 'SELECT 1' >/dev/null ||
    fail "password change not applied"
grep -qE '^host +all all 0\.0\.0\.0/0 scram-sha-256$' "$data/pg_hba.conf" || fail "external_access not applied"

echo "== Hot backup and restore"
docker exec "$name" addon-backup-pre
[ -f "$data/dump/manifest.tsv" ] || fail "no dump written"
# What a restored backup looks like: everything but the excluded cluster.
restored=$(mktemp -d)
dirs+=("$restored")
sudo cp -a "$data/." "$restored/"
sudo rm -rf "$restored/postgres"
docker exec "$name" addon-backup-post
[ ! -e "$data/dump" ] || fail "backup_post left the dump behind"
stop
data=$restored
start current
logged 'Restore finished' || fail "restore did not run"
[ "$(q 'SELECT count(*) FROM m')" = "$rows" ] || fail "row count changed after restore"
[ "$(q "SELECT count(*) FROM timescaledb_information.hypertables WHERE hypertable_name = 'm'")" = 1 ] || fail "hypertable missing after restore"
[ ! -e "$data/dump" ] || fail "dump left behind after restore"
stop

echo "PASS"
