#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Checks the C ABI end to end (CLAUDE.md section 1): builds package roci as a shared
# library, checks that the functions it exports are exactly the ones include/roci.h
# declares, and builds examples/c/circle.c against the header and the library. Pass
# `--run` to run the C example for 2 seconds as well (it opens a window).
#
# Needs odin, a C compiler, nm, and SDL3 where the linker can find it. Not part of
# `ci` yet, because the GitLab image has no SDL3.
set -eu
cd "$(dirname "$0")/.."
mkdir -p output
case "$(uname -s)" in
  Darwin) lib=output/libroci.dylib; syms='_roci_' ;;
  *)      lib=output/libroci.so;    syms='roci_' ;;
esac
odin build roci -build-mode:shared -no-entry-point -vet -strict-style -out:"$lib"

# Every function the header declares is exported, and nothing else is.
sed -n 's/.* \(roci_[a-z0-9_]*\)(.*/\1/p' include/roci.h | sort > output/abi-header.txt
nm -g "$lib" | sed -n "s/.* [TDRS] _\{0,1\}\(roci_[a-z0-9_]*\)\$/\1/p" | sort > output/abi-library.txt
if ! diff output/abi-header.txt output/abi-library.txt; then
  echo "abi-check: the header and the library disagree (header on the left)" >&2
  exit 1
fi
echo "abi-check: $(wc -l < output/abi-header.txt | tr -d ' ') functions, the header and the library agree"

cc -Wall -Wextra -Werror examples/c/circle.c -Iinclude -Loutput -lroci -o output/c_circle
echo "abi-check: examples/c/circle.c builds"
if [ "${1:-}" = "--run" ]; then
  LD_LIBRARY_PATH=output DYLD_LIBRARY_PATH=output ./output/c_circle 2
  echo "abi-check: the C example ran"
fi
