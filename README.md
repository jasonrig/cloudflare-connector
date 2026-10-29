# Cloudflare Mesh gateway

A distroless dual-stack subnet router using the Cloudflare One Client
(`warp-svc` / `warp-cli`), version `2026.8.2115.0`. The final image is built
`FROM scratch`. It contains the vendor's native supervisor, the two Mesh
binaries, D-Bus and nft helpers, their required shared libraries, CA certificates,
and a small static launcher. It has no shell, login utilities, package manager,
systemd, or distribution root filesystem. Vendor and compiler stages are pinned
by digest. Build-stage tools never enter the final image.

```sh
bash build-oci.sh
```

The script produces an OCI archive and SHA-256 file in `artifacts/`. Verify
the checksum from that directory. Import the archive into OCI-capable Proxmox.
To validate the runtime locally without enrolling a node:

```sh
docker buildx build --platform linux/amd64 --provenance=false --sbom=false \
  --load --tag home/cloudflare-mesh:2026.8.2115.0-r4 .
bash verify-image.sh
```

The image needs root **inside an unprivileged container**, `NET_ADMIN`,
`NET_RAW`, `/dev/net/tun`, and a writable `/var/lib/cloudflare-warp` that persists
across restarts. The vendor entrypoint reads `MESH_NODE_TOKEN` from the runtime
environment to enroll the node and accepts the Cloudflare One Client terms.
Set it under **Options → Environment** in Proxmox; no credential is built
into the image, supplied as a build argument, or stored in this repository.
Copy the actual enrollment command with Cloudflare's **Copy command** button
and use its token; the visibly masked command is not a valid credential.
No guest login password is used. Keep registration state outside Git.

Cloudflare documents a minimum of 3 CPUs and 1 GiB RAM for Mesh. Size and
validate the gateway against the intended workload. Distroless packaging removes
unneeded filesystem contents; it does not eliminate the client's runtime memory
requirement.

`SRCNAT_ENABLED=false` preserves source addresses for bidirectional/site-to-site
routing. Routers must send responses through the Mesh gateway. Do not enable
blanket masquerading to hide a missing return route.

## Deployment configuration

Choose and record these site-specific values before deployment. They are
configuration placeholders, not ranges advertised by this image.

| Setting | Deployment value |
| --- | --- |
| Gateway container ID and resource allocation | Retain the existing gateway policy |
| Bridge, VLAN, and MAC | Retain the existing network identity |
| Gateway IPv4 | `GATEWAY_IPV4`, with a DHCP reservation for that MAC |
| Gateway IPv6 | Stable `GATEWAY_IPV6` reachable from the LAN router |
| Local IPv4 advertisement | `LOCAL_IPV4_CIDR` |
| Local IPv6 advertisement | `LOCAL_IPV6_CIDR` |
| Mesh device IPv4 pool | `100.96.0.0/12` |
| Mesh device IPv6 pool | `2606:4700:cf1:1000::/64` |

Persist forwarding in the container's network namespace:

```text
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1
net.ipv6.conf.all.accept_ra=2
net.ipv6.conf.default.accept_ra=2
net.ipv6.conf.eth0.accept_ra=2
```

The static `/mesh-init` launcher applies these on every boot by writing only
the container's namespaced `/proc/sys/net` settings, then executes Cloudflare's
native `/entrypoint` supervisor. It never invokes a shell or modifies host
sysctls. Configure `/dev/net/tun` through Proxmox's **Device Passthrough** GUI.
Retain the unprivileged UID map and normal AppArmor confinement. Do not use a
privileged container or disable AppArmor.

Perform infrastructure configuration in the Proxmox, Cloudflare, and EdgeRouter
GUIs. OCI creation extracts the image into a root disk; there is no live image
reference to replace. Recreate the gateway under its existing ID when changing
the root filesystem, retaining its resources and reserved MAC. Proxmox's generic
creation wizard requires a password field even for this image; the unmanaged
guest handler skips password setup.

## Cloudflare and return paths

