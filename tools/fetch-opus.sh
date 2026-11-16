#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Fetches libopus (Xiph.Org, BSD-3-Clause) into .cache/sound/src/opus-<version> and prints that
# folder, for tools/sound-libs.sh and the phones' libs.sh scripts, which compile the files that
# vendor/sound/c/opus_files.txt lists. The release archive's checksum is checked, and a copy
# that is there already is used as it is. Needs curl and tar.
#
#     tools/fetch-opus.sh
set -eu

OPUS_VERSION=1.6.1
OPUS_SHA256=6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1
OPUS_URL="https://downloads.xiph.org/releases/opus/opus-$OPUS_VERSION.tar.gz"

root=$(cd "$(dirname "$0")/.." && pwd)
src="$root/.cache/sound/src"
folder="$src/opus-$OPUS_VERSION"
if [ -f "$folder/include/opus.h" ]; then
	echo "$folder"
	exit 0
fi
mkdir -p "$src"
archive="$src/opus-$OPUS_VERSION.tar.gz"
curl -fsSL -o "$archive" "$OPUS_URL" || { echo "fetch-opus: cannot download $OPUS_URL" >&2; exit 1; }
if command -v sha256sum >/dev/null 2>&1; then
	sum=$(sha256sum "$archive" | cut -d ' ' -f 1)
elif command -v shasum >/dev/null 2>&1; then
	sum=$(shasum -a 256 "$archive" | cut -d ' ' -f 1)
else
	sum=$(sha256 -q "$archive")
fi
if [ "$sum" != "$OPUS_SHA256" ]; then
	rm -f "$archive"
	echo "fetch-opus: the archive's checksum is $sum, not $OPUS_SHA256" >&2
	exit 1
fi
tar -xzf "$archive" -C "$src"
rm -f "$archive"
echo "$folder"
