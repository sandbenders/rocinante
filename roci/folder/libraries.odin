// SPDX-License-Identifier: 0BSD
//
// Vendored libraries: `roci get` copies a library from a git repository into the
// sketch's `libs/` folder, and `roci update` fetches a newer copy and says what
// changed. A library is a folder of .roci files; what it came from is written in a
// `source` file beside them. git is the user's own tool, and nothing is fetched
// except when one of these is asked for (or a `use` of a git URL is met).
package folder

import "../lang"
import "core:os"
import "core:slice"
import "core:strings"

Library_Error :: enum {
	None,
	Git_Missing,      // git is not installed
	Bad_Name,         // the name cannot be a folder
	Needs_Address,    // a short name: there is no index to look it up in yet
	Already_Here,     // libs/<name> is there already
	Clone_Failed,     // git could not fetch it; the detail is git's own words
	No_Roci_Files,    // the repository holds no .roci file
	Cannot_Write,     // a file or folder could not be made
	Not_From_Get,     // libs/<name> has no `source` file, so there is nothing to fetch it from
	Not_Found,        // there is no libs/<name>
}

// What `get_library` did.
Fetched :: struct {
	name:      string,
	url:       string,
	commit:    string,
	files:     []string, // the .roci files, relative to libs/<name>
	needs:     []string, // libraries it asked for with a git URL, fetched too
	missing:   []string, // libraries it asked for by name only, which have to be fetched by hand
	conflicts: []string, // a library it asks for that is here already, from another place
}

// What `update_library` found.
Updated :: struct {
	name:       string,
	old_commit: string,
	new_commit: string,
	added:      []string,
	changed:    []string,
	removed:    []string,
	same:       bool, // nothing differs; the copy was left as it was
}

// Where a library came from, as `source` records it.
Library_Source :: struct {
	url:    string,
	commit: string,
}

SOURCE_FILE :: "source"

// The address git is given for what the writer typed: a scheme, a path, `git@` and `~`
// stay as written, and a bare `github.com/someone/name` is an https address.
clone_url :: proc(written: string) -> string {
	switch {
	case strings.contains(written, "://"), strings.has_prefix(written, "/"), strings.has_prefix(written, "."), strings.has_prefix(written, "~"), strings.has_prefix(written, "git@"):
		return written
	}
	first := written[:strings.index_byte(written, '/')] if strings.contains(written, "/") else written
	if strings.contains(first, ".") {
		return strings.concatenate({"https://", written}, context.temp_allocator)
	}
	return written
}

// Whether a library name can be a folder name: letters, digits, `-` and `_`.
valid_library_name :: proc(name: string) -> bool {
	if name == "" {
		return false
	}
	for r in name {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '-', r == '_':
		case:
			return false
		}
	}
	return true
}

// Reads `libs/<name>/source`.
read_library_source :: proc(root, name: string) -> (source: Library_Source, found: bool) {
	data, err := os.read_entire_file(strings.concatenate({root, "/libs/", name, "/", SOURCE_FILE}, context.temp_allocator), context.temp_allocator)
	if err != nil {
		return {}, false
	}
	for line in strings.split_lines(string(data), context.temp_allocator) {
		key, _, value := strings.partition(line, "=")
		value = strings.trim(strings.trim_space(value), "\"")
		switch strings.trim_space(key) {
		case "url":    source.url = value
		case "commit": source.commit = value
		}
	}
	return source, source.url != ""
}

// The libraries in `libs/` that came from `roci get`, by name.
vendored_libraries :: proc(root: string) -> []string {
	found := make([dynamic]string, context.temp_allocator)
	libs := strings.concatenate({root, "/libs"}, context.temp_allocator)
	handle, err := os.open(libs)
	if err != nil {
		return nil
	}
	defer os.close(handle)
	entries, _ := os.read_dir(handle, -1, context.temp_allocator)
	for entry in entries {
		if _, has := read_library_source(root, entry.name); has {
			append(&found, strings.clone(entry.name, context.temp_allocator))
		}
	}
	slice.sort(found[:])
	return found[:]
}

