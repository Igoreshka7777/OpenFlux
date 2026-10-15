#!/bin/sh
# OpenFlux online installer for APK-based OpenWrt. Does not start the VPN.
set -eu
VERSION=0.1.2-r1
BASE="https://github.com/Igoreshka7777/OpenFlux/releases/download/openwrt-v$VERSION"
KEY_SHA256=aa1adf87b3da4b9a9811d707c6ecf3dbeefa367bc51456325c271a41df421ee3
die() { printf 'OpenFlux: %s\n' "$*" >&2; exit 1; }
mode=install
case "${1:-}" in
 --check) mode=check;;
 --download-only) mode=download;;
 --help) echo 'Usage: sh install.sh [--check | --download-only]'; exit 0;;
 '') ;;
 *) die 'Unknown argument. Use --help';;
esac
[ -f /etc/openwrt_release ] || die 'Requires OpenWrt (not Android or a desktop Linux distribution)'
command -v apk >/dev/null || die 'Requires APK-based OpenWrt 25.12+. Older opkg firmware is not supported.'
arch=$(head -n 1 /etc/apk/arch 2>/dev/null || apk --print-arch)
case "$arch" in
 aarch64_cortex-a53|aarch64_generic|x86_64|arm_cortex-a7_neon-vfpv4|mipsel_24kc) ;;
 *) die "No verified package for architecture: $arch";;
esac
ram=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
free_space=$(df -k /overlay | awk 'END {print $4}')
[ "$ram" -ge 120000 ] && [ "$free_space" -ge 30000 ] || die 'Requires 128 MB RAM and at least 30 MB free overlay'
command -v sha256sum >/dev/null || die 'sha256sum is required'
if command -v curl >/dev/null; then
 fetch() { curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 300 --retry 2 "$1" -o "$2"; }
elif command -v uclient-fetch >/dev/null; then
 fetch() { uclient-fetch -T 300 -O "$2" "$1"; }
else
 die 'Install curl and ca-bundle from your OpenWrt repositories first'
fi
echo "OpenFlux $VERSION; architecture: $arch"
[ "$mode" != check ] || { echo 'System requirements passed. No files or settings changed.'; exit 0; }
[ "$mode" != install ] || [ "$(id -u)" = 0 ] || die 'Run installation as root'
umask 077
tmp=$(mktemp -d /tmp/openflux-install.XXXXXX)
cleanup() { rm -f "$tmp/package.apk" "$tmp/openflux-router.pem" "$tmp/SHA256SUMS"; rmdir "$tmp" 2>/dev/null || true; }
trap cleanup EXIT HUP INT TERM
package="openflux-router-$VERSION-$arch.apk"
fetch "$BASE/$package" "$tmp/package.apk"
fetch "$BASE/openflux-router.pem" "$tmp/openflux-router.pem"
fetch "$BASE/SHA256SUMS" "$tmp/SHA256SUMS"
printf '%s  %s\n' "$KEY_SHA256" "$tmp/openflux-router.pem" | sha256sum -c - || die 'Unexpected signing key'
expected=$(awk -v file="$package" '$2 == file { print $1 }' "$tmp/SHA256SUMS")
[ "${#expected}" = 64 ] || die 'Release checksum missing or ambiguous'
case "$expected" in *[!0-9a-f]*) die 'Invalid checksum';; esac
printf '%s  %s\n' "$expected" "$tmp/package.apk" | sha256sum -c - || die 'Damaged package'
# Signature verification uses a temporary trusted-key directory, before changing the router.
apk --keys-dir "$tmp" verify "$tmp/package.apk"
if [ "$mode" = download ]; then
 trap - EXIT HUP INT TERM
 echo "Verified package saved in $tmp (no installation performed)."
 exit 0
fi
backup="/root/openflux-before-$(date +%Y%m%d-%H%M%S)-$$.tar.gz"
if [ -d /etc/openflux ]; then
 tar -czf "$backup" /etc/config /etc/openflux /etc/apk/world 2>/dev/null
else
 tar -czf "$backup" /etc/config /etc/apk/world 2>/dev/null
fi
mkdir -p /etc/apk/keys
if [ -e /etc/apk/keys/openflux-router.pem ]; then
 cmp -s "$tmp/openflux-router.pem" /etc/apk/keys/openflux-router.pem || die 'Installed signing key differs; stopped'
else
 cp "$tmp/openflux-router.pem" /etc/apk/keys/openflux-router.pem
 chmod 644 /etc/apk/keys/openflux-router.pem
fi
apk update
apk add --simulate dnsmasq-full ip-full "$tmp/package.apk"
apk add dnsmasq-full ip-full "$tmp/package.apk"
echo "OpenFlux installed. Backup: $backup"
echo 'Open http://192.168.1.1/cgi-bin/luci/admin/services/openflux (or your router address).'
echo 'Existing links/settings are preserved. VPN routes are not switched by this installer.'
