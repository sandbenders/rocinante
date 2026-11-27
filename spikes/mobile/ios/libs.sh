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
# A library is built when it is missing or when what it is made from changed (tools/stamps.sh): a tag or a build setting
# below, or our own files it is compiled from, so running this again after pulling is cheap and brings everything up to date.
# Each fetched source is kept in a folder named after its tag.
#
#     SDL_IOS_LIB=... SDL_IOS_SRC=... spikes/mobile/ios/libs.sh
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
cache="$root/.cache/ios"
src="$cache/src"
lib="$cache/lib"
stamps="$cache/stamps"
. "$root/tools/stamps.sh"
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

# What every library here depends on besides its own sources.
setting="ios=$MIN_IOS"

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
key="$SDL_TTF_TAG $setting sdl=$(basename "$SDL_IOS_SRC")"
if ! fresh "$lib/libSDL3_ttf.a" SDL3_ttf "$key"; then
  ttf="$src/SDL_ttf-$SDL_TTF_TAG"
  [ -d "$ttf" ] || git clone -q --depth 1 --branch "$SDL_TTF_TAG" --recurse-submodules --shallow-submodules \
    https://github.com/libsdl-org/SDL_ttf "$ttf"
  rm -rf "$ttf/build-ios"
  ios_cmake "$ttf" "$ttf/build-ios" -DSDLTTF_VENDORED=ON -DSDLTTF_HARFBUZZ=ON \
    -DSDLTTF_PLUTOSVG=OFF -DSDLTTF_SAMPLES=OFF -DSDL3_DIR="$SDL_IOS_LIB"
  cp "$ttf/build-ios/libSDL3_ttf.a" "$lib/"
  # FreeType and HarfBuzz are built beside it, as static libraries of their own.
  rm -f "$lib"/libfreetype*.a "$lib"/libharfbuzz*.a
  find "$ttf/build-ios" -name 'libfreetype*.a' -o -name 'libharfbuzz*.a' | while read -r f; do cp "$f" "$lib/"; done
  stamp SDL3_ttf "$key"
fi

echo "== SPIRV-Cross $SPIRV_CROSS_TAG"
key="$SPIRV_CROSS_TAG $setting"
if ! fresh "$lib/libspirv-cross-c.a" SPIRV-Cross "$key"; then
  cross="$src/SPIRV-Cross-$SPIRV_CROSS_TAG"
  clone https://github.com/KhronosGroup/SPIRV-Cross "$SPIRV_CROSS_TAG" "$cross"
  rm -rf "$cross/build-ios"
  ios_cmake "$cross" "$cross/build-ios" -DSPIRV_CROSS_SHARED=OFF -DSPIRV_CROSS_STATIC=ON \
    -DSPIRV_CROSS_CLI=OFF -DSPIRV_CROSS_ENABLE_TESTS=OFF
  rm -f "$lib"/libspirv-cross-*.a
  cp "$cross"/build-ios/libspirv-cross-*.a "$lib/"
  stamp SPIRV-Cross "$key"
fi

echo "== shaderc $SHADERC_TAG"
key="$SHADERC_TAG $setting"
if ! fresh "$lib/libshaderc_combined.a" shaderc "$key"; then
  shaderc="$src/shaderc-$SHADERC_TAG"
  clone https://github.com/google/shaderc "$SHADERC_TAG" "$shaderc"
  # The commits its DEPS file names (its own git-sync-deps is Python).
  deps="$shaderc/DEPS"
  rev() { sed -n "s/.*'$1_revision': *'\([0-9a-f]*\)'.*/\1/p" "$deps"; }
  fetch https://github.com/KhronosGroup/glslang "$(rev glslang)" "$shaderc/third_party/glslang"
  fetch https://github.com/KhronosGroup/SPIRV-Tools "$(rev spirv_tools)" "$shaderc/third_party/spirv-tools"
  fetch https://github.com/KhronosGroup/SPIRV-Headers "$(rev spirv_headers)" "$shaderc/third_party/spirv-headers"
  rm -rf "$shaderc/build-ios"
  ios_cmake "$shaderc" "$shaderc/build-ios" -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON \
    -DSHADERC_SKIP_COPYRIGHT_CHECK=ON -DSPIRV_SKIP_EXECUTABLES=ON -DSPIRV_SKIP_TESTS=ON \
    -DENABLE_GLSLANG_BINARIES=OFF -DSHADERC_ENABLE_SHARED_CRT=OFF
  cp "$shaderc/build-ios/libshaderc/libshaderc_combined.a" "$lib/"
  stamp shaderc "$key"
fi

