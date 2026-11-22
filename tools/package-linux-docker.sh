#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Makes a Linux app of a sketch from a computer that is not Linux (a Mac, or Windows with a POSIX shell), in a container of the
# image `tools/ci/package-linux.Dockerfile` makes. `roci package linux` runs inside it, on a copy of this repository kept in
# ~/.cache/rocinante-linux (so what it builds is built once), and the packages come out in the sketch's own
# output/package/linux, with its sketch.toml kept as `roci package` keeps it. Everything after the sketch's folder is for
# `roci package linux`:
#
#   tools/package-linux-docker.sh ~/code/mysketch --format all --maintainer "Ada <ada@example.org>"
#
# Needs docker running. The image is built the first time (a few minutes).
set -eu

sketch="${1:-}"
[ -n "$sketch" ] && [ -d "$sketch" ] || { echo "usage: tools/package-linux-docker.sh <sketch folder> [roci package linux options]" >&2; exit 2; }
shift
command -v docker > /dev/null 2>&1 || { echo "package-linux-docker: docker is not installed" >&2; exit 1; }
docker info > /dev/null 2>&1 || { echo "package-linux-docker: docker is not running" >&2; exit 1; }
root=$(cd "$(dirname "$0")/.." && pwd)
sketch=$(cd "$sketch" && pwd)
work="${ROCI_LINUX_WORK:-$HOME/.cache/rocinante-linux}"
image="${ROCI_LINUX_IMAGE:-rocinante-linux}"

if ! docker image inspect "$image" > /dev/null 2>&1; then
  echo "== building the image $image (once)"
  docker build --platform linux/amd64 -t "$image" -f "$root/tools/ci/package-linux.Dockerfile" "$root"
fi

# the source, without what this computer built; the container's own builds stay in the copy from one run to the next
mkdir -p "$work/src"
rsync -a --delete --exclude .git --exclude .cache --exclude output --exclude artifacts "$root/" "$work/src/"

terminal=""
[ -t 0 ] && terminal="-it"
exec docker run --rm $terminal --platform linux/amd64 -v "$work/src:/src" -v "$sketch:/work/$(basename "$sketch")" -w /src "$image" sh -c '
  set -e
  [ -f .cache/ui/libroci_ui.a ] || odin run build -- ui-libs
  # the screen-reader bridge: without it the app builds and runs, but says nothing to a screen reader
  [ -f .cache/ui/accesskit/libaccesskit.a ] || sh tools/ui-libs.sh accesskit
  [ -f .cache/sound/libroci_sound.a ] || odin run build -- sound-libs
  [ -d .cache/net ] || odin run build -- net-libs
  mkdir -p output
  odin build cli -o:minimal -out:output/roci
  folder="$1"; shift
  exec output/roci package linux "/work/$folder" "$@"
' sh "$(basename "$sketch")" "$@"
