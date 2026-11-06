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

import "base:runtime"
import "core:os"
import "core:slice"
import "core:strings"
import "core:unicode/utf16"

Font_Info :: struct {
	family:    string,
	style:     string, // the subfamily (name id 2): Regular, Bold, Italic…
	full:      string, // the full name (name id 4): Helvetica Neue Condensed Black
	postscript: string, // the PostScript name (name id 6): HelveticaNeue-CondensedBlack
	typo_family: string, // the typographic family (name id 16), when the family above is a style group
	typo_style: string, // the typographic subfamily (name id 17)
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

// Reads the licence fields of a font file (TrueType, OpenType, or a collection, of which the
// font at `face` is read, the first by default). Strings are made with the allocator given.
// False when the bytes are not a font this can read.
read_font_info :: proc(bytes: []u8, allocator := context.allocator, face := 0) -> (info: Font_Info, ok: bool) {
	start := 0
	if len(bytes) >= 16 && string(bytes[:4]) == "ttcf" {
		start = int(be32(bytes, 12 + max(face, 0) * 4))
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
	read_name_table(bytes[name_at:][:min(name_len, len(bytes) - name_at)], &info, allocator)
	return info, true
}

// Reads a font file's family and style names only, without reading the whole file:
// its table directory and its `name` table. False when it is not a font this can read.
// Strings are made with the temporary allocator.
read_font_names :: proc(path: string) -> (info: Font_Info, ok: bool) {
	f, err := os.open(path)
	if err != nil {
		return {}, false
	}
	defer os.close(f)
	head: [16]u8
	if n, _ := os.read_at(f, head[:], 0); n < 12 {
		return {}, false
	}
	start := 0
	if string(head[:4]) == "ttcf" {
		start = int(be32(head[:], 12))
	}
	return read_names_at(f, start)
}

// The names of every font in a file, one for a plain font and one for each face of a collection,
// read without reading the whole file. Strings are made with the temporary allocator.
read_collection_names :: proc(path: string) -> []Font_Info {
	f, err := os.open(path)
	if err != nil {
		return nil
	}
	defer os.close(f)
	head: [16]u8
	if n, _ := os.read_at(f, head[:], 0); n < 12 {
		return nil
	}
	starts := make([dynamic]int, context.temp_allocator)
	if string(head[:4]) == "ttcf" {
		count := min(int(be32(head[:], 8)), 256)
		offsets := make([]u8, count * 4, context.temp_allocator)
		if n, _ := os.read_at(f, offsets, 12); n < len(offsets) {
			return nil
		}
		for i in 0 ..< count {
			append(&starts, int(be32(offsets, i * 4)))
		}
	} else {
		append(&starts, 0)
	}
	out := make([dynamic]Font_Info, context.temp_allocator)
	for start in starts {
		if info, ok := read_names_at(f, start); ok {
			append(&out, info)
		}
	}
	return out[:]
}

// The names of the font that starts at `start` in an open file.
@(private)
read_names_at :: proc(f: ^os.File, start: int) -> (info: Font_Info, ok: bool) {
	head: [12]u8
	if n, _ := os.read_at(f, head[:], i64(start)); n < 12 {
		return {}, false
	}
	version := string(head[:4])
	if version != "\x00\x01\x00\x00" && version != "OTTO" && version != "true" {
		return {}, false
	}
	directory := make([]u8, int(be16(head[:], 4)) * 16, context.temp_allocator)
	if n, _ := os.read_at(f, directory, i64(start + 12)); n < len(directory) {
		return {}, false
	}
	for i in 0 ..< len(directory) / 16 {
		record := directory[i * 16:][:16]
		if string(record[:4]) != "name" {
			continue
		}
		table := make([]u8, int(be32(record, 12)), context.temp_allocator)
		if n, _ := os.read_at(f, table, i64(be32(record, 8))); n < 6 {
			return {}, false
		}
		read_name_table(table, &info, context.temp_allocator)
		return info, true
	}
	return {}, false
}

// The names a font's `name` table holds, its bytes given alone.
@(private)
read_name_table :: proc(table: []u8, info: ^Font_Info, allocator: runtime.Allocator) {
	if len(table) < 6 {
		return
	}
	count := int(be16(table, 2))
	strings_at := int(be16(table, 4))
	// Windows and Unicode names are UTF-16, Macintosh ones are plain Roman text; the
	// first of each id found is kept, English Windows names first.
	best := [18]int{}
	for i in 0 ..< count {
		record := 6 + i * 12
		if record + 12 > len(table) {
			break
		}
		platform, language, id := be16(table, record), be16(table, record + 4), int(be16(table, record + 6))
		if id > 17 {
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
		length, offset := int(be16(table, record + 8)), int(be16(table, record + 10))
		from := strings_at + offset
		if from + length > len(table) {
			continue
		}
		text := decode_name(table[from:][:length], platform != 1, allocator)
		best[id] = rank
		switch id {
		case 0:  info.copyright = text
		case 1:  info.family = text
		case 2:  info.style = text
		case 4:  info.full = text
		case 6:  info.postscript = text
		case 13: info.licence = text
		case 14: info.url = text
		case 16: info.typo_family = text
		case 17: info.typo_style = text
		}
	}
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

// The offset of each font in a file: one, 0, for a plain font, and one for each font of a
// collection (a `.ttc` or `.otc`, which holds several faces that share tables).
face_offsets :: proc(bytes: []u8, allocator := context.temp_allocator) -> []int {
	if len(bytes) >= 16 && string(bytes[:4]) == "ttcf" {
		count := min(int(be32(bytes, 8)), 256)
		offsets := make([]int, count, allocator)
		for i in 0 ..< count {
			offsets[i] = int(be32(bytes, 12 + i * 4))
		}
		return offsets
	}
	offsets := make([]int, 1, allocator)
	return offsets
}

// Reads the names (and licence fields) of the font that starts at `start` in a file's bytes.
@(private)
face_info_at :: proc(bytes: []u8, start: int, allocator: runtime.Allocator) -> (info: Font_Info, ok: bool) {
	if start < 0 || start + 12 > len(bytes) {
		return {}, false
	}
	version := string(bytes[start:][:4])
	if version != "\x00\x01\x00\x00" && version != "OTTO" && version != "true" {
		return {}, false
	}
	tables := int(be16(bytes, start + 4))
	for i in 0 ..< tables {
		record := start + 12 + i * 16
		if record + 16 > len(bytes) {
			return {}, false
		}
		if string(bytes[record:][:4]) != "name" {
			continue
		}
		at, length := int(be32(bytes, record + 8)), int(be32(bytes, record + 12))
		if at < 0 || at + 6 > len(bytes) {
			return {}, false
		}
		read_name_table(bytes[at:][:min(length, len(bytes) - at)], &info, allocator)
		return info, true
	}
	return {}, false
}

// Whether a face goes by this name (already simple-spelled, `simple_name`): its full name
// (`Helvetica Neue Condensed Black`), its PostScript name (`HelveticaNeue-CondensedBlack`),
// or its family and style (`Helvetica Neue` and `Bold`), under the plain or the typographic
// family, and the family alone for a regular style.
face_goes_by :: proc(info: Font_Info, wanted: string) -> bool {
	if wanted == "" {
		return false
	}
	candidates := [?]string{info.full, info.postscript}
	for candidate in candidates {
		if candidate != "" && simple_name(candidate) == wanted {
			return true
		}
	}
	pairs := [?][2]string{{info.family, info.style}, {info.typo_family, info.typo_style}}
	for pair in pairs {
		if pair[0] == "" {
			continue
		}
		family := simple_name(pair[0])
		style := simple_name(pair[1])
		if style != "" && strings.concatenate({family, style}, context.temp_allocator) == wanted {
			return true
		}
		if (style == "" || style == "regular") && family == wanted {
			return true
		}
	}
	return false
}

// Which face of a font file goes by this name: its number counting from 0, and false when no
// face does. A plain font is one face, 0.
face_named :: proc(bytes: []u8, name: string) -> (index: int, found: bool) {
	wanted := simple_name(name)
	for offset, i in face_offsets(bytes) {
		info, ok := face_info_at(bytes, offset, context.temp_allocator)
		if ok && face_goes_by(info, wanted) {
			return i, true
		}
	}
	return 0, false
}

// Words in a font's licence fields that name a free licence.
@(private)
OPEN_LICENCE_WORDS := [?]string{
	"sil open font license", "sil open font licence", "scripts.sil.org/ofl", "openfontlicense", "open font license",
	"apache license", "apache.org/licenses", "ubuntu font licence", "ubuntu font license", "mit license",
	"opensource.org/licenses/mit", "public domain", "creativecommons.org/publicdomain", "cc0",
}

// Words in a font's licence fields that forbid sharing it. They win over a free
// licence named in the same fields: Windows' Segoe UI and Arial say "Any other use is
// prohibited" and then name the MIT License, which covers only their Hebrew layout code.
@(private)
CLOSED_LICENCE_WORDS := [?]string{
	"any other use is prohibited", "may not be redistributed", "may not redistribute",
	"redistribution is prohibited", "redistribution is not permitted",
}

// What a font's own fields say about sharing it. The embedding bit 2 ("restricted
// licence") always wins, then words that forbid sharing, and otherwise a free licence
// has to be named: a font that says nothing is not assumed free.
font_licence :: proc(info: Font_Info) -> Font_Licence {
	if info.has_os2 && info.embedding & 0x0002 != 0 {
		return .Restricted
	}
	all := strings.to_lower(strings.concatenate({info.copyright, " ", info.licence, " ", info.url}, context.temp_allocator), context.temp_allocator)
	for word in CLOSED_LICENCE_WORDS {
		if strings.contains(all, word) {
			return .Restricted
		}
	}
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
// A file named for the font (`Helvetica Neue`, `HelveticaNeue`), or for the name and
// `Regular`, with or without a hyphen, is found from its name alone. Otherwise each
// font file is asked its family name, so `Consolas` finds Windows' `consola.ttf`, and
// a regular style wins over the others, and a name that is none of those may be a face of a collection
// (`Helvetica Neue Condensed Black`). The folders are searched a few levels down,
// those of the user first. The path is made with the temporary allocator.
find_system_font :: proc(name: string) -> (path: string, found: bool) {
	wanted := simple_name(name)
	if wanted == "" {
		return "", false
	}
	dirs := system_font_dirs if system_font_dirs != nil else default_font_dirs()
	exact, regular := "", ""
	fonts := make([dynamic]string, context.temp_allocator)
	for dir in dirs {
		search_font_dir(dir, wanted, 0, &exact, &regular, &fonts)
		if exact != "" {
			break
		}
	}
	if exact != "" {
		return exact, true
	}
	if regular != "" {
		return regular, true
	}
	any_style := ""
	for font in fonts {
		info, ok := read_font_names(font)
		if !ok || simple_name(info.family) != wanted {
			continue
		}
		if simple_name(info.style) == "regular" {
			return font, true
		}
		if any_style == "" {
			any_style = font
		}
	}
	if any_style != "" {
		return any_style, true
	}
	// Last, a face of a collection that goes by the name: `Helvetica Neue Condensed Black` is
	// one of the faces of Helvetica Neue.ttc, whose first face is the regular one.
	for font in fonts {
		if !is_collection_name(font) {
			continue
		}
		for info in read_collection_names(font) {
			if face_goes_by(info, wanted) {
				return font, true
			}
		}
	}
	return "", false
}

@(private)
search_font_dir :: proc(dir, wanted: string, depth: int, exact, regular: ^string, fonts: ^[dynamic]string) {
	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil {
		return
	}
	// in the order of their names, so every computer finds the same file first
	slice.sort_by(entries, proc(a, b: os.File_Info) -> bool {return a.name < b.name})
	for entry in entries {
		full := strings.concatenate({dir, "/", entry.name}, context.temp_allocator)
		if entry.type == .Directory {
			if depth < 4 {
				search_font_dir(full, wanted, depth + 1, exact, regular, fonts)
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
		append(fonts, full)
		stem := simple_name(entry.name[:dot])
		if stem == wanted && exact^ == "" {
			exact^ = full
		} else if stem == strings.concatenate({wanted, "regular"}, context.temp_allocator) && regular^ == "" {
			regular^ = full
		}
	}
}

// Is the name that of a font collection (`.ttc` or `.otc`)?
is_collection_name :: proc(path: string) -> bool {
	ext := font_extension(path)
	return ext == ".ttc" || ext == ".otc"
}

// The extension (with its dot) of a font file name, in lowercase.
font_extension :: proc(path: string) -> string {
	dot := strings.last_index_byte(path, '.')
	if dot < 0 {
		return ""
	}
	return strings.to_lower(path[dot:], context.temp_allocator)
}

// A collection (`.ttc`) made of whole font files, each kept as it is with its table offsets
// moved to where it now sits: the first font is the first file, and so on. Fonts that share no
// tables make a bigger file than a real collection, which is the only difference. Tests and
// tools use it where no installed collection can be counted on. Gives nil for no font or a
// file that is not a font.
join_fonts :: proc(fonts: [][]u8, allocator := context.allocator) -> []u8 {
	if len(fonts) == 0 {
		return nil
	}
	out := make([dynamic]u8, allocator)
	put32 :: proc(out: ^[dynamic]u8, v: int) {
		append(out, u8(v >> 24), u8(v >> 16), u8(v >> 8), u8(v))
	}
	append(&out, 't', 't', 'c', 'f')
	put32(&out, 0x00010000)
	put32(&out, len(fonts))
	header := 12 + 4 * len(fonts)
	at := header
	for font in fonts {
		if len(font) < 12 {
			delete(out)
			return nil
		}
		put32(&out, at)
		at += len(font)
	}
	at = header
	for font in fonts {
		start := len(out)
		append(&out, ..font)
		for i in 0 ..< int(be16(font, 4)) {
			record := start + 12 + i * 16
			if record + 16 > len(out) {
				delete(out)
				return nil
			}
			moved := int(be32(out[:], record + 8)) + at
			out[record + 8], out[record + 9], out[record + 10], out[record + 11] = u8(moved >> 24), u8(moved >> 16), u8(moved >> 8), u8(moved)
		}
		at += len(font)
	}
	return out[:]
}
