#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Fetches what an Android App Bundle is made with into .cache/android/tools and prints that folder: bundletool (Google, Apache-2.0,
# one jar, run with the JDK) and the build of aapt2 that Google publishes for bundles (the one in the SDK's build-tools is not
# the one bundletool supports). Each download's checksum is checked, and files that are there already are used as they are.
# Needs curl and unzip.
#
#     tools/fetch-bundle-tools.sh
set -eu

BUNDLETOOL_VERSION=1.18.3
BUNDLETOOL_SHA256=a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29
BUNDLETOOL_URL="https://github.com/google/bundletool/releases/download/$BUNDLETOOL_VERSION/bundletool-all-$BUNDLETOOL_VERSION.jar"
AAPT2_VERSION=9.5.2-16666295
AAPT2_BASE="https://dl.google.com/dl/android/maven2/com/android/tools/build/aapt2/$AAPT2_VERSION/aapt2-$AAPT2_VERSION"
AAPT2_SHA256_OSX=a43df4c45549e8a877a8d61b130ee255669eec8a36064f2fc8cd58206457f2a3
AAPT2_SHA256_LINUX=fa1014cb1431622d292ef55ba870e75882ea19987bec541698b912f446a2d08f
AAPT2_SHA256_WINDOWS=0cca28660dd8f8ac75c28023c14e929392e6d094ddac1564945d6ceca8fc6df8

root=$(cd "$(dirname "$0")/.." && pwd)
folder="$root/.cache/android/tools"
mkdir -p "$folder"

case "$(uname -s)" in
Darwin) kind=osx; aapt2_sha=$AAPT2_SHA256_OSX ;;
Linux) kind=linux; aapt2_sha=$AAPT2_SHA256_LINUX ;;
*) kind=windows; aapt2_sha=$AAPT2_SHA256_WINDOWS ;;
esac

sha256_of() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | cut -d ' ' -f 1
	else
		shasum -a 256 "$1" | cut -d ' ' -f 1
	fi
}

# fetch <url> <sha256> <file>: downloads to <file> and checks it, removing it when the checksum is not the one pinned
fetch() {
	curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors --connect-timeout 30 -o "$3" "$1" || { rm -f "$3"; echo "fetch-bundle-tools: cannot download $1" >&2; exit 1; }
	sum=$(sha256_of "$3")
	if [ "$sum" != "$2" ]; then
		rm -f "$3"
		echo "fetch-bundle-tools: the checksum of $1 is $sum, not $2" >&2
		exit 1
	fi
}

jar="$folder/bundletool-$BUNDLETOOL_VERSION.jar"
[ -f "$jar" ] || fetch "$BUNDLETOOL_URL" "$BUNDLETOOL_SHA256" "$jar"

aapt2_folder="$folder/aapt2-$AAPT2_VERSION"
if [ ! -x "$aapt2_folder/aapt2" ]; then
	archive="$folder/aapt2-$AAPT2_VERSION.jar"
	fetch "$AAPT2_BASE-$kind.jar" "$aapt2_sha" "$archive"
	rm -rf "$aapt2_folder"
	mkdir -p "$aapt2_folder"
	unzip -q -o "$archive" aapt2 -d "$aapt2_folder"
	chmod +x "$aapt2_folder/aapt2"
	rm -f "$archive"
fi
echo "$folder"
