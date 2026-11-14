#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Builds the sound file decoders into .cache/sound (ignored by git): vendor/sound/c/roci_sound.c,
# which holds miniaudio's decoders and stb_vorbis from the vendor folder of the Odin on the
# PATH, so their versions are the pinned Odin's. Needs a C compiler (cc; on Windows MSVC's cl
# and lib, from Git Bash started inside vcvars64.bat).
#
#     tools/sound-libs.sh
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cache="$root/.cache/sound"
mkdir -p "$cache"
cd "$cache"

case "$(uname -s)" in
MINGW* | MSYS* | CYGWIN*)
	for tool in cl lib odin; do
		command -v "$tool" >/dev/null 2>&1 && continue
		echo "sound-libs: $tool is not on the PATH; in a plain cmd window run the Build Tools' vcvars64.bat, then start Git Bash in it" >&2
		exit 1
	done
	export MSYS2_ARG_CONV_EXCL='*'
	odin_root=$(cygpath -m "$(odin root)")
	m=$(cygpath -m "$cache")
	src=$(cygpath -m "$root/vendor/sound/c/roci_sound.c")
	# the static C runtime (-MT), which Odin links
	cl -nologo -O2 -MT -I"$odin_root/vendor/miniaudio/src" -I"$odin_root/vendor/stb/src" \
		-c -Fo"$m/roci_sound.obj" "$src" >/dev/null || { echo "sound-libs: cl failed" >&2; exit 1; }
	rm -f roci_sound.lib
	lib -nologo -OUT:"$m/roci_sound.lib" "$m/roci_sound.obj"
	rm -f roci_sound.obj
	echo "sound-libs: built $cache/roci_sound.lib"
	exit 0
	;;
esac

odin_root=$(odin root)
for header in "$odin_root/vendor/miniaudio/src/miniaudio.h" "$odin_root/vendor/stb/src/stb_vorbis.c"; do
	[ -f "$header" ] || { echo "sound-libs: $header is missing from the Odin on the PATH" >&2; exit 1; }
done
cc=${CC:-cc}
ar=${AR:-ar}
$cc -c -O2 -fPIC -I"$odin_root/vendor/miniaudio/src" -I"$odin_root/vendor/stb/src" \
	-o roci_sound.o "$root/vendor/sound/c/roci_sound.c"
rm -f libroci_sound.a
$ar rcs libroci_sound.a roci_sound.o
rm -f roci_sound.o
echo "sound-libs: built $cache/libroci_sound.a"
