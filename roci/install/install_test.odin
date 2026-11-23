// SPDX-License-Identifier: 0BSD
package install

import "core:encoding/endian"
import "core:hash"
import "core:strings"
import "core:testing"

@(test)
test_an_archive_gives_back_every_file_deflated_or_stored :: proc(t: ^testing.T) {
	text := strings.repeat("the same words again and again ", 200, context.temp_allocator)
	picture := []u8{0x89, 'P', 'N', 'G', 1, 2, 3, 4}
	files := []File{
		{path = "app.exe", data = transmute([]u8)text},
		{path = "assets/pictures/sky.png", data = picture},
		{path = "empty.txt", data = nil},
		{path = "short", data = transmute([]u8)string("x")},
	}
	archive := pack(files, context.temp_allocator)
	entries, ok := read_archive(archive, context.temp_allocator)
	testing.expect(t, ok)
	testing.expect_value(t, len(entries), 4)
	if len(entries) != 4 {
		return
	}
	testing.expect_value(t, entries[0].method, Method.Deflate)
	testing.expect(t, len(entries[0].packed) < len(text), "words that repeat get smaller")
	testing.expect_value(t, entries[1].method, Method.Stored)  // a PNG is compressed already
	testing.expect_value(t, entries[2].method, Method.Stored)  // nothing to compress
	testing.expect_value(t, entries[3].method, Method.Stored)  // one byte deflates to more than one
	for e, i in entries {
		testing.expect_value(t, e.path, files[i].path)
		data, good := entry_bytes(e, context.temp_allocator)
		testing.expect(t, good, e.path)
		testing.expect_value(t, string(data), string(files[i].data))
	}
	empty := pack(nil, context.temp_allocator)
	none, empty_ok := read_archive(empty, context.temp_allocator)
	testing.expect(t, empty_ok && len(none) == 0, "an archive of nothing")
}

@(test)
test_a_damaged_archive_is_refused :: proc(t: ^testing.T) {
	text := strings.repeat("abc", 100, context.temp_allocator)
	archive := pack([]File{{path = "a.txt", data = transmute([]u8)text}}, context.temp_allocator)
	_, ok := read_archive(archive[:len(archive) - 1], context.temp_allocator)
	testing.expect(t, !ok, "cut short in the data")
	_, ok = read_archive(archive[:14], context.temp_allocator)
	testing.expect(t, !ok, "cut short in an entry's header")
	_, ok = read_archive(archive[:11], context.temp_allocator)
	testing.expect(t, !ok, "shorter than the header")
	_, ok = read_archive(transmute([]u8)string("NOTANARCHIVEATALL"), context.temp_allocator)
	testing.expect(t, !ok, "another magic")
	more := make([]u8, len(archive), context.temp_allocator)
	copy(more, archive)
	endian.put_u32(more[8:12], .Little, 2)
	_, ok = read_archive(more, context.temp_allocator)
	testing.expect(t, !ok, "more entries said than there are")
	method := make([]u8, len(archive), context.temp_allocator)
	copy(method, archive)
	method[12 + 2 + len("a.txt")] = 9
	_, ok = read_archive(method, context.temp_allocator)
	testing.expect(t, !ok, "a method that does not exist")

	// bytes that do not match their sum, deflated and stored
	entries, _ := read_archive(archive, context.temp_allocator)
	bad := entries[0]
	bad.crc += 1
	_, ok = entry_bytes(bad, context.temp_allocator)
	testing.expect(t, !ok, "a deflated file whose sum is wrong")
	bad = entries[0]
	bad.size += 1
	_, ok = entry_bytes(bad, context.temp_allocator)
	testing.expect(t, !ok, "a deflated file of another size")
	bad = entries[0]
	bad.packed = []u8{0xFF, 0xFF, 0xFF}
	_, ok = entry_bytes(bad, context.temp_allocator)
	testing.expect(t, !ok, "bytes that are not deflate")
	stored := Entry{path = "s", method = .Stored, size = 3, crc = hash.crc32(transmute([]u8)string("abc")), packed = transmute([]u8)string("abd")}
	_, ok = entry_bytes(stored, context.temp_allocator)
	testing.expect(t, !ok, "a stored file whose sum is wrong")
	stored.packed = transmute([]u8)string("abc")
	data, good := entry_bytes(stored, context.temp_allocator)
	testing.expect(t, good && string(data) == "abc")
}

