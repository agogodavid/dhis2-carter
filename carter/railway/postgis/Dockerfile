# PostGIS 16 for DHIS2 on Railway, with first-boot demo DB load + hardening.

# Stage 1: fetch the demo dump at build time (the PostGIS image has no working
# downloader, and its Debian bullseye apt mirrors are unreliable).
# Railway passes the service variable DHIS2_DB_DUMP_URL as this build arg; empty = blank DB.
FROM curlimages/curl:8.11.1 AS dump
ARG DHIS2_DB_DUMP_URL=""
USER root
RUN mkdir -p /out && if [ -n "$DHIS2_DB_DUMP_URL" ]; then \
      curl -fsSL --retry 3 -o /out/40-dhis2-dump.sql.gz "$DHIS2_DB_DUMP_URL"; \
    fi

FROM postgis/postgis:16-3.5
# Railway volumes contain lost+found at the mount root; keep PGDATA in a subdirectory.
ENV PGDATA=/var/lib/postgresql/data/dhis2
# The postgres entrypoint loads *.sql.gz natively (40-…), then runs our hardening (50-…).
COPY --from=dump /out/ /docker-entrypoint-initdb.d/
COPY 50-dhis2-init.sh /docker-entrypoint-initdb.d/50-dhis2-init.sh
RUN chmod 755 /docker-entrypoint-initdb.d/50-dhis2-init.sh
CMD ["postgres", "-c", "max_locks_per_transaction=128", "-c", "shared_buffers=512MB", "-c", "jit=off"]
