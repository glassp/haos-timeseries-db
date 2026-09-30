# Current and previous PostgreSQL major, same TimescaleDB version in both.
# The previous major's binaries are bundled so the add-on can pg_upgrade
# existing data when the major version is bumped.
ARG PG_IMAGE=timescale/timescaledb:2.30.2-pg18
ARG PG_PREV_IMAGE=timescale/timescaledb:2.30.2-pg17

FROM ${PG_PREV_IMAGE} AS prev
# PostgreSQL binaries are relocatable as long as bin/, lib/postgresql and
# share/postgresql keep their relative layout.
RUN set -eux; \
    mkdir -p /out/lib /out/share; \
    cp -a /usr/local/bin /out/bin; \
    cp -a /usr/local/lib/postgresql /out/lib/; \
    cp -a /usr/local/share/postgresql /out/share/; \
    pg_config --version | sed -E 's/^PostgreSQL ([0-9]+).*/\1/' > /out/PG_MAJOR

FROM ${PG_IMAGE}

RUN apk add --no-cache jq su-exec

COPY --from=prev /out /opt/pg-prev
# Fail the build if the bundled old server cannot run on this base image.
RUN /opt/pg-prev/bin/postgres -V && /opt/pg-prev/bin/pg_ctl -V

COPY rootfs /
RUN chmod +x /usr/local/bin/addon-*

ENV PGDATA=/data/postgres
# SIGINT = fast shutdown; SIGTERM would wait for clients like the recorder.
STOPSIGNAL SIGINT
ENTRYPOINT ["/usr/local/bin/addon-run"]
CMD []

ARG BUILD_ARCH
ARG BUILD_VERSION
LABEL \
    io.hass.type="addon" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.version="${BUILD_VERSION}" \
    org.opencontainers.image.source="https://github.com/glassp/haos-timeseries-db"
