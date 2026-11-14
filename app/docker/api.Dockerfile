# syntax=docker/dockerfile:1
# Build context: ./app  (docker build -f app/docker/api.Dockerfile app)

FROM golang:1.23-alpine AS build
WORKDIR /src

# Dependencies first, so this layer is reused while only the source changes.
COPY api/go.mod api/go.sum ./
RUN go mod download

COPY api/*.go ./

# CGO disabled => fully static binary, no libc needed in the final image.
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/api .

# The API only speaks plain HTTP and talks to Postgres inside the cluster, so it needs
# neither CA certificates nor timezone data: an empty image is enough.
FROM scratch
COPY --from=build /out/api /api

# Unprivileged numeric user (scratch has no /etc/passwd).
USER 65534:65534
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["/api"]
