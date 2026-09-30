# Shared helpers for the add-on scripts. Sourced, not executed.
# shellcheck shell=bash

OPTIONS=${ADDON_OPTIONS:-/data/options.json}
export PGDATA=${PGDATA:-/data/postgres}
CONF_DIR=/data/conf.d
HBA_FILE=/data/pg_hba.conf
SOCKET_DIR=/var/run/postgresql
PREV_DIR=/opt/pg-prev
ANALYZE_FLAG=/data/.analyze-after-upgrade
DUMP_DIR=/data/dump

log()  { echo "[$(date +%H:%M:%S)] INFO: $*"; }
warn() { echo "[$(date +%H:%M:%S)] WARNING: $*" >&2; }
die()  { echo "[$(date +%H:%M:%S)] FATAL: $*" >&2; exit 1; }

# opt <jq filter> — read from the add-on options.
opt() { jq -r "$1" "$OPTIONS"; }

as_pg() { su-exec postgres "$@"; }

# pg_major <bindir> — major version of the server binary in <bindir>.
pg_major() { "$1/postgres" -V | sed -E 's/^[^0-9]*([0-9]+).*/\1/'; }

# sql [psql args...] — run psql as the superuser over the local socket.
sql() { as_pg psql -X -q -v ON_ERROR_STOP=1 -h "$SOCKET_DIR" -U postgres "$@"; }

wait_ready() {
    local timeout=${1:-3600}
    until as_pg pg_isready -q -h "$SOCKET_DIR" -U postgres; do
        timeout=$((timeout - 1))
        [ "$timeout" -gt 0 ] || return 1
        sleep 1
    done
}

# Bring the timescaledb extension up to the version shipped in the image in
# every database that has it. ALTER EXTENSION must be the first command of
# the session, so each database gets a fresh psql.
update_timescaledb() {
    local db
    sql -d postgres -At -c "SELECT datname FROM pg_database WHERE datallowconn" |
        while IFS= read -r db; do
            if [ "$(sql -d "$db" -At -c "SELECT count(*) FROM pg_extension WHERE extname = 'timescaledb'")" = 1 ]; then
                sql -d "$db" -c 'ALTER EXTENSION timescaledb UPDATE'
            fi
        done
}
