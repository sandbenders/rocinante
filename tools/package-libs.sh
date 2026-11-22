#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Builds the libraries a packaged app carries, for this computer, into .cache/package/<system>/lib (ignored by git).
#
# On a Mac:
#   libSDL3.0.dylib       SDL3 as a shared library whose install name is @rpath/libSDL3.0.dylib, so an app finds it in
#                         its own Frameworks folder (SDL is Zlib)
#   libSDL3_ttf.0.dylib   SDL3_ttf the same way, with the FreeType and HarfBuzz it is built with inside it (the FreeType
#                         Project Licence and the old MIT licence, both permissive)
# A sketch is linked against the copies on the computer (Homebrew's), and `roci package` points the program at these
# instead, because Homebrew's SDL3_ttf pulls in HarfBuzz's glib, which is LGPL and may not be in a packaged sketch.
# Needs cmake and ninja, and Xcode's command-line tools, git and curl.
#
# On Linux, only SDL3_ttf (`roci package` copies SDL3 and the other libraries a program asks for from where the computer keeps them):
#   libSDL3_ttf.so.0      SDL3_ttf built here against it, with FreeType and HarfBuzz inside it and libstdc++ linked in, so
#                         it asks the computer for SDL3 and the C library only (the distribution's SDL3_ttf pulls in
#                         HarfBuzz's glib, which is LGPL and may not be in a packaged sketch)
# Needs cmake, git, curl, a C and C++ compiler and SDL3 with its headers (Arch's sdl3, built from source elsewhere).
#
#     tools/package-libs.sh macos
#     tools/package-libs.sh linux
set -eu

target="${1:-}"
case "$target" in
  macos) [ "$(uname -s)" = Darwin ] || { echo "package-libs: macos is for a Mac" >&2; exit 1; } ;;
  linux) [ "$(uname -s)" = Linux ] || { echo "package-libs: linux is for a Linux computer" >&2; exit 1; } ;;
  *) echo "usage: tools/package-libs.sh macos|linux" >&2; exit 2 ;;
esac
tools="cmake git curl"
[ "$target" = macos ] && tools="cmake ninja git curl"
for tool in $tools; do
  command -v "$tool" > /dev/null 2>&1 || { echo "package-libs: $tool is not installed" >&2; exit 1; }
done

SDL_VERSION="${SDL_VERSION:-3.4.18}"
SDL_TTF_TAG=release-3.2.2
MIN_MACOS="${MIN_MACOS:-12.0}"
root=$(cd "$(dirname "$0")/.." && pwd)
cache="$root/.cache/package/$target"
lib="$cache/lib"
mkdir -p "$lib"

if [ "$target" = linux ]; then
  [ -f "$lib/libSDL3_ttf.so.0" ] && { echo "$lib"; exit 0; }
  # SDL3 itself is copied by `roci package` from where the loader finds the one the program is linked with; SDL3 and its headers
  # have to be installed here for SDL3_ttf to be built against
  command -v pkg-config > /dev/null 2>&1 && ! pkg-config --exists sdl3 2> /dev/null && { echo "package-libs: SDL3 is not installed (Arch: pacman -S sdl3)" >&2; exit 1; }
  echo "== SDL3_ttf $SDL_TTF_TAG"
  ttf_src="$root/.cache/ios/src/SDL_ttf-$SDL_TTF_TAG"
  if [ ! -d "$ttf_src" ]; then
    ttf_src="$cache/src/SDL_ttf-$SDL_TTF_TAG"
    [ -d "$ttf_src" ] || git clone -q --depth 1 --branch "$SDL_TTF_TAG" --recurse-submodules --shallow-submodules https://github.com/libsdl-org/SDL_ttf "$ttf_src"
  fi
  ttf_build="$cache/ttf-build"
  generator=""
  command -v ninja > /dev/null 2>&1 && generator="-G Ninja"
  # shellcheck disable=SC2086
  cmake -S "$ttf_src" -B "$ttf_build" $generator -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DSDLTTF_VENDORED=ON -DSDLTTF_HARFBUZZ=ON -DSDLTTF_PLUTOSVG=OFF -DSDLTTF_SAMPLES=OFF \
    -DCMAKE_SHARED_LINKER_FLAGS="-static-libstdc++ -static-libgcc" > /dev/null
  cmake --build "$ttf_build" --parallel > /dev/null
  cp -P "$ttf_build"/libSDL3_ttf.so* "$lib/"
  [ -f "$lib/libSDL3_ttf.so.0" ] || { echo "package-libs: SDL3_ttf did not build a libSDL3_ttf.so.0" >&2; exit 1; }
  # nothing but SDL3 and the C library may be left for the app to find
  if readelf -d "$lib/libSDL3_ttf.so.0" | awk '/NEEDED/ {print $5}' | tr -d '[]' | grep -v -e '^libSDL3\.so' -e '^libc\.so' -e '^libm\.so' -e '^ld-linux' -e '^libpthread' -e '^libdl' -e '^librt' > /dev/null; then
    echo "package-libs: libSDL3_ttf depends on something that is not SDL3 or the C library:" >&2
    readelf -d "$lib/libSDL3_ttf.so.0" | grep NEEDED >&2
    exit 1
  fi
  echo "$lib"
  exit 0
