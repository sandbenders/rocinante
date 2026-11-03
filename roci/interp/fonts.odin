// SPDX-License-Identifier: 0BSD
//
// Fonts a sketch brings: `font "Mono"` finds Inter's two faces inside the program, then
// a font file in the sketch's `assets/`, by its name with or without `.ttf`, `.otf`,
// `.ttc` or `.otc`, and last a font installed on the computer. An installed font is
// copied into `assets/fonts` the first time (so the sketch looks the same everywhere
// and travels with it) and says so in a line; one whose own licence fields do not name
// a free licence also gets a warning, and nothing more: sharing it is the writer's call. A
// font is read once, the first time a sketch asks for it, and a name nothing answers
// is not looked for again while the sketch runs.
package interp

import "../"
import "../folder"
import "../lang"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"

FONT_EXTENSIONS :: [?]string{"", ".ttf", ".otf", ".ttc", ".otc"}

// Makes sure a font of this name is there, reading it from the sketch's assets when it
// is not built in and not read yet. False when there is none.
@(private)
ensure_font :: proc(it: ^Interp, name: string, span: lang.Span) -> bool {
	if roci.has_font(name) {
		return true
	}
	if it.fonts_missed[name] {
		return false
	}
	root, found := assets_root(it)
	if found && font_from_assets(it, root, name) {
		return true
	}
	if font_from_system(it, root if found else "", name, span) {
		return true
	}
	if it.fonts_missed == nil {
		it.fonts_missed = make(map[string]bool, runtime.heap_allocator())
	}
	it.fonts_missed[strings.clone(name, runtime.heap_allocator())] = true
	return false
}

// Reads the font file `name` from the sketch's assets.
@(private)
font_from_assets :: proc(it: ^Interp, root, name: string) -> bool {
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

// Finds an installed font by name and copies it into the sketch (`root` is "" for a
// lone file, which has no folder to copy into). A font whose licence is not known to
// be free is copied too, with a warning: sharing it is the writer's decision.
@(private)
font_from_system :: proc(it: ^Interp, root, name: string, span: lang.Span) -> bool {
	path, found := folder.find_system_font(name)
	if !found {
		return false
	}
	bytes, read_err := os.read_entire_file(path, context.temp_allocator)
	if read_err != nil {
		return false
	}
	info, readable := folder.read_font_info(bytes, context.temp_allocator)
	licence := folder.font_licence(info) if readable else .Unknown
	if !roci.add_font(name, bytes) {
		return false
	}
	if root != "" {
		copy_font_into(it, root, name, path, bytes, info, licence)
	}
	if licence != .Open {
		// What the licence means for sharing is the writer's own business: say it and go on.
		why := "its licence does not say that it may be shared." if licence == .Unknown else "its licence says it may not be shared."
		fail(it, .Font_Licence, span, name, why, "", "font \"Inter\"")
	}
	return true
}

// Puts a copy of an installed font into `assets/fonts` under the name the sketch
// asked for, unless a file of that name is there, and says so in one line.
@(private)
copy_font_into :: proc(it: ^Interp, root, name, from: string, bytes: []u8, info: folder.Font_Info, licence: folder.Font_Licence) {
	directory := concat(root, "/assets/fonts")
	if !folder.ensure_directory(concat(root, "/assets")) || !folder.ensure_directory(directory) {
		return
	}
	target := concat(directory, "/", name, folder.font_extension(from))
	if os.exists(target) {
		return
	}
	if os.write_entire_file(target, bytes) != nil {
		return
	}
	if licence == .Open {
		notice(it, fmt.tprintf("copied the font %s into assets/fonts, under the %s, so your sketch travels with it", name, folder.font_licence_name(info)))
	} else {
		notice(it, fmt.tprintf("copied the font %s into assets/fonts, so your sketch looks the same everywhere", name))
	}
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
