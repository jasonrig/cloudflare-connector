# syntax=docker/dockerfile:1.7
# Linux/amd64 connector image. Build with build-oci.sh.
# Distroless runtime base pinned by digest.
FROM gcr.io/distroless/base-debian13:nonroot@sha256:7e22204ffcba783587afba539fcc199cc8c91a7583b66299ac4dccdb5fed5f03

# Immutable release URL and the SHA256 published by Cloudflare for this binary.
ADD --checksum=sha256:1f99fb518b83dec2ba8d870a7cc991d82a77e6196295a3d2754ba17ab9f91872 --chmod=0555 \
    https://github.com/cloudflare/cloudflared/releases/download/2026.10.7/cloudflared-linux-amd64 \
    /usr/local/bin/cloudflared

LABEL org.opencontainers.image.title="Cloudflare connector" \
      org.opencontainers.image.version="2026.10.7-r1" \
      org.opencontainers.image.description="Private-network connector; tunnel credentials supplied at runtime"

USER 65532:65532
WORKDIR /
ENTRYPOINT ["/usr/local/bin/cloudflared", "--no-autoupdate"]
CMD ["tunnel", "--protocol", "quic", "--metrics", "127.0.0.1:2000", "run"]
