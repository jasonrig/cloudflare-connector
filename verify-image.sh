#!/usr/bin/env bash
# Validate the distroless runtime contract without enrolling any Mesh node.
set -euo pipefail

image_tag=${1:-home/cloudflare-mesh:2026.8.2115.0-r4}
fixture_name="cloudflare-mesh-verify-$$"
scratch_dir=$(mktemp -d)
cleanup() {
    docker rm -f "$fixture_name" >/dev/null 2>&1 || true
    rm -rf -- "$scratch_dir"
}
trap cleanup EXIT

image_env=$(docker image inspect "$image_tag" --format '{{json .Config.Env}}')
if [[ "$image_env" == *MESH_NODE_TOKEN=* || "$image_env" == *TUNNEL_TOKEN=* ]]; then
    echo 'FAIL: credentials must not be defined in the image environment.' >&2
    exit 1
fi
[[ "$image_env" == *SRCNAT_ENABLED=false* ]] || {
    echo 'FAIL: source NAT must be disabled by default.' >&2
    exit 1
}

docker run --rm --platform linux/amd64 --entrypoint /usr/bin/warp-cli "$image_tag" --version
docker run --rm --platform linux/amd64 --entrypoint /usr/sbin/nft "$image_tag" --version

# A monitor keeps only this disposable network namespace alive. No host network
# mode, published ports, credentials, or Cloudflare enrollment are involved.
docker run -d --name "$fixture_name" --platform linux/amd64 \
    --cap-add NET_ADMIN --entrypoint /usr/sbin/nft "$image_tag" monitor >/dev/null
docker export "$fixture_name" | tar -tf - > "$scratch_dir/files"
if grep -Eq '^(\./)?((usr/)?(s?bin)/(sh|ash|bash|dash|ksh|zsh|busybox|python[0-9.]*|perl|ruby|apk|apt|apt-get|dpkg|login|passwd|su|getty)|etc/(os-release|shadow)|usr/lib/os-release|usr/local/bin/cloudflared)$' "$scratch_dir/files"; then
    echo 'FAIL: shell, distribution, login, package, or Tunnel runtime content found.' >&2
    exit 1
fi

docker exec -i "$fixture_name" /usr/sbin/nft -f - <<'NFT'
add table inet mesh_verify
add chain inet mesh_verify forward { type filter hook forward priority filter; policy accept; }
add rule inet mesh_verify forward meta l4proto tcp counter accept
add rule inet mesh_verify forward meta l4proto udp counter accept
add rule inet mesh_verify forward meta l4proto ipv6-icmp counter accept
NFT
docker exec "$fixture_name" /usr/sbin/nft list table inet mesh_verify > "$scratch_dir/rules"
for protocol in tcp udp ipv6-icmp; do
    grep -Fq "meta l4proto $protocol counter" "$scratch_dir/rules"
done
echo 'PASS: distroless contents, runtime-only credentials, ELF helpers, and dual-stack firewall rules.'
