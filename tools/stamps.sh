# SPDX-License-Identifier: 0BSD
#
# Sourced by the scripts that build the phones' libraries, so a library is built again when what it is made from changed,
# not only when it is missing. Each library has a stamp in `$stamps` (a folder the sourcing script sets) holding a line that
# describes its sources: the tag it was fetched at and the build settings, or a checksum of our own files it is compiled from.
# POSIX sh only.

# A checksum of every file under the paths given, read in a fixed order, so it changes when any of them does.
sum_files() { # path...
	find "$@" -type f | LC_ALL=C sort | while read -r f; do cat "$f"; done | cksum | cut -d ' ' -f 1
}

# Whether `library` exists and its stamp `name` says it was built from what `key` describes.
fresh() { # library name key
	[ -f "$1" ] && [ -f "$stamps/$2" ] && [ "$(cat "$stamps/$2")" = "$3" ]
}

# Notes that the library `name` was built from what `key` describes.
stamp() { # name key
	mkdir -p "$stamps"
	printf '%s\n' "$2" > "$stamps/$1"
}
