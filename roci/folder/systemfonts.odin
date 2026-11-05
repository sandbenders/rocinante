// SPDX-License-Identifier: 0BSD
//
// Fonts installed on the computer, for `font "Name"` when the sketch's own `assets/`
// has no such file. The font is copied into the sketch whatever its licence; this
// file also reads the licence fields of a font file (the OpenType `name` table's
// copyright, licence description and licence URL, and the `OS/2` table's embedding
// bits) so the sketch can be warned when nothing names a free licence (SIL Open Font
// License, Apache, Ubuntu, MIT, public domain) or a restriction bit is set. What to
// do about it is the writer's business.
package folder

import "core:os"
import "core:strings"
import "core:unicode/utf16"

Font_Info :: struct {
	family:    string,
	copyright: string,
	licence:   string, // the licence description (name id 13)
	url:       string, // the licence URL (name id 14)
	embedding: u16,    // `OS/2` fsType, 0 when the table is missing
	has_os2:   bool,
}

Font_Licence :: enum {
	Unknown,    // nothing says it may be shared, or it cannot be read
	Open,       // a free licence is named and no restriction is set
	Restricted, // the font says it may not be embedded or shared
}

// Reads the licence fields of a font file (TrueType, OpenType, or a collection, of
// which the first font is read). Strings are made with the allocator given. False
// when the bytes are not a font this can read.
read_font_info :: proc(bytes: []u8, allocator := context.allocator) -> (info: Font_Info, ok: bool) {
	start := 0
	if len(bytes) >= 16 && string(bytes[:4]) == "ttcf" {
		start = int(be32(bytes, 12))
	}
	if start + 12 > len(bytes) {
		return {}, false
	}
	version := string(bytes[start:][:4])
	if version != "\x00\x01\x00\x00" && version != "OTTO" && version != "true" {
		return {}, false
	}
	tables := int(be16(bytes, start + 4))
	name_at, name_len, os2_at := -1, 0, -1
	for i in 0 ..< tables {
		record := start + 12 + i * 16
		if record + 16 > len(bytes) {
			return {}, false
		}
		offset, length := int(be32(bytes, record + 8)), int(be32(bytes, record + 12))
		switch string(bytes[record:][:4]) {
		case "name":
			name_at, name_len = offset, length
		case "OS/2":
			os2_at = offset
		}
	}
	if name_at < 0 || name_at + 6 > len(bytes) {
		return {}, false
	}
	if os2_at >= 0 && os2_at + 10 <= len(bytes) {
		info.embedding = be16(bytes, os2_at + 8)
		info.has_os2 = true
	}
	count := int(be16(bytes, name_at + 2))
	strings_at := name_at + int(be16(bytes, name_at + 4))
	// Windows and Unicode names are UTF-16, Macintosh ones are plain Roman text; the
	// first of each id found is kept, English Windows names first.
	best := [15]int{}
	for i in 0 ..< count {
		record := name_at + 6 + i * 12
		if record + 12 > len(bytes) {
			break
		}
		platform, language, id := be16(bytes, record), be16(bytes, record + 4), int(be16(bytes, record + 6))
		if id > 14 {
			continue
		}
		rank := 1
		if platform == 3 && language == 0x0409 {
			rank = 3
		} else if platform == 3 || platform == 0 {
			rank = 2
		}
		if rank <= best[id] {
			continue
		}
		length, offset := int(be16(bytes, record + 8)), int(be16(bytes, record + 10))
		from := strings_at + offset
		if from + length > len(bytes) {
			continue
		}
		text := decode_name(bytes[from:][:length], platform != 1, allocator)
		best[id] = rank
		switch id {
		case 0:  info.copyright = text
		case 1:  info.family = text
		case 13: info.licence = text
		case 14: info.url = text
		}
	}
	return info, true
}

@(private)
be16 :: proc(bytes: []u8, at: int) -> u16 {
	if at < 0 || at + 2 > len(bytes) {
		return 0
	}
	return u16(bytes[at]) << 8 | u16(bytes[at + 1])
}

@(private)
be32 :: proc(bytes: []u8, at: int) -> u32 {
	return u32(be16(bytes, at)) << 16 | u32(be16(bytes, at + 2))
}

@(private)
decode_name :: proc(raw: []u8, utf16_be: bool, allocator := context.allocator) -> string {
	if !utf16_be {
		return strings.clone(string(raw), allocator)
	}
	units := make([]u16, len(raw) / 2, context.temp_allocator)
	for i in 0 ..< len(units) {
		units[i] = be16(raw, i * 2)
	}
	runes := make([]rune, len(units), context.temp_allocator)
	n := utf16.decode(runes, units)
	return strings.clone(runes_to_string(runes[:n]), allocator)
}

@(private)
runes_to_string :: proc(runes: []rune) -> string {
	builder := strings.builder_make(context.temp_allocator)
	for r in runes {
		strings.write_rune(&builder, r)
	}
	return strings.to_string(builder)
}

// Words in a font's licence fields that name a free licence.
@(private)
OPEN_LICENCE_WORDS := [?]string{
	"sil open font license", "sil open font licence", "scripts.sil.org/ofl", "openfontlicense", "open font license",
	"apache license", "apache.org/licenses", "ubuntu font licence", "ubuntu font license", "mit license",
	"opensource.org/licenses/mit", "public domain", "creativecommons.org/publicdomain", "cc0",
}

