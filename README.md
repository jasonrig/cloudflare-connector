# Cloudflare connector

A small `cloudflared` image for private-network access through Cloudflare Tunnel.
The runtime base and connector binary are pinned by checksum.

Build a Linux/amd64 OCI archive with Docker and Buildx:

```sh
bash build-oci.sh
```

Import the archive from `artifacts/` into an OCI-capable Proxmox installation.
Set the `TUNNEL_TOKEN` environment variable in the container's runtime settings
(in Proxmox: **Options → Environment**). No secret mount is required.
Keep credentials and network configuration outside the image and repository.

Configure private routes, client enrollment and access policies in Cloudflare
Zero Trust. No services are published by the build script.
