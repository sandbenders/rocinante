#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Builds the user interface libraries into .cache/ui (ignored by git):
#
#     tools/ui-libs.sh              fetch Dear ImGui at its pinned tag and build
#                                   libroci_ui.a: Dear ImGui, its SDL3 and SDL_GPU
#                                   backends and the C wrappers committed in
#                                   vendor/imgui/c. Needs git and a C++ compiler.
#     tools/ui-libs.sh accesskit    fetch accesskit-c (the screen-reader bridge's library) into
#                                   .cache/ui/accesskit: its own release libraries where it
#                                   publishes one for this computer (checked by sha256), a build
#                                   from source with cargo and cmake where it does not.
#     tools/ui-libs.sh regenerate   make those wrappers and vendor/imgui/imgui.odin
#                                   again after a new Dear ImGui or dear_bindings
#                                   tag (needs python3, which only dear_bindings
#                                   uses, in a throwaway virtual environment).
#
# SDL_INCLUDE: the folder that holds SDL3/SDL.h (default: pkg-config, then Homebrew).
set -eu

IMGUI_TAG=v1.93.0
DEAR_BINDINGS_TAG=v0.26
ACCESSKIT_TAG=0.23.1
# the release archive of that tag (accesskit-c's own: the header, the licences and a static
# and shared library for macOS, Windows, Linux x86 and x86_64, iOS and Android)
ACCESSKIT_ZIP_SHA256=35b7ca8a6f1e038b5da35e1e9e5a0adaed9bfcf21e1496d29598fbbadcc7043f

root=$(cd "$(dirname "$0")/.." && pwd)
cache="$root/.cache/ui"
c_api="$root/vendor/imgui/c"
mkdir -p "$cache"
cd "$cache"

if [ "${1:-}" = accesskit ]; then
	dir="$cache/accesskit"
	marker="$dir/.accesskit-$ACCESSKIT_TAG"
	libfile=libaccesskit.a # what the library is called in .cache/ui/accesskit
	if [ -f "$marker" ]; then
		echo "ui-libs: accesskit-c $ACCESSKIT_TAG is there ($dir)"
		exit 0
	fi
	rm -rf "$dir"
	mkdir -p "$dir"
	# the folder of the release's libraries for this computer, if it has one
	case "$(uname -s)-$(uname -m)" in
	Darwin-arm64) prebuilt=lib/macos/arm64/static/libaccesskit.a ;;
	Darwin-x86_64) prebuilt=lib/macos/x86_64/static/libaccesskit.a ;;
	Linux-x86_64) prebuilt=lib/linux/x86_64/static/libaccesskit.a ;;
	# Git Bash (MINGW64), MSYS2 and Cygwin on Windows: the library for MSVC, which Odin links with there
	MINGW64_NT-*-x86_64 | MSYS_NT-*-x86_64 | CYGWIN_NT-*-x86_64)
		prebuilt=lib/windows/x86_64/msvc/static/accesskit.lib
		libfile=accesskit.lib
		;;
	*) prebuilt= ;;
	esac
	if [ -n "$prebuilt" ]; then
		zip="$cache/accesskit-c-$ACCESSKIT_TAG.zip"
		if [ ! -f "$zip" ]; then
			curl -fsSL -o "$zip.part" "https://github.com/AccessKit/accesskit-c/releases/download/$ACCESSKIT_TAG/accesskit-c-$ACCESSKIT_TAG.zip"
			mv "$zip.part" "$zip"
		fi
		if command -v sha256sum >/dev/null 2>&1; then
			got=$(sha256sum "$zip" | cut -d' ' -f1)
		else
			got=$(shasum -a 256 "$zip" | cut -d' ' -f1)
		fi
		if [ "$got" != "$ACCESSKIT_ZIP_SHA256" ]; then
			rm -f "$zip"
			echo "ui-libs: the accesskit-c archive's checksum is $got, not $ACCESSKIT_ZIP_SHA256" >&2
			exit 1
		fi
		if command -v unzip >/dev/null 2>&1; then
			unzip -q -o "$zip" "accesskit-c-$ACCESSKIT_TAG/$prebuilt" "accesskit-c-$ACCESSKIT_TAG/include/accesskit.h" \
				"accesskit-c-$ACCESSKIT_TAG/LICENSE-MIT" "accesskit-c-$ACCESSKIT_TAG/LICENSE-APACHE" "accesskit-c-$ACCESSKIT_TAG/LICENSE.chromium" -d "$dir.tmp"
		elif command -v powershell.exe >/dev/null 2>&1; then
			# Git for Windows has no unzip: PowerShell opens the whole archive (every system's library, 70 MB)
			powershell.exe -NoProfile -Command "Expand-Archive -LiteralPath '$(cygpath -w "$zip")' -DestinationPath '$(cygpath -w "$dir.tmp")' -Force"
		else
			echo "ui-libs: unzip (or PowerShell) is needed to open the accesskit-c archive" >&2
			exit 1
		fi
		mv "$dir.tmp/accesskit-c-$ACCESSKIT_TAG/$prebuilt" "$dir/$libfile"
		mv "$dir.tmp/accesskit-c-$ACCESSKIT_TAG/include/accesskit.h" "$dir/accesskit.h"
		mv "$dir.tmp/accesskit-c-$ACCESSKIT_TAG"/LICENSE* "$dir/"
		rm -rf "$dir.tmp"
	else
		# FreeBSD, OpenBSD, arm64 Linux: no library is published, so it is built (cargo and cmake)
		[ -d "$cache/accesskit-c-src" ] || git clone -q --depth 1 --branch "$ACCESSKIT_TAG" https://github.com/AccessKit/accesskit-c "$cache/accesskit-c-src"
		cmake -S "$cache/accesskit-c-src" -B "$cache/accesskit-c-src/build" -DCMAKE_BUILD_TYPE=Release >/dev/null
		cmake --build "$cache/accesskit-c-src/build" >/dev/null
		cp "$cache/accesskit-c-src/build/libaccesskit.a" "$dir/libaccesskit.a"
		cp "$cache/accesskit-c-src/include/accesskit.h" "$dir/accesskit.h"
		cp "$cache/accesskit-c-src"/LICENSE* "$dir/"
	fi
	touch "$marker"
	echo "ui-libs: accesskit-c $ACCESSKIT_TAG is in $dir"
	exit 0