// Fetches the repository at `url` into a new folder `dest` (which must not exist), and
// gives the commit it is at. The `.git` folder is not kept: the copy is the sketch's.
@(private)
clone_into :: proc(url, dest: string) -> (commit: string, err: Library_Error, detail: string) {
	if !git_installed() {
		return "", .Git_Missing, ""
	}
	if ok, text := run("", "git", "clone", "--depth", "1", "-q", clone_url(url), dest); !ok {
		_ = os.remove_all(dest)
		return "", .Clone_Failed, text
	}
	ok, hash := run(dest, "git", "rev-parse", "HEAD")
	_ = os.remove_all(strings.concatenate({dest, "/.git"}, context.temp_allocator))
	if !ok {
		_ = os.remove_all(dest)
		return "", .Clone_Failed, hash
	}
	return strings.clone(hash, context.temp_allocator), .None, ""
}

@(private)
write_source :: proc(dir, url, commit: string) -> bool {
	text := strings.concatenate({"url = \"", url, "\"\ncommit = \"", commit, "\"\n"}, context.temp_allocator)
	return os.write_entire_file(strings.concatenate({dir, "/", SOURCE_FILE}, context.temp_allocator), transmute([]byte)text) == nil
}

// Copies the library at `url` into `libs/<name>/` of the sketch in `root`: the name is the
// last part of the address unless `as_name` gives one. The libraries it asks for with a git
// URL are fetched too, flat, and one that is there already from another address is said,
// never replaced.
get_library :: proc(root, url: string, as_name := "", depth := 0) -> (result: Fetched, err: Library_Error, detail: string) {
	if !strings.contains(url, "/") && !strings.contains(url, ":") && !os.exists(url) {
		return {}, .Needs_Address, url
	}
	name := as_name if as_name != "" else lang.library_name(url)
	if !valid_library_name(name) {
		return {}, .Bad_Name, name
	}
	libs := strings.concatenate({root, "/libs"}, context.temp_allocator)
	dest := strings.concatenate({libs, "/", name}, context.temp_allocator)
	if os.exists(dest) {
		return {}, .Already_Here, name
	}
	if !ensure_directory(libs) {
		return {}, .Cannot_Write, libs
	}
	staging := strings.concatenate({libs, "/.fetching-", name}, context.temp_allocator)
	_ = os.remove_all(staging)
	commit: string
	commit, err, detail = clone_into(url, staging)
	if err != .None {
		return {}, err, detail
	}
	files := library_files(staging)
	if len(files) == 0 {
		_ = os.remove_all(staging)
		return {}, .No_Roci_Files, url
	}
	if !write_source(staging, url, commit) || os.rename(staging, dest) != nil {
		_ = os.remove_all(staging)
		return {}, .Cannot_Write, dest
	}
	result = Fetched{name = name, url = url, commit = commit}
	listed := make([dynamic]string, context.temp_allocator)
	needs := make([dynamic]string, context.temp_allocator)
	missing := make([dynamic]string, context.temp_allocator)
	conflicts := make([dynamic]string, context.temp_allocator)
	for path in library_files(dest) {
		append(&listed, strings.trim_prefix(path, strings.concatenate({dest, "/"}, context.temp_allocator)))
		data, read_err := os.read_entire_file(path, context.temp_allocator)
		if read_err != nil {
			continue
		}
		for wanted in lang.use_texts_in(path, string(data), context.temp_allocator) {
			dep := lang.library_name(wanted)
			if os.is_directory(strings.concatenate({libs, "/", dep}, context.temp_allocator)) {
				if there, has := read_library_source(root, dep); has && strings.contains(wanted, "/") && clone_url(there.url) != clone_url(wanted) {
					append(&conflicts, strings.concatenate({dep, " from ", wanted, ", but libs/", dep, " came from ", there.url}, context.temp_allocator))
				}
			} else if strings.contains(wanted, "/") && depth < 8 {
				if _, dep_err, _ := get_library(root, wanted, "", depth + 1); dep_err == .None {
					append(&needs, dep)
				} else {
					append(&missing, wanted)
				}
			} else {
				append(&missing, wanted)
			}
		}
	}
	result.files, result.needs, result.missing, result.conflicts = listed[:], needs[:], missing[:], conflicts[:]
	return result, .None, ""
}