echo "== Dear ImGui $IMGUI_TAG"
# our C wrappers and configuration are compiled in, so a change to them builds it again
key="$IMGUI_TAG $setting wrappers=$(sum_files "$root/vendor/imgui/c") sdl=$(basename "$SDL_IOS_SRC")"
if ! fresh "$lib/libroci_ui.a" imgui "$key"; then
  imgui="$src/imgui-$IMGUI_TAG"
  clone https://github.com/ocornut/imgui "$IMGUI_TAG" "$imgui"
  c_api="$root/vendor/imgui/c"
  obj="$src/imgui-obj"
  rm -rf "$obj"
  mkdir -p "$obj"
  for s in "$imgui/imgui" "$imgui/imgui_demo" "$imgui/imgui_draw" "$imgui/imgui_tables" \
    "$imgui/imgui_widgets" "$imgui/backends/imgui_impl_sdl3" "$imgui/backends/imgui_impl_sdlgpu3" \
    "$c_api/dcimgui" "$c_api/roci_context" "$c_api/backends/dcimgui_impl_sdl3" "$c_api/backends/dcimgui_impl_sdlgpu3"; do
    xcrun --sdk iphoneos clang++ -target "arm64-apple-ios$MIN_IOS" -isysroot "$sdk" -std=c++17 -O2 \
      -DIMGUI_USER_CONFIG='"imconfig_roci.h"' -I"$imgui" -I"$imgui/backends" \
      -I"$c_api" -I"$c_api/backends" -I"$SDL_IOS_SRC/include" -c "$s.cpp" -o "$obj/$(basename "$s").o"
  done
  rm -f "$lib/libroci_ui.a"
  ar rcs "$lib/libroci_ui.a" "$obj"/*.o
  stamp imgui "$key"
fi

# The sound file decoders: miniaudio's and stb_vorbis, from the vendor folder of the Odin on the PATH, and
# libopus, fetched by tools/fetch-opus.sh. AAC is read by AudioToolbox, which is part of iOS. Built again when our C
# source, the libopus version or the Odin whose decoders it compiles changes.
key="$setting c=$(sum_files "$root/vendor/sound/c" "$root/tools/fetch-opus.sh") odin=$(odin version)"
if ! fresh "$lib/libroci_sound.a" sound "$key"; then
  odin_root="$(odin root)"
  opus="$("$root/tools/fetch-opus.sh")"
  compile() { # file object [flags...]
    f="$1"; o="$2"; shift 2
    xcrun --sdk iphoneos clang -target "arm64-apple-ios$MIN_IOS" -isysroot "$sdk" -O2 -fvisibility=hidden "$@" -c "$f" -o "$o"
  }
  compile "$root/vendor/sound/c/roci_sound.c" "$src/roci_sound.o" -I"$odin_root/vendor/miniaudio/src" -I"$odin_root/vendor/stb/src" -I"$opus/include"
  objs="$src/roci_sound.o"
  while read -r file; do
    case "$file" in "#"* | "") continue ;; esac
    obj="$src/opus_$(basename "$file" .c).o"
    compile "$opus/$file" "$obj" -DOPUS_BUILD -DUSE_ALLOCA -DHAVE_LRINTF -DPACKAGE_VERSION='"1.6.1"' \
      -I"$opus/include" -I"$opus/celt" -I"$opus/silk" -I"$opus"
    objs="$objs $obj"
  done < "$root/vendor/sound/c/opus_files.txt"
  rm -f "$lib/libroci_sound.a"
  ar rcs "$lib/libroci_sound.a" $objs
  stamp sound "$key"
fi
# libcurl and mbedTLS for fetch, built by tools/net-libs.sh (HTTP and HTTPS, static). The phone has no list of
# trusted certificates in a file, so the program carries its own. The scripts name the versions, so a change to them
# builds it again.
key="$setting net=$(sum_files "$root/tools/fetch-net.sh" "$root/tools/net-libs.sh")"
if ! fresh "$lib/libcurl.a" curl "$key"; then
  MIN_IOS="$MIN_IOS" "$root/tools/net-libs.sh" ios
  cp "$root/.cache/net-ios/lib/"lib*.a "$lib/"
  stamp curl "$key"
fi
# Box2D for 2D physics, built by tools/physics-libs.sh (static). The scripts name the version, so a change to them builds it again.
key="$setting physics=$(sum_files "$root/tools/fetch-physics.sh" "$root/tools/physics-libs.sh")"
if ! fresh "$lib/libbox2d.a" box2d "$key"; then
  MIN_IOS="$MIN_IOS" "$root/tools/physics-libs.sh" ios
  cp "$root/.cache/physics-ios/lib/libbox2d.a" "$lib/"
  stamp box2d "$key"
fi
echo "built into $lib"
