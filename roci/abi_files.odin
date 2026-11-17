// SPDX-License-Identifier: 0BSD
//
// Files for C: the language reads and writes data files into records and lists, which C has no kind for, so C
// gets the files themselves as text and parses them as it likes. A write goes beside its name and is moved
// over it, so a file is never left half written.
package roci

import "core:c"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

abi_files_group :: proc(all: ^[dynamic]Abi_Entry) {
	append(all, abi_entry("roci_read_file", typeid_of(type_of(abi_read_file)), "const char *roci_read_file(const char *path)", "The text of a file, or NULL when it is not there or cannot be read. The text stays valid until the next function that gives text back."))
	append(all, abi_entry("roci_write_file", typeid_of(type_of(abi_write_file)), "int roci_write_file(const char *path, const char *text)", "Writes text to a file, making the folders in its path, and gives 1 when it was written. A file is never left half written."))
	append(all, abi_entry("roci_file_count", typeid_of(type_of(abi_file_count)), "int roci_file_count(const char *folder)", "How many files are in a folder, 0 for one that is not there. Folders inside it are not counted."))
	append(all, abi_entry("roci_file_name", typeid_of(type_of(abi_file_name)), "const char *roci_file_name(const char *folder, int index)", "The name of a file of a folder, counting from 0 in the order of the names, or NULL past the last. The text stays valid until the next function that gives text back."))
}

// Writes a text to a file whole: the folders of its path are made, and the text goes into a file beside it that
// is moved over the real one.
write_text_file :: proc(path, text: string) -> bool {
	if slash := strings.last_index_byte(path, '/'); slash > 0 {
		if err := os.make_directory_all(path[:slash]); err != nil && err != .Exist {
			return false
		}
	}
	partial := strings.concatenate({path, ".part"}, context.temp_allocator)
	if os.write_entire_file(partial, transmute([]byte)text) != nil {
		return false
	}
	if os.rename(partial, path) != nil {
		os.remove(partial)
		return false
	}
	return true
}

// The names of the files directly inside a folder, in the order of the names.
file_names :: proc(folder: string, allocator := context.temp_allocator) -> []string {
	entries, err := os.read_all_directory_by_path(folder, context.temp_allocator)
	if err != nil {
		return nil
	}
	names := make([dynamic]string, allocator)
	for e in entries {
		if e.type != .Directory {
			append(&names, strings.clone(filepath.base(e.name), allocator))
		}
	}
	slice.sort(names[:])
	return names[:]
}

@(export, link_name = "roci_read_file")
abi_read_file :: proc "c" (path: cstring) -> cstring {
	context = abi_context()
	bytes, err := os.read_entire_file(text_from_abi(path), context.temp_allocator)
	if err != nil {
		return nil
	}
	return abi_give_text(string(bytes))
}

@(export, link_name = "roci_write_file")
abi_write_file :: proc "c" (path, text: cstring) -> c.int {
	context = abi_context()
	return 1 if write_text_file(text_from_abi(path), text_from_abi(text)) else 0
}

@(export, link_name = "roci_file_count")
abi_file_count :: proc "c" (folder: cstring) -> c.int {
	context = abi_context()
	return c.int(len(file_names(text_from_abi(folder))))
}

@(export, link_name = "roci_file_name")
abi_file_name :: proc "c" (folder: cstring, index: c.int) -> cstring {
	context = abi_context()
	names := file_names(text_from_abi(folder))
	if index < 0 || int(index) >= len(names) {
		return nil
	}
	return abi_give_text(names[index])
}
