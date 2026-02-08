# Dockerfile for FHIRant Server
#
# Build context must be the parent monorepo directory (fhir/):
#   docker build -f fhirant/Dockerfile -t fhirant .
#
# This is required because fhirant has path dependencies on fhir_r4 packages.

FROM dart:stable AS build

WORKDIR /app

# Copy fhir_r4 packages (path dependencies)
COPY fhir_r4/packages/fhir_r4/ /app/fhir_r4/packages/fhir_r4/
COPY fhir_r4/packages/fhir_r4_path/ /app/fhir_r4/packages/fhir_r4_path/
COPY fhir_r4/packages/fhir_r4_mapping/ /app/fhir_r4/packages/fhir_r4_mapping/
COPY fhir_r4/packages/fhir_r4_validation/ /app/fhir_r4/packages/fhir_r4_validation/

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
FROM dart:stable

COPY --from=build /app/server /app/server
COPY --from=build /app/fhirant/packages/fhirant_server/lib/sqlcipher/linux/libsqlcipher.so /app/lib/libsqlcipher.so

EXPOSE 8080

# Set secrets at runtime via -e or docker-compose environment, not here.

CMD ["/app/server", "--port", "8080", "--db-path", "/data", "--sqlcipher-path", "/app/lib/libsqlcipher.so"]
