#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Builds the user interface libraries into .cache/ui (ignored by git):
#
#     tools/ui-libs.sh              fetch Dear ImGui at its pinned tag and build
#                                   libroci_ui.a: Dear ImGui, its SDL3 and SDL_GPU
#                                   backends and the C wrappers committed in
#                                   vendor/imgui/c. Needs git and a C++ compiler.
#     tools/ui-libs.sh regenerate   make those wrappers and vendor/imgui/imgui.odin
#                                   again after a new Dear ImGui or dear_bindings
#                                   tag (needs python3, which only dear_bindings
#                                   uses, in a throwaway virtual environment).
#
# SDL_INCLUDE: the folder that holds SDL3/SDL.h (default: pkg-config, then Homebrew).
set -eu

IMGUI_TAG=v1.93.0
DEAR_BINDINGS_TAG=v0.26

root=$(cd "$(dirname "$0")/.." && pwd)
cache="$root/.cache/ui"
c_api="$root/vendor/imgui/c"
mkdir -p "$cache"
cd "$cache"

clone() { # url tag dir
	if [ ! -d "$3" ]; then
		git clone -q --depth 1 --branch "$2" "$1" "$3"
	fi
}
clone https://github.com/ocornut/imgui "$IMGUI_TAG" imgui

if [ -z "${SDL_INCLUDE:-}" ]; then
	# pkg-config when it is there, else the usual places (Arch's image has no pkg-config)
	SDL_INCLUDE=$(pkg-config --variable=includedir sdl3 2>/dev/null || true)
	for dir in /usr/include /usr/local/include /opt/homebrew/include; do
		if [ -z "$SDL_INCLUDE" ] || [ ! -f "$SDL_INCLUDE/SDL3/SDL.h" ]; then
			SDL_INCLUDE=$dir
		fi
	done
fi
[ -f "$SDL_INCLUDE/SDL3/SDL.h" ] || { echo "ui-libs: SDL3/SDL.h not found in $SDL_INCLUDE; set SDL_INCLUDE" >&2; exit 1; }

if [ "${1:-}" = regenerate ]; then
	clone https://github.com/dearimgui/dear_bindings "$DEAR_BINDINGS_TAG" dear_bindings
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
	mkdir -p "$c_api/backends"
	cp "$gen/dcimgui.h" "$gen/dcimgui.cpp" "$c_api/"
	cp "$gen"/backends/dcimgui_impl_*.h "$gen"/backends/dcimgui_impl_*.cpp "$c_api/backends/"
	(cd "$root" && odin run tools/imgui -- "$gen")
fi

obj="$cache/obj"
mkdir -p "$obj"
flags="-std=c++17 -O2 -fPIC -I$cache/imgui -I$cache/imgui/backends -I$c_api -I$c_api/backends -I$SDL_INCLUDE"
for src in "$cache/imgui/imgui" "$cache/imgui/imgui_demo" "$cache/imgui/imgui_draw" "$cache/imgui/imgui_tables" \
	"$cache/imgui/imgui_widgets" "$cache/imgui/backends/imgui_impl_sdl3" "$cache/imgui/backends/imgui_impl_sdlgpu3" \
	"$c_api/dcimgui" "$c_api/backends/dcimgui_impl_sdl3" "$c_api/backends/dcimgui_impl_sdlgpu3"; do
	# shellcheck disable=SC2086
	c++ $flags -c "$src.cpp" -o "$obj/$(basename "$src").o"
done
rm -f libroci_ui.a
ar rcs libroci_ui.a "$obj"/*.o
echo "ui-libs: built $cache/libroci_ui.a (Dear ImGui $IMGUI_TAG)"
