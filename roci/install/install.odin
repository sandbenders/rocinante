// SPDX-License-Identifier: 0BSD
//
// The Windows installer of a packaged sketch, the parts that are only bytes and text, so they are tested on every system: the
// archive that carries the app's files (each deflated, or stored when that is no smaller), where it sits in the installer
// (appended to the setup program, before the signature signtool adds), the description of the app the installer reads first
// (`setup.ini`), the words of its command line, and the values it writes for Settings, Apps. `roci package windows` writes the
// archive; the setup program (`roci/install/setup`) reads it.
package install

import "../../vendor/sancho/deflate"
import inflate "core:compress/deflate"
import "core:encoding/endian"
import "core:fmt"
import "core:hash"
import "core:strconv"
import "core:strings"

// The first bytes of an archive, and of the trailer that ends a setup program carrying one.
ARCHIVE_MAGIC :: "ROCIARC1"
TRAILER_MAGIC :: "ROCISETUP1\x00\x00\x00\x00\x00\x00"
TRAILER_SIZE :: 32 // the magic, then where the archive starts in the file and its length, 8 bytes each

// The file in the archive that says what the app is, read before anything is unpacked.
SETUP_INI :: "setup.ini"

Method :: enum u8 {
	Stored  = 0,
	Deflate = 1,
}

// A file to put in the archive: its path in the app's folder, with slashes, and its bytes.
File :: struct {
	path: string,
	data: []u8,
}

// A file of an archive, as it is read: where its bytes are in the archive, how they are kept, how many there are unpacked, and
// the CRC-32 of the unpacked bytes.
Entry :: struct {
	path:   string,
	method: Method,
	size:   int,
	crc:    u32,
	packed: []u8,
}

// Kinds of file that are compressed already, so deflate would only spend time: they are stored.
STORED_KINDS :: [?]string{".png", ".jpg", ".jpeg", ".webp", ".gif", ".ogg", ".opus", ".mp3", ".m4a", ".aac", ".flac", ".mp4", ".webm", ".mkv", ".mov", ".zip", ".gz", ".zst", ".7z", ".glb", ".woff", ".woff2", ".ktx2"}

stored_kind :: proc(path: string) -> bool {
	lower := strings.to_lower(path, context.temp_allocator)
	for kind in STORED_KINDS {
		if strings.has_suffix(lower, kind) {
			return true
		}
	}
	return false
}

// The archive of `files`, in the order given: `ROCIARC1`, the count as 4 bytes, then for each file the length of its path (2
// bytes), the path, its method (1 byte), its size and its packed size (8 bytes each), its CRC-32 (4 bytes), and the packed
// bytes. Every number is little-endian.
pack :: proc(files: []File, allocator := context.allocator) -> []u8 {
	out: [dynamic]u8
	out.allocator = allocator
	append(&out, ARCHIVE_MAGIC)
	put_u32(&out, u32(len(files)))
	for f in files {
		packed := f.data
		method := Method.Stored
		if len(f.data) > 0 && !stored_kind(f.path) {
			squeezed := deflate.compress(f.data, context.temp_allocator)
			if len(squeezed) < len(f.data) {
				packed, method = squeezed, .Deflate
			}
		}
		path := transmute([]u8)f.path
		put_u16(&out, u16(len(path)))
		append(&out, ..path)
		append(&out, u8(method))
		put_u64(&out, u64(len(f.data)))
		put_u64(&out, u64(len(packed)))
		put_u32(&out, hash.crc32(f.data))
		append(&out, ..packed)
	}
	return out[:]
}

put_u16 :: proc(out: ^[dynamic]u8, v: u16) {
	b: [2]u8
	endian.put_u16(b[:], .Little, v)
	append(out, ..b[:])
}

put_u32 :: proc(out: ^[dynamic]u8, v: u32) {
	b: [4]u8
	endian.put_u32(b[:], .Little, v)
	append(out, ..b[:])
}

put_u64 :: proc(out: ^[dynamic]u8, v: u64) {
	b: [8]u8
	endian.put_u64(b[:], .Little, v)
	append(out, ..b[:])
}