@(test)
test_an_archive_never_writes_outside_its_folder :: proc(t: ^testing.T) {
	for bad in ([]string{"", "/etc/x", "../x", "a/../../x", "a//b", "./a", `a\b`, "C:x", "a/b:c", "a/<b>", "a/b?", "a/b*", "a/b|c", "a\x01b", `a"b`, "a/."}) {
		testing.expectf(t, !safe_path(bad), "%q", bad)
		archive := pack([]File{{path = bad, data = nil}}, context.temp_allocator)
		_, ok := read_archive(archive, context.temp_allocator)
		testing.expectf(t, !ok, "an archive holding %q", bad)
	}
	for good in ([]string{"app.exe", "assets/a b/c.d.png", "libs/x/Ü.roci", "...x"}) {
		testing.expectf(t, safe_path(good), "%q", good)
	}
}

@(test)
test_the_archive_is_found_after_the_program_signed_or_not :: proc(t: ^testing.T) {
	program := fake_program(1000)
	archive := pack([]File{{path = "a.txt", data = transmute([]u8)string("hello")}}, context.temp_allocator)
	tail := trailer(len(program), len(archive), context.temp_allocator)
	whole := make([dynamic]u8, context.temp_allocator)
	append(&whole, ..program)
	append(&whole, ..archive)
	append(&whole, ..tail)
	testing.expect_value(t, len(whole) % 8, 0)
	found, ok := find_archive(whole[:])
	testing.expect(t, ok)
	testing.expect_value(t, len(found), len(archive))
	entries, read_ok := read_archive(found, context.temp_allocator)
	testing.expect(t, read_ok && len(entries) == 1 && entries[0].path == "a.txt")

	// signed: the certificate table follows, named by the PE header
	signed := make([dynamic]u8, context.temp_allocator)
	append(&signed, ..whole[:])
	table_at := len(signed)
	append(&signed, ..make([]u8, 64, context.temp_allocator))
	signed[table_at + 7] = 1 // a certificate table does not end in zeros alone
	signed[len(signed) - 1] = 2
	put_certificate_table(signed[:], table_at, 64)
	found, ok = find_archive(signed[:])
	testing.expect(t, ok && len(found) == len(archive), "past the signature")

	// a few zeros of padding between the trailer and the signature, as signtool may add
	padded := make([dynamic]u8, context.temp_allocator)
	append(&padded, ..whole[:])
	append(&padded, 0, 0, 0, 0, 0)
	table_at = len(padded)
	append(&padded, ..make([]u8, 16, context.temp_allocator))
	padded[len(padded) - 1] = 3
	put_certificate_table(padded[:], table_at, 16)
	found, ok = find_archive(padded[:])
	testing.expect(t, ok && len(found) == len(archive), "past padding")

	// no archive at all, and a trailer that points past itself
	_, ok = find_archive(program)
	testing.expect(t, !ok, "a program alone")
	_, ok = find_archive(nil)
	testing.expect(t, !ok, "nothing")
	wrong := make([]u8, len(whole), context.temp_allocator)
	copy(wrong, whole[:])
	endian.put_u64(wrong[len(wrong) - 16:], .Little, u64(len(wrong)))
	_, ok = find_archive(wrong)
	testing.expect(t, !ok, "a trailer pointing past itself")
	long := make([]u8, len(whole), context.temp_allocator)
	copy(long, whole[:])
	endian.put_u64(long[len(long) - 8:], .Little, u64(len(long)))
	_, ok = find_archive(long)
	testing.expect(t, !ok, "an archive said to be longer than the room for it")
	zeros := make([]u8, 40, context.temp_allocator)
	_, ok = find_archive(zeros)
	testing.expect(t, !ok, "zeros only")
}

