# syntax=docker/dockerfile:1.7
# Build tools and the vendor's distribution are never included in the final image.
FROM --platform=$BUILDPLATFORM golang:1.27.2-alpine@sha256:f92b6ef800e499660581efdabdf25d9d817a9d124eaf900924f0504e7e27e12d AS launcher
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src
COPY mesh-init.go .
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -ldflags='-s -w -buildid=' -o /mesh-init mesh-init.go

# Official Linux/amd64 Cloudflare One Client 2026.8.2115.0, resolved 2026-10-29.
FROM cloudflare/mesh@sha256:1c135f07ddac619562f45da5816b25d3ac7663a491c2a065bd83c005007dec5e AS vendor
COPY collect-runtime.sh /collect-runtime.sh
RUN /bin/sh /collect-runtime.sh

# No shell, package manager, login utilities, systemd, or distribution rootfs.
FROM scratch
COPY --from=vendor /rootfs/ /
COPY --from=launcher --chmod=0555 /mesh-init /mesh-init

LABEL org.opencontainers.image.title="Cloudflare Mesh gateway" \
      org.opencontainers.image.version="2026.8.2115.0-r4" \
      org.opencontainers.image.description="Distroless dual-stack Mesh gateway; MESH_NODE_TOKEN supplied at runtime"

# Preserve source addresses for bidirectional and future site-to-site routing.
# The subnet router must provide return routes through this node.
ENV SRCNAT_ENABLED=false \
    PATH=/usr/bin \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# Root in the container's unprivileged user namespace is required for routing.
USER 0:0
WORKDIR /
ENTRYPOINT ["/mesh-init"]
