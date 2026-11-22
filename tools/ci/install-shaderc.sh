#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Builds shaderc's shared library (libshaderc_shared.so.1) from source at a pinned release, with glslang and SPIRV-Tools built
# into it, for the Linux images whose own shaderc cannot be linked: Debian 12's libshaderc.so.1 (2023.2) leaves glslang's
# symbols undefined without naming the library that has them (found 2026-11-22). The release is the one Arch carried when it was
# pinned. glslang, SPIRV-Tools and SPIRV-Headers are fetched at the revisions shaderc's DEPS file names, read here with sed
# instead of shaderc's own Python script; the libraries only its tests use (abseil, effcee, re2, googletest) are left out.
#
#   tools/ci/install-shaderc.sh <prefix>      build and install into <prefix>/lib
#
# Needs curl, tar, sed, cmake, ninja and a C++ compiler.
set -eu

TAG="v2026.4"
prefix="${1:?usage: install-shaderc.sh <prefix>}"
marker="$prefix/.shaderc-$TAG"
if [ -f "$marker" ]; then
  echo "install-shaderc: $TAG is already in $prefix"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
echo "install-shaderc: building $TAG into $prefix"
src="$work/shaderc"
mkdir "$src"
curl -fsSL "https://github.com/google/shaderc/archive/refs/tags/$TAG.tar.gz" | tar -xzf - -C "$src" --strip-components=1

# one dependency: its revision from DEPS (a line such as `'glslang_revision': 'e1b5...',`), fetched into third_party
fetch() {
  revision="$(sed -n "s/.*'$1_revision': *'\([0-9a-f]*\)'.*/\1/p" "$src/DEPS")"
  [ -n "$revision" ] || { echo "install-shaderc: DEPS names no $1_revision" >&2; exit 1; }
  mkdir -p "$src/third_party/$3"
  curl -fsSL "https://github.com/KhronosGroup/$2/archive/$revision.tar.gz" | tar -xzf - -C "$src/third_party/$3" --strip-components=1
}
fetch glslang glslang glslang
fetch spirv_tools SPIRV-Tools spirv-tools
fetch spirv_headers SPIRV-Headers spirv-headers

cmake -S "$src" -B "$src/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_INSTALL_LIBDIR=lib \
  -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON -DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
  -DSPIRV_SKIP_TESTS=ON -DSPIRV_SKIP_EXECUTABLES=ON -DSPIRV_HEADERS_SKIP_EXAMPLES=ON -DENABLE_GLSLANG_BINARIES=OFF
cmake --build "$src/build" --target shaderc_shared
mkdir -p "$prefix/lib" "$prefix/include"
rm -f "$prefix"/lib/libshaderc_shared.so*
cp -P "$src"/build/libshaderc/libshaderc_shared.so* "$prefix/lib/"
cp -R "$src/libshaderc/include/shaderc" "$prefix/include/"
# what a packaged app carries may ask the computer for the C and C++ runtimes only
if readelf -d "$prefix/lib/libshaderc_shared.so.1" | awk '/NEEDED/ {print $5}' | tr -d '[]' \
  | grep -v -e '^libstdc++\.so' -e '^libgcc_s\.so' -e '^libc\.so' -e '^libm\.so' -e '^ld-linux' > /dev/null; then
  echo "install-shaderc: libshaderc_shared.so.1 depends on more than the C and C++ runtimes:" >&2
  readelf -d "$prefix/lib/libshaderc_shared.so.1" | grep NEEDED >&2
  exit 1
fi
touch "$marker"
echo "install-shaderc: done"
