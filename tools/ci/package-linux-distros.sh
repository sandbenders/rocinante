#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Makes the Linux packages of a sketch on older distributions, in containers, so they install and run on more computers than
# packages made on a new Linux (a program asks for the glibc and libstdc++ of the computer that built it):
#
#   debian   Debian 12: the .deb and the AppImage (glibc 2.36, so the AppImage runs on the others too)
#   ubuntu   Ubuntu 24.04 LTS: a .deb
#   fedora   Fedora 43: the RPM (the oldest Fedora still updated in 2026-11; move it to 44 when 43 ends)
#   arch     Arch Linux as it is today (it has no older releases): the Arch package, which asks for Arch's own SDL3 and
#            shader libraries instead of carrying them
#
#   tools/ci/package-linux-distros.sh <sketch folder> [debian] [ubuntu] [fedora] [arch] [-- roci package linux options]
#
# With no distribution named it makes all four, side by side. Each is packaged from its own copy of this repository and of the
# sketch, kept in ~/.cache/rocinante-distros/<name> (ROCI_DISTROS_WORK) so the libraries it builds are built once, and what it
# makes is copied to the sketch's output/package/linux-<name>; the sketch's sketch.toml gets the raised build number back.
# The images are built the first time from tools/ci/package-debian.Containerfile, package-fedora.Containerfile and
# package-linux.Dockerfile (a few minutes each; the Debian one builds shaderc too). A --format among the options takes the
# place of each distribution's formats (`-- --format all` makes all five on each). Needs podman (or docker) and rsync; on an Apple silicon Mac they run
# under x86-64 emulation, slowly. The base images can be changed with ROCI_DEBIAN_BASE, ROCI_UBUNTU_BASE, ROCI_FEDORA_BASE and ROCI_ARCH_BASE.
set -eu

sketch="${1:-}"
[ -n "$sketch" ] && [ -d "$sketch" ] || { echo "usage: tools/ci/package-linux-distros.sh <sketch folder> [debian] [ubuntu] [fedora] [arch] [-- options]" >&2; exit 2; }
shift
sketch=$(cd "$sketch" && pwd)
names=""
while [ $# -gt 0 ] && [ "$1" != "--" ]; do
  case "$1" in
    debian | ubuntu | fedora | arch) names="$names $1" ;;
    *) echo "package-linux-distros: no distribution called $1 (debian, ubuntu, fedora or arch)" >&2; exit 2 ;;
  esac
  shift
done
[ "${1:-}" = "--" ] && shift
[ -n "$names" ] || names="debian ubuntu fedora arch"

engine=""
for tool in podman docker; do
  command -v "$tool" > /dev/null 2>&1 && { engine=$tool; break; }
done
[ -n "$engine" ] || { echo "package-linux-distros: neither podman nor docker is installed" >&2; exit 1; }
command -v rsync > /dev/null 2>&1 || { echo "package-linux-distros: rsync is not installed" >&2; exit 1; }
root=$(cd "$(dirname "$0")/../.." && pwd)
work="${ROCI_DISTROS_WORK:-$HOME/.cache/rocinante-distros}"

# The image of a distribution is tagged with a sum of what it is made from (its Containerfile, the install scripts, the pinned
# Odin, the base and the arguments), so a change to any of them builds a new one and an unchanged one is used as it is.
tag() { # name, base, Containerfile, extra build arguments
  name=$1 base=$2 file=$3
  shift 3
  sum=$( { cat "$root/tools/ci/$file" "$root"/tools/ci/install-*.sh "$root/ODIN_VERSION"; echo "$base $*"; } | cksum | cut -d' ' -f1)
  echo "roci-pkg-$name:$sum"
}
image() { # name, base, Containerfile, extra build arguments
  name=$1 base=$2 file=$3
  shift 3
  wanted=$(tag "$name" "$base" "$file" "$@")
  if ! "$engine" image inspect "$wanted" > /dev/null 2>&1; then
    echo "== building the image $wanted from $base (once)"
    "$engine" build --platform linux/amd64 --build-arg "BASE=$base" "$@" -t "$wanted" -f "$root/tools/ci/$file" "$root"
  fi
  eval "image_$name=\$wanted"
}

