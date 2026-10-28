#!/bin/bash
# Sign RPMs in place with rpmsign (Debian/Ubuntu "rpm" package or any recent rpm).
# Usage: release/sign.sh <rpm-dir> <public-key-out>
# Environment:
#   RPM_SIGNING_KEY         ASCII-armored private key (RSA: Amazon Linux 1's rpm cannot verify EdDSA)
#   RPM_SIGNING_PASSPHRASE  its passphrase, if any
set -euo pipefail
RPMDIR="${1:?usage: sign.sh <rpm-dir> <public-key-out>}"
PUBOUT="${2:?usage: sign.sh <rpm-dir> <public-key-out>}"
: "${RPM_SIGNING_KEY:?RPM_SIGNING_KEY is not set}"

export GNUPGHOME=$(mktemp -d); trap 'rm -rf "$GNUPGHOME"' EXIT
echo "$RPM_SIGNING_KEY" | gpg --batch --import 2>/dev/null
KEYID=$(gpg --batch --list-secret-keys --with-colons | awk -F: '$1=="sec"{print $5; exit}')
gpg --batch --armor --export "$KEYID" > "$PUBOUT"

printf '%s' "${RPM_SIGNING_PASSPHRASE:-}" > "$GNUPGHOME/pass"
rpmsign --addsign \
  --define "__gpg $(command -v gpg)" \
  --define "_gpg_name $KEYID" \
  --define '_gpg_digest_algo sha256' \
  --define "_gpg_sign_cmd_extra_args --pinentry-mode loopback --passphrase-file $GNUPGHOME/pass" \
  "$RPMDIR"/*.rpm
echo "Signed $(ls "$RPMDIR"/*.rpm | wc -l) RPMs with key $KEYID"
