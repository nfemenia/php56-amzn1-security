#!/bin/bash
# Pack built RPMs with install.sh/rollback.sh into a release tarball.
# Usage: release/package.sh <rpm-dir> <output-dir> [RPM-GPG-KEY]
# Produces <output-dir>/php56-amzn1-security-<version>.tar.gz and its .sha256,
# e.g. php56-amzn1-security-5.6.40-1.144.sec1.tar.gz
set -euo pipefail
RPMDIR="${1:?usage: package.sh <rpm-dir> <output-dir> [RPM-GPG-KEY]}"
OUTDIR="${2:?usage: package.sh <rpm-dir> <output-dir> [RPM-GPG-KEY]}"
KEY="${3:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"

shopt -s nullglob
rpms=("$RPMDIR"/php56-5.6.40-*.x86_64.rpm)
[ ${#rpms[@]} -eq 1 ] || { echo "expected one php56-5.6.40-*.x86_64.rpm in $RPMDIR" >&2; exit 1; }
VERSION=$(basename "${rpms[0]}" .x86_64.rpm); VERSION="${VERSION#php56-}"; VERSION="${VERSION%.amzn1}"
NAME="php56-amzn1-security-$VERSION"

STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/$NAME/rpms"
cp "$RPMDIR"/*.x86_64.rpm "$STAGE/$NAME/rpms/"
cp "$HERE/install.sh" "$HERE/rollback.sh" "$STAGE/$NAME/"
sed "s|OWNER/php56-amzn1-security|${GITHUB_REPOSITORY:-OWNER/php56-amzn1-security}|" "$HERE/README.txt" > "$STAGE/$NAME/README.txt"
[ -z "$KEY" ] || cp "$KEY" "$STAGE/$NAME/RPM-GPG-KEY"
(cd "$STAGE/$NAME" && sha256sum rpms/*.rpm > SHA256SUMS)

mkdir -p "$OUTDIR"
tar czf "$OUTDIR/$NAME.tar.gz" -C "$STAGE" "$NAME"
(cd "$OUTDIR" && sha256sum "$NAME.tar.gz" > "$NAME.tar.gz.sha256")
echo "$OUTDIR/$NAME.tar.gz"
