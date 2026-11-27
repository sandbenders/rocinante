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
# A library is built when it is missing or when what it is made from changed (tools/stamps.sh): a tag or a build setting
# below, or our own files it is compiled from, so running this again after pulling is cheap and brings everything up to date.
# Each fetched source is kept in a folder named after its tag.
#
#     SDL_ANDROID_LIB=... SDL_ANDROID_SRC=... spikes/mobile/android/libs.sh
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
cache="$root/.cache/android"
src="$cache/src"
lib="$cache/lib"
stamps="$cache/stamps"
. "$root/tools/stamps.sh"

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

# What every library here depends on besides its own sources.
setting="ndk=$NDK_VERSION api=$API_LEVEL"

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
key="$SDL_TTF_TAG $setting sdl=$(basename "$SDL_ANDROID_SRC")"
if ! fresh "$lib/libSDL3_ttf.so" SDL3_ttf "$key"; then
  ttf="$src/SDL_ttf-$SDL_TTF_TAG"
  [ -d "$ttf" ] || git clone -q --depth 1 --branch "$SDL_TTF_TAG" --recurse-submodules --shallow-submodules \
    https://github.com/libsdl-org/SDL_ttf "$ttf"
  rm -rf "$ttf/build"
  android_cmake "$ttf" "$ttf/build" -DSDLTTF_VENDORED=ON -DSDLTTF_HARFBUZZ=ON \
    -DSDLTTF_PLUTOSVG=OFF -DSDLTTF_SAMPLES=OFF -DBUILD_SHARED_LIBS=ON \
    -DSDL3_DIR="$SDL_ANDROID_LIB"
  cp "$ttf/build/libSDL3_ttf.so" "$lib/"
  stamp SDL3_ttf "$key"
fi

echo "== SPIRV-Cross $SPIRV_CROSS_TAG"
key="$SPIRV_CROSS_TAG $setting"
if ! fresh "$lib/libspirv-cross-c-shared.so" SPIRV-Cross "$key"; then
  cross="$src/SPIRV-Cross-$SPIRV_CROSS_TAG"
  clone https://github.com/KhronosGroup/SPIRV-Cross "$SPIRV_CROSS_TAG" "$cross"
  rm -rf "$cross/build"
  android_cmake "$cross" "$cross/build" -DSPIRV_CROSS_SHARED=ON -DSPIRV_CROSS_STATIC=OFF \
    -DSPIRV_CROSS_CLI=OFF -DSPIRV_CROSS_ENABLE_TESTS=OFF
  cp "$cross/build/libspirv-cross-c-shared.so" "$lib/"
  stamp SPIRV-Cross "$key"
fi

echo "== shaderc $SHADERC_TAG"
key="$SHADERC_TAG $setting"
if ! fresh "$lib/libshaderc_shared.so" shaderc "$key"; then
  shaderc="$src/shaderc-$SHADERC_TAG"
  clone https://github.com/google/shaderc "$SHADERC_TAG" "$shaderc"
  # The commits its DEPS file names (its own git-sync-deps is Python).
  deps="$shaderc/DEPS"
  rev() { sed -n "s/.*'$1_revision': *'\([0-9a-f]*\)'.*/\1/p" "$deps"; }
  fetch https://github.com/KhronosGroup/glslang "$(rev glslang)" "$shaderc/third_party/glslang"
  fetch https://github.com/KhronosGroup/SPIRV-Tools "$(rev spirv_tools)" "$shaderc/third_party/spirv-tools"
  fetch https://github.com/KhronosGroup/SPIRV-Headers "$(rev spirv_headers)" "$shaderc/third_party/spirv-headers"
  rm -rf "$shaderc/build"
  android_cmake "$shaderc" "$shaderc/build" -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON \
    -DSHADERC_SKIP_COPYRIGHT_CHECK=ON -DSPIRV_SKIP_EXECUTABLES=ON -DSPIRV_SKIP_TESTS=ON \
    -DENABLE_GLSLANG_BINARIES=OFF -DSHADERC_ENABLE_SHARED_CRT=OFF
  cp "$shaderc/build/libshaderc/libshaderc_shared.so" "$lib/"
  stamp shaderc "$key"
fi

