#!/bin/bash
# Build one variant in a throwaway amazonlinux:2018.03 container.
# Usage: build/docker-build.sh full|min [output-dir]
# The RPMs, build.log and test results land in <output-dir>/<variant> (default ./out).
set -euo pipefail
VARIANT="${1:?usage: docker-build.sh full|min [output-dir]}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUTDIR="$(mkdir -p "${2:-$REPO/out}" && cd "${2:-$REPO/out}" && pwd)"

docker run --rm --platform linux/amd64 \
  ${DOCKER_ARGS:-} \
  -e PACKAGER \
  -v "$REPO:/repo:ro" -v "$OUTDIR:/out" \
  amazonlinux:2018.03 /repo/build/build.sh "$VARIANT"
