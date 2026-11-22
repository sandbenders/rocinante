#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Builds libcurl and mbedTLS (the TLS it uses) as static libraries into .cache/net (ignored by git):
# .cache/net/lib/libcurl.a and the mbedTLS libraries beside it, .cache/net/include. HTTP and HTTPS only:
# no HTTP/2, no compression, no other protocol, so nothing else is linked. The sources are fetched by
# tools/fetch-net.sh. Needs cmake and a C compiler (cc). On Windows libcurl uses the system's Schannel and
# builds with MSVC's cl, from Git Bash started inside vcvars64.bat (not yet run there).
#
#     tools/net-libs.sh                 for this computer, into .cache/net
#     tools/net-libs.sh ios             for an iPhone (arm64), into .cache/net-ios (Xcode; MIN_IOS, default 15.0)
#     tools/net-libs.sh android         for arm64 Android, into .cache/net-android (the NDK: ANDROID_HOME,
#                                       NDK_VERSION and API_LEVEL as in spikes/mobile/android/libs.sh)
# The phones' libraries are copied into the phones' own lib folders by their libs.sh scripts.
set -eu

target="${1:-}"

root=$(cd "$(dirname "$0")/.." && pwd)
folders=$("$root/tools/fetch-net.sh") || exit 1
curl_src=$(echo "$folders" | sed -n 1p)
mbed_src=$(echo "$folders" | sed -n 2p)
cache="$root/.cache/net"
[ -n "$target" ] && cache="$root/.cache/net-$target"
prefix="$cache"
build="$cache/build"
mkdir -p "$build"

if ! command -v cmake >/dev/null 2>&1; then
	echo "net-libs: cmake is not installed" >&2
	exit 1
fi

# curl's options: the library only, HTTP and HTTPS, mbedTLS (Schannel on Windows) for the secure part
# (always into lib/, where the bindings look: cmake would choose lib64/ on Fedora and openSUSE)
common="-DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_INSTALL_PREFIX=$prefix -DCMAKE_INSTALL_LIBDIR=lib"
curl_options="-DBUILD_SHARED_LIBS=OFF -DBUILD_CURL_EXE=OFF -DBUILD_TESTING=OFF -DHTTP_ONLY=ON \
 -DCURL_USE_LIBPSL=OFF -DCURL_USE_LIBSSH2=OFF -DCURL_USE_LIBSSH=OFF -DUSE_NGHTTP2=OFF -DCURL_ZLIB=OFF \
 -DCURL_BROTLI=OFF -DCURL_ZSTD=OFF -DUSE_LIBIDN2=OFF -DCURL_DISABLE_LDAP=ON -DENABLE_WEBSOCKETS=ON \
 -DCURL_DISABLE_INSTALL=OFF"

# What a phone needs to be told: where its compiler is. Test programs are built as static libraries because
# an iPhone program cannot run (or be linked) without signing, and Android's cmake looks for libraries only
# under its own root.
cross=""
case "$target" in
ios)
	cross="-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 \
 -DCMAKE_OSX_DEPLOYMENT_TARGET=${MIN_IOS:-15.0} -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
 -DCMAKE_FIND_ROOT_PATH=$prefix"
	;;
android)
	case "$(uname -s)" in
	Darwin) default_home="$HOME/Library/Android/sdk" ;;
	*) default_home="$HOME/Android/Sdk" ;;
	esac
	ndk="${ANDROID_HOME:-$default_home}/ndk/${NDK_VERSION:-29.0.14206865}"
	cross="-DCMAKE_TOOLCHAIN_FILE=$ndk/build/cmake/android.toolchain.cmake -DANDROID_ABI=arm64-v8a \
 -DANDROID_PLATFORM=android-${API_LEVEL:-28} -DCMAKE_FIND_ROOT_PATH=$prefix"
	;;
"") ;;
*)
	echo "net-libs: the targets are ios and android" >&2
	exit 1
	;;
esac

case "$(uname -s)" in
MINGW* | MSYS* | CYGWIN*)
	cmake -S "$curl_src" -B "$build/curl" -G "NMake Makefiles" $common $curl_options -DCURL_USE_SCHANNEL=ON -DCURL_STATIC_CRT=ON >/dev/null
	cmake --build "$build/curl" >/dev/null
	cmake --install "$build/curl" >/dev/null
	;;
*)
	cmake -S "$mbed_src" -B "$build/mbedtls" $common $cross -DENABLE_PROGRAMS=OFF -DENABLE_TESTING=OFF \
		-DUSE_SHARED_MBEDTLS_LIBRARY=OFF -DUSE_STATIC_MBEDTLS_LIBRARY=ON >/dev/null
	cmake --build "$build/mbedtls" -j 4 >/dev/null
	cmake --install "$build/mbedtls" >/dev/null
	# a phone's cmake looks for libraries under its own root only, so curl is told where mbedTLS is
	found=""
	[ -n "$target" ] && found="-DMBEDTLS_LIBRARY=$prefix/lib/libmbedtls.a -DMBEDX509_LIBRARY=$prefix/lib/libmbedx509.a -DMBEDCRYPTO_LIBRARY=$prefix/lib/libmbedcrypto.a"
	cmake -S "$curl_src" -B "$build/curl" $common $cross $found $curl_options -DCURL_USE_MBEDTLS=ON \
		-DCMAKE_PREFIX_PATH="$prefix" -DMBEDTLS_INCLUDE_DIR="$prefix/include" >/dev/null
	cmake --build "$build/curl" -j 4 >/dev/null
	cmake --install "$build/curl" >/dev/null
	;;
esac
echo "net-libs: built into $cache"
