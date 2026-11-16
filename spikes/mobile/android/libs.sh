#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Builds, for arm64 Android with the NDK, the libraries roci links beside SDL3:
# SDL3_ttf (with its own FreeType and HarfBuzz), shaderc, SPIRV-Cross, Dear ImGui
# with its C wrappers and the sound file decoders, into .cache/android/lib. Written for the phone smoke test;
# `roci package android` will ship these prebuilt.
#
# Needs git, cmake, ninja and SDL3 already built for Android (SDL_ANDROID_LIB, the
# folder with libSDL3.so, and SDL_ANDROID_SRC, SDL's source, for its headers).
# Optional: ANDROID_HOME, NDK_VERSION, API_LEVEL.
#
#     SDL_ANDROID_LIB=... SDL_ANDROID_SRC=... spikes/mobile/android/libs.sh
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
cache="$root/.cache/android"
src="$cache/src"
lib="$cache/lib"

case "$(uname -s)" in
  Darwin) default_home="$HOME/Library/Android/sdk"; host=darwin-x86_64 ;;
  *) default_home="$HOME/Android/Sdk"; host=linux-x86_64 ;;
esac
ANDROID_HOME="${ANDROID_HOME:-$default_home}"
NDK_VERSION="${NDK_VERSION:-29.0.14206865}"
API_LEVEL="${API_LEVEL:-28}"
: "${SDL_ANDROID_LIB:?set SDL_ANDROID_LIB to the folder with libSDL3.so}"
: "${SDL_ANDROID_SRC:?set SDL_ANDROID_SRC to the folder with the SDL source}"
ndk="$ANDROID_HOME/ndk/$NDK_VERSION"

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

android_cmake() { # source build [options...]
  s="$1"; b="$2"; shift 2
  cmake -S "$s" -B "$b" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM="android-$API_LEVEL" -DANDROID_STL=c++_static "$@" > /dev/null
  cmake --build "$b" > /dev/null
}

echo "== SDL3_ttf $SDL_TTF_TAG"
if [ ! -f "$lib/libSDL3_ttf.so" ]; then
  [ -d "$src/SDL_ttf" ] || git clone -q --depth 1 --branch "$SDL_TTF_TAG" --recurse-submodules --shallow-submodules \
    https://github.com/libsdl-org/SDL_ttf "$src/SDL_ttf"
  android_cmake "$src/SDL_ttf" "$src/SDL_ttf/build" -DSDLTTF_VENDORED=ON -DSDLTTF_HARFBUZZ=ON \
    -DSDLTTF_PLUTOSVG=OFF -DSDLTTF_SAMPLES=OFF -DBUILD_SHARED_LIBS=ON \
    -DSDL3_DIR="$SDL_ANDROID_LIB"
  cp "$src/SDL_ttf/build/libSDL3_ttf.so" "$lib/"
fi

echo "== SPIRV-Cross $SPIRV_CROSS_TAG"
if [ ! -f "$lib/libspirv-cross-c-shared.so" ]; then
  clone https://github.com/KhronosGroup/SPIRV-Cross "$SPIRV_CROSS_TAG" "$src/SPIRV-Cross"
  android_cmake "$src/SPIRV-Cross" "$src/SPIRV-Cross/build" -DSPIRV_CROSS_SHARED=ON -DSPIRV_CROSS_STATIC=OFF \
    -DSPIRV_CROSS_CLI=OFF -DSPIRV_CROSS_ENABLE_TESTS=OFF
  cp "$src/SPIRV-Cross/build/libspirv-cross-c-shared.so" "$lib/"
fi

echo "== shaderc $SHADERC_TAG"
if [ ! -f "$lib/libshaderc_shared.so" ]; then
  clone https://github.com/google/shaderc "$SHADERC_TAG" "$src/shaderc"
  # The commits its DEPS file names (its own git-sync-deps is Python).
  deps="$src/shaderc/DEPS"
  rev() { sed -n "s/.*'$1_revision': *'\([0-9a-f]*\)'.*/\1/p" "$deps"; }
  fetch https://github.com/KhronosGroup/glslang "$(rev glslang)" "$src/shaderc/third_party/glslang"
  fetch https://github.com/KhronosGroup/SPIRV-Tools "$(rev spirv_tools)" "$src/shaderc/third_party/spirv-tools"
  fetch https://github.com/KhronosGroup/SPIRV-Headers "$(rev spirv_headers)" "$src/shaderc/third_party/spirv-headers"
  android_cmake "$src/shaderc" "$src/shaderc/build" -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON \
    -DSHADERC_SKIP_COPYRIGHT_CHECK=ON -DSPIRV_SKIP_EXECUTABLES=ON -DSPIRV_SKIP_TESTS=ON \
    -DENABLE_GLSLANG_BINARIES=OFF -DSHADERC_ENABLE_SHARED_CRT=OFF
  cp "$src/shaderc/build/libshaderc/libshaderc_shared.so" "$lib/"
