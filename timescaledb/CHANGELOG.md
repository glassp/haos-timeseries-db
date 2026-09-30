# Changelog

## 1.0.0

- PostgreSQL 18 with TimescaleDB 2.30.2.
- Users, databases and pg_hba rules managed from the add-on options.
- `timescaledb-tune` on every start.
- In-place `pg_upgrade` from PostgreSQL 17.
- Hot backups via `pg_dump`, restored automatically on start.
- `external_access` toggle; Home Assistant and add-ons can always connect.
- Optional read-only DB explorer (DbGate) in the ingress panel.
