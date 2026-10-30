#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Copies sancho (rocinante's PNG writer and deflate compressor, published on their
# own) into vendor/sancho at a commit of its repository, and records which one in
# vendor/sancho/SOURCE. A change to how PNG files are written is made in sancho
# first; this brings it in. Run it from the repository root:
#
#   tools/vendor-sancho.sh            the newest commit of sancho's main
#   tools/vendor-sancho.sh <ref>      a tag, a branch or a commit
#
# Needs git. Afterwards run `odin run build -- ci`: the golden images say whether the
# files written changed.
set -eu

url="https://github.com/sandbenders/sancho"
ref="${1:-main}"
[ -d vendor ] && [ -f ODIN_VERSION ] || { echo "vendor-sancho: run it from the repository root" >&2; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git clone --quiet "$url" "$work/sancho"
git -C "$work/sancho" checkout --quiet "$ref"
commit="$(git -C "$work/sancho" rev-parse HEAD)"

rm -rf vendor/sancho
mkdir -p vendor/sancho
for part in deflate png_writer LICENSE README.md; do
  cp -R "$work/sancho/$part" vendor/sancho/
done
printf 'url %s\ncommit %s\n' "$url" "$commit" > vendor/sancho/SOURCE
echo "vendor-sancho: vendor/sancho is sancho at $commit"
