#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Fetches libcurl (the curl licence, MIT-style) and mbedTLS (Apache-2.0, which it is offered under
# beside GPL-2.0-or-later) into .cache/net/src/curl-<version> and .cache/net/src/mbedtls-<version>, and
# prints the two folders (curl first), for tools/net-libs.sh and the phones' libs.sh scripts. The release
# archives' checksums are checked (curl's was read from curl.se and GitHub, mbedTLS's is the one its release
# lists), and a copy that is there already is used as it is. Needs curl and tar.
#
#     tools/fetch-net.sh
set -eu

CURL_VERSION=8.23.0
CURL_SHA256=e3de77cfa6367083c776a26647fc9f633b538c06c3baa73d931a252ac8f72b49
CURL_URL="https://curl.se/download/curl-$CURL_VERSION.tar.gz"
MBEDTLS_VERSION=4.3.0
MBEDTLS_SHA256=1c87cba094cb40f097ebe0eba440a74939b71dab4e1d0d566bc90749ff381d18
MBEDTLS_URL="https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-$MBEDTLS_VERSION/mbedtls-$MBEDTLS_VERSION.tar.bz2"

root=$(cd "$(dirname "$0")/.." && pwd)
src="$root/.cache/net/src"
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

# fetch <name> <version> <url> <sha256> <flag for tar> <a file the folder holds>
fetch() {
	folder="$src/$1-$2"
	if [ -f "$folder/$6" ]; then
		return 0
	fi
	archive="$src/$1-$2.archive"
	curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors --connect-timeout 30 -o "$archive" "$3" || { echo "fetch-net: cannot download $3" >&2; exit 1; }
	sum=$(checksum "$archive")
	if [ "$sum" != "$4" ]; then
		rm -f "$archive"
		echo "fetch-net: the archive of $1 has the checksum $sum, not $4" >&2
		exit 1
	fi
	tar "$5" "$archive" -C "$src"
	rm -f "$archive"
}

fetch curl "$CURL_VERSION" "$CURL_URL" "$CURL_SHA256" -xzf include/curl/curl.h
fetch mbedtls "$MBEDTLS_VERSION" "$MBEDTLS_URL" "$MBEDTLS_SHA256" -xjf CMakeLists.txt
echo "$src/curl-$CURL_VERSION"
echo "$src/mbedtls-$MBEDTLS_VERSION"
