#!/bin/bash
# Replace the php56 packages installed on this Amazon Linux AMI 2018.03 server with the
# patched build shipped next to this script, keeping everything needed to roll back.
#
# Usage: sudo ./install.sh [--yes] [--dry-run] [--no-pin] [--check-url URL] [--rollback-rpms DIR]
#   --rollback-rpms DIR  RPMs for rollback.sh to reinstall, instead of downloading the
#                        installed versions (needed if they are not Amazon's or not downloadable)
#
# What it does:
#   1. Verifies the RPMs (SHA256SUMS, and the GPG signature when RPM-GPG-KEY is present).
#   2. Upgrades only the php56 5.6.40 packages already installed; nothing new is added.
#   3. Backs up PHP config, the package list and the current Amazon RPMs to
#      /root/php56-amzn1-security-backup-<timestamp> (used by rollback.sh).
#   4. Adds an exclude= for those packages to amzn-main/amzn-updates so a yum update
#      does not replace them with Amazon's unpatched build (skip with --no-pin).
#   5. Checks the PHP module list did not change, then restarts php-fpm if it is running.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR=/var/lib/php56-amzn1-security
MARK=php56-amzn1-security
YES=0 DRY=0 PIN=1 CHECK_URL="" ROLLBACK_RPMS=""

die() { echo "ERROR: $*" >&2; exit 1; }
usage() { sed -n '2,/^set -e/{/^#/s/^# \{0,1\}//p}' "$0"; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y) YES=1 ;;
    --dry-run) DRY=1 ;;
    --no-pin) PIN=0 ;;
    --check-url) CHECK_URL="${2:?--check-url needs a URL}"; shift ;;
    --rollback-rpms) ROLLBACK_RPMS="${2:?--rollback-rpms needs a directory}"; shift ;;
    -h|--help) usage ;;
    *) echo "unknown option: $1" >&2; usage 2 ;;
  esac
  shift
done

[ "$(id -u)" = 0 ] || die "run as root (sudo $0)"
grep -q 'Amazon Linux AMI release 2018.03' /etc/system-release 2>/dev/null \
  || die "this build is only for Amazon Linux AMI 2018.03 (found: $(cat /etc/system-release 2>/dev/null))"

