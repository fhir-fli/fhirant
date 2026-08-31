# Dockerfile for FHIRant Server
#
#   cd /path/to/fhirant && docker build -t fhirant .
#
# The build context is this repository. It used to have to be the parent
# directory, because fhirant_server depended on cicada by a path that left the
# repo; cicada is a git dependency now, so `pub get` fetches it at the commit
# the lock file names and nothing outside this repo is copied in.

FROM dart:stable AS build

# The sqlite3 build hook compiles SQLite from the sqlite3mc source
# (SQLite3 Multiple Ciphers — SQLCipher-compatible encryption), which
# needs a C toolchain. git is needed to fetch the cicada dependency.
RUN apt-get update && apt-get install -y --no-install-recommends clang git && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY packages/fhirant_logging/ /app/packages/fhirant_logging/
COPY packages/fhirant_db/ /app/packages/fhirant_db/
COPY packages/fhirant_server/ /app/packages/fhirant_server/

RUN cd /app/packages/fhirant_server && dart pub get

# Compile to a native bundle (dart build cli runs the sqlite3mc build hook
# and places libsqlite3mc.so next to the executable; `dart compile exe`
# does not support build hooks)
RUN cd /app/packages/fhirant_server && \
    dart build cli -o /app/out

# --- Runtime stage ---
FROM dart:stable

# bundle/ contains bin/server plus lib/libsqlite3mc.so, which the
# executable resolves relative to itself
COPY --from=build /app/out/bundle/ /app/
COPY --from=build /app/packages/fhirant_server/assets/fhir_spec/ /app/fhir_spec/
COPY --from=build /app/packages/fhirant_server/assets/terminology_fixtures/ /app/terminology_fixtures/

EXPOSE 8080

CMD ["/app/bin/server", "--port", "8080", "--db-path", "/data"]