package() { # name, formats, then the options for roci package
  name=$1 formats=$2
  shift 2
  here="$work/$name"
  eval "use=\$image_$name"
  rm -f "$here/made"
  mkdir -p "$here/src" "$here/cache" "$here/sketch"
  # the source without what this computer built, and the sketch without what it made; the container's builds stay in cache
  rsync -a --delete --exclude .git --exclude .cache --exclude output --exclude artifacts "$root/" "$here/src/"
  rsync -a --delete --exclude .git --exclude output --exclude artifacts "$sketch/" "$here/sketch/"
  "$engine" run --rm --platform linux/amd64 -v "$here/src:/src:Z" -v "$here/cache:/src/.cache:Z" -v "$here/sketch:/work/sketch:Z" -w /src "$use" sh -c '
    set -e
    [ -f .cache/ui/libroci_ui.a ] || odin run build -- ui-libs
    [ -f .cache/ui/accesskit/libaccesskit.a ] || sh tools/ui-libs.sh accesskit
    [ -f .cache/sound/libroci_sound.a ] || odin run build -- sound-libs
    [ -d .cache/net/lib ] || odin run build -- net-libs
    mkdir -p output
    odin build cli -o:minimal -out:output/roci
    formats="$1"; shift
    exec output/roci package linux /work/sketch --yes --format "$formats" "$@"
  ' sh "$formats" "$@" > "$here/package.log" 2>&1 || { echo "$name: failed; what it said is in $here/package.log" >&2; return 1; }
  out="$sketch/output/package/linux-$name"
  rm -rf "$out"
  mkdir -p "$out"
  for made in "$here"/sketch/output/package/linux/*.deb "$here"/sketch/output/package/linux/*.rpm "$here"/sketch/output/package/linux/*.pkg.tar.zst "$here"/sketch/output/package/linux/*.tar.gz "$here"/sketch/output/package/linux/*.AppImage; do
    [ -f "$made" ] && cp "$made" "$out/"
  done
  grep -E '^(It runs|It also needs)' "$here/package.log" | sed "s/^/$name: /"
  echo "$name: made $(cd "$out" && ls | tr '\n' ' ')in $out"
  touch "$here/made"
}

for name in $names; do
  case "$name" in
    debian) image debian "${ROCI_DEBIAN_BASE:-docker.io/library/debian:12}" package-debian.Containerfile --build-arg SHADERC=source ;;
    ubuntu) image ubuntu "${ROCI_UBUNTU_BASE:-docker.io/library/ubuntu:24.04}" package-debian.Containerfile --build-arg SHADERC=system ;;
    fedora) image fedora "${ROCI_FEDORA_BASE:-docker.io/library/fedora:43}" package-fedora.Containerfile ;;
    arch) image arch "${ROCI_ARCH_BASE:-docker.io/library/archlinux:latest}" package-linux.Dockerfile ;;
  esac
done

failed=0
pids=""
for name in $names; do
  case "$name" in
    debian) package debian deb,appimage "$@" & ;;
    ubuntu) package ubuntu deb "$@" & ;;
    fedora) package fedora rpm "$@" & ;;
    arch) package arch arch "$@" & ;;
  esac
  pids="$pids $!"
done
for pid in $pids; do
  wait "$pid" || failed=1
done

# the build number each copy spent (they started from the same one, so they agree), and the answers a first package asked for
for name in $names; do
  if [ -f "$work/$name/made" ] && [ -f "$work/$name/sketch/sketch.toml" ]; then
    cp "$work/$name/sketch/sketch.toml" "$sketch/sketch.toml"
    break
  fi
done
exit $failed