echo "== Dear ImGui $IMGUI_TAG"
# our C wrappers and configuration are compiled in, so a change to them builds it again
key="$IMGUI_TAG $setting wrappers=$(sum_files "$root/vendor/imgui/c") sdl=$(basename "$SDL_ANDROID_SRC")"
if ! fresh "$lib/libroci_ui.a" imgui "$key"; then
  imgui="$src/imgui-$IMGUI_TAG"
  clone https://github.com/ocornut/imgui "$IMGUI_TAG" "$imgui"
  cxx="$ndk/toolchains/llvm/prebuilt/$host/bin/aarch64-linux-android$API_LEVEL-clang++"
  ar="$ndk/toolchains/llvm/prebuilt/$host/bin/llvm-ar"
  c_api="$root/vendor/imgui/c"
  obj="$src/imgui-obj"
  rm -rf "$obj"
  mkdir -p "$obj"
  for s in "$imgui/imgui" "$imgui/imgui_demo" "$imgui/imgui_draw" "$imgui/imgui_tables" \
    "$imgui/imgui_widgets" "$imgui/backends/imgui_impl_sdl3" "$imgui/backends/imgui_impl_sdlgpu3" \
    "$c_api/dcimgui" "$c_api/roci_context" "$c_api/backends/dcimgui_impl_sdl3" "$c_api/backends/dcimgui_impl_sdlgpu3"; do
    "$cxx" -std=c++17 -O2 -fPIC -DIMGUI_USER_CONFIG='"imconfig_roci.h"' -I"$imgui" -I"$imgui/backends" \
      -I"$c_api" -I"$c_api/backends" -I"$SDL_ANDROID_SRC/include" -c "$s.cpp" -o "$obj/$(basename "$s").o"
  done
  rm -f "$lib/libroci_ui.a"
  "$ar" rcs "$lib/libroci_ui.a" "$obj"/*.o
  stamp imgui "$key"
fi

# The sound file decoders: miniaudio's and stb_vorbis, from the vendor folder of the Odin on the PATH, and
# libopus, fetched by tools/fetch-opus.sh. They are built for Android 9 (API level 28), the first with
# AMediaDataSource, which the AAC decoder (MediaCodec) reads a file through. Built again when our C source, the libopus
# version or the Odin whose decoders it compiles changes.
key="$setting c=$(sum_files "$root/vendor/sound/c" "$root/tools/fetch-opus.sh") odin=$(odin version)"
if ! fresh "$lib/libroci_sound.a" sound "$key"; then
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
  stamp sound "$key"
fi

# libcurl and mbedTLS for fetch, built by tools/net-libs.sh (HTTP and HTTPS, static). The system's certificates
# are read from /system/etc/security/cacerts at run time. The scripts name the versions, so a change to them builds it again.
key="$setting net=$(sum_files "$root/tools/fetch-net.sh" "$root/tools/net-libs.sh")"
if ! fresh "$lib/libcurl.a" curl "$key"; then
  ANDROID_HOME="$ANDROID_HOME" NDK_VERSION="$NDK_VERSION" API_LEVEL="$API_LEVEL" "$root/tools/net-libs.sh" android
  cp "$root/.cache/net-android/lib/"lib*.a "$lib/"
  stamp curl "$key"
fi

# Box2D for 2D physics, built by tools/physics-libs.sh (static). The scripts name the version, so a change to them builds it again.
key="$setting physics=$(sum_files "$root/tools/fetch-physics.sh" "$root/tools/physics-libs.sh")"
if ! fresh "$lib/libbox2d.a" box2d "$key"; then
  ANDROID_HOME="$ANDROID_HOME" NDK_VERSION="$NDK_VERSION" API_LEVEL="$API_LEVEL" "$root/tools/physics-libs.sh" android
  cp "$root/.cache/physics-android/lib/libbox2d.a" "$lib/"
  stamp box2d "$key"
fi

# The C++ runtime the libraries above were built against, linked statically into libmain.so.
cp "$ndk/toolchains/llvm/prebuilt/$host/sysroot/usr/lib/aarch64-linux-android/libc++_static.a" "$lib/"
cp "$ndk/toolchains/llvm/prebuilt/$host/sysroot/usr/lib/aarch64-linux-android/libc++abi.a" "$lib/"
# Without their symbols the shared libraries are a tenth of the size (shaderc: 149 MB to 9 MB).
"$ndk/toolchains/llvm/prebuilt/$host/bin/llvm-strip" --strip-unneeded "$lib"/*.so
echo "built into $lib"
