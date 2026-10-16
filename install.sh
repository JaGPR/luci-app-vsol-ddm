#!/bin/sh
# luci-app-vsol-ddm installer for OpenWrt (no SDK, no package signing needed).
# Installs this fork straight from GitHub:
#
#   wget -qO /tmp/install.sh https://raw.githubusercontent.com/JaGPR/luci-app-vsol-ddm/main/install.sh && sh /tmp/install.sh
#
# Environment overrides:
#   REPO=user/luci-app-vsol-ddm   GitHub repository to install from
#   BRANCH=main                   branch or tag
#   TARBALL=/tmp/x.tar.gz         install from a local archive instead of GitHub
#   DRY_RUN=1                     print every step, change nothing
#
# Licensed under the Apache License, Version 2.0. See LICENSE.

set -e

REPO="${REPO:-JaGPR/luci-app-vsol-ddm}"
BRANCH="${BRANCH:-main}"
WORK="/tmp/vsol-ddm-install.$$"

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mNOTE:\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; rm -rf "$WORK"; exit 1; }
run()  { if [ "$DRY_RUN" = "1" ]; then echo "    [dry-run] $*"; else eval "$@"; fi; }

[ "$(id -u)" = "0" ] || die "run this as root on the OpenWrt router"
[ -f /etc/openwrt_release ] || die "this does not look like OpenWrt (/etc/openwrt_release missing)"
command -v uci >/dev/null    || die "uci not found"
command -v nc >/dev/null     || die "BusyBox nc is required (it talks telnet to the ONT)"
[ -d /www/luci-static ]      || die "LuCI is not installed (install luci first)"

# Every telnet session is bounded with `timeout ... nc`. Stock OpenWrt BusyBox has
# no timeout applet, so the coreutils one is required.
if ! command -v timeout >/dev/null 2>&1; then
	say "Installing required dependency: coreutils-timeout"
	if command -v apk >/dev/null 2>&1; then
		run "apk update >/dev/null && apk add coreutils-timeout" || die "could not install coreutils-timeout (run: apk add coreutils-timeout)"
	elif command -v opkg >/dev/null 2>&1; then
		run "opkg update >/dev/null && opkg install coreutils-timeout" || die "could not install coreutils-timeout (run: opkg update && opkg install coreutils-timeout)"
	else
		die "no package manager found; install coreutils-timeout manually"
	fi
	[ "$DRY_RUN" = "1" ] || command -v timeout >/dev/null 2>&1 || die "timeout is still missing after installing coreutils-timeout"
fi

# The upstream .apk/.ipk may already be installed. Its files are overwritten here,
# but a later package upgrade would put the upstream versions back.
PKG_INSTALLED=0
if command -v apk >/dev/null 2>&1 && apk info -e luci-app-vsol-ddm >/dev/null 2>&1; then
	PKG_INSTALLED=1
elif command -v opkg >/dev/null 2>&1 && opkg list-installed 2>/dev/null | grep -q '^luci-app-vsol-ddm '; then
	PKG_INSTALLED=1
fi

mkdir -p "$WORK"

# 1. Fetch the source
if [ -n "$TARBALL" ]; then
	say "Using local archive $TARBALL"
	cp "$TARBALL" "$WORK/src.tar.gz" || die "cannot read $TARBALL"
else
	URL="https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH"
	say "Downloading $REPO ($BRANCH)"
	wget -qO "$WORK/src.tar.gz" "$URL" || die "download failed: $URL (is HTTPS support installed? try: apk add ca-bundle / opkg install ca-bundle)"
fi
tar -xzf "$WORK/src.tar.gz" -C "$WORK" || die "archive is not a valid .tar.gz"
SRC="$(find "$WORK" -maxdepth 2 -type f -name Makefile -path '*vsol-ddm*' | head -1 | xargs dirname 2>/dev/null)"
[ -n "$SRC" ] && [ -f "$SRC/root/usr/libexec/rpcd/vsol_ddm" ] || die "archive does not contain luci-app-vsol-ddm"

# 2. Install files (config is only created if it does not exist yet)
say "Installing files"
run "/etc/init.d/vsol_ddm stop 2>/dev/null || true"
run "mkdir -p /usr/libexec/rpcd /usr/share/vsol_ddm /www/luci-static/resources/view/vsol_ddm /etc/init.d /etc/config /usr/share/luci/menu.d /usr/share/rpcd/acl.d /lib/upgrade/keep.d"
run "cp '$SRC/root/usr/libexec/rpcd/vsol_ddm' /usr/libexec/rpcd/vsol_ddm"
run "cp '$SRC'/root/usr/share/vsol_ddm/*.awk /usr/share/vsol_ddm/"
run "cp '$SRC'/htdocs/luci-static/resources/view/vsol_ddm/*.js /www/luci-static/resources/view/vsol_ddm/"
run "cp '$SRC/root/etc/init.d/vsol_ddm' /etc/init.d/vsol_ddm"
run "cp '$SRC/root/usr/share/luci/menu.d/luci-app-vsol-ddm.json' /usr/share/luci/menu.d/"
run "cp '$SRC/root/usr/share/rpcd/acl.d/luci-app-vsol-ddm.json' /usr/share/rpcd/acl.d/"
run "cp '$SRC/root/lib/upgrade/keep.d/luci-app-vsol-ddm' /lib/upgrade/keep.d/"
if [ -f /etc/config/vsol_ddm ]; then
	say "Keeping existing /etc/config/vsol_ddm (your address and login are preserved)"
else
	run "cp '$SRC/root/etc/config/vsol_ddm' /etc/config/vsol_ddm"
fi
run "chmod 755 /usr/libexec/rpcd/vsol_ddm /etc/init.d/vsol_ddm"
run "chmod 600 /etc/config/vsol_ddm"
run "chmod 644 /usr/share/vsol_ddm/*.awk /www/luci-static/resources/view/vsol_ddm/*.js /usr/share/luci/menu.d/luci-app-vsol-ddm.json /usr/share/rpcd/acl.d/luci-app-vsol-ddm.json /lib/upgrade/keep.d/luci-app-vsol-ddm"

# 3. Seed defaults (never overwrites existing values), register with rpcd, start
#    the background poller (the uci-defaults script enables and restarts it).
say "Applying defaults and registering with LuCI"
run "sh '$SRC/root/etc/uci-defaults/80_luci-app-vsol-ddm'"
run "/etc/init.d/rpcd reload"

rm -rf "$WORK"

say "Done."
if [ "$PKG_INSTALLED" = "1" ]; then
	warn "the upstream luci-app-vsol-ddm package is also installed. Its files were"
	warn "replaced with this fork, but upgrading that package (apk upgrade / opkg"
	warn "upgrade) would bring the upstream versions back. Re-run this installer"
	warn "after such an upgrade."
fi
cat <<'EOF'

  Next steps:
   1. Log in to LuCI again (the installer clears LuCI sessions so the new
      menu permissions are picked up).
   2. Open  Status -> VSOL V2802RH DDM -> Settings
      - ONT address, telnet username and password
      - Save & Apply, then press "Test connection"
   3. Open the dashboard. The background poller reads the ONT every 30 s,
      so the first reading appears within about half a minute.
EOF