// The files of an archive, without unpacking them (`entry_bytes` does). False when the bytes are not an archive, or one is cut
// short, or a path would leave the app's folder (an absolute path, a drive, `..`, or a character Windows refuses in a name).
read_archive :: proc(data: []u8, allocator := context.allocator) -> (entries: []Entry, ok: bool) {
	if len(data) < 12 || string(data[:8]) != ARCHIVE_MAGIC {
		return nil, false
	}
	count, _ := endian.get_u32(data[8:12], .Little)
	found := make([dynamic]Entry, allocator)
	at := 12
	for _ in 0 ..< count {
		if at + 2 > len(data) {
			delete(found)
			return nil, false
		}
		path_len, _ := endian.get_u16(data[at:at + 2], .Little)
		at += 2
		if at + int(path_len) + 21 > len(data) {
			delete(found)
			return nil, false
		}
		path := string(data[at:at + int(path_len)])
		at += int(path_len)
		method := data[at]
		size, _ := endian.get_u64(data[at + 1:at + 9], .Little)
		packed_size, _ := endian.get_u64(data[at + 9:at + 17], .Little)
		crc, _ := endian.get_u32(data[at + 17:at + 21], .Little)
		at += 21
		if method > u8(max(Method)) || packed_size > u64(len(data) - at) || size > 1 << 40 || !safe_path(path) {
			delete(found)
			return nil, false
		}
		append(&found, Entry{path = path, method = Method(method), size = int(size), crc = crc, packed = data[at:at + int(packed_size)]})
		at += int(packed_size)
	}
	return found[:], true
}

// Whether a path in an archive stays inside the folder it is unpacked into.
safe_path :: proc(path: string) -> bool {
	if path == "" || strings.has_prefix(path, "/") || strings.contains(path, "\\") || strings.contains(path, ":") {
		return false
	}
	for part in strings.split(path, "/", context.temp_allocator) {
		if part == "" || part == "." || part == ".." {
			return false
		}
		for c in transmute([]u8)part {
			switch c {
			case '<', '>', '"', '|', '?', '*':
				return false
			case:
				if c < ' ' {
					return false
				}
			}
		}
	}
	return true
}

// The unpacked bytes of an entry, checked against its size and CRC-32. False when they do not match.
entry_bytes :: proc(e: Entry, allocator := context.allocator) -> (data: []u8, ok: bool) {
	switch e.method {
	case .Stored:
		if len(e.packed) != e.size || hash.crc32(e.packed) != e.crc {
			return nil, false
		}
		return e.packed, true
	case .Deflate:
		out := make([dynamic]u8, 0, e.size, allocator)
		if inflate.inflate_raw(&out, e.packed, e.size, e.size + 1, allocator) != nil || len(out) != e.size || hash.crc32(out[:]) != e.crc {
			delete(out)
			return nil, false
		}
		return out[:], true
	}
	return nil, false
}

// The trailer that goes after an archive appended to a setup program of `program_size` bytes: the magic, where the archive
// starts and how long it is. Padding of zeros comes first, so the file ends on 8 bytes and signtool adds none between the trailer
// and its signature.
trailer :: proc(program_size, archive_size: int, allocator := context.allocator) -> []u8 {
	used := program_size + archive_size + TRAILER_SIZE
	padding := (8 - used % 8) % 8
	out := make([]u8, padding + TRAILER_SIZE, allocator)
	copy(out[padding:], TRAILER_MAGIC)
	endian.put_u64(out[padding + 16:], .Little, u64(program_size))
	endian.put_u64(out[padding + 24:], .Little, u64(archive_size))
	return out
}

// The archive a setup program carries, found from the end of the program's bytes: past the signature, when it has one (the PE
// header's certificate table, which signtool puts at the end of the file), past up to seven bytes of padding, to the trailer.
// False when there is no archive.
find_archive :: proc(program: []u8) -> (archive: []u8, ok: bool) {
	end := len(program)
	if table_at, table_size, signed := certificate_table(program); signed && table_at + table_size == len(program) && table_at <= end {
		end = table_at
	}
	for _ in 0 ..< 8 {
		if end >= TRAILER_SIZE && string(program[end - TRAILER_SIZE:end - 16]) == TRAILER_MAGIC {
			start, _ := endian.get_u64(program[end - 16:end - 8], .Little)
			length, _ := endian.get_u64(program[end - 8:end], .Little)
			if start > u64(end - TRAILER_SIZE) || length > u64(end - TRAILER_SIZE) - start {
				return nil, false
			}
			return program[start:start + length], true
		}
		if end == 0 || program[end - 1] != 0 {
			break
		}
		end -= 1
	}
	return nil, false
}