# 1. Verify the RPMs
cd "$HERE"
sha256sum -c --quiet SHA256SUMS || die "checksum mismatch, download the release again"
shopt -s nullglob
RPMS=(rpms/*.x86_64.rpm)
[ ${#RPMS[@]} -gt 0 ] || die "no RPMs found in $HERE/rpms"
if [ -f RPM-GPG-KEY ] && [ $DRY = 1 ]; then
  echo "Dry run: skipping the GPG check (it needs to import RPM-GPG-KEY)"
elif [ -f RPM-GPG-KEY ]; then
  rpm --import RPM-GPG-KEY
  for f in "${RPMS[@]}"; do
    out=$(rpm -K "$f" 2>&1) || die "signature check failed: $out"
    echo "$out" | grep -qiE '(pgp|gpg).* OK$' || die "not signed with RPM-GPG-KEY: $out"
  done
else
  echo "WARNING: no RPM-GPG-KEY in this release, RPMs are only checked against SHA256SUMS"
fi

# 2. Work out which installed packages get replaced
declare -A NEW_FILE NEW_EVR
for f in "${RPMS[@]}"; do
  read -r name evr < <(rpm -qp --nosignature --qf '%{NAME} %{VERSION}-%{RELEASE}\n' "$f")
  NEW_FILE[$name]="$f"; NEW_EVR[$name]="$evr"
done

PKGS=() FILES=() missing=()
while read -r name evr; do
  [[ "$evr" == 5.6.40-* ]] || continue        # php56-jsonc, php56-pecl-* etc. are separate packages
  if [ -z "${NEW_FILE[$name]:-}" ]; then missing+=("$name"); continue; fi
  PKGS+=("$name")
  if [ "$evr" = "${NEW_EVR[$name]}" ]; then
    printf '  %-16s %s (already installed)\n' "$name" "$evr"
  else
    printf '  %-16s %s -> %s\n' "$name" "$evr" "${NEW_EVR[$name]}"
    FILES+=("${NEW_FILE[$name]}")
  fi
done < <(rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE}\n' 'php56*' | sort)

[ ${#PKGS[@]} -gt 0 ] || die "no php56 5.6.40 packages are installed"
[ ${#missing[@]} -eq 0 ] || die "installed but not in this release: ${missing[*]}"
if [ ${#FILES[@]} -eq 0 ]; then echo "Nothing to do."; exit 0; fi
if [ $DRY = 1 ]; then echo "Dry run, nothing changed."; exit 0; fi
if [ $YES = 0 ]; then
  read -r -p "Replace these ${#FILES[@]} packages? [y/N] " a
  [[ "$a" =~ ^[Yy] ]] || exit 1
fi

# 3. Back up
BACKUP="/root/$MARK-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP/rpms"
exec > >(tee "$BACKUP/install.log") 2>&1
echo "Backup: $BACKUP"
etc=()
for p in /etc/php.ini /etc/php-5.6.ini /etc/php.d /etc/php-5.6.d /etc/php-fpm.conf /etc/php-fpm-5.6.conf \
         /etc/php-fpm.d /etc/php-fpm-5.6.d /etc/yum.repos.d; do
  [ -e "$p" ] && etc+=("$p")
done
tar czf "$BACKUP/etc.tgz" "${etc[@]}" 2>/dev/null
rpm -qa | sort > "$BACKUP/rpm-qa.txt"
php -m > "$BACKUP/modules-before.txt"

# Keep the RPMs currently installed so rollback.sh can reinstall them. If they are not
# Amazon's (an earlier install of this project), carry over the previous backup's RPMs.
current=$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' "${PKGS[@]}")
if [ -n "$ROLLBACK_RPMS" ]; then
  cp -p "$ROLLBACK_RPMS"/*.rpm "$BACKUP/rpms/" || { rm -rf "$BACKUP"; die "no RPMs in $ROLLBACK_RPMS"; }
else
  command -v yumdownloader >/dev/null || { rm -rf "$BACKUP"; die "yumdownloader not found: yum install yum-utils"; }
  if ! (cd "$BACKUP/rpms" && yumdownloader -q --disableexcludes=all --disablerepo='*' \
          --enablerepo='amzn-main,amzn-updates' $current) || [ "$(ls "$BACKUP/rpms" | wc -l)" -ne ${#PKGS[@]} ]; then
    prev=$(cat "$STATE_DIR/last-backup" 2>/dev/null || true)
    if [ -z "$prev" ] || [ ! -d "$prev/rpms" ]; then
      rm -rf "$BACKUP"
      die "could not download the installed RPMs ($current) for rollback; nothing changed.
If you have the original Amazon RPMs, pass them with --rollback-rpms DIR"
    fi
    echo "Installed packages are not Amazon's; reusing rollback RPMs from $prev"
    rm -f "$BACKUP/rpms/"*; cp -p "$prev/rpms/"*.rpm "$BACKUP/rpms/"
  fi
fi
mkdir -p "$STATE_DIR"; echo "$BACKUP" > "$STATE_DIR/last-backup"

# 4. Install. rpm instead of yum: the exact files, no repo access, works as upgrade or downgrade.
rpm -Uvh --oldpackage "${FILES[@]}"
rpm -q "${PKGS[@]}"

if [ $PIN = 1 ]; then
  for repo in /etc/yum.repos.d/amzn-main.repo /etc/yum.repos.d/amzn-updates.repo; do
    [ -f "$repo" ] || continue
    sed -i "/^# BEGIN $MARK/,/^# END $MARK/d" "$repo"
    if grep -q '^exclude' "$repo"; then
      echo "WARNING: $repo already has an exclude= line; add these yourself: ${PKGS[*]}"
      continue
    fi
    section="[$(basename "$repo" .repo)]"
    sed -i "/^\[$(basename "$repo" .repo)\]\$/a # BEGIN $MARK (rollback.sh removes this)\nexclude=${PKGS[*]}\n# END $MARK" "$repo"
    grep -q "^# BEGIN $MARK" "$repo" || echo "WARNING: no $section section in $repo, not pinned"
  done
fi

# 5. Check and restart
php -m > "$BACKUP/modules-after.txt"
if [ "$(cat "$BACKUP/modules-before.txt")" != "$(cat "$BACKUP/modules-after.txt")" ]; then
  comm -3 "$BACKUP/modules-before.txt" "$BACKUP/modules-after.txt"
  die "PHP modules changed after the upgrade (left: before, right: after); php-fpm was NOT restarted. Run ./rollback.sh"
fi
php -v | head -1

FPM=""
for s in php-fpm-5.6 php-fpm; do [ -x "/etc/init.d/$s" ] && { FPM=$s; break; }; done
if [ -n "$FPM" ] && service "$FPM" status >/dev/null 2>&1; then
  php-fpm -t
  service "$FPM" restart
else
  echo "php-fpm is not running; not restarted"
fi
if pgrep -x httpd >/dev/null && httpd -M 2>/dev/null | grep -q php5_module; then
  echo "NOTE: Apache runs PHP via mod_php; restart it to load the new build: service httpd graceful"
fi

if [ -n "$CHECK_URL" ]; then
  sleep 2
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$CHECK_URL" || echo 000)
  echo "$CHECK_URL -> HTTP $code"
  [ "$code" -ge 200 ] && [ "$code" -lt 500 ] || die "site check failed; to undo: ./rollback.sh"
fi

echo "Done. To undo: sudo ./rollback.sh   (backup: $BACKUP)"
