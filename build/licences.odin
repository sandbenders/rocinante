// SPDX-License-Identifier: 0BSD
package build

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

import "../tools/term"

ALLOWED_LICENCES :: []string{
	"0BSD", "MIT", "MIT-0", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause",
	"ISC", "Zlib", "Unlicense", "Public-Domain",
}

// Licences that may only be used with a source notice shipped alongside.
NOTICE_LICENCES :: []string{"MPL-2.0"}

contains :: proc(list: []string, s: string) -> bool {
	for item in list {
		if item == s {
			return true
		}
	}
	return false
}

// Turns the text of tools/licences.txt into a map from entry name to licence
// id. A line that is not `<what> <SPDX id>` is reported and skipped.
parse_licence_table :: proc(text: string) -> (table: map[string]string, errors: [dynamic]string) {
	table = make(map[string]string)
	remaining := text
	for raw in strings.split_lines_iterator(&remaining) {
		line := strings.trim_space(raw)
		if len(line) == 0 || line[0] == '#' {
			continue
		}
		fields := strings.fields(line)
		if len(fields) != 2 {
			append(&errors, fmt.aprintf("expected '<what> <SPDX id>', got '%s'", line))
			continue
		}
		table[fields[0]] = fields[1]
	}
	return
}

// Reads tools/licences.txt under root.
read_licence_table :: proc(root: string) -> (table: map[string]string, ok: bool) {
	path := fmt.tprintf("%s/tools/licences.txt", root)
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		fmt.eprintfln("cannot read %s: %v", path, err)
		return
	}
	errors: [dynamic]string
	table, errors = parse_licence_table(string(data))
	for message in errors {
		fmt.eprintfln("%s: %s", path, message)
	}
	ok = len(errors) == 0
	return
}

// The vendor: packages that Odin source text imports, as `vendor:<package>`,
// with any sub-package folded into its package (vendor:sdl3/image is
// vendor:sdl3) because one entry in the table covers both. Only real import
// lines count, not comments or other code that mentions a vendor: path.
vendor_imports :: proc(text: string) -> (names: [dynamic]string) {
	remaining := text
	for line in strings.split_lines_iterator(&remaining) {
		trimmed := strings.trim_space(line)
		is_import := strings.has_prefix(trimmed, "import ") || strings.has_prefix(trimmed, "foreign import ")
		at := strings.index(line, "\"vendor:")
		if !is_import || at < 0 {
			continue
		}
		rest := line[at + len("\"vendor:"):]
		end := strings.index_byte(rest, '"')
		if end < 0 {
			continue
		}
		top, _, _ := strings.partition(rest[:end], "/")
		append(&names, fmt.aprintf("vendor:%s", top))
	}
	return
}

// Finds the vendor: packages imported by .odin files and the directories in vendor/.
collect_dependencies :: proc(root: string) -> (imports: map[string]string, dirs: [dynamic]string, ok: bool) {
	imports = make(map[string]string)
	ok = true

	w: os.Walker
	os.walker_init(&w, root)
	defer os.walker_destroy(&w)
	for fi in os.walker_walk(&w) {
		if path, err := os.walker_error(&w); err != nil {
			fmt.eprintfln("cannot read %s: %v", path, err)
			ok = false
			continue
		}
		if fi.type == .Directory {
			// .cache holds the Odin the pipelines install; its vendor: packages are not ours.
			if fi.name == ".git" || fi.name == "output" || fi.name == ".cache" {
				os.walker_skip_dir(&w)
			}
			continue
		}
		if !strings.has_suffix(fi.name, ".odin") {
			continue
		}
		data, err := os.read_entire_file(fi.fullpath, context.allocator)
		if err != nil {
			fmt.eprintfln("cannot read %s: %v", fi.fullpath, err)
			ok = false
			continue
		}
		for name in vendor_imports(string(data)) {
			imports[name] = strings.clone(fi.fullpath)
		}
	}

	vendor_dir := fmt.tprintf("%s/vendor", root)
	if os.exists(vendor_dir) {
		infos, err := os.read_all_directory_by_path(vendor_dir, context.allocator)
		if err != nil {
			fmt.eprintfln("cannot read %s: %v", vendor_dir, err)
			ok = false
		}
		for info in infos {
			if info.type == .Directory {
				append(&dirs, fmt.aprintf("vendor/%s", info.name))
			}
		}
	}
	return
}

