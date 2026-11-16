#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Builds the sound file decoders into .cache/sound (ignored by git): vendor/sound/c/roci_sound.c,
# which holds miniaudio's decoders and stb_vorbis from the vendor folder of the Odin on the
# PATH, so their versions are the pinned Odin's, and libopus, fetched here (curl and tar; its
# checksum is checked) and built beside them into the same library. Needs a C compiler (cc; on Windows MSVC's cl
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
	# fetched before path conversion is turned off below, which would hand curl and tar
	# paths such as /c/Users/... that they cannot write to
	opus=$("$root/tools/fetch-opus.sh") || exit 1
	export MSYS2_ARG_CONV_EXCL='*'
	odin_root=$(cygpath -m "$(odin root)")
	m=$(cygpath -m "$cache")
	src=$(cygpath -m "$root/vendor/sound/c/roci_sound.c")
	opus_m=$(cygpath -m "$opus")
	# the static C runtime (-MT), which Odin links
	cl -nologo -O2 -MT -I"$odin_root/vendor/miniaudio/src" -I"$odin_root/vendor/stb/src" -I"$opus_m/include" \
		-c -Fo"$m/roci_sound.obj" "$src" >/dev/null || { echo "sound-libs: cl failed" >&2; exit 1; }
	# libopus: the decoder's files, with alloca for its arrays (Visual C has no variable-length ones)
	objs="$m/roci_sound.obj"
	while read -r file; do
		case "$file" in "#"* | "") continue ;; esac
		obj="$m/opus_$(basename "$file" .c).obj"
		cl -nologo -O2 -MT -DOPUS_BUILD -DUSE_ALLOCA -DHAVE_LRINTF -DPACKAGE_VERSION='"1.6.1"' -I"$opus_m/include" -I"$opus_m/celt" -I"$opus_m/silk" -I"$opus_m" \
			-c -Fo"$obj" "$opus_m/$file" >/dev/null || { echo "sound-libs: cl failed on $file" >&2; exit 1; }
		objs="$objs $obj"
	done < "$root/vendor/sound/c/opus_files.txt"
	rm -f roci_sound.lib
	lib -nologo -OUT:"$m/roci_sound.lib" $objs
	rm -f ./*.obj
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
opus=$("$root/tools/fetch-opus.sh") || exit 1
# hidden: the decoders are linked into roci and must not be exported by its shared library
$cc -c -O2 -fPIC -fvisibility=hidden -I"$odin_root/vendor/miniaudio/src" -I"$odin_root/vendor/stb/src" -I"$opus/include" \
	-o roci_sound.o "$root/vendor/sound/c/roci_sound.c"
# libopus: the decoder's files, with alloca for its arrays
objs=roci_sound.o
while read -r file; do
	case "$file" in "#"* | "") continue ;; esac
	obj="opus_$(basename "$file" .c).o"
	$cc -c -O2 -fPIC -fvisibility=hidden -DOPUS_BUILD -DUSE_ALLOCA -DHAVE_LRINTF -DPACKAGE_VERSION='"1.6.1"' \
		-I"$opus/include" -I"$opus/celt" -I"$opus/silk" -I"$opus" -o "$obj" "$opus/$file"
	objs="$objs $obj"
done < "$root/vendor/sound/c/opus_files.txt"
rm -f libroci_sound.a
$ar rcs libroci_sound.a $objs
rm -f $objs
echo "sound-libs: built $cache/libroci_sound.a"
