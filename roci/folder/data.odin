// SPDX-License-Identifier: 0BSD
//
// Data files (`load "birds.json"`) found in a sketch's `assets/` by name, as pictures and sounds are, and read
// as text. The checker reads them through `data_reader`, so a sketch is checked against the file it will load.
package folder

import "core:os"
import "core:strings"

// Reads the data file `name` of the sketch in `root`: its text, or why there is none, in words that finish the
// sentence "the sketch's assets folder ... and": a name that is missing, or shared by two files.
read_data :: proc(root, name: string, allocator := context.temp_allocator) -> (text: string, found: bool, why: string) {
	path, status, candidates := find_asset(root, name, context.temp_allocator)
	#partial switch status {
	case .Missing:
		return "", false, "there is no file of that name in it"
	case .Ambiguous:
		trimmed := make([]string, len(candidates), context.temp_allocator)
		for c, i in candidates {
			trimmed[i] = strings.trim_prefix(c, "assets/")
		}
		return "", false, strings.concatenate({"more than one file has that name (", strings.join(trimmed, " and ", context.temp_allocator), "), so write the folder as well"}, context.temp_allocator)
	}
	bytes, err := os.read_entire_file(strings.concatenate({root, "/", path}, context.temp_allocator), allocator)
	if err != nil {
		return "", false, "the file is there but cannot be read"
	}
	return string(bytes), true, ""
}

// The folder `data_reader` looks in, for the thread that checks a sketch.
@(thread_local) @(private) data_root: string

// Makes `data_reader` look in the sketch folder `root` (nothing takes it away).
set_data_root :: proc(root: string) {
	data_root = strings.clone(root, context.temp_allocator) // only needed while the checker runs
}

// The reader the checker is given (`lang.set_data_reader`): the data files of the folder `set_data_root` named.
data_reader :: proc(name: string) -> (text: string, found: bool, why: string) {
	if data_root == "" {
		return "", false, "this sketch has no folder to look in"
	}
	return read_data(data_root, name)
}