fi

echo "== Dear ImGui $IMGUI_TAG"
if [ ! -f "$lib/libroci_ui.a" ]; then
  clone https://github.com/ocornut/imgui "$IMGUI_TAG" "$src/imgui"
  cxx="$ndk/toolchains/llvm/prebuilt/$host/bin/aarch64-linux-android$API_LEVEL-clang++"
  ar="$ndk/toolchains/llvm/prebuilt/$host/bin/llvm-ar"
  c_api="$root/vendor/imgui/c"
  obj="$src/imgui-obj"
  mkdir -p "$obj"
  for s in "$src/imgui/imgui" "$src/imgui/imgui_demo" "$src/imgui/imgui_draw" "$src/imgui/imgui_tables" \
    "$src/imgui/imgui_widgets" "$src/imgui/backends/imgui_impl_sdl3" "$src/imgui/backends/imgui_impl_sdlgpu3" \
    "$c_api/dcimgui" "$c_api/roci_context" "$c_api/backends/dcimgui_impl_sdl3" "$c_api/backends/dcimgui_impl_sdlgpu3"; do
    "$cxx" -std=c++17 -O2 -fPIC -DIMGUI_USER_CONFIG='"imconfig_roci.h"' -I"$src/imgui" -I"$src/imgui/backends" \
      -I"$c_api" -I"$c_api/backends" -I"$SDL_ANDROID_SRC/include" -c "$s.cpp" -o "$obj/$(basename "$s").o"
  done
  "$ar" rcs "$lib/libroci_ui.a" "$obj"/*.o
fi

# The sound file decoders: miniaudio's and stb_vorbis, from the vendor folder of the Odin on the PATH, and
# libopus, fetched by tools/fetch-opus.sh. They are built for Android 9 (API level 28), the first with
# AMediaDataSource, which the AAC decoder (MediaCodec) reads a file through.
if [ ! -f "$lib/libroci_sound.a" ]; then
  cc="$ndk/toolchains/llvm/prebuilt/$host/bin/aarch64-linux-android28-clang"
  ar="$ndk/toolchains/llvm/prebuilt/$host/bin/llvm-ar"
  odin_root="$(odin root)"
  opus="$("$root/tools/fetch-opus.sh")"
  "$cc" -O2 -fPIC -fvisibility=hidden -I"$odin_root/vendor/miniaudio/src" -I"$odin_root/vendor/stb/src" -I"$opus/include" \
    -c "$root/vendor/sound/c/roci_sound.c" -o "$src/roci_sound.o"
  objs="$src/roci_sound.o"
  while read -r file; do
    case "$file" in "#"* | "") continue ;; esac
    obj="$src/opus_$(basename "$file" .c).o"
    "$cc" -c -O2 -fPIC -fvisibility=hidden -DOPUS_BUILD -DUSE_ALLOCA -DHAVE_LRINTF -DPACKAGE_VERSION='"1.6.1"' \
      -I"$opus/include" -I"$opus/celt" -I"$opus/silk" -I"$opus" -o "$obj" "$opus/$file"
    objs="$objs $obj"
  done < "$root/vendor/sound/c/opus_files.txt"
  rm -f "$lib/libroci_sound.a"
  "$ar" rcs "$lib/libroci_sound.a" $objs
fi

# The C++ runtime the libraries above were built against, linked statically into libmain.so.
cp "$ndk/toolchains/llvm/prebuilt/$host/sysroot/usr/lib/aarch64-linux-android/libc++_static.a" "$lib/"
cp "$ndk/toolchains/llvm/prebuilt/$host/sysroot/usr/lib/aarch64-linux-android/libc++abi.a" "$lib/"
# Without their symbols the shared libraries are a tenth of the size (shaderc: 149 MB to 9 MB).
"$ndk/toolchains/llvm/prebuilt/$host/bin/llvm-strip" --strip-unneeded "$lib"/*.so
echo "built into $lib"