fi

[ -f "$lib/libSDL3.0.dylib" ] && [ -f "$lib/libSDL3_ttf.0.dylib" ] && { echo "$lib"; exit 0; }
arch=$(uname -m)

# SDL's release archive, in the folder the phones' build uses
sdl_src="$root/.cache/mobile/SDL3-$SDL_VERSION"
if [ ! -d "$sdl_src" ]; then
  echo "== fetching SDL $SDL_VERSION"
  mkdir -p "$root/.cache/mobile"
  curl -fsSL "https://github.com/libsdl-org/SDL/releases/download/release-$SDL_VERSION/SDL3-$SDL_VERSION.tar.gz" -o "$root/.cache/mobile/SDL3-$SDL_VERSION.tar.gz"
  tar -xzf "$root/.cache/mobile/SDL3-$SDL_VERSION.tar.gz" -C "$root/.cache/mobile"
  rm -f "$root/.cache/mobile/SDL3-$SDL_VERSION.tar.gz"
fi

echo "== SDL $SDL_VERSION"
sdl_build="$cache/sdl-build"
cmake -S "$sdl_src" -B "$sdl_build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES="$arch" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_MACOS" -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF > /dev/null
cmake --build "$sdl_build" > /dev/null
cp -P "$sdl_build"/libSDL3.0.dylib "$sdl_build"/libSDL3.dylib "$lib/"
name=$(otool -D "$lib/libSDL3.0.dylib" | tail -n 1)
[ "$name" = "@rpath/libSDL3.0.dylib" ] || install_name_tool -id "@rpath/libSDL3.0.dylib" "$lib/libSDL3.0.dylib"

echo "== SDL3_ttf $SDL_TTF_TAG"
# the phones' build has fetched it already when it was made there
ttf_src="$root/.cache/ios/src/SDL_ttf-$SDL_TTF_TAG"
if [ ! -d "$ttf_src" ]; then
  ttf_src="$cache/src/SDL_ttf-$SDL_TTF_TAG"
  [ -d "$ttf_src" ] || git clone -q --depth 1 --branch "$SDL_TTF_TAG" --recurse-submodules --shallow-submodules https://github.com/libsdl-org/SDL_ttf "$ttf_src"
fi
ttf_build="$cache/ttf-build"
cmake -S "$ttf_src" -B "$ttf_build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES="$arch" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_MACOS" -DBUILD_SHARED_LIBS=ON -DSDLTTF_VENDORED=ON -DSDLTTF_HARFBUZZ=ON \
  -DSDLTTF_PLUTOSVG=OFF -DSDLTTF_SAMPLES=OFF -DSDL3_DIR="$sdl_build" > /dev/null
cmake --build "$ttf_build" > /dev/null
cp -P "$ttf_build"/libSDL3_ttf*.dylib "$lib/"
name=$(otool -D "$lib/libSDL3_ttf.0.dylib" | tail -n 1)
[ "$name" = "@rpath/libSDL3_ttf.0.dylib" ] || install_name_tool -id "@rpath/libSDL3_ttf.0.dylib" "$lib/libSDL3_ttf.0.dylib"
# nothing but SDL3 and the system may be left for the app to find
if otool -L "$lib/libSDL3_ttf.0.dylib" | tail -n +2 | awk '{print $1}' | grep -v -e '^/System/' -e '^/usr/lib/' -e '^@rpath/libSDL3' > /dev/null; then
  echo "package-libs: libSDL3_ttf depends on something that is not SDL3 or the system:" >&2
  otool -L "$lib/libSDL3_ttf.0.dylib" >&2
  exit 1
fi
echo "$lib"
