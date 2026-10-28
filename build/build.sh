#!/bin/bash
# Rebuild Amazon Linux 1's php56 source RPM with this repo's patches, then run PHP's test suite.
# Runs inside an amazonlinux:2018.03 container; see build/docker-build.sh.
#
# Usage: build.sh full|min
# Environment:
#   REPO      repo checkout mounted in the container (default /repo)
#   OUT       output directory (default /out/<variant>)
#   PACKAGER  name and email written to the RPM changelog
set -euo pipefail

VARIANT="${1:?usage: build.sh full|min}"
REPO="${REPO:-/repo}"
OUT="${OUT:-/out/$VARIANT}"
PACKAGER="${PACKAGER:-php56-amzn1-security <php56-amzn1-security@users.noreply.github.com>}"
. "$REPO/build/versions.env"

case "$VARIANT" in
  full) SUFFIX="$FULL_SUFFIX" ;;
  min)  SUFFIX="$MIN_SUFFIX" ;;
  *) echo "unknown variant: $VARIANT" >&2; exit 2 ;;
esac

rm -rf "$OUT"; mkdir -p "$OUT"
exec > >(tee "$OUT/build.log") 2>&1 </dev/null

yum install -y -q rpm-build yum-utils gcc gcc-c++ make tar xz which

cd /root
yumdownloader --source "php56-$AMZN_VERSION"
rpm -i "php56-$AMZN_VERSION.src.rpm"
SPEC=/root/rpmbuild/SPECS/php.spec
SOURCES=/root/rpmbuild/SOURCES

# The spec carries the release as "%define _buildid .<n>"; append our suffix to it
grep -q "^%define _buildid $AMZN_BUILDID\$" "$SPEC" || { echo "spec _buildid is not $AMZN_BUILDID" >&2; exit 1; }
sed -i "s/^%define _buildid $AMZN_BUILDID\$/%define _buildid $AMZN_BUILDID.$SUFFIX/" "$SPEC"

case "$VARIANT" in
  full)
    cp "$REPO/patches/full/backports.patch" "$REPO/patches/full/test-fixtures.tar.gz" "$SOURCES/"
    sed -i '/^Patch10002: CVE-2023-0662.patch/a Patch10003: backports.patch\nSource200: test-fixtures.tar.gz' "$SPEC"
    # GNU patch on Amazon Linux 1 cannot apply binary diffs, so the binary test fixtures come as a tarball
    sed -i '/^%patch10002 -p1/a %patch10003 -p1\ntar xzf %{SOURCE200}' "$SPEC"
    CHANGE="Backport post-5.6.40 security fixes from deb.sury.org php5.6 $SURY_VERSION, incl. CVE-2026-109618, CVE-2026-109619"
    ;;
  min)
    cp "$REPO/patches/min/php2shell-CVE-2026-109618-109619.patch" "$SOURCES/"
    sed -i '/^Patch10002: CVE-2023-0662.patch/a Patch10003: php2shell-CVE-2026-109618-109619.patch' "$SPEC"
    sed -i '/^%patch10002 -p1/a %patch10003 -p1' "$SPEC"
    CHANGE="Fix CVE-2026-109618, CVE-2026-109619 (PHP2Shell), backported from deb.sury.org php5.6 $SURY_VERSION"
    ;;
esac
sed -i "0,/^%changelog/s//%changelog\n* $(LC_ALL=C date -u '+%a %b %d %Y') $PACKAGER\n- $CHANGE\n/" "$SPEC"
grep -nE '^%define _buildid|^Patch1000|^Source200|^%patch1000|SOURCE200' "$SPEC"

yum-builddep -y -q "$SPEC"

# Build without %check so the RPMs are produced even if a test hangs; tests run below with a timeout
START=$(date +%s)
rpmbuild -ba --define "_smp_mflags -j$(nproc)" --define 'runselftest 0' "$SPEC"
echo "BUILD_SECONDS=$(( $(date +%s) - START ))"
cp /root/rpmbuild/RPMS/x86_64/*.rpm /root/rpmbuild/SRPMS/*.rpm "$OUT/"

# Same environment as the spec's %check, plus a 60s per-test timeout
cd /root/rpmbuild/BUILD/php-5.6.40/build-apache
export NO_INTERACTION=1 SKIP_ONLINE_TESTS=1 SKIP_SLOW_TESTS=1
unset TZ LANG LC_ALL
START=$(date +%s)
make test TESTS="--set-timeout 60 -s $OUT/test-results.txt" > "$OUT/test.log" 2>&1 || true
echo "TEST_SECONDS=$(( $(date +%s) - START ))"
"$REPO/tests/compare-results.sh" "$OUT/test-results.txt" "$REPO/tests/expected-failures-$VARIANT.txt"
