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

RUN apt-get update && \
    apt-get install -y --no-install-recommends libsqlcipher0 && \
    rm -rf /var/lib/apt/lists/*

COPY --from=build /app/server /app/server

EXPOSE 8080

ENV FHIRANT_ENCRYPTION_KEY=change-me-in-production
ENV FHIRANT_JWT_SECRET=change-me-in-production

CMD ["/app/server", "--port", "8080", "--db-path", "/data", "--sqlcipher-path", "/usr/lib/x86_64-linux-gnu/libsqlcipher.so.0"]