// A PE file's first bytes: a DOS header pointing at a PE header with a 64-bit optional header, then zeros to `size`.
@(private = "file")
fake_program :: proc(size: int) -> []u8 {
	data := make([]u8, size, context.temp_allocator)
	data[0], data[1] = 'M', 'Z'
	endian.put_u32(data[0x3C:], .Little, 0x80)
	copy(data[0x80:], "PE\x00\x00")
	endian.put_u16(data[0x80 + 24:], .Little, 0x20B)
	data[size - 1] = 0xCC // a program does not end in zeros
	return data
}

@(private = "file")
put_certificate_table :: proc(data: []u8, at, size: int) {
	security := 0x80 + 24 + 112 + 4 * 8
	endian.put_u32(data[security:], .Little, u32(at))
	endian.put_u32(data[security + 4:], .Little, u32(size))
}

@(test)
test_the_certificate_table_is_read_from_the_pe_header :: proc(t: ^testing.T) {
	program := fake_program(600)
	_, _, signed := certificate_table(program)
	testing.expect(t, !signed, "no table")
	put_certificate_table(program, 512, 88)
	at, size, ok := certificate_table(program)
	testing.expect(t, ok && at == 512 && size == 88)
	// 32-bit, and what is not a PE file
	old := fake_program(600)
	endian.put_u16(old[0x80 + 24:], .Little, 0x10B)
	endian.put_u32(old[0x80 + 24 + 96 + 32:], .Little, 100)
	endian.put_u32(old[0x80 + 24 + 96 + 36:], .Little, 8)
	at, size, ok = certificate_table(old)
	testing.expect(t, ok && at == 100 && size == 8, "a 32-bit program")
	rom := fake_program(600)
	endian.put_u16(rom[0x80 + 24:], .Little, 0x107)
	_, _, ok = certificate_table(rom)
	testing.expect(t, !ok)
	_, _, ok = certificate_table(transmute([]u8)strings.repeat("x", 100, context.temp_allocator))
	testing.expect(t, !ok)
	far := fake_program(600)
	endian.put_u32(far[0x3C:], .Little, 590)
	_, _, ok = certificate_table(far)
	testing.expect(t, !ok, "a PE header past the end")
	short := fake_program(0x80 + 24 + 112 + 30)
	_, _, ok = certificate_table(short)
	testing.expect(t, !ok, "no room for the directories")
}

@(test)
test_setup_ini_says_what_the_app_is_and_refuses_what_leaves_program_files :: proc(t: ^testing.T) {
	app := App{name = "Wild\nVex", id = "org.example.wildvex", version = "1.0.1", publisher = "Ada", folder = "Wild Vex", executable = "wildvex.exe", size_kb = 5120}
	text := write_ini(app, context.temp_allocator)
	back, ok := read_ini(text, context.temp_allocator)
	testing.expect(t, ok)
	testing.expect_value(t, back.name, "Wild Vex")
	testing.expect_value(t, back.id, app.id)
	testing.expect_value(t, back.version, "1.0.1")
	testing.expect_value(t, back.publisher, "Ada")
	testing.expect_value(t, back.folder, "Wild Vex")
	testing.expect_value(t, back.executable, "wildvex.exe")
	testing.expect_value(t, back.size_kb, 5120)

	_, ok = read_ini("name = A\nid = a\nfolder = A\nexecutable = a.exe\nsize-kb = lots\nnot a line\n", context.temp_allocator)
	testing.expect(t, ok, "a size that is not a number is 0, and a line with no = is passed over")
	for bad in ([]string{
		"id = a\nfolder = A\nexecutable = a.exe\n",
		"name = A\nfolder = A\nexecutable = a.exe\n",
		"name = A\nid = a\nexecutable = a.exe\n",
		"name = A\nid = a\nfolder = A\n",
		"name = A\nid = a\nfolder = ..\nexecutable = a.exe\n",
		"name = A\nid = a\nfolder = C:\\Windows\nexecutable = a.exe\n",
		"name = A\nid = a\nfolder = A/B\nexecutable = a.exe\n",
		"name = A\nid = a\nfolder = A\nexecutable = ..\\x.exe\n",
		"name = A\nid = a\\b\nfolder = A\nexecutable = a.exe\n",
	}) {
		_, refused := read_ini(bad, context.temp_allocator)
		testing.expectf(t, !refused, "%q", bad)
	}
}

