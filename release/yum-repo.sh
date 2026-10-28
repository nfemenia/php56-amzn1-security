#!/bin/bash
# Turn the release tarballs into yum repositories for GitHub Pages.
# Runs inside amazonlinux:2018.03, so the metadata is written by the same createrepo the servers' yum expects.
# Usage: release/yum-repo.sh <dir with php56-amzn1-security-{full,min}.tar.gz and RPM-GPG-KEY> <site-dir> <base-url>
# Produces <site-dir>/{full,min}/ with repodata, <site-dir>/php56-amzn1-security-{full,min}.repo,
# <site-dir>/RPM-GPG-KEY and <site-dir>/index.html
set -euo pipefail
IN="${1:?usage: yum-repo.sh <in-dir> <site-dir> <base-url>}"
SITE="${2:?usage: yum-repo.sh <in-dir> <site-dir> <base-url>}"
BASEURL="${3:?usage: yum-repo.sh <in-dir> <site-dir> <base-url>}"
BASEURL="${BASEURL%/}"

yum install -y -q createrepo >/dev/null
rpm --import "$IN/RPM-GPG-KEY"
mkdir -p "$SITE"
cp "$IN/RPM-GPG-KEY" "$SITE/"

for v in full min; do
    TMP=$(mktemp -d)
    tar xzf "$IN/php56-amzn1-security-$v.tar.gz" -C "$TMP"
    (cd "$TMP"/php56-amzn1-security-*/ && sha256sum -c --quiet SHA256SUMS)
    mkdir -p "$SITE/$v"
    cp "$TMP"/php56-amzn1-security-*/rpms/*.rpm "$SITE/$v/"
    rm -rf "$TMP"
    # Refuse to publish anything that is not signed with the release key
    for r in "$SITE/$v"/*.rpm; do
        rpm -K "$r" | grep -q 'pgp.*OK' || { echo "not signed with RPM-GPG-KEY: $r" >&2; exit 1; }
    done
    createrepo -q --checksum sha256 "$SITE/$v"
    # priority only matters where yum-plugin-priorities is enabled; Amazon's repos use 10
    cat > "$SITE/php56-amzn1-security-$v.repo" <<EOF
[php56-amzn1-security-$v]
name=php56 security backports for Amazon Linux AMI 2018.03 ($v)
baseurl=$BASEURL/$v/
enabled=1
gpgcheck=1
gpgkey=$BASEURL/RPM-GPG-KEY
priority=5
EOF
done

VERSION=$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$SITE"/full/php56-5.6.40-*.x86_64.rpm)
cat > "$SITE/index.html" <<EOF
<!doctype html>
<meta charset="utf-8">
<title>php56-amzn1-security yum repository</title>
<h1>php56-amzn1-security</h1>
<p>Yum repositories with security-patched php56 for Amazon Linux AMI 2018.03 (Amazon Linux 1).
Current full build: <code>$VERSION</code>.</p>
<pre>sudo curl -fLo /etc/yum.repos.d/php56-amzn1-security-full.repo $BASEURL/php56-amzn1-security-full.repo
sudo yum update 'php56*'</pre>
<p>Read the <a href="https://github.com/${GITHUB_REPOSITORY:-nfemenia/php56-amzn1-security}#install-with-yum">README</a> first.</p>
EOF
ls -R "$SITE"
