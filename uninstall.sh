#!/bin/sh
# Removes luci-app-vsol-ddm installed by install.sh.
#   wget -qO /tmp/uninstall.sh https://raw.githubusercontent.com/JaGPR/luci-app-vsol-ddm/main/uninstall.sh && sh /tmp/uninstall.sh
# KEEP_CONFIG=1 keeps /etc/config/vsol_ddm (address and login) for a later reinstall.
#
# Licensed under the Apache License, Version 2.0. See LICENSE.

[ "$(id -u)" = "0" ] || { echo "run as root" >&2; exit 1; }

# If the upstream package is installed, let the package manager remove it so its
# database stays consistent.
if command -v apk >/dev/null 2>&1 && apk info -e luci-app-vsol-ddm >/dev/null 2>&1; then
	echo "luci-app-vsol-ddm is installed as a package; remove it with: apk del luci-app-vsol-ddm" >&2
	exit 1
fi
if command -v opkg >/dev/null 2>&1 && opkg list-installed 2>/dev/null | grep -q '^luci-app-vsol-ddm '; then
	echo "luci-app-vsol-ddm is installed as a package; remove it with: opkg remove luci-app-vsol-ddm" >&2
	exit 1
fi

/etc/init.d/vsol_ddm stop 2>/dev/null
/etc/init.d/vsol_ddm disable 2>/dev/null

rm -f  /usr/libexec/rpcd/vsol_ddm /etc/init.d/vsol_ddm \
       /usr/share/luci/menu.d/luci-app-vsol-ddm.json /usr/share/rpcd/acl.d/luci-app-vsol-ddm.json \
       /lib/upgrade/keep.d/luci-app-vsol-ddm /etc/uci-defaults/80_luci-app-vsol-ddm
rm -rf /usr/share/vsol_ddm /www/luci-static/resources/view/vsol_ddm
rm -f  /tmp/vsol_ddm_* /tmp/vsol_ddm.lock
[ "$KEEP_CONFIG" = "1" ] || rm -f /etc/config/vsol_ddm

rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache*
/etc/init.d/rpcd reload 2>/dev/null

echo "luci-app-vsol-ddm removed.$([ "$KEEP_CONFIG" = "1" ] && echo " Config kept in /etc/config/vsol_ddm.")"