@(test)
test_the_setup_command_line_is_read :: proc(t: ^testing.T) {
	c := parse_command(nil)
	testing.expect_value(t, c.mode, Mode.Install)
	testing.expect(t, !c.silent && c.folder == "" && c.bad == "")
	c = parse_command({"/S", `/D=C:\Apps\Wild Vex`})
	testing.expect(t, c.silent && c.mode == .Install)
	testing.expect_value(t, c.folder, `C:\Apps\Wild Vex`)
	c = parse_command({`/d="C:\x"`})
	testing.expect_value(t, c.folder, `C:\x`)
	c = parse_command({"/uninstall", "/s"})
	testing.expect(t, c.mode == .Uninstall && c.silent)
	c = parse_command({"/remove", `C:\Program Files\X`, "/wait", "1234", "/S"})
	testing.expect(t, c.mode == .Remove && c.folder == `C:\Program Files\X` && c.waiting == 1234 && c.silent)
	c = parse_command({"/wait", "soon"})
	testing.expect_value(t, c.bad, "soon")
	c = parse_command({"/wait", "0"})
	testing.expect_value(t, c.bad, "0")
	c = parse_command({"--help"})
	testing.expect_value(t, c.bad, "--help")
	c = parse_command({"/remove"})
	testing.expect_value(t, c.bad, "/remove")
}

@(test)
test_the_uninstall_entry_has_what_settings_shows :: proc(t: ^testing.T) {
	app := App{name = "Wildvex", id = "org.example.wildvex", version = "1.0.1", publisher = "Ada", folder = "Wildvex", executable = "wildvex.exe", size_kb = 7000}
	values := uninstall_values(app, `C:\Program Files\Wildvex`)
	named := make(map[string]Registry_Value, len(values), context.temp_allocator)
	for v in values {
		named[v.name] = v
	}
	testing.expect_value(t, named["DisplayName"].text, "Wildvex")
	testing.expect_value(t, named["DisplayVersion"].text, "1.0.1")
	testing.expect_value(t, named["Publisher"].text, "Ada")
	testing.expect_value(t, named["DisplayIcon"].text, `C:\Program Files\Wildvex\wildvex.exe,0`)
	testing.expect_value(t, named["InstallLocation"].text, `C:\Program Files\Wildvex`)
	testing.expect_value(t, named["UninstallString"].text, `"C:\Program Files\Wildvex\uninstall.exe" /uninstall`)
	testing.expect_value(t, named["QuietUninstallString"].text, `"C:\Program Files\Wildvex\uninstall.exe" /uninstall /S`)
	testing.expect(t, named["EstimatedSize"].is_number && named["EstimatedSize"].number == 7000)
	testing.expect(t, named["NoModify"].is_number && named["NoModify"].number == 1)
	testing.expect(t, named["NoRepair"].is_number)
	app.publisher = ""
	for v in uninstall_values(app, `C:\x`) {
		testing.expect(t, v.name != "Publisher", "no publisher, no value")
	}
}

@(test)
test_the_installer_says_what_it_does_in_plain_words :: proc(t: ^testing.T) {
	app := App{name = "Wildvex", version = "1.0.1"}
	testing.expect_value(t, ask_install(app, `C:\Program Files\Wildvex`, ""), `Install Wildvex 1.0.1 for everyone on this computer, in C:\Program Files\Wildvex?`)
	testing.expect(t, strings.contains(ask_install(app, `C:\x`, "1.0.0"), "It replaces version 1.0.0."))
	testing.expect(t, strings.contains(ask_install(app, `C:\x`, "1.0.1"), "installed already"))
	testing.expect(t, strings.contains(said_installed(app), "Start menu"))
	testing.expect(t, strings.contains(ask_remove(app), "Remove Wildvex"))
	testing.expect_value(t, said_removed(app), "Wildvex has been removed.")
	testing.expect(t, strings.contains(said_in_use(app), "Close it"))
	testing.expect(t, stored_kind("A/B.PNG") && !stored_kind("a.roci"))
	testing.expect_value(t, one_line("a\r\nb"), "a  b")
	testing.expect(t, plain_name("Wild Vex") && !plain_name(".") && !plain_name("a/b"))
}
