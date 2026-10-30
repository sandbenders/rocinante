#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Installs the Hugo release named in HUGO_VERSION from Hugo's official GitHub
# releases (Linux amd64 and arm64), checked against the release's own checksums.
# Hugo builds the documentation site and is never shipped.
# Usage: tools/ci/install-hugo.sh <dir>; afterwards add <dir> to PATH.
set -eu
dest="${1:?usage: install-hugo.sh <dir>}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
version="$(tr -d '[:space:]' < "$root/HUGO_VERSION")"
case "$(uname -m)" in
  x86_64 | amd64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) echo "install-hugo: no official Hugo archive for $(uname -m)" >&2; exit 1 ;;
esac
file="hugo_${version}_linux-$arch.tar.gz"
base="https://github.com/gohugoio/hugo/releases/download/v$version"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
echo "install-hugo: $base/$file"
curl -fsSL -o "$work/$file" "$base/$file"
curl -fsSL -o "$work/checksums.txt" "$base/hugo_${version}_checksums.txt"
(cd "$work" && grep " $file\$" checksums.txt | sha256sum -c -)
mkdir -p "$dest"
tar -xzf "$work/$file" -C "$dest" hugo
"$dest/hugo" version
