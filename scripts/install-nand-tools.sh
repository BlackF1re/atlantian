#!/usr/bin/env bash
set -euo pipefail
PROJECT=$(cd "$(dirname "$0")/.." && pwd)
ROOT=${1:?usage: install-nand-tools.sh ROOTFS EDITION}
EDITION=${2:?usage: install-nand-tools.sh ROOTFS EDITION}
[[ -d $ROOT ]] || { echo "missing rootfs: $ROOT" >&2; exit 2; }
case "$EDITION" in sd|nand) ;; *) echo "invalid storage edition: $EDITION" >&2; exit 64 ;; esac
. "$PROJECT/config/nand-layout.env"

for tool in atlantian-nand-backup atlantian-nand-upgrade atlantian-nand-rebase atlantian-storage atlantian-nand-firstboot atlantian-nand-reconcile; do
  install -D -m 0755 "$PROJECT/scripts/$tool.sh" "$ROOT/usr/local/sbin/$tool"
done
# Keep an early public guard and make the destructive implementation repeat the
# same exact NAND-ID check so invoking .real directly cannot skip it.
install -D -m 0755 "$PROJECT/scripts/atlantian-nand-install.sh" "$ROOT/usr/local/sbin/atlantian-nand-install.real"
install -D -m 0755 "$PROJECT/scripts/atlantian-nand-install-guard.sh" "$ROOT/usr/local/sbin/atlantian-nand-install"
for installer in \
  "$ROOT/usr/local/sbin/atlantian-nand-install" \
  "$ROOT/usr/local/sbin/atlantian-nand-install.real"; do
  sed -i \
    -e "s/@ATLANTIAN_NAND_MANUFACTURER_ID@/$ATLANTIAN_NAND_MANUFACTURER_ID/g" \
    -e "s/@ATLANTIAN_NAND_DEVICE_ID@/$ATLANTIAN_NAND_DEVICE_ID/g" \
    "$installer"
  ! grep -Eq '@ATLANTIAN_NAND_(MANUFACTURER|DEVICE)_ID@' "$installer" || {
    echo "NAND installer hardware identity placeholders were not resolved in $installer" >&2
    exit 2
  }
done
install -D -m 0755 "$PROJECT/scripts/atlantian-sysupgrade.sh" "$ROOT/usr/local/sbin/atlantian-sysupgrade"
install -D -m 0755 "$PROJECT/scripts/atlantian-sysupgrade-sd.sh" "$ROOT/usr/lib/atlantian/atlantian-sysupgrade-sd"
install -D -m 0755 "$PROJECT/scripts/atlantian-sysupgrade-nand.sh" "$ROOT/usr/lib/atlantian/atlantian-sysupgrade-nand"
install -D -m 0755 "$PROJECT/scripts/atlantian-verify-release.sh" "$ROOT/usr/local/sbin/atlantian-verify-release"
install -D -m 0644 "$PROJECT/config/release-trust.env" "$ROOT/usr/lib/atlantian/release-trust.env"
install -D -m 0644 "$PROJECT/systemd/atlantian-nand-auto-resume.service" "$ROOT/usr/lib/systemd/system/atlantian-nand-auto-resume.service"
install -D -m 0644 "$PROJECT/systemd/atlantian-nand-reconcile.service" "$ROOT/usr/lib/systemd/system/atlantian-nand-reconcile.service"

install -d -m 0755 "$ROOT/etc/systemd/system/multi-user.target.wants"
if [[ $EDITION == sd ]]; then
  ln -sfn /usr/lib/systemd/system/atlantian-nand-auto-resume.service "$ROOT/etc/systemd/system/multi-user.target.wants/atlantian-nand-auto-resume.service"
  rm -f "$ROOT/etc/systemd/system/multi-user.target.wants/atlantian-nand-reconcile.service"
else
  rm -f "$ROOT/etc/systemd/system/multi-user.target.wants/atlantian-nand-auto-resume.service"
  ln -sfn /usr/lib/systemd/system/atlantian-nand-reconcile.service "$ROOT/etc/systemd/system/multi-user.target.wants/atlantian-nand-reconcile.service"
fi

install -d -m 0755 "$ROOT/usr/lib/atlantian" "$ROOT/etc/profile.d"
printf '%s\n' "$EDITION" >"$ROOT/usr/lib/atlantian/storage-edition"
cat >"$ROOT/etc/profile.d/20-atlantian-nand-firstboot.sh" <<'EOF_PROFILE'
if [ -x /usr/local/sbin/atlantian-nand-firstboot ]; then
    /usr/local/sbin/atlantian-nand-firstboot
fi
EOF_PROFILE
chmod 0644 "$ROOT/etc/profile.d/20-atlantian-nand-firstboot.sh"
