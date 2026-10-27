#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Checks the C ABI end to end (CLAUDE.md section 1): builds package roci as a shared
# library, checks that the functions it exports are exactly the ones include/roci.h
# declares, and builds examples/c/circle.c against the header and the library. Pass
# `--run` to run the C example for 2 seconds as well (it opens a window).
#
# Needs odin, a C compiler, nm, and SDL3 where the linker can find it; exits 3 when
# the compiler or SDL3 is missing. `ci` runs it, and skips it with a note on a
# computer without SDL3 unless ROCI_REQUIRE_SDL3 is set (as both pipelines do).
set -eu
cd "$(dirname "$0")/.."
mkdir -p output
case "$(uname -s)" in
  Darwin) lib=output/libroci.dylib ;;
  *)      lib=output/libroci.so ;;
esac
# No C compiler, or no SDL3 for the linker (Odin knows where Homebrew keeps it, a bare
# `cc` does not, so the question is put to Odin itself): say so with the exit code
# `ci` knows. The pipelines treat it as a failure; a contributor's computer skips.
if ! command -v cc >/dev/null 2>&1; then
  echo "abi-check: no C compiler here" >&2
  exit 3
fi
if ! odin build roci -build-mode:shared -no-entry-point -vet -strict-style -out:"$lib" >output/abi-build.log 2>&1; then
  if grep -qi 'SDL3' output/abi-build.log; then
    echo "abi-check: SDL3 cannot be linked here" >&2
    exit 3
  fi
  cat output/abi-build.log >&2
  exit 1
fi

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