fi

clone() { # url tag dir
	if [ ! -d "$3" ]; then
		git clone -q --depth 1 --branch "$2" "$1" "$3"
	fi
}
clone https://github.com/ocornut/imgui "$IMGUI_TAG" imgui

case "$(uname -s)" in
MINGW* | MSYS* | CYGWIN*)
	# Windows (Git Bash): MSVC's cl and lib build roci_ui.lib, with the static C runtime (-MT),
	# because Odin links that one. SDL's headers are Odin's own (vendor/sdl3/include), which
	# match the SDL3.dll Odin ships, copied afresh each time so a new Odin brings its own.
	if [ "${1:-}" = regenerate ]; then
		echo "ui-libs: regenerate the wrappers on another system (they are the same everywhere and committed)" >&2
		exit 1
	fi
	for tool in cl lib odin; do
		command -v "$tool" >/dev/null 2>&1 && continue
		echo "ui-libs: $tool is not on the PATH; in a plain cmd window run the Build Tools' vcvars64.bat, then start Git Bash in it:" >&2
		echo '    call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat"' >&2
		echo '    "C:\Program Files\Git\bin\bash.exe" --login -i' >&2
		exit 1
	done
	# Git Bash would rewrite arguments that look like Unix paths; none are meant to be.
	export MSYS2_ARG_CONV_EXCL='*'
	odin_sdl="$(cygpath -u "$(odin root)")/vendor/sdl3/include"
	[ -f "$odin_sdl/SDL.h" ] || { echo "ui-libs: Odin's vendor/sdl3/include has no SDL.h" >&2; exit 1; }
	rm -rf sdl-include
	mkdir -p sdl-include
	cp -r "$odin_sdl" sdl-include/SDL3
	m=$(cygpath -m "$cache")
	c=$(cygpath -m "$c_api")
	rm -rf obj
	mkdir -p obj
	for src in "$m/imgui/imgui" "$m/imgui/imgui_demo" "$m/imgui/imgui_draw" "$m/imgui/imgui_tables" \
		"$m/imgui/imgui_widgets" "$m/imgui/backends/imgui_impl_sdl3" "$m/imgui/backends/imgui_impl_sdlgpu3" \
		"$c/dcimgui" "$c/roci_context" "$c/backends/dcimgui_impl_sdl3" "$c/backends/dcimgui_impl_sdlgpu3"; do
		cl -nologo -std:c++17 -O2 -MT -EHsc -DIMGUI_USER_CONFIG='"imconfig_roci.h"' \
			-I"$m/imgui" -I"$m/imgui/backends" -I"$c" -I"$c/backends" -I"$m/sdl-include" \
			-c -Fo"$m/obj/$(basename "$src").obj" "$src.cpp" >/dev/null || { echo "ui-libs: cl failed on $src.cpp" >&2; exit 1; }
	done
	rm -f roci_ui.lib
	lib -nologo -OUT:"$m/roci_ui.lib" obj/*.obj
	echo "ui-libs: built $cache/roci_ui.lib (Dear ImGui $IMGUI_TAG)"
	exit 0
	;;
esac

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
	# dear_bindings writes a null default as reinterpret_cast<T>(NULL), which C++ refuses where
	# NULL is nullptr (OpenBSD); static_cast of nullptr means the same everywhere.
	sed 's/reinterpret_cast<\([^>]*\)>(NULL)/static_cast<\1>(nullptr)/g' "$c_api/dcimgui.cpp" > "$c_api/dcimgui.cpp.part"
	mv "$c_api/dcimgui.cpp.part" "$c_api/dcimgui.cpp"
	cp "$gen"/backends/dcimgui_impl_*.h "$gen"/backends/dcimgui_impl_*.cpp "$c_api/backends/"
	(cd "$root" && odin run tools/imgui -- "$gen")
fi

obj="$cache/obj"
mkdir -p "$obj"
flags="-std=c++17 -O2 -fPIC -DIMGUI_USER_CONFIG=\"imconfig_roci.h\" -I$cache/imgui -I$cache/imgui/backends -I$c_api -I$c_api/backends -I$SDL_INCLUDE"
for src in "$cache/imgui/imgui" "$cache/imgui/imgui_demo" "$cache/imgui/imgui_draw" "$cache/imgui/imgui_tables" \
	"$cache/imgui/imgui_widgets" "$cache/imgui/backends/imgui_impl_sdl3" "$cache/imgui/backends/imgui_impl_sdlgpu3" \
	"$c_api/dcimgui" "$c_api/roci_context" "$c_api/backends/dcimgui_impl_sdl3" "$c_api/backends/dcimgui_impl_sdlgpu3"; do
	# shellcheck disable=SC2086
	c++ $flags -c "$src.cpp" -o "$obj/$(basename "$src").o"
done
rm -f libroci_ui.a
ar rcs libroci_ui.a "$obj"/*.o
echo "ui-libs: built $cache/libroci_ui.a (Dear ImGui $IMGUI_TAG)"
