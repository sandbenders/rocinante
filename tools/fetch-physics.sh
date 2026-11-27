#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Fetches Box2D (Erin Catto's 2D physics, MIT licence) into .cache/physics/src/box2d-<version> and prints the folder, for
# tools/physics-libs.sh and the phones' libs.sh scripts. The archive is GitHub's of the release's tag; its checksum was taken
# when version 3.2.0 was approved (2026-11-27) and is checked, and a copy that is there already is used as it is. Needs curl
# and tar.
#
#     tools/fetch-physics.sh
set -eu

BOX2D_VERSION=3.2.0
BOX2D_SHA256=ffec747b27a2267016f8d0240d658c82d187fb2271fa0f69fcbe53fbc067180d
BOX2D_URL="https://github.com/erincatto/box2d/archive/refs/tags/v$BOX2D_VERSION.tar.gz"

root=$(cd "$(dirname "$0")/.." && pwd)
src="$root/.cache/physics/src"
mkdir -p "$src"

checksum() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | cut -d ' ' -f 1
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | cut -d ' ' -f 1
	else
		sha256 -q "$1"
	fi
}

folder="$src/box2d-$BOX2D_VERSION"
if [ ! -f "$folder/include/box2d/box2d.h" ]; then
	archive="$src/box2d-$BOX2D_VERSION.archive"
	curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors --connect-timeout 30 -o "$archive" "$BOX2D_URL" || { echo "fetch-physics: cannot download $BOX2D_URL" >&2; exit 1; }
	sum=$(checksum "$archive")
	if [ "$sum" != "$BOX2D_SHA256" ]; then
		rm -f "$archive"
		echo "fetch-physics: the archive of Box2D has the checksum $sum, not $BOX2D_SHA256" >&2
		exit 1
	fi
	tar -xzf "$archive" -C "$src"
	rm -f "$archive"
fi
echo "$folder"
