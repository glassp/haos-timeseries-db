# TimescaleDB

PostgreSQL 18 with the TimescaleDB extension, for keeping Home Assistant
history (recorder, LTSS, Grafana, …) in a real time-series database.

## Getting started

1. Set a password for the `homeassistant` user in the **Configuration** tab.
2. Start the add-on and check the **Log** tab for
   `Users and databases are up to date`.
3. Look up the add-on's **Hostname** on its **Info** tab (something like
   `1a2b3c4d-timescaledb`) and point the recorder at it in
   `configuration.yaml`:

   ```yaml
   recorder:
     db_url: !secret recorder_db_url
   ```

   ```yaml
   # secrets.yaml
   recorder_db_url: postgresql://homeassistant:YOUR_PASSWORD@1a2b3c4d-timescaledb/homeassistant
   ```

## Configuration

```yaml
databases:
  - name: homeassistant
    owner: homeassistant
    timescaledb: true
users:
  - name: homeassistant
    password: change-me
pg_hba: []
max_connections: 100
tune: true
postgresql_config: []
telemetry: false
```

### `databases`

Databases to create. `owner` must be `postgres` or one of `users` (default
`postgres`). With `timescaledb: true` (the default) the extension is created
in that database. Removing a database here does **not** drop it.

### `users`

Login roles. Passwords are (re)applied on every start, so changing one here
and restarting changes it in the database. `superuser: true` makes the role a
superuser. Removing a user here does **not** drop the role.

### `pg_hba`

Extra client authentication rules, checked before the defaults. Each rule has
`type` (`local`, `host`, `hostssl`, `hostnossl`), `database`, `user`,
`method` and, for everything but `local`, an `address`:

```yaml
pg_hba:
  - type: host
    database: all
    user: all
    address: 192.168.1.0/24
    method: scram-sha-256
```

The generated file always ends with these defaults:

```
local all all trust                  # unix socket, only reachable inside the add-on
host  all all 0.0.0.0/0 scram-sha-256
host  all all ::/0      scram-sha-256
```

So password logins work from anywhere unless you add `reject` rules.
Home Assistant and other add-ons connect from the Supervisor network
(`172.30.32.0/23`), so keep that network allowed if you restrict access.

### `max_connections`, `tune`, `memory`, `cpus`

With `tune: true`, `timescaledb-tune` computes memory and worker settings on
every start. By default it assumes a quarter of the host's RAM and all CPUs,
because Home Assistant runs on the same machine. Override with `memory` (e.g.
`2GB`) and `cpus`.

### `postgresql_config`

Any PostgreSQL setting as `name = value`, applied after the tuning, e.g.:

```yaml
postgresql_config:
  - work_mem = 16MB
  - log_min_duration_statement = 1000
```

### `telemetry`

Send TimescaleDB's anonymous telemetry. Off by default.

## Access from outside Home Assistant

The PostgreSQL port is not published by default. Set a host port for
`5432/tcp` in the **Network** section to connect with psql, DBeaver or
Grafana running elsewhere.

## Backups

The add-on uses cold backups: Home Assistant stops the database for the
duration of a backup so the copied files are consistent. The recorder queues
events meanwhile.

For a logical dump, use the mapped `/share` folder, e.g. from the
*Advanced SSH & Web Terminal* add-on with protection mode off:

```sh
docker exec addon_<hostname-with-underscores> \
  pg_dump -U postgres -Fc -f /share/homeassistant.dump homeassistant
```

## PostgreSQL major upgrades

Each add-on version bundles the previous PostgreSQL major as well. When an
add-on update moves to a new major, the first start upgrades your data in
place with `pg_upgrade --link`, which is quick and needs almost no extra disk
space. Tick **Create backup** when updating the add-on, because a failed
upgrade can only be rolled back from a backup.

Skipping a major (e.g. 17 → 19) is not supported; update through the add-on
version in between.

## Migrating from another PostgreSQL / TimescaleDB add-on

Add-ons cannot see each other's data, so migrate with a dump:

1. With the old add-on running, dump the database to `/share`:
   `docker exec <old container> pg_dump -U postgres -Fc -f /share/ha.dump homeassistant`
2. Install and start this add-on (with the same database and user names).
3. Restore:

   ```sh
   docker exec addon_<this add-on> psql -U postgres -d homeassistant -c 'SELECT timescaledb_pre_restore()'
   docker exec addon_<this add-on> pg_restore -U postgres -d homeassistant --no-owner --role=homeassistant /share/ha.dump
   docker exec addon_<this add-on> psql -U postgres -d homeassistant -c 'SELECT timescaledb_post_restore()'
   ```

TimescaleDB requires the same extension version on both sides of a dump. If
the old add-on runs an older TimescaleDB, run `ALTER EXTENSION timescaledb
UPDATE` there first (if its image ships the newer version), or migrate only
the recorder data and let Home Assistant recreate its schema.