// Fetches a newer copy of `libs/<name>/`, says which of its files were added, changed or
// removed, and replaces the copy when any were (or the commit moved). The library has to have
// come from `roci get`, which is what `source` records.
update_library :: proc(root, name: string) -> (result: Updated, err: Library_Error, detail: string) {
	dir := strings.concatenate({root, "/libs/", name}, context.temp_allocator)
	if !os.is_directory(dir) {
		return {}, .Not_Found, name
	}
	source, has := read_library_source(root, name)
	if !has {
		return {}, .Not_From_Get, name
	}
	staging := strings.concatenate({root, "/libs/.fetching-", name}, context.temp_allocator)
	_ = os.remove_all(staging)
	commit: string
	commit, err, detail = clone_into(source.url, staging)
	if err != .None {
		return {}, err, detail
	}
	defer os.remove_all(staging)
	result = Updated{name = name, old_commit = source.commit, new_commit = commit}
	old_files, new_files := all_files(dir), all_files(staging)
	added := make([dynamic]string, context.temp_allocator)
	changed := make([dynamic]string, context.temp_allocator)
	removed := make([dynamic]string, context.temp_allocator)
	for file in new_files {
		if file == SOURCE_FILE {
			continue
		}
		if !slice.contains(old_files, file) {
			append(&added, file)
			continue
		}
		before, _ := os.read_entire_file(strings.concatenate({dir, "/", file}, context.temp_allocator), context.temp_allocator)
		after, _ := os.read_entire_file(strings.concatenate({staging, "/", file}, context.temp_allocator), context.temp_allocator)
		if !slice.equal(before, after) {
			append(&changed, file)
		}
	}
	for file in old_files {
		if file != SOURCE_FILE && !slice.contains(new_files, file) {
			append(&removed, file)
		}
	}
	result.added, result.changed, result.removed = added[:], changed[:], removed[:]
	if len(added) + len(changed) + len(removed) == 0 {
		result.same = true
		return result, .None, ""
	}
	if !write_source(staging, source.url, commit) {
		return {}, .Cannot_Write, staging
	}
	if os.remove_all(dir) != nil || os.rename(staging, dir) != nil {
		return {}, .Cannot_Write, dir
	}
	return result, .None, ""
}

// Every file under a folder, relative to it, in the order of their names.
@(private)
all_files :: proc(dir: string) -> []string {
	found := make([dynamic]string, context.temp_allocator)
	w: os.Walker
	os.walker_init(&w, dir)
	defer os.walker_destroy(&w)
	cwd, _ := os.get_working_directory(context.temp_allocator)
	prefix := strings.concatenate({dir, "/"}, context.temp_allocator) if strings.has_prefix(dir, "/") else strings.concatenate({cwd, "/", strings.trim_prefix(dir, "./"), "/"}, context.temp_allocator)
	for fi in os.walker_walk(&w) {
		if fi.type == .Directory {
			continue
		}
		append(&found, strings.clone(strings.trim_prefix(fi.fullpath, prefix), context.temp_allocator))
	}
	slice.sort(found[:])
	return found[:]
}

// The libraries a program asks for by git address that are not in `libs/` yet, fetched.
// `use "github.com/someone/flocking"` is what makes `roci run` do this the first time.
fetch_missing_libraries :: proc(root: string, files: []lang.File_Text) -> []Fetched {
	fetched := make([dynamic]Fetched, context.temp_allocator)
	for f in files {
		for wanted in lang.use_texts_in(f.name, f.text, context.temp_allocator) {
			name := lang.library_name(wanted)
			if !strings.contains(wanted, "/") || os.is_directory(strings.concatenate({root, "/libs/", name}, context.temp_allocator)) {
				continue
			}
			if result, err, _ := get_library(root, wanted); err == .None {
				append(&fetched, result)
			}
		}
	}
	return fetched[:]
}
