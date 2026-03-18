# Dockerfile for FHIRant Server
#
# Build context must be the parent monorepo directory (fhir/):
#   cd /path/to/fhir && docker build -f fhirant/Dockerfile -t fhirant .
#
# This is required because fhirant has path dependencies on sibling packages.

FROM dart:stable AS build

WORKDIR /app

# Copy fhir_r4 packages (path dependencies)
COPY fhir_r4/packages/fhir_r4/ /app/fhir_r4/packages/fhir_r4/
COPY fhir_r4/packages/fhir_r4_path/ /app/fhir_r4/packages/fhir_r4_path/
COPY fhir_r4/packages/fhir_r4_mapping/ /app/fhir_r4/packages/fhir_r4_mapping/
COPY fhir_r4/packages/fhir_r4_validation/ /app/fhir_r4/packages/fhir_r4_validation/
COPY fhir_r4/packages/fhir_r4_cql/ /app/fhir_r4/packages/fhir_r4_cql/
COPY fhir_r4/packages/fhir_r4_db/ /app/fhir_r4/packages/fhir_r4_db/

# Copy cicada (immunization forecasting dependency)
COPY cicada/cicada/ /app/cicada/cicada/

# Copy fhirant packages
COPY fhirant/packages/fhirant_logging/ /app/fhirant/packages/fhirant_logging/
COPY fhirant/packages/fhirant_db/ /app/fhirant/packages/fhirant_db/
COPY fhirant/packages/fhirant_server/ /app/fhirant/packages/fhirant_server/

# Resolve dependencies
RUN cd /app/fhirant/packages/fhirant_server && dart pub get

# Compile to native executable
RUN cd /app/fhirant/packages/fhirant_server && \
    dart compile exe bin/server.dart -o /app/server

# --- Runtime stage ---
# Must match the glibc version that libsqlcipher.so was compiled against.
# dart:stable is based on Debian with a recent glibc.
FROM dart:stable

COPY --from=build /app/server /app/server
COPY --from=build /app/fhirant/packages/fhirant_server/lib/sqlcipher/linux/libsqlcipher.so /app/lib/libsqlcipher.so
COPY --from=build /app/fhirant/packages/fhirant_server/assets/fhir_spec/ /app/fhir_spec/
COPY --from=build /app/fhirant/packages/fhirant_server/assets/terminology_fixtures/ /app/terminology_fixtures/

# Ensure the dynamic linker can find libsqlcipher
ENV LD_LIBRARY_PATH=/app/lib

EXPOSE 8080

CMD ["/app/server", "--port", "8080", "--db-path", "/data", "--sqlcipher-path", "/app/lib/libsqlcipher.so"]
