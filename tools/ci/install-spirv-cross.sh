#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Builds and installs SPIRV-Cross's C library (libspirv-cross-c-shared) from source at a pinned
# release, for the pipelines whose package is too old: Ubuntu 24.04's lacks the functions rocinante's
# Metal translation calls (`spvc_msl_resource_binding_init_2`), and the bindings link them on every
# system. The tag is the one Homebrew and Arch carried when it was pinned; the workflow caches the
# build under a key that holds it, so changing it rebuilds and leaving it costs nothing.
#
#   tools/ci/install-spirv-cross.sh <prefix>      build and install into <prefix>
#
# Afterwards point the compiler and the loader at it:
#   export LIBRARY_PATH="<prefix>/lib:$LIBRARY_PATH"
#   export LD_LIBRARY_PATH="<prefix>/lib:$LD_LIBRARY_PATH"
# Needs curl, tar, cmake, ninja and a C++ compiler.
set -eu

TAG="vulkan-sdk-1.4.363.0"

if [ "${1:-}" = "--tag" ]; then
  echo "$TAG"
  exit 0
fi

prefix="${1:?usage: install-spirv-cross.sh <prefix> | --tag}"
marker="$prefix/.spirv-cross-$TAG"

if [ -f "$marker" ]; then
  echo "install-spirv-cross: $TAG is already in $prefix"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
echo "install-spirv-cross: building $TAG into $prefix"
mkdir "$work/src"
curl -fsSL "https://github.com/KhronosGroup/SPIRV-Cross/archive/refs/tags/$TAG.tar.gz" | tar -xzf - -C "$work/src" --strip-components=1
cmake -S "$work/src" -B "$work/src/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$prefix" \
  -DSPIRV_CROSS_SHARED=ON -DSPIRV_CROSS_STATIC=OFF -DSPIRV_CROSS_CLI=OFF \
  -DSPIRV_CROSS_ENABLE_TESTS=OFF -DSPIRV_CROSS_FORCE_PIC=ON
cmake --build "$work/src/build"
cmake --install "$work/src/build"
touch "$marker"
echo "install-spirv-cross: done"
