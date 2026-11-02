#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Builds and installs the latest stable SDL3 and SDL3_ttf releases from source, for the
# pipelines that have no recent enough package (Ubuntu 24.04 has no SDL3 at all).
# Decided 2026-10-27: always the latest release, cached
# by the workflow under a key that holds the release's tag, so a new release
# rebuilds and an unchanged one costs nothing. SDL3_ttf joined on 2026-11-02, for text.
#
#   tools/ci/install-sdl3.sh --latest             print the latest releases' tags, SDL3's and
#                                                 SDL3_ttf's, joined by +
#   tools/ci/install-sdl3.sh <prefix> [<tags>]    build and install both into <prefix>
#                                                 (the latest if no tags are given)
#
# Afterwards point the compiler and the loader at it:
#   export LIBRARY_PATH="<prefix>/lib:$LIBRARY_PATH"
#   export LD_LIBRARY_PATH="<prefix>/lib:$LD_LIBRARY_PATH"
#   export PKG_CONFIG_PATH="<prefix>/lib/pkgconfig:$PKG_CONFIG_PATH"
# Needs curl, tar, cmake, ninja and a C compiler, and the FreeType and HarfBuzz
# development packages SDL3_ttf uses; the video and audio libraries SDL should use
# (X11, Wayland, ALSA and so on) are the workflow's job to install.
set -eu

# SDL tags its stable releases "release-3.x.y" and its previews "prerelease-...".
# Only 3.x is looked for, so a future SDL 4 never changes what the pipelines build.
# $1 is the repository: SDL or SDL_ttf.
latest_tag() {
  auth=""
  [ -n "${GITHUB_TOKEN:-}" ] && auth="Authorization: Bearer $GITHUB_TOKEN"
  tag="$(curl -fsSL ${auth:+-H "$auth"} "https://api.github.com/repos/libsdl-org/$1/releases?per_page=30" \
    | sed -n 's/.*"tag_name": *"\(release-3\.[0-9.]*\)".*/\1/p' | head -n 1)"
  [ -n "$tag" ] || { echo "install-sdl3: no stable $1 release found" >&2; exit 1; }
  echo "$tag"
}

if [ "${1:-}" = "--latest" ]; then
  echo "$(latest_tag SDL)+$(latest_tag SDL_ttf)"
  exit 0
fi

prefix="${1:?usage: install-sdl3.sh <prefix> [<sdl tag>+<sdl_ttf tag>] | --latest}"
tags="${2:-$(latest_tag SDL)+$(latest_tag SDL_ttf)}"
tag="${tags%%+*}"
ttf_tag="${tags#*+}"
marker="$prefix/.sdl3-$tag-ttf-$ttf_tag"

if [ -f "$marker" ]; then
  echo "install-sdl3: $tag and $ttf_tag are already in $prefix"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
echo "install-sdl3: building $tag and $ttf_tag into $prefix"
mkdir "$work/sdl" "$work/ttf"
curl -fsSL "https://github.com/libsdl-org/SDL/archive/refs/tags/$tag.tar.gz" | tar -xzf - -C "$work/sdl" --strip-components=1
cmake -S "$work/sdl" -B "$work/sdl/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$prefix" \
  -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF -DSDL_INSTALL_TESTS=OFF
cmake --build "$work/sdl/build"
# A cached older release may be in $prefix; start clean so nothing of it lingers.
rm -rf "$prefix"
cmake --install "$work/sdl/build"

# SDL3_ttf uses the system's FreeType and HarfBuzz, and the SDL3 just installed.
curl -fsSL "https://github.com/libsdl-org/SDL_ttf/archive/refs/tags/$ttf_tag.tar.gz" | tar -xzf - -C "$work/ttf" --strip-components=1
cmake -S "$work/ttf" -B "$work/ttf/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$prefix" \
  -DCMAKE_PREFIX_PATH="$prefix" \
  -DSDLTTF_VENDORED=OFF -DSDLTTF_STRICT=ON -DSDLTTF_SAMPLES=OFF -DSDLTTF_PLUTOSVG=OFF
cmake --build "$work/ttf/build"
cmake --install "$work/ttf/build"
touch "$marker"
echo "install-sdl3: done, $tag and $ttf_tag"
