#!/usr/bin/env bash
# Fetch a zmx release for both macOS arches, lipo to a universal
# binary, and update Resources/zmx-binary/{zmx,VERSION,CHECKSUMS}.
#
# Usage:
#   ./scripts/bump-zmx.sh             # bumps to latest GitHub release
#   ZMX_VERSION=0.5.0 ./scripts/bump-zmx.sh   # pins a specific version
#
# Requires: gh, curl, shasum, lipo, tar.

set -euo pipefail

for tool in gh curl shasum lipo tar; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "missing required tool: $tool" >&2
        exit 1
    }
done

cd "$(dirname "$0")/.."

VERSION="${ZMX_VERSION:-}"
if [[ -z "$VERSION" ]]; then
    VERSION=$(gh api repos/neurosnap/zmx/releases/latest --jq .tag_name 2>/dev/null) || {
        echo "couldn't fetch latest zmx version (is gh authenticated and online?)" >&2
        echo "  workaround: pin a version with ZMX_VERSION=0.5.0 ./scripts/bump-zmx.sh" >&2
        exit 1
    }
fi
VERSION="${VERSION#v}"
echo "→ vendoring zmx ${VERSION}"

mkdir -p Resources/zmx-binary
TMP="$(mktemp -d)"
trap "rm -rf '$TMP'" EXIT

declare -a checksums
for zmx_arch in aarch64 x86_64; do
    url="https://zmx.sh/a/zmx-${VERSION}-macos-${zmx_arch}.tar.gz"
    echo "  → fetching $url"
    curl -fL --silent --show-error -o "${TMP}/zmx-${zmx_arch}.tar.gz" "$url" || {
        echo "failed to fetch $url — does the release ship a macos-${zmx_arch} artifact?" >&2
        exit 1
    }
    tar -xzf "${TMP}/zmx-${zmx_arch}.tar.gz" -C "$TMP"
    mv "${TMP}/zmx" "${TMP}/zmx-${zmx_arch}"
    sha=$(shasum -a 256 "${TMP}/zmx-${zmx_arch}" | awk '{print $1}')
    checksums+=("${sha}  zmx-${zmx_arch}")
done

lipo -create "${TMP}/zmx-aarch64" "${TMP}/zmx-x86_64" -output Resources/zmx-binary/zmx
chmod +x Resources/zmx-binary/zmx

uni_sha=$(shasum -a 256 Resources/zmx-binary/zmx | awk '{print $1}')
checksums+=("${uni_sha}  zmx (universal)")

echo "$VERSION" > Resources/zmx-binary/VERSION
{
    echo "# zmx ${VERSION} — fetched from https://zmx.sh/a/"
    printf "%s\n" "${checksums[@]}"
} > Resources/zmx-binary/CHECKSUMS

echo
echo "✓ vendored zmx ${VERSION}"
echo "  arm64:     ${checksums[0]%% *}"
echo "  x86_64:    ${checksums[1]%% *}"
echo "  universal: ${uni_sha}"
echo "  size:      $(stat -f%z Resources/zmx-binary/zmx) bytes"
echo
echo "Review the diff and commit."
