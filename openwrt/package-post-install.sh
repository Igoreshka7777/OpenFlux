#!/bin/sh
chmod 600 /etc/config/openflux
mkdir -p /etc/openflux
chmod 700 /etc/openflux
if [ ! -e /etc/openflux/direct-domains.txt ]; then
 uci -q get openflux.main.direct_domain | tr ' ' '\n' > /etc/openflux/direct-domains.txt
fi
chmod 600 /etc/openflux/direct-domains.txt
/etc/init.d/openflux enable
rm -f /tmp/luci-indexcache
rm -f /tmp/luci-indexcache.*.json
rm -rf /tmp/luci-modulecache
/etc/init.d/rpcd reload
exit 0