// Where a PE file's certificate table is and how long it is (its fifth data directory, which holds a place in the file, not
// in memory). False when the bytes are not a PE file or it is not signed.
certificate_table :: proc(data: []u8) -> (at, size: int, ok: bool) {
	if len(data) < 64 || data[0] != 'M' || data[1] != 'Z' {
		return 0, 0, false
	}
	pe_u32, _ := endian.get_u32(data[0x3C:0x40], .Little)
	pe := int(pe_u32)
	if pe < 0 || pe + 26 > len(data) || string(data[pe:pe + 4]) != "PE\x00\x00" {
		return 0, 0, false
	}
	optional := pe + 24
	magic, _ := endian.get_u16(data[optional:optional + 2], .Little)
	directories: int
	switch magic {
	case 0x20B: directories = optional + 112
	case 0x10B: directories = optional + 96
	case:       return 0, 0, false
	}
	security := directories + 4 * 8
	if security + 8 > len(data) {
		return 0, 0, false
	}
	place, _ := endian.get_u32(data[security:security + 4], .Little)
	length, _ := endian.get_u32(data[security + 4:security + 8], .Little)
	if place == 0 || length == 0 {
		return 0, 0, false
	}
	return int(place), int(length), true
}

// What the installer knows about the app it carries: written by `roci package windows` as `setup.ini`, one `key = value` a line.
App :: struct {
	name:       string, // what people call it: Wildvex
	id:         string, // org.example.wildvex, which names its entry in Settings, Apps
	version:    string, // 1.0.1
	publisher:  string, // who made it, or empty
	folder:     string, // its folder in Program Files: Wildvex
	executable: string, // wildvex.exe
	size_kb:    int,    // what it takes on the disk, in kilobytes, for Settings, Apps
}

write_ini :: proc(app: App, allocator := context.allocator) -> string {
	return fmt.aprintf("name = %s\nid = %s\nversion = %s\npublisher = %s\nfolder = %s\nexecutable = %s\nsize-kb = %d\n", one_line(app.name), one_line(app.id), one_line(app.version), one_line(app.publisher), one_line(app.folder), one_line(app.executable), app.size_kb, allocator = allocator)
}

// A value on one line: a line break in it would start another key.
one_line :: proc(text: string) -> string {
	result, _ := strings.replace_all(text, "\n", " ", context.temp_allocator)
	result, _ = strings.replace_all(result, "\r", " ", context.temp_allocator)
	return result
}

// The app `setup.ini` describes; false when the name, the id, the folder or the program is missing, or the folder or the program
// is not a plain name (so the installer only ever writes inside Program Files).
read_ini :: proc(text: string, allocator := context.allocator) -> (app: App, ok: bool) {
	for line in strings.split_lines(text, context.temp_allocator) {
		equals := strings.index_byte(line, '=')
		if equals < 0 {
			continue
		}
		key := strings.trim_space(line[:equals])
		value := strings.clone(strings.trim_space(line[equals + 1:]), allocator)
		switch key {
		case "name":       app.name = value
		case "id":         app.id = value
		case "version":    app.version = value
		case "publisher":  app.publisher = value
		case "folder":     app.folder = value
		case "executable": app.executable = value
		case "size-kb":
			n, parsed := strconv.parse_int(value, 10)
			app.size_kb = n if parsed && n >= 0 else 0
		}
	}
	ok = app.name != "" && app.id != "" && app.folder != "" && app.executable != "" && plain_name(app.folder) && plain_name(app.executable) && plain_name(app.id)
	return app, ok
}

// A name with no folder in it and nothing that leaves one.
plain_name :: proc(name: string) -> bool {
	return name != "." && name != ".." && !strings.contains_any(name, "/\\:") && safe_path(name)
}

// What the setup program was asked to do, from its command line (Windows' own spelling of switches, as NSIS and others take them).
Mode :: enum {
	Install,   // put the app in Program Files
	Uninstall, // the uninstaller as Settings, Apps starts it: copy itself out of the folder, start that copy, and end
	Remove,    // the copy: wait for the uninstaller to end, then take the app away
}

