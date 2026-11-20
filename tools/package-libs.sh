#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Builds the libraries a packaged app carries, for this computer, into .cache/package/<system>/lib (ignored by git):
#   libSDL3.0.dylib       SDL3 as a shared library whose install name is @rpath/libSDL3.0.dylib, so an app finds it in
#                         its own Frameworks folder (SDL is Zlib)
#   libSDL3_ttf.0.dylib   SDL3_ttf the same way, with the FreeType and HarfBuzz it is built with inside it (the FreeType
#                         Project Licence and the old MIT licence, both permissive)
# A sketch is linked against the copies on the computer (Homebrew's), and `roci package` points the program at these
# instead, because Homebrew's SDL3_ttf pulls in HarfBuzz's glib, which is LGPL and may not be in a packaged sketch.
# Needs cmake and ninja, and Xcode's command-line tools, git and curl.
#
#     tools/package-libs.sh macos
set -eu

target="${1:-}"
case "$target" in
  macos) ;;
  *) echo "usage: tools/package-libs.sh macos" >&2; exit 2 ;;
esac
[ "$(uname -s)" = Darwin ] || { echo "package-libs: this is for a Mac" >&2; exit 1; }
for tool in cmake ninja git curl; do
  command -v "$tool" > /dev/null 2>&1 || { echo "package-libs: $tool is not installed" >&2; exit 1; }
done

SDL_VERSION="${SDL_VERSION:-3.4.18}"
SDL_TTF_TAG=release-3.2.2
MIN_MACOS="${MIN_MACOS:-12.0}"
root=$(cd "$(dirname "$0")/.." && pwd)
cache="$root/.cache/package/$target"
lib="$cache/lib"
mkdir -p "$lib"
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
ttf_src="$root/.cache/ios/src/SDL_ttf"
if [ ! -d "$ttf_src" ]; then
  ttf_src="$cache/src/SDL_ttf"
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
