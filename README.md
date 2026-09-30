# Home Assistant add-on: TimescaleDB

PostgreSQL 18 + TimescaleDB 2.30 as a Home Assistant add-on, built on the
official `timescale/timescaledb` images.

[![Add repository to Home Assistant](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fglassp%2Fhaos-timeseries-db)

Or add `https://github.com/glassp/haos-timeseries-db` under
**Settings → Add-ons → Add-on store → ⋮ → Repositories**.

See [timescaledb/DOCS.md](timescaledb/DOCS.md) for configuration.

## Development

The add-on image is built by the Supervisor from `timescaledb/Dockerfile`.
`tests/test.sh` builds it for the previous and current PostgreSQL major and
tests a fresh install plus the in-place upgrade; CI runs it on amd64 and
aarch64.

### Bumping versions

1. Update both `ARG` image tags in `timescaledb/Dockerfile`. Keep them on the
   same TimescaleDB version: `pg_upgrade` needs it on both sides.
2. Bump `version` in `timescaledb/config.yaml` and add a `CHANGELOG.md` entry.
