#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Spike 4 on Windows (CLAUDE.md section 8): the same as setup.sh, with MSVC.
# Run it from Git Bash that was started from the "x64 Native Tools Command
# Prompt for VS" (so that cl and lib are on the PATH), from the repository root:
#
#     spikes/ui/setup-windows.sh
#     cp "$(odin root)/vendor/sdl3/SDL3.dll" .      # once, as for Spike 1
#     odin run spikes/ui
#     odin run spikes/ui -- interactive
#
# It builds .cache/ui/roci_ui.lib. SDL's C headers come from Odin's own
# vendor/sdl3/include, which match the SDL3.dll that Odin ships (3.4.2), so the
# backends are compiled against the library they will run with. The AccessKit
# adapter for Windows is not wired into the spike yet, so there is no Rust step.
# Needs git, python (only for dear_bindings, in a throwaway virtual environment),
# cl and lib from the Visual Studio Build Tools, and Odin.
set -eu

IMGUI_TAG=v1.93.0
DEAR_BINDINGS_TAG=v0.26

# Git Bash would rewrite arguments that look like Unix paths; none are meant to be.
export MSYS2_ARG_CONV_EXCL='*'

for tool in git cl lib odin; do
	command -v "$tool" >/dev/null 2>&1 || { echo "setup: $tool not found on the PATH (start Git Bash from the x64 Native Tools Command Prompt)" >&2; exit 1; }
done
python=
for candidate in python3 python; do
	if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import venv' >/dev/null 2>&1; then
		python=$candidate
		break
	fi
done
[ -n "$python" ] || { echo "setup: python (with venv) not found" >&2; exit 1; }

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

# 1. SDL's headers, under the SDL3/ folder the backends include them from.
odin_root=$(cygpath -u "$(odin root)")
if [ ! -f sdl-include/SDL3/SDL.h ]; then
	rm -rf sdl-include
	mkdir -p sdl-include
	cp -r "$odin_root/vendor/sdl3/include" sdl-include/SDL3
fi
[ -f sdl-include/SDL3/SDL.h ] || { echo "setup: Odin's vendor/sdl3/include has no SDL.h" >&2; exit 1; }

# 2. The C API, generated from the Dear ImGui headers.
if [ ! -d venv ]; then
	"$python" -m venv venv
	venv/Scripts/python.exe -m pip -q install -r dear_bindings/requirements.txt
fi
gen="$cache/generated"
mkdir -p "$gen/backends"
(
	cd dear_bindings
	"$cache/venv/Scripts/python.exe" dear_bindings.py -o "$gen/dcimgui" ../imgui/imgui.h
	for backend in sdl3 sdlgpu3; do
		"$cache/venv/Scripts/python.exe" dear_bindings.py --backend --include ../imgui/imgui.h \
			-o "$gen/backends/dcimgui_impl_$backend" "../imgui/backends/imgui_impl_$backend.h"
	done
)

# 3. One static library with Dear ImGui, its two backends and the C wrappers.
mkdir -p obj
m=$(cygpath -m "$cache")
for src in imgui/imgui imgui/imgui_demo imgui/imgui_draw imgui/imgui_tables imgui/imgui_widgets \
	imgui/backends/imgui_impl_sdl3 imgui/backends/imgui_impl_sdlgpu3 \
	generated/dcimgui generated/backends/dcimgui_impl_sdl3 generated/backends/dcimgui_impl_sdlgpu3; do
	name=$(basename "$src")
	cl -nologo -std:c++17 -O2 -MD -EHsc -c \
		-I"$m/imgui" -I"$m/imgui/backends" -I"$m/generated" -I"$m/generated/backends" -I"$m/sdl-include" \
		-Fo"$m/obj/$name.obj" "$m/$src.cpp"
done
rm -f roci_ui.lib
lib -nologo -OUT:"$m/roci_ui.lib" obj/*.obj
echo "setup: built $cache/roci_ui.lib (Dear ImGui $IMGUI_TAG, dear_bindings $DEAR_BINDINGS_TAG)"