Command :: struct {
	mode:    Mode,
	silent:  bool,   // /S: no question, no message
	folder:  string, // /D=<folder>: where to install, instead of Program Files\<name>; /remove <folder>: what to take away
	waiting: int,    // /wait <process id>: the uninstaller the copy waits for
	bad:     string, // a word it does not know
}

parse_command :: proc(args: []string) -> Command {
	c: Command
	for i := 0; i < len(args); i += 1 {
		arg := args[i]
		lower := strings.to_lower(arg, context.temp_allocator)
		switch {
		case lower == "/s":
			c.silent = true
		case lower == "/uninstall":
			c.mode = .Uninstall
		case lower == "/remove" && i + 1 < len(args):
			c.mode = .Remove
			c.folder = args[i + 1]
			i += 1
		case lower == "/wait" && i + 1 < len(args):
			n, ok := strconv.parse_int(args[i + 1], 10)
			if !ok || n <= 0 {
				c.bad = args[i + 1]
				return c
			}
			c.waiting = n
			i += 1
		case strings.has_prefix(lower, "/d="):
			c.folder = strings.trim(arg[3:], `"`)
		case:
			c.bad = arg
			return c
		}
	}
	return c
}

// A value written in the app's key of Settings, Apps (`HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\<id>`): text or
// a number.
Registry_Value :: struct {
	name:   string,
	text:   string,
	number: u32,
	is_number: bool,
}

UNINSTALL_KEY :: `Software\Microsoft\Windows\CurrentVersion\Uninstall\`

// The values of the app's uninstall entry, for an app installed in `folder` (a Windows path).
uninstall_values :: proc(app: App, folder: string, allocator := context.temp_allocator) -> []Registry_Value {
	values := make([dynamic]Registry_Value, allocator)
	uninstaller := strings.concatenate({`"`, folder, `\uninstall.exe"`}, allocator)
	append(&values, Registry_Value{name = "DisplayName", text = app.name})
	append(&values, Registry_Value{name = "DisplayVersion", text = app.version})
	if app.publisher != "" {
		append(&values, Registry_Value{name = "Publisher", text = app.publisher})
	}
	append(&values, Registry_Value{name = "DisplayIcon", text = strings.concatenate({folder, `\`, app.executable, ",0"}, allocator)})
	append(&values, Registry_Value{name = "InstallLocation", text = folder})
	append(&values, Registry_Value{name = "UninstallString", text = strings.concatenate({uninstaller, " /uninstall"}, allocator)})
	append(&values, Registry_Value{name = "QuietUninstallString", text = strings.concatenate({uninstaller, " /uninstall /S"}, allocator)})
	append(&values, Registry_Value{name = "URLInfoAbout", text = "https://rocinante-lang.org"})
	append(&values, Registry_Value{name = "EstimatedSize", number = u32(app.size_kb), is_number = true})
	append(&values, Registry_Value{name = "NoModify", number = 1, is_number = true})
	append(&values, Registry_Value{name = "NoRepair", number = 1, is_number = true})
	return values[:]
}

// The words the installer says, kept here so they are read and tested on every system.
ask_install :: proc(app: App, folder, installed_version: string) -> string {
	if installed_version != "" && installed_version != app.version {
		return fmt.tprintf("Install %s %s for everyone on this computer, in %s?\n\nIt replaces version %s.", app.name, app.version, folder, installed_version)
	}
	if installed_version != "" {
		return fmt.tprintf("%s %s is installed already. Install it again, in %s?", app.name, app.version, folder)
	}
	return fmt.tprintf("Install %s %s for everyone on this computer, in %s?", app.name, app.version, folder)
}

said_installed :: proc(app: App) -> string {
	return fmt.tprintf("%s is installed. It is in the Start menu, and Settings, Apps can remove it.", app.name)
}

ask_remove :: proc(app: App) -> string {
	return fmt.tprintf("Remove %s from this computer? What it keeps for each person (in their AppData folder) stays.", app.name)
}

said_removed :: proc(app: App) -> string {
	return fmt.tprintf("%s has been removed.", app.name)
}

said_in_use :: proc(app: App) -> string {
	return fmt.tprintf("%s is open. Close it, then try again.", app.name)
}
