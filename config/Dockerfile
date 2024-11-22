# Use a Golang base image to build your custom PocketBase
FROM golang:1.21-alpine AS builder

# Set the working directory inside the container
WORKDIR /app

# Copy the Go modules manifests and download the dependencies
COPY go.mod go.sum ./
RUN go mod download

# Copy the rest of your PocketBase source code
COPY src/ .

# Build the custom PocketBase binary
RUN CGO_ENABLED=0 go build -o pocketfhir

# Use a minimal base image to package the custom PocketBase binary
FROM alpine:latest

# Set the working directory inside the container
WORKDIR /app

# Install necessary packages
RUN apk add --no-cache unzip openssh

# Copy the built binary from the builder stage
COPY --from=builder /app/pocketfhir /app/

# Set environment variables for directories (not secrets)
ENV PB_DATA_DIR /app/pb_data
ENV PB_PUBLIC_DIR /app/pb_public
ENV PB_HOOKS_DIR /app/pb_hooks

# Expose the necessary port
EXPOSE 8090

# Start the PocketBase server
CMD ["/app/pocketfhir", "serve", "--http=0.0.0.0:8090"]
