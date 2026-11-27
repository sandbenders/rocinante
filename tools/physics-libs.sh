#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Builds Box2D as a static library into .cache/physics (ignored by git): .cache/physics/lib/libbox2d.a (box2d.lib on Windows) and
# .cache/physics/include. Its sources are fetched by tools/fetch-physics.sh. Needs cmake and a C compiler (cc). On Windows it builds
# with MSVC's cl and the cmake Visual Studio Build Tools carry, from Git Bash started inside vcvars64.bat.
#
#     tools/physics-libs.sh                 for this computer, into .cache/physics
#     tools/physics-libs.sh ios             for an iPhone (arm64), into .cache/physics-ios (Xcode; MIN_IOS, default 15.0)
#     tools/physics-libs.sh android         for arm64 Android, into .cache/physics-android (the NDK: ANDROID_HOME,
#                                           NDK_VERSION and API_LEVEL as in spikes/mobile/android/libs.sh)
# The phones' libraries are copied into the phones' own lib folders by their libs.sh scripts.
set -eu

target="${1:-}"

root=$(cd "$(dirname "$0")/.." && pwd)
source=$("$root/tools/fetch-physics.sh") || exit 1
cache="$root/.cache/physics"
[ -n "$target" ] && cache="$root/.cache/physics-$target"
prefix="$cache"
build="$cache/build"
mkdir -p "$build"

if ! command -v cmake >/dev/null 2>&1; then
	echo "physics-libs: cmake is not installed" >&2
	exit 1
fi

# the library only: no samples, tests, benchmarks or documentation, and none of the heavy checking that is on by default
options="-DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_INSTALL_PREFIX=$prefix -DCMAKE_INSTALL_LIBDIR=lib \
 -DBUILD_SHARED_LIBS=OFF -DBOX2D_SAMPLES=OFF -DBOX2D_UNIT_TESTS=OFF -DBOX2D_BENCHMARKS=OFF -DBOX2D_DOCS=OFF -DBOX2D_VALIDATE=OFF"

cross=""
case "$target" in
ios)
	cross="-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 \
 -DCMAKE_OSX_DEPLOYMENT_TARGET=${MIN_IOS:-15.0} -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY"
	;;
android)
	case "$(uname -s)" in
	Darwin) default_home="$HOME/Library/Android/sdk" ;;
	*) default_home="$HOME/Android/Sdk" ;;
	esac
	ndk="${ANDROID_HOME:-$default_home}/ndk/${NDK_VERSION:-29.0.14206865}"
	cross="-DCMAKE_TOOLCHAIN_FILE=$ndk/build/cmake/android.toolchain.cmake -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-${API_LEVEL:-28}"
	;;
"") ;;
*)
	echo "physics-libs: the targets are ios and android" >&2
	exit 1
	;;
esac

case "$(uname -s)" in
MINGW* | MSYS* | CYGWIN*)
	cmake -S "$source" -B "$build/box2d" -G "NMake Makefiles" $options >/dev/null
	;;
*)
	cmake -S "$source" -B "$build/box2d" $options $cross >/dev/null
	;;
esac
cmake --build "$build/box2d" -j 4 >/dev/null
cmake --install "$build/box2d" >/dev/null
echo "physics-libs: built into $cache"