// What is wrong with the licences, as messages, in a stable order: entries
// with a forbidden or unknown licence, then imports and vendor/ directories
// that have no entry. Warnings are things that pass but need action later.
licence_problems :: proc(table: map[string]string, imports: map[string]string, dirs: []string) -> (errors, warnings: [dynamic]string) {
	names, _ := slice.map_keys(table, context.temp_allocator)
	slice.sort(names)
	for name in names {
		id := table[name]
		lower := strings.to_lower(id, context.temp_allocator)
		if strings.contains(lower, "gpl") {
			append(&errors, fmt.aprintf("%s is %s. GPL, LGPL and AGPL code may not ship.", name, id))
		} else if contains(NOTICE_LICENCES, id) {
			append(&warnings, fmt.aprintf("%s is %s; a source notice must ship with packaged sketches.", name, id))
		} else if !contains(ALLOWED_LICENCES, id) {
			append(&errors, fmt.aprintf("%s has the licence '%s', which is not on the allowed list in build/licences.odin.", name, id))
		}
	}

	imported, _ := slice.map_keys(imports, context.temp_allocator)
	slice.sort(imported)
	for name in imported {
		if name not_in table {
			append(&errors, fmt.aprintf("%s imports %s, which is not in tools/licences.txt. Read its licence file and add a line.", imports[name], name))
		}
	}

	sorted_dirs := slice.clone(dirs, context.temp_allocator)
	slice.sort(sorted_dirs)
	for dir in sorted_dirs {
		if dir not_in table {
			append(&errors, fmt.aprintf("%s is not in tools/licences.txt. Add a line with its SPDX licence id.", dir))
		}
	}
	return
}

check_licences :: proc(root: string) -> bool {
	table, table_ok := read_licence_table(root)
	if !table_ok {
		return false
	}
	imports, dirs, deps_ok := collect_dependencies(root)
	errors, warnings := licence_problems(table, imports, dirs[:])

	for message in warnings {
		fmt.eprintfln("%s %s", term.err("licences: warning:", .Yellow), message)
	}
	for message in errors {
		fmt.eprintfln("%s %s", term.err("licences:", .Bold_Red), message)
	}
	ok := deps_ok && len(errors) == 0
	if ok {
		fmt.printfln("%s %s", term.out("licences:", .Bold), term.out(fmt.tprintf("ok (%d entries, %d vendor: imports, %d vendor/ directories)", len(table), len(imports), len(dirs)), .Green))
	}
	return ok
}

// The files git tracks that are fonts and are not the ones rocinante ships (roci/gfx/fonts:
// Inter, under the SIL Open Font License). An installed font that a run copied into a sketch
// carries the licence of its owner, which may not allow it to be shared, so one must never be
// committed by accident: `git add -A` after a run that copied one did exactly that.
unexpected_fonts :: proc(files: []string, allocator := context.temp_allocator) -> []string {
	found := make([dynamic]string, allocator)
	for file in files {
		lower := strings.to_lower(file, context.temp_allocator)
		is_font := false
		for extension in ([?]string{".ttf", ".otf", ".ttc", ".otc", ".woff", ".woff2"}) {
			is_font ||= strings.has_suffix(lower, extension)
		}
		if is_font && !strings.has_prefix(file, "roci/gfx/fonts/") {
			append(&found, file)
		}
	}
	return found[:]
}

// Says whether git tracks a font that it should not. A folder that is not a git repository (a
// source archive) has nothing tracked, so nothing is wrong.
check_tracked_fonts :: proc(root: string) -> bool {
	state, stdout, _, err := os.process_exec({command = {"git", "-C", root, "ls-files", "-z"}}, context.temp_allocator)
	if err != nil || !state.success {
		return true
	}
	files := strings.split(string(stdout), "\x00", context.temp_allocator)
	extra := unexpected_fonts(files)
	for file in extra {
		fmt.eprintfln("%s %s", term.err("fonts:", .Bold_Red), fmt.tprintf("%s is a font that git tracks, and it is not one that rocinante ships (roci/gfx/fonts). A font that was installed on a computer may not be shared: take it out of git with `git rm --cached`.", file))
	}
	if len(extra) == 0 {
		fmt.printfln("%s %s", term.out("fonts:", .Bold), term.out("ok (no font but Inter is tracked)", .Green))
	}
	return len(extra) == 0
}
