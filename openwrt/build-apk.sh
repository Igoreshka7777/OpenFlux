#!/bin/sh
# Run in the pinned official Alpine tools container with /build mounted.
set -eu
cd /build
mkdir -p output keys public
[ -s keys/openflux-router.pem ] || { echo 'Signing key is required'; exit 1; }
openssl pkey -in keys/openflux-router.pem -pubout -out public/openflux-router.pem
cmp public/openflux-router.pem openflux-router.pem || { echo "Signing key mismatch"; exit 1; }
for pair in aarch64_cortex-a53:arm64 aarch64_generic:arm64 x86_64:amd64 arm_cortex-a7_neon-vfpv4:arm mipsel_24kc:mipsle; do
 arch=${pair%:*}; goarch=${pair#*:}
 [ -f "dist/openflux-client-$goarch" ] || continue
 root="stage-$arch"
 mkdir -p "$root"
 cp -a files/. "$root/"
 cp "$root/www/luci-static/resources/view/openflux/main.js" "$root/www/luci-static/resources/view/openflux/main-v6.js"
 mkdir -p "$root/usr/bin" "$root/lib/apk/packages" "$root/lib/upgrade/keep.d" "$root/usr/share/licenses/openflux-router"
 cp "dist/openflux-client-$goarch" "$root/usr/bin/openflux-client"
 cp NOTICE.txt "$root/usr/share/licenses/openflux-router/NOTICE"
 cp COPYING "$root/usr/share/licenses/openflux-router/COPYING"
 find "$root" -type d -exec chmod 755 {} \;
 find "$root" -type f -exec chmod 644 {} \;
 chmod 755 "$root/usr/bin/openflux-client" "$root/etc/init.d/openflux" "$root/usr/libexec/openflux-network"
 chmod 600 "$root/etc/config/openflux"
 printf '/etc/config/openflux\n/etc/openflux/\n' > "$root/lib/upgrade/keep.d/openflux"
 printf '/etc/config/openflux\n' > "$root/lib/apk/packages/openflux-router.conffiles"
 (cd "$root" && sha256sum etc/config/openflux | sed 's|  etc/|  /etc/|') > "$root/lib/apk/packages/openflux-router.conffiles_static"
 apk mkpkg --compat 3.0.0 --sign-key keys/openflux-router.pem \
  --info 'name:openflux-router' --info 'version:0.1.2-r2' \
  --info "arch:$arch" --info 'license:GPL-3.0-only AND MIT' --info 'origin:openflux-router' \
  --info 'description:OpenFlux VPN client and LuCI control for OpenWrt' \
  --info 'url:https://openfluxvpn.ru/' --info 'maintainer:OpenFlux' \
  --info 'depends:kmod-tun ip-full nftables-json dnsmasq-full luci-base rpcd-mod-file ca-bundle' \
  --script post-install:package-post-install.sh \
  --script post-upgrade:package-post-install.sh \
  --script pre-deinstall:package-pre-deinstall.sh \
  --files "$root" --output "output/openflux-router-0.1.2-r2-$arch.apk"
 apk --keys-dir /build/public verify "output/openflux-router-0.1.2-r2-$arch.apk"
done
cp public/openflux-router.pem output/
cp install.sh output/
cp README.md output/
(cd output && sha256sum *.apk openflux-router.pem > SHA256SUMS)
