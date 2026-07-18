# Dockerfile for FHIRant Server
#
# Build context must be the parent monorepo directory (fhir/):
#   cd /path/to/fhir && docker build -f fhirant/Dockerfile -t fhirant .
#
# This is required because fhirant_server has a path dependency on cicada
# (unpublished). The fhir_r4 family resolves from pub.dev.

FROM dart:stable AS build

# The sqlite3 build hook compiles SQLite from the sqlite3mc source
# (SQLite3 Multiple Ciphers — SQLCipher-compatible encryption), which
# needs a C toolchain.
RUN apt-get update && apt-get install -y --no-install-recommends clang && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy cicada (immunization forecasting dependency — unpublished path dep)
COPY cicada/cicada/ /app/cicada/cicada/

# Copy fhirant packages
COPY fhirant/packages/fhirant_logging/ /app/fhirant/packages/fhirant_logging/
COPY fhirant/packages/fhirant_db/ /app/fhirant/packages/fhirant_db/
COPY fhirant/packages/fhirant_server/ /app/fhirant/packages/fhirant_server/

# Resolve dependencies
RUN cd /app/fhirant/packages/fhirant_server && dart pub get

# Compile to a native bundle (dart build cli runs the sqlite3mc build hook
# and places libsqlite3mc.so next to the executable; `dart compile exe`
# does not support build hooks)
RUN cd /app/fhirant/packages/fhirant_server && \
    dart build cli -o /app/out

# --- Runtime stage ---
FROM dart:stable

# bundle/ contains bin/server plus lib/libsqlite3mc.so, which the
# executable resolves relative to itself
COPY --from=build /app/out/bundle/ /app/
COPY --from=build /app/fhirant/packages/fhirant_server/assets/fhir_spec/ /app/fhir_spec/
COPY --from=build /app/fhirant/packages/fhirant_server/assets/terminology_fixtures/ /app/terminology_fixtures/

EXPOSE 8080

CMD ["/app/bin/server", "--port", "8080", "--db-path", "/data"]
