#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Installs the Odin release named in ODIN_VERSION from Odin's official GitHub
# releases (Linux amd64 and arm64). Used by both pipelines so they cannot
# drift apart. Usage: tools/ci/install-odin.sh <dir>
# Afterwards add <dir> to PATH. Needs curl and tar; Odin itself needs clang.
set -eu
dest="${1:?usage: install-odin.sh <dir>}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
version="$(tr -d '[:space:]' < "$root/ODIN_VERSION")"
case "$(uname -m)" in
  x86_64 | amd64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) echo "install-odin: no official Odin archive for $(uname -m)" >&2; exit 1 ;;
esac
url="https://github.com/odin-lang/Odin/releases/download/$version/odin-linux-$arch-$version.tar.gz"
mkdir -p "$dest"
echo "install-odin: $url"
curl -fsSL "$url" | tar -xzf - -C "$dest" --strip-components=1
"$dest/odin" version
