// SPDX-License-Identifier: 0BSD
package build

import "core:fmt"
import "core:os"
import "core:strings"

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

// Reads tools/licences.txt into a map from entry name to licence id.
read_licence_table :: proc(root: string) -> (table: map[string]string, ok: bool) {
	path := fmt.tprintf("%s/tools/licences.txt", root)
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		fmt.eprintfln("cannot read %s: %v", path, err)
		return
	}
	table = make(map[string]string)
	ok = true
	text := string(data)
	for raw in strings.split_lines_iterator(&text) {
		line := strings.trim_space(raw)
		if len(line) == 0 || line[0] == '#' {
			continue
		}
		fields := strings.fields(line)
		if len(fields) != 2 {
			fmt.eprintfln("%s: expected '<what> <SPDX id>', got '%s'", path, line)
			ok = false
			continue
		}
		table[fields[0]] = fields[1]
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
			if fi.name == ".git" || fi.name == "output" {
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
		text := string(data)
		for line in strings.split_lines_iterator(&text) {
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
			package_path := rest[:end]
			// vendor:sdl3/image is covered by the entry for vendor:sdl3.
			top, _, _ := strings.partition(package_path, "/")
			imports[fmt.aprintf("vendor:%s", top)] = strings.clone(fi.fullpath)
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

check_licences :: proc(root: string) -> bool {
	table, table_ok := read_licence_table(root)
	if !table_ok {
		return false
	}
	imports, dirs, deps_ok := collect_dependencies(root)
	ok := deps_ok

	for name, id in table {
		lower := strings.to_lower(id, context.temp_allocator)
		if strings.contains(lower, "gpl") {
			fmt.eprintfln("licences: %s is %s. GPL, LGPL and AGPL code may not ship (CLAUDE.md section 3).", name, id)
			ok = false
		} else if contains(NOTICE_LICENCES, id) {
			fmt.eprintfln("licences: warning: %s is %s; a source notice must ship with packaged sketches.", name, id)
		} else if !contains(ALLOWED_LICENCES, id) {
			fmt.eprintfln("licences: %s has the licence '%s', which is not on the allowed list in build/licences.odin.", name, id)
			ok = false
		}
	}

	for name, file in imports {
		if name not_in table {
			fmt.eprintfln("licences: %s imports %s, which is not in tools/licences.txt. Read its licence file and add a line.", file, name)
			ok = false
		}
	}
	for dir in dirs {
		if dir not_in table {
			fmt.eprintfln("licences: %s is not in tools/licences.txt. Add a line with its SPDX licence id.", dir)
			ok = false
		}
	}

	if ok {
		fmt.printfln("licences: ok (%d entries, %d vendor: imports, %d vendor/ directories)", len(table), len(imports), len(dirs))
	}
	return ok
}
