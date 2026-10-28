#!/bin/bash
# Undo install.sh: reinstall the RPMs saved in its backup, remove the yum exclude it
# added, and restart php-fpm.
#
# Usage: sudo ./rollback.sh [--yes] [--backup DIR] [--restore-config]
#   --backup DIR      backup to restore (default: the one from the last install.sh run)
#   --restore-config  also restore /etc/php*, /etc/php-fpm* and /etc/yum.repos.d from it
set -euo pipefail

STATE_DIR=/var/lib/php56-amzn1-security
MARK=php56-amzn1-security
YES=0 RESTORE_CONFIG=0 BACKUP=""

die() { echo "ERROR: $*" >&2; exit 1; }
usage() { sed -n '2,/^set -e/{/^#/s/^# \{0,1\}//p}' "$0"; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y) YES=1 ;;
    --backup) BACKUP="${2:?--backup needs a directory}"; shift ;;
    --restore-config) RESTORE_CONFIG=1 ;;
    -h|--help) usage ;;
    *) echo "unknown option: $1" >&2; usage 2 ;;
  esac
  shift
done

[ "$(id -u)" = 0 ] || die "run as root (sudo $0)"
BACKUP="${BACKUP:-$(cat "$STATE_DIR/last-backup" 2>/dev/null || true)}"
[ -n "$BACKUP" ] && [ -d "$BACKUP/rpms" ] || die "no backup found; pass --backup /root/$MARK-backup-<timestamp>"
shopt -s nullglob
RPMS=("$BACKUP"/rpms/*.rpm)
[ ${#RPMS[@]} -gt 0 ] || die "no RPMs in $BACKUP/rpms"

echo "Reinstalling from $BACKUP:"
printf '  %s\n' "${RPMS[@]##*/}"
if [ $YES = 0 ]; then
  read -r -p "Continue? [y/N] " a
  [[ "$a" =~ ^[Yy] ]] || exit 1
fi

rpm -Uvh --oldpackage --replacepkgs "${RPMS[@]}"

for repo in /etc/yum.repos.d/amzn-main.repo /etc/yum.repos.d/amzn-updates.repo; do
  [ -f "$repo" ] && sed -i "/^# BEGIN $MARK/,/^# END $MARK/d" "$repo"
done

if [ $RESTORE_CONFIG = 1 ]; then
  tar xzf "$BACKUP/etc.tgz" -C /
  echo "Restored config from $BACKUP/etc.tgz"
fi

php -v | head -1
FPM=""
for s in php-fpm-5.6 php-fpm; do [ -x "/etc/init.d/$s" ] && { FPM=$s; break; }; done
if [ -n "$FPM" ] && service "$FPM" status >/dev/null 2>&1; then
  php-fpm -t
  service "$FPM" restart
fi
if pgrep -x httpd >/dev/null && httpd -M 2>/dev/null | grep -q php5_module; then
  echo "NOTE: Apache runs PHP via mod_php; restart it: service httpd graceful"
fi
echo "Rolled back."