Create a Mesh node and select a MASQUE, Traffic and DNS device profile.
Use a dedicated Include-mode profile for nodes, matching
`warp_connector@<TEAM_NAME>.cloudflareaccess.com`. Route the Mesh pool,
the advertised local site CIDRs, and later the remote site CIDRs through
Cloudflare. Check local subnet delivery after adding the profile to prevent
routing loops.

On client profiles, both local site prefixes must route through Cloudflare.
The default `100.64.0.0/10` exclusion covers the Mesh pool: replace it with `100.64.0.0/11`
and `100.112.0.0/12` to make only `100.96.0.0/12` eligible for Mesh routing.
Verify unique device IPs, enrolled-device reachability, and TCP/UDP proxying.
Enable ICMP only when needed for diagnostics. Keep existing identity policies.

The LAN router needs `100.96.0.0/12` via `GATEWAY_IPV4` and
`2606:4700:cf1:1000::/64` via `GATEWAY_IPV6`. Do not assume IPv4 return
routing also covers IPv6. Future remote subnet routes also point to the local
gateway. Scope host firewall rules to the intended peers and services.

Cutover sequence:

1. Back up the gateway and save its runtime configuration securely outside Git.
2. Stage and validate the new root filesystem without registering a second
   production node or changing existing advertisements.
3. Configure the Mesh profile and return routes, then enroll the replacement.
4. Move the existing local IPv4 and IPv6 CIDRs to the Mesh node and test IPv4
   and IPv6 TCP/UDP from an enrolled client. Confirm the packets use Mesh and
   preserve source IPs.
5. Verify reboot persistence. Remove the old Cloudflare Tunnel resource only
   after tests pass; remove its token and daemon from the active container.
6. Remove temporary staging resources. Retain a clearly identified rollback
   backup until it is no longer needed.

## Future GCP site

Choose non-overlapping VPC ranges before creating routes. Avoid the local
site CIDRs, Mesh/device pools, and Cloudflare reserved ranges. Leave unknown
subnets unadvertised; do not guess a broad `10.0.0.0/8` route.

Deploy one dedicated Linux Mesh gateway VM with `canIpForward=true`, guest IPv4
and IPv6 forwarding, a persistent identity, and a static internal IPv4 address.
Use a dual-stack NIC when IPv6 is required. The rest of the VPC workloads need
no Mesh agent.

| Location | Destination | Next hop / action |
| --- | --- | --- |
| Cloudflare | Every chosen GCP subnet CIDR | GCP Mesh node |
| Cloudflare | Local site IPv4 and IPv6 prefixes | Local Mesh node |
| EdgeRouter | Chosen GCP IPv4/IPv6 CIDRs | Local gateway address of the same family |
| GCP VPC custom static routes | Local site IPv4 prefix and Mesh IPv4 pool | GCP gateway instance |
| GCP VPC custom static routes | Local site IPv6 prefix and device IPv6 pool | Dual-stack GCP gateway instance |
| Each node's split-tunnel profile | Remote site prefixes and Mesh pools | Include through Cloudflare |
| User device profiles | GCP subnet CIDRs | Include through Cloudflare |

For VPC-wide access, create untagged custom routes that apply to all workload VMs.
Use the gateway instance name/zone (or a valid primary NIC address) as next hop.
Allow forwarding and application traffic in VPC and guest firewalls for the
approved source ranges. Give the gateway outbound access to Cloudflare's client
endpoints. An external address or Cloud NAT may be needed for that egress.
Do not replace VPC subnet routes or its default Internet route.

Test both directions with a workload that has no agent installed, including
IPv6, reboot recovery, PMTU, and DNS. Add HA gateways only with an explicit
failover design for both Cloudflare advertisements and cloud/router next hops.

## References

- [Mesh container runtime](https://developers.cloudflare.com/mesh/guides/run-mesh-in-containers/)
- [Mesh routes and return paths](https://developers.cloudflare.com/mesh/features/routes/)
- [Required account settings](https://developers.cloudflare.com/mesh/get-started/#required-account-settings)
- [Cloud VPC guidance](https://developers.cloudflare.com/mesh/best-practices/#cloud-vpc-deployments)
- [GCP custom routes and IP forwarding](https://docs.cloud.google.com/vpc/docs/using-routes)
