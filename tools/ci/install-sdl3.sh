#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Builds and installs the latest stable SDL3 release from source, for the
# pipelines that have no recent enough package (Ubuntu 24.04 has no SDL3 at all;
# CLAUDE.md section 11). Decided 2026-10-27: always the latest release, cached
# by the workflow under a key that holds the release's tag, so a new release
# rebuilds and an unchanged one costs nothing.
#
#   tools/ci/install-sdl3.sh --latest             print the latest release's tag
#   tools/ci/install-sdl3.sh <prefix> [<tag>]     build and install it into <prefix>
#                                                 (the latest if no tag is given)
#
# Afterwards point the compiler and the loader at it:
#   export LIBRARY_PATH="<prefix>/lib:$LIBRARY_PATH"
#   export LD_LIBRARY_PATH="<prefix>/lib:$LD_LIBRARY_PATH"
#   export PKG_CONFIG_PATH="<prefix>/lib/pkgconfig:$PKG_CONFIG_PATH"
# Needs curl, tar, cmake, ninja and a C compiler; the video and audio libraries SDL
# should use (X11, Wayland, ALSA and so on) are the workflow's job to install.
set -eu

# SDL tags its stable releases "release-3.x.y" and its previews "prerelease-...".
# Only 3.x is looked for, so a future SDL 4 never changes what the pipelines build.
latest_tag() {
  auth=""
  [ -n "${GITHUB_TOKEN:-}" ] && auth="Authorization: Bearer $GITHUB_TOKEN"
  tag="$(curl -fsSL ${auth:+-H "$auth"} "https://api.github.com/repos/libsdl-org/SDL/releases?per_page=30" \
    | sed -n 's/.*"tag_name": *"\(release-3\.[0-9.]*\)".*/\1/p' | head -n 1)"
  [ -n "$tag" ] || { echo "install-sdl3: no stable SDL3 release found" >&2; exit 1; }
  echo "$tag"
}

if [ "${1:-}" = "--latest" ]; then
  latest_tag
  exit 0
fi

prefix="${1:?usage: install-sdl3.sh <prefix> [<tag>] | --latest}"
tag="${2:-$(latest_tag)}"
marker="$prefix/.sdl3-$tag"

if [ -f "$marker" ]; then
  echo "install-sdl3: $tag is already in $prefix"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
echo "install-sdl3: building $tag into $prefix"
curl -fsSL "https://github.com/libsdl-org/SDL/archive/refs/tags/$tag.tar.gz" | tar -xzf - -C "$work" --strip-components=1
cmake -S "$work" -B "$work/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$prefix" \
  -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF -DSDL_INSTALL_TESTS=OFF
cmake --build "$work/build"
# A cached older release may be in $prefix; start clean so nothing of it lingers.
rm -rf "$prefix"
cmake --install "$work/build"
touch "$marker"
echo "install-sdl3: done, $tag"
