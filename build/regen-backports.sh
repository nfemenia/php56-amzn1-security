#!/bin/bash
# Regenerate patches/full/backports.patch and test-fixtures.tar.gz from patches/full/series,
# applied on top of Amazon's patched source tree. Runs inside amazonlinux:2018.03:
#   docker run --rm -v "$PWD:/repo" amazonlinux:2018.03 /repo/build/regen-backports.sh
# Review the series files; this script only shows they add up to the shipped patch.
set -euo pipefail
REPO="${REPO:-/repo}"
. "$REPO/build/versions.env"

yum install -y -q rpm-build yum-utils git patch tar gzip
cd /root
yumdownloader -q --source "php56-$AMZN_VERSION"
rpm -i "php56-$AMZN_VERSION.src.rpm"
rpmbuild -bp --nodeps /root/rpmbuild/SPECS/php.spec >/dev/null

cd /root/rpmbuild/BUILD/php-5.6.40
# rpmbuild keeps the tarball's file owners, which git would otherwise refuse
git config --global --add safe.directory "$PWD"
git init -q && git add -A && git -c user.name=x -c user.email=x@x commit -qm amazon
while read -r p; do
  # NEWS conflicts between branches and is not shipped in the RPMs
  git apply --index --exclude=NEWS "$REPO/patches/full/series/$p" || { echo "FAILED: $p" >&2; exit 1; }
done < "$REPO/patches/full/series/series"

git diff --cached --numstat | awk '$1=="-"{print $3}' | sort > /tmp/binary-files
# Binary files go in the tarball; GNU patch 2.7 cannot apply them
git diff --cached -- . $(sed 's/^/:(exclude)/' /tmp/binary-files) > "$REPO/patches/full/backports.patch"
tar cf - --owner=0 --group=0 --numeric-owner --mtime=2019-01-01 -T /tmp/binary-files | gzip -n > "$REPO/patches/full/test-fixtures.tar.gz"
echo "$(git diff --cached --stat | tail -1); binary fixtures: $(wc -l < /tmp/binary-files)"
