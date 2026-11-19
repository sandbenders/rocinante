#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Builds SDL3 for a phone into .cache/mobile (ignored by git): a static libSDL3.a for an iPhone (arm64) in
# .cache/mobile/ios, or libSDL3.so for arm64 Android in .cache/mobile/android, from the release tarball of the SDL
# the bindings are written for. The Java glue Android needs is in .cache/mobile/SDL3-<version>/android-project.
# Needs cmake and ninja, and Xcode (iOS) or the Android NDK (ANDROID_HOME, NDK_VERSION, API_LEVEL as in
# spikes/mobile/android/libs.sh).
#
#     tools/mobile-sdl.sh ios
#     tools/mobile-sdl.sh android
set -eu

target="${1:-}"
case "$target" in
  ios|android) ;;
  *) echo "usage: tools/mobile-sdl.sh ios|android" >&2; exit 2 ;;
esac

VERSION="${SDL_VERSION:-3.4.18}"
root=$(cd "$(dirname "$0")/.." && pwd)
cache="$root/.cache/mobile"
src="$cache/SDL3-$VERSION"
build="$cache/$target"
mkdir -p "$cache"

if [ ! -d "$src" ]; then
  echo "== fetching SDL $VERSION"
  curl -fsSL "https://github.com/libsdl-org/SDL/releases/download/release-$VERSION/SDL3-$VERSION.tar.gz" -o "$cache/SDL3-$VERSION.tar.gz"
  tar -xzf "$cache/SDL3-$VERSION.tar.gz" -C "$cache"
  rm -f "$cache/SDL3-$VERSION.tar.gz"
fi

for tool in cmake ninja; do
  command -v "$tool" > /dev/null 2>&1 || { echo "mobile-sdl: $tool is not installed" >&2; exit 1; }
done

if [ "$target" = ios ]; then
  [ -f "$build/libSDL3.a" ] && { echo "$build"; exit 0; }
  MIN_IOS="${MIN_IOS:-15.0}"
  echo "== building SDL for an iPhone"
  cmake -S "$src" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_IOS" \
    -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF > /dev/null
  cmake --build "$build" > /dev/null
else
  [ -f "$build/libSDL3.so" ] && { echo "$build"; exit 0; }
  case "$(uname -s)" in
    Darwin) default_home="$HOME/Library/Android/sdk" ;;
    *) default_home="$HOME/Android/Sdk" ;;
  esac
  ANDROID_HOME="${ANDROID_HOME:-$default_home}"
  NDK_VERSION="${NDK_VERSION:-29.0.14206865}"
  API_LEVEL="${API_LEVEL:-28}"
  ndk="$ANDROID_HOME/ndk/$NDK_VERSION"
  [ -d "$ndk" ] || { echo "mobile-sdl: the Android NDK $NDK_VERSION is not in $ANDROID_HOME" >&2; exit 1; }
  echo "== building SDL for arm64 Android"
  cmake -S "$src" -B "$build" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM="android-$API_LEVEL" -DCMAKE_BUILD_TYPE=Release \
    -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF > /dev/null
  cmake --build "$build" > /dev/null
fi
echo "$build"
