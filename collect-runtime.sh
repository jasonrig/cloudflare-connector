#!/bin/sh
# Build-stage only: collect an explicit runtime and its transitive ELF libraries.
set -eu
root=/rootfs
mkdir -p "$root/usr/bin" "$root/usr/lib" "$root/etc/ssl/certs" \
    "$root/usr/share/dbus-1" "$root/etc/dbus-1" "$root/run/dbus" \
    "$root/var/lib/dbus" "$root/var/lib/cloudflare-warp" "$root/tmp" "$root/dev/net"
chmod 1777 "$root/tmp"
chmod 0700 "$root/var/lib/cloudflare-warp"
ln -s usr/lib "$root/lib"
ln -s usr/lib "$root/lib64"
ln -s usr/bin "$root/bin"
ln -s usr/bin "$root/sbin"
ln -s bin "$root/usr/sbin"
ln -s ../run "$root/var/run"

copy_elf() {
    source=$1
    destination=$2
    cp -L "$source" "$root$destination"
    dependencies=$(/usr/lib/ld-linux-x86-64.so.2 --list "$source")
    printf '%s\n' "$dependencies" \
        | awk '/=> \// { print $3 } /^[[:space:]]*\// { print $1 }' \
        | while IFS= read -r library; do
            cp -L "$library" "$root/usr/lib/$(basename "$library")"
        done
}

cp /entrypoint "$root/entrypoint"
for binary in warp-svc warp-cli dbus-daemon nft; do
    copy_elf "/usr/bin/$binary" "/usr/bin/$binary"
done
# NSS loads these crypto modules at runtime rather than via ELF DT_NEEDED.
for library in libsoftokn3.so libfreebl3.so libfreeblpriv3.so libnssckbi.so \
    libnss_dns.so.2 libnss_files.so.2; do
    copy_elf "/usr/lib/$library" "/usr/lib/$library"
done
cp /usr/lib/libsoftokn3.chk /usr/lib/libfreebl3.chk /usr/lib/libfreeblpriv3.chk "$root/usr/lib/"
cp /usr/lib/ld-linux-x86-64.so.2 "$root/usr/lib/"
cp /etc/ssl/certs/ca-certificates.crt "$root/etc/ssl/certs/"
cp /etc/protocols /etc/services "$root/etc/"
cp /usr/share/dbus-1/system.conf "$root/usr/share/dbus-1/"
cp /etc/dbus-1/system.conf "$root/etc/dbus-1/"
cp /init.nft "$root/init.nft"
awk -F: '$1 == "root" || $1 == "messagebus"' /etc/passwd > "$root/etc/passwd"
awk -F: '$1 == "root" || $1 == "messagebus"' /etc/group > "$root/etc/group"
printf 'passwd: files\ngroup: files\nhosts: files dns\n' > "$root/etc/nsswitch.conf"
# PVE supplies networking and resolv.conf. No os-release or password database is copied.
touch "$root/etc/resolv.conf" "$root/etc/hosts"
