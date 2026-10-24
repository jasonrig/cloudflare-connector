# Cloudflare connector

A small `cloudflared` image for private-network access through Cloudflare Tunnel.
The runtime base and connector binary are pinned by checksum.

Build a Linux/amd64 OCI archive with Docker and Buildx:

```sh
bash build-oci.sh
```

Import the archive from `artifacts/` into an OCI-capable Proxmox installation.
Supply the tunnel token at runtime as `/run/secrets/cloudflared-token`, readable
by UID 65532. Keep credentials and network configuration outside the image
and repository.

Configure private routes, client enrollment and access policies in Cloudflare
Zero Trust. No services are published by the build script.
