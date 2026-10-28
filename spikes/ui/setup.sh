#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Spike 4: fetch the pinned Dear ImGui and dear_bindings,
# generate the C API (dcimgui) with the SDL3 and SDL_GPU backends, and build it
# into .cache/ui/libroci_ui.a for the spike to link. Nothing here is committed:
# .cache/ is ignored by git. Needs git, a C++ compiler (c++), ar and python3
# (only dear_bindings itself uses Python, in a throwaway virtual environment).
#
#     spikes/ui/setup.sh
#
# On macOS it also builds accesskit-c (the screen-reader bridge) into
# .cache/ui/libaccesskit.a, which needs Rust (cargo) and CMake; the other systems'
# adapters are not wired into the spike yet, so they skip it.
#
# SDL_INCLUDE: the folder that holds SDL3/SDL.h (default: pkg-config, then Homebrew).
set -eu

IMGUI_TAG=v1.93.0
DEAR_BINDINGS_TAG=v0.26
ACCESSKIT_TAG=0.23.1

root=$(cd "$(dirname "$0")/../.." && pwd)
cache="$root/.cache/ui"
mkdir -p "$cache"
cd "$cache"

clone() { # url tag dir
	if [ ! -d "$3" ]; then
		git clone -q --depth 1 --branch "$2" "$1" "$3"
	fi
}
clone https://github.com/ocornut/imgui "$IMGUI_TAG" imgui
clone https://github.com/dearimgui/dear_bindings "$DEAR_BINDINGS_TAG" dear_bindings
if [ "$(uname)" = Darwin ]; then
	clone https://github.com/AccessKit/accesskit-c "$ACCESSKIT_TAG" accesskit-c
fi

if [ -z "${SDL_INCLUDE:-}" ]; then
	SDL_INCLUDE=$(pkg-config --variable=includedir sdl3 2>/dev/null || echo /opt/homebrew/include)
fi
[ -f "$SDL_INCLUDE/SDL3/SDL.h" ] || { echo "setup: SDL3/SDL.h not found in $SDL_INCLUDE; set SDL_INCLUDE" >&2; exit 1; }

# 1. The C API, generated from the Dear ImGui headers.
if [ ! -d venv ]; then
	python3 -m venv venv
	venv/bin/pip -q install -r dear_bindings/requirements.txt
fi
gen="$cache/generated"
mkdir -p "$gen/backends"
(
	cd dear_bindings
	"$cache/venv/bin/python" dear_bindings.py -o "$gen/dcimgui" ../imgui/imgui.h
	for backend in sdl3 sdlgpu3; do
		"$cache/venv/bin/python" dear_bindings.py --backend --include ../imgui/imgui.h \
			-o "$gen/backends/dcimgui_impl_$backend" "../imgui/backends/imgui_impl_$backend.h"
	done
)

# 2. One static library with Dear ImGui, its two backends and the C wrappers.
obj="$cache/obj"
mkdir -p "$obj"
flags="-std=c++17 -O2 -fPIC -I$cache/imgui -I$cache/imgui/backends -I$gen -I$gen/backends -I$SDL_INCLUDE"
for src in imgui/imgui imgui/imgui_demo imgui/imgui_draw imgui/imgui_tables imgui/imgui_widgets \
	imgui/backends/imgui_impl_sdl3 imgui/backends/imgui_impl_sdlgpu3 \
	generated/dcimgui generated/backends/dcimgui_impl_sdl3 generated/backends/dcimgui_impl_sdlgpu3; do
	# shellcheck disable=SC2086
	c++ $flags -c "$cache/$src.cpp" -o "$obj/$(basename "$src").o"
done
rm -f libroci_ui.a
ar rcs libroci_ui.a "$obj"/*.o
echo "setup: built $cache/libroci_ui.a (Dear ImGui $IMGUI_TAG, dear_bindings $DEAR_BINDINGS_TAG)"

# 3. accesskit-c, as a static library (its CMake build runs cargo), on macOS only.
if [ "$(uname)" = Darwin ]; then
	if [ ! -f libaccesskit.a ]; then
		cmake -S accesskit-c -B accesskit-c/build -DCMAKE_BUILD_TYPE=Release >/dev/null
		cmake --build accesskit-c/build >/dev/null
		cp accesskit-c/build/libaccesskit.a libaccesskit.a
	fi
	echo "setup: built $cache/libaccesskit.a (accesskit-c $ACCESSKIT_TAG)"
fi
