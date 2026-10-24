#!/usr/bin/env bash
# Build an image archive locally. This script never contacts Proxmox or Cloudflare APIs.
set -euo pipefail

recipe_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
builder_name=${BUILDX_BUILDER:-cloudflare-connector-oci}
archive_path=${1:-"$recipe_dir/artifacts/cloudflare-connector-2026.10.3-amd64.oci.tar"}

command -v docker >/dev/null || { echo 'Docker with Buildx is required.' >&2; exit 1; }
docker info >/dev/null 2>&1 || {
    echo 'Start the Docker daemon, then run this script again.' >&2
    exit 1
}
docker buildx version >/dev/null

if [[ -e "$archive_path" ]]; then
    echo "Archive already exists; choose another output path: $archive_path" >&2
    exit 1
fi
mkdir -p -- "$(dirname -- "$archive_path")"

# The docker-container driver supports the OCI exporter. Reuse it on later builds.
if ! docker buildx inspect "$builder_name" >/dev/null 2>&1; then
    docker buildx create --name "$builder_name" --driver docker-container >/dev/null
fi

docker buildx build \
    --builder "$builder_name" \
    --platform linux/amd64 \
    --provenance=false \
    --sbom=false \
    --tag home/cloudflare-connector:2026.10.3 \
    --output "type=oci,dest=$archive_path" \
    "$recipe_dir"

(
    cd -- "$(dirname -- "$archive_path")"
    if command -v sha256sum >/dev/null; then
        sha256sum "$(basename -- "$archive_path")"
    else
        shasum -a 256 "$(basename -- "$archive_path")"
    fi
) > "$archive_path.sha256"
echo "Built OCI archive: $archive_path"
echo "Archive checksum: $archive_path.sha256"
