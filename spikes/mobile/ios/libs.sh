#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Builds, for an iPhone (arm64), the static libraries roci links beside SDL3: SDL3_ttf (with its
# own FreeType and HarfBuzz), shaderc, SPIRV-Cross, Dear ImGui with its C wrappers and the sound
# file decoders, into .cache/ios/lib. Written for the phone smoke test; `roci package ios` will ship
# these prebuilt.
#
# Needs a Mac with Xcode, git, cmake, ninja, and SDL3 already built static for the iPhone
# (SDL_IOS_LIB, the folder with libSDL3.a and SDL3Config.cmake; SDL_IOS_SRC, SDL's source, for
# its headers).
#
#     SDL_IOS_LIB=... SDL_IOS_SRC=... spikes/mobile/ios/libs.sh
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
cache="$root/.cache/ios"
src="$cache/src"
lib="$cache/lib"
: "${SDL_IOS_LIB:?set SDL_IOS_LIB to the folder with libSDL3.a for the iPhone}"
: "${SDL_IOS_SRC:?set SDL_IOS_SRC to the folder with the SDL source}"
MIN_IOS="${MIN_IOS:-15.0}"
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"

# The versions the desktop builds use.
SDL_TTF_TAG=release-3.2.2
SHADERC_TAG=v2026.4
SPIRV_CROSS_TAG=vulkan-sdk-1.4.363.0
IMGUI_TAG=v1.93.0

mkdir -p "$src" "$lib"

# One commit of a repository, with no history.
fetch() { # url commit-or-tag folder
  [ -d "$3" ] && return 0
  git init -q "$3"
  git -C "$3" fetch -q --depth 1 "$1" "$2"
  git -C "$3" checkout -q FETCH_HEAD
}
clone() { # url tag folder
  [ -d "$3" ] || git clone -q --depth 1 --branch "$2" "$1" "$3"
}

ios_cmake() { # source build [options...]
  s="$1"; b="$2"; shift 2
  cmake -S "$s" -B "$b" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_IOS" \
    -DBUILD_SHARED_LIBS=OFF "$@" > /dev/null
  cmake --build "$b" > /dev/null
}

echo "== SDL3_ttf $SDL_TTF_TAG"
if [ ! -f "$lib/libSDL3_ttf.a" ]; then
  [ -d "$src/SDL_ttf" ] || git clone -q --depth 1 --branch "$SDL_TTF_TAG" --recurse-submodules --shallow-submodules \
    https://github.com/libsdl-org/SDL_ttf "$src/SDL_ttf"
  ios_cmake "$src/SDL_ttf" "$src/SDL_ttf/build-ios" -DSDLTTF_VENDORED=ON -DSDLTTF_HARFBUZZ=ON \
    -DSDLTTF_PLUTOSVG=OFF -DSDLTTF_SAMPLES=OFF -DSDL3_DIR="$SDL_IOS_LIB"
  cp "$src/SDL_ttf/build-ios/libSDL3_ttf.a" "$lib/"
  # FreeType and HarfBuzz are built beside it, as static libraries of their own.
  find "$src/SDL_ttf/build-ios" -name 'libfreetype*.a' -o -name 'libharfbuzz*.a' | while read -r f; do cp "$f" "$lib/"; done
fi

echo "== SPIRV-Cross $SPIRV_CROSS_TAG"
if [ ! -f "$lib/libspirv-cross-c.a" ]; then
  clone https://github.com/KhronosGroup/SPIRV-Cross "$SPIRV_CROSS_TAG" "$src/SPIRV-Cross"
  ios_cmake "$src/SPIRV-Cross" "$src/SPIRV-Cross/build-ios" -DSPIRV_CROSS_SHARED=OFF -DSPIRV_CROSS_STATIC=ON \
    -DSPIRV_CROSS_CLI=OFF -DSPIRV_CROSS_ENABLE_TESTS=OFF
  cp "$src"/SPIRV-Cross/build-ios/libspirv-cross-*.a "$lib/"
fi

echo "== shaderc $SHADERC_TAG"
if [ ! -f "$lib/libshaderc_combined.a" ]; then
  clone https://github.com/google/shaderc "$SHADERC_TAG" "$src/shaderc"
  # The commits its DEPS file names (its own git-sync-deps is Python).
  deps="$src/shaderc/DEPS"
  rev() { sed -n "s/.*'$1_revision': *'\([0-9a-f]*\)'.*/\1/p" "$deps"; }
  fetch https://github.com/KhronosGroup/glslang "$(rev glslang)" "$src/shaderc/third_party/glslang"
  fetch https://github.com/KhronosGroup/SPIRV-Tools "$(rev spirv_tools)" "$src/shaderc/third_party/spirv-tools"
  fetch https://github.com/KhronosGroup/SPIRV-Headers "$(rev spirv_headers)" "$src/shaderc/third_party/spirv-headers"
  ios_cmake "$src/shaderc" "$src/shaderc/build-ios" -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON \
    -DSHADERC_SKIP_COPYRIGHT_CHECK=ON -DSPIRV_SKIP_EXECUTABLES=ON -DSPIRV_SKIP_TESTS=ON \
    -DENABLE_GLSLANG_BINARIES=OFF -DSHADERC_ENABLE_SHARED_CRT=OFF
  cp "$src/shaderc/build-ios/libshaderc/libshaderc_combined.a" "$lib/"
fi

echo "== Dear ImGui $IMGUI_TAG"
if [ ! -f "$lib/libroci_ui.a" ]; then
  clone https://github.com/ocornut/imgui "$IMGUI_TAG" "$src/imgui"
  c_api="$root/vendor/imgui/c"
  obj="$src/imgui-obj"
  mkdir -p "$obj"
  for s in "$src/imgui/imgui" "$src/imgui/imgui_demo" "$src/imgui/imgui_draw" "$src/imgui/imgui_tables" \
    "$src/imgui/imgui_widgets" "$src/imgui/backends/imgui_impl_sdl3" "$src/imgui/backends/imgui_impl_sdlgpu3" \
    "$c_api/dcimgui" "$c_api/roci_context" "$c_api/backends/dcimgui_impl_sdl3" "$c_api/backends/dcimgui_impl_sdlgpu3"; do
    xcrun --sdk iphoneos clang++ -target "arm64-apple-ios$MIN_IOS" -isysroot "$sdk" -std=c++17 -O2 \
      -DIMGUI_USER_CONFIG='"imconfig_roci.h"' -I"$src/imgui" -I"$src/imgui/backends" \
      -I"$c_api" -I"$c_api/backends" -I"$SDL_IOS_SRC/include" -c "$s.cpp" -o "$obj/$(basename "$s").o"
  done
  ar rcs "$lib/libroci_ui.a" "$obj"/*.o
fi

# The sound file decoders: miniaudio's and stb_vorbis, from the vendor folder of the Odin on the PATH.
if [ ! -f "$lib/libroci_sound.a" ]; then
  odin_root="$(odin root)"
  xcrun --sdk iphoneos clang -target "arm64-apple-ios$MIN_IOS" -isysroot "$sdk" -O2 -fvisibility=hidden \
    -I"$odin_root/vendor/miniaudio/src" -I"$odin_root/vendor/stb/src" \
    -c "$root/vendor/sound/c/roci_sound.c" -o "$src/roci_sound.o"
  ar rcs "$lib/libroci_sound.a" "$src/roci_sound.o"
fi
echo "built into $lib"
