// SPDX-License-Identifier: 0BSD
//
// Fonts a sketch brings: `font "Mono"` finds Inter's two faces inside the program and
// anything else as a font file in the sketch's `assets/`, by its name with or without
// `.ttf` or `.otf`. A font is read once, the first time a sketch asks for it.
package interp

import "../"
import "../folder"
import "core:os"

FONT_EXTENSIONS :: [?]string{"", ".ttf", ".otf"}

// Makes sure a font of this name is there, reading it from the sketch's assets when it
// is not built in and not read yet. False when there is none.
@(private)
ensure_font :: proc(it: ^Interp, name: string) -> bool {
	if roci.has_font(name) {
		return true
	}
	if it.path == "" {
		return false
	}
	root, found := folder.program_root(it.path)
	if !found {
		return false
	}
	for extension in FONT_EXTENSIONS {
		wanted := name if extension == "" else concat(name, extension)
		path, status, _ := folder.find_asset(root, wanted, context.temp_allocator)
		if status != .Found {
			continue
		}
		bytes, read_err := os.read_entire_file(concat(root, "/", path), context.temp_allocator)
		if read_err != nil {
			continue
		}
		if roci.add_font(name, bytes) {
			return true
		}
	}
	return false
}

@(private)
concat :: proc(parts: ..string) -> string {
	total := 0
	for p in parts {
		total += len(p)
	}
	buffer := make([]u8, total, context.temp_allocator)
	at := 0
	for p in parts {
		copy(buffer[at:], p)
		at += len(p)
	}
	return string(buffer)
}