// What a font's own fields say about sharing it. The embedding bit 2 ("restricted
// licence") always wins, and otherwise a free licence has to be named: a font that
// says nothing is not assumed free.
font_licence :: proc(info: Font_Info) -> Font_Licence {
	if info.has_os2 && info.embedding & 0x0002 != 0 {
		return .Restricted
	}
	all := strings.to_lower(strings.concatenate({info.copyright, " ", info.licence, " ", info.url}, context.temp_allocator), context.temp_allocator)
	for word in OPEN_LICENCE_WORDS {
		if strings.contains(all, word) {
			return .Open
		}
	}
	return .Unknown
}

// The name of the licence to say when a font is copied, from its fields.
font_licence_name :: proc(info: Font_Info) -> string {
	all := strings.to_lower(strings.concatenate({info.copyright, " ", info.licence, " ", info.url}, context.temp_allocator), context.temp_allocator)
	switch {
	case strings.contains(all, "open font licen") || strings.contains(all, "scripts.sil.org/ofl") || strings.contains(all, "openfontlicense"):
		return "SIL Open Font License"
	case strings.contains(all, "apache"):
		return "Apache License"
	case strings.contains(all, "ubuntu font licen"):
		return "Ubuntu Font Licence"
	case strings.contains(all, "mit license"):
		return "MIT License"
	}
	return "a free licence"
}

FONT_FILE_EXTENSIONS :: [?]string{".ttf", ".otf", ".ttc", ".otc"}

// Where the computer keeps its fonts. A test sets `system_font_dirs` to look
// somewhere else.
@(thread_local)
system_font_dirs: []string

@(private)
default_font_dirs :: proc() -> []string {
	dirs := make([dynamic]string, context.temp_allocator)
	when ODIN_OS == .Darwin {
		home := os.get_env("HOME", context.temp_allocator)
		append(&dirs, strings.concatenate({home, "/Library/Fonts"}, context.temp_allocator), "/Library/Fonts", "/System/Library/Fonts", "/System/Library/Fonts/Supplemental")
	} else when ODIN_OS == .Windows {
		local := os.get_env("LOCALAPPDATA", context.temp_allocator)
		if local != "" {
			append(&dirs, strings.concatenate({local, "/Microsoft/Windows/Fonts"}, context.temp_allocator))
		}
		append(&dirs, "C:/Windows/Fonts")
	} else {
		home := os.get_env("HOME", context.temp_allocator)
		append(&dirs, strings.concatenate({home, "/.local/share/fonts"}, context.temp_allocator), strings.concatenate({home, "/.fonts"}, context.temp_allocator), "/usr/local/share/fonts", "/usr/share/fonts")
	}
	return dirs[:]
}

// A name as the files of fonts spell it: lowercase letters and digits only, so
// "Helvetica Neue", "HelveticaNeue" and "helvetica-neue" are one name.
@(private)
simple_name :: proc(name: string) -> string {
	builder := strings.builder_make(context.temp_allocator)
	for r in name {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9':
			strings.write_rune(&builder, r)
		case r >= 'A' && r <= 'Z':
			strings.write_rune(&builder, r + 32)
		case r > 127:
			strings.write_rune(&builder, r)
		}
	}
	return strings.to_string(builder)
}

// The font file installed on this computer for a name, or "" when there is none.
// The file's name has to be the font's name (`Helvetica Neue`, `HelveticaNeue`) or
// the name and `Regular`, with or without a hyphen; the folders are searched a few
// levels down, those of the user first. The path is made with the temporary allocator.
find_system_font :: proc(name: string) -> (path: string, found: bool) {
	wanted := simple_name(name)
	if wanted == "" {
		return "", false
	}
	dirs := system_font_dirs if system_font_dirs != nil else default_font_dirs()
	exact, regular := "", ""
	for dir in dirs {
		search_font_dir(dir, wanted, 0, &exact, &regular)
		if exact != "" {
			break
		}
	}
	if exact != "" {
		return exact, true
	}
	return regular, regular != ""
}

@(private)
search_font_dir :: proc(dir, wanted: string, depth: int, exact, regular: ^string) {
	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil {
		return
	}
	for entry in entries {
		full := strings.concatenate({dir, "/", entry.name}, context.temp_allocator)
		if entry.type == .Directory {
			if depth < 4 {
				search_font_dir(full, wanted, depth + 1, exact, regular)
			}
			continue
		}
		dot := strings.last_index_byte(entry.name, '.')
		if dot < 0 {
			continue
		}
		is_font := false
		lower := strings.to_lower(entry.name[dot:], context.temp_allocator)
		for extension in FONT_FILE_EXTENSIONS {
			is_font ||= lower == extension
		}
		if !is_font {
			continue
		}
		stem := simple_name(entry.name[:dot])
		if stem == wanted && exact^ == "" {
			exact^ = full
		} else if stem == strings.concatenate({wanted, "regular"}, context.temp_allocator) && regular^ == "" {
			regular^ = full
		}
	}
}

// The extension (with its dot) of a font file name, in lowercase.
font_extension :: proc(path: string) -> string {
	dot := strings.last_index_byte(path, '.')
	if dot < 0 {
		return ""
	}
	return strings.to_lower(path[dot:], context.temp_allocator)
}
