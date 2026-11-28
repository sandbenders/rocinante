// SPDX-License-Identifier: 0BSD
//
// How the build script knows a library it built earlier is still the library its sources make: a stamp of those sources is written next to the
// library when it is built, and the library is fresh while the stamp of the sources now is the same. A stamp is a hash of the names and
// contents of the files (so a clone, a checkout that gave every file the time it was made and a cache the pipelines restore all agree, which
// the modification times they used to be compared by could not), and the library is built again when any of its sources changed, however
// old the library is. A library with no stamp is built again once, which writes one.
package build

import "core:fmt"
import "core:hash"
import "core:os"
import "core:slice"
import "core:strings"

// The name of the file beside a library that holds the stamp of what it was built from.
STAMP_FILE :: ".sources-stamp"

// The stamp of some files and the files of some folders (not the folders inside them): a hash of each name and its contents, in the order of
// the names. A file that is not there counts as one with no contents, so it is not the same as the file being there.
sources_stamp :: proc(files: []string, folders: []string, allocator := context.temp_allocator) -> string {
	names := make([dynamic]string, context.temp_allocator)
	for f in files {
		append(&names, f)
	}
	for folder in folders {
		entries, err := os.read_all_directory_by_path(folder, context.temp_allocator)
		if err != nil {
			append(&names, folder) // a folder that is not there is its own difference
			continue
		}
		for entry in entries {
			if entry.type != .Directory {
				append(&names, strings.concatenate({folder, "/", entry.name}, context.temp_allocator))
			}
		}
	}
	slice.sort(names[:])
	state := hash.fnv64a(nil)
	for name in names {
		state = hash.fnv64a(transmute([]byte)name, state)
		data, err := os.read_entire_file(name, context.temp_allocator)
		marker := []byte{0, 1 if err == nil else 2, 0}
		state = hash.fnv64a(marker, state)
		if err == nil {
			state = hash.fnv64a(data, state)
		}
	}
	return fmt.aprintf("%016x", state, allocator = allocator)
}

// Whether the stamp stored in a file is this one.
stamp_matches :: proc(path, stamp: string) -> bool {
	data, err := os.read_entire_file(path, context.temp_allocator)
	return err == nil && string(data) == stamp
}

// Stores a stamp, which says the library beside it was made from the sources it is the stamp of.
stamp_write :: proc(path, stamp: string) {
	_ = os.write_entire_file(path, transmute([]byte)stamp)
}
