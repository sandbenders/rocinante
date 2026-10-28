// SPDX-License-Identifier: 0BSD
//
// A sketch folder is one program: every .roci file in it belongs to the same program
// and sees every other file's verbs and constants. This finds those files and reads
// them, in the order they are joined and run in (the other files by name, then
// `sketch.roci`, which is the only one with statements that run).
package folder

import "../lang"
import "core:os"
import "core:slice"
import "core:strings"

// The files of a program, in joining order, and where each one is on disk.
Program :: struct {
	files: []lang.File_Text,
	paths: []string, // the same order: the path to read each file again from
}

// Folders whose files are not the sketch's own code: its assets, the libraries
// vendored into it, what it writes, and anything hidden (git's, the cache).
is_foreign_folder :: proc(name: string) -> bool {
	return name == "assets" || name == "libs" || name == "output" || strings.has_prefix(name, ".")
}

// Every .roci file in a folder and the folders inside it that the sketch owns, as
// paths that start with `root`, in the order of their names.
roci_files :: proc(root: string, allocator := context.temp_allocator) -> []string {
	found := make([dynamic]string, allocator)
	cwd, _ := os.get_working_directory(context.temp_allocator)
	here := strings.concatenate({cwd, "/"}, context.temp_allocator)
	w: os.Walker
	os.walker_init(&w, root)
	defer os.walker_destroy(&w)
	for fi in os.walker_walk(&w) {
		if fi.type == .Directory {
			if is_foreign_folder(fi.name) && fi.fullpath != root {
				os.walker_skip_dir(&w)
			}
			continue
		}
		if strings.has_suffix(fi.name, ".roci") {
			// The walker gives full paths; show them from where we are.
			shown := strings.trim_prefix(fi.fullpath, here)
			append(&found, strings.clone(shown, allocator))
		}
	}
	slice.sort(found[:])
	return found[:]
}

// Reads the program whose sketch is `sketch` (the path to its `sketch.roci`): all the
// .roci files of that file's folder. A problem (a file that cannot be read) is said
// in words and no program is given.
read_program :: proc(sketch: string, allocator := context.temp_allocator) -> (program: Program, problem: string) {
	root := root_of(sketch)
	paths := roci_files(root, allocator)
	files := make([dynamic]lang.File_Text, allocator)
	for path in paths {
		data, err := os.read_entire_file(path, allocator)
		if err != nil {
			return {}, strings.concatenate({"I cannot read `", path, "`."}, allocator)
		}
		append(&files, lang.File_Text{name = path, text = string(data)})
	}
	// `sketch` may be spelled differently from the walker's path (`./x/sketch.roci`):
	// it is the one file that runs, so it goes last whatever it is called here.
	slice.sort_by(files[:], proc(a, b: lang.File_Text) -> bool {return a.name < b.name})
	ordered := slice.clone_to_dynamic(files[:], allocator)
	lang.order_files(ordered[:])
	ordered_paths := make([]string, len(ordered), allocator)
	for f, i in ordered {
		ordered_paths[i] = f.name
	}
	return Program{files = ordered[:], paths = ordered_paths}, ""
}

// The folder a sketch file lives in.
root_of :: proc(sketch: string) -> string {
	if i := strings.last_index_byte(sketch, '/'); i >= 0 {
		return sketch[:i] if i > 0 else "/"
	}
	return "."
}

// The folder of the program a file belongs to: the nearest folder above it (or its
// own) that holds a `sketch.roci`. A file with no such folder is a program alone.
program_root :: proc(file: string) -> (root: string, found: bool) {
	dir := root_of(file)
	for {
		if os.exists(strings.concatenate({dir, "/sketch.roci"}, context.temp_allocator)) {
			return dir, true
		}
		up := root_of(dir)
		if up == dir || dir == "." || dir == "/" {
			return "", false
		}
		dir = up
	}
}
