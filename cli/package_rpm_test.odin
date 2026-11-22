// SPDX-License-Identifier: 0BSD
package main

import "core:crypto/hash"
import "core:encoding/hex"
import "core:strconv"
import "core:strings"
import "core:testing"

// A header read back as rpm reads it, with every rule rpm checks: the magic, the region entry first and its trailer at the end
// of the data with minus the index's size, the entries in tag order, each value on its alignment and none overlapping another.
Read_Header :: struct {
	ok:      bool,
	size:    int, // bytes from the magic to the end of the data
	entries: map[u32]Rpm_Entry,
}

get_u32_be :: proc(b: []byte) -> u32 {
	return u32(b[0]) << 24 | u32(b[1]) << 16 | u32(b[2]) << 8 | u32(b[3])
}

read_rpm_header :: proc(t: ^testing.T, b: []byte, region: u32) -> (h: Read_Header) {
	h.entries = make(map[u32]Rpm_Entry, 64, context.temp_allocator)
	if !testing.expect(t, len(b) >= 16 && string(b[:8]) == "\x8e\xad\xe8\x01\x00\x00\x00\x00", "header magic") {
		return
	}
	il, dl := int(get_u32_be(b[8:])), int(get_u32_be(b[12:]))
	data := b[16 + 16 * il:][:dl]
	h.size = 16 + 16 * il + dl
	first := b[16:]
	testing.expect_value(t, get_u32_be(first[0:]), region)
	testing.expect_value(t, get_u32_be(first[4:]), u32(Rpm_Type.Bin))
	testing.expect_value(t, int(get_u32_be(first[8:])), dl - 16) // the trailer is the last 16 bytes
	testing.expect_value(t, get_u32_be(first[12:]), 16)
	trailer := data[dl - 16:]
	testing.expect_value(t, get_u32_be(trailer[0:]), region)
	testing.expect_value(t, get_u32_be(trailer[4:]), u32(Rpm_Type.Bin))
	testing.expect_value(t, i32(get_u32_be(trailer[8:])), i32(-16 * il))
	testing.expect_value(t, get_u32_be(trailer[12:]), 16)
	last_tag: u32 = 0
	end := 0
	for i in 1 ..< il {
		e := b[16 + 16 * i:]
		tag, type, offset, count := get_u32_be(e[0:]), Rpm_Type(get_u32_be(e[4:])), int(get_u32_be(e[8:])), get_u32_be(e[12:])
		testing.expectf(t, tag > last_tag, "tag %d after %d", tag, last_tag)
		testing.expectf(t, offset % rpm_alignment(type) == 0, "tag %d at %d is not aligned", tag, offset)
		testing.expectf(t, offset >= end, "tag %d overlaps the one before", tag)
		length := 0
		switch type {
		case .Int16:        length = 2 * int(count)
		case .Int32:        length = 4 * int(count)
		case .Bin:          length = int(count)
		case .String, .I18n_String, .String_Array:
			for _ in 0 ..< count {
				for data[offset + length] != 0 {
					length += 1
				}
				length += 1
			}
		}
		testing.expectf(t, offset + length <= dl - 16, "tag %d runs into the trailer", tag)
		h.entries[tag] = Rpm_Entry{tag, type, count, data[offset:][:length]}
		last_tag, end = tag, offset + length
	}
	h.ok = true
	return
}

entry_strings :: proc(e: Rpm_Entry) -> []string {
	words := strings.split(string(e.data[:len(e.data) - 1]), "\x00", context.temp_allocator)
	return words
}

entry_u32 :: proc(e: Rpm_Entry, i: int) -> u32 {
	return get_u32_be(e.data[4 * i:])
}

sample_files :: proc() -> []Rpm_File {
	files := make([]Rpm_File, 5, context.temp_allocator)
	files[0] = {path = "/usr/bin/wild-vex", mode = RPM_KIND_LINK | 0o777, link = "../lib/wild-vex/wild-vex", mtime = 1700000000}
	files[1] = {path = "/usr/lib/wild-vex", mode = RPM_KIND_FOLDER | 0o755, mtime = 1700000000}
	files[2] = {path = "/usr/lib/wild-vex/assets.txt", mode = RPM_KIND_FILE | 0o644, data = transmute([]byte)string("hello\n"), mtime = 1700000000}
	files[3] = {path = "/usr/lib/wild-vex/wild-vex", mode = RPM_KIND_FILE | 0o755, data = transmute([]byte)string("\x7fELF program"), mtime = 1700000000}
	files[4] = {path = "/usr/share/applications/org.example.wildvex.desktop", mode = RPM_KIND_FILE | 0o644, data = transmute([]byte)string("[Desktop Entry]\n"), mtime = 1700000000}
	return files
}

sample_info :: proc() -> Rpm_Info {
	return Rpm_Info{
		name = "wild-vex", version = "1.0.1", release = "1", summary = "A game\nsecond line", description = "A game",
		packager = "Ada <ada@example.org>", arch = "x86_64", archnum = 1, build_time = 1700000000,
		requires = rpm_requires("2.35", 30), provides = rpm_provides("wild-vex", "1.0.1", "1", "x86_64"),
		compressor = "zstd", level = "19",
	}
}

@(test)
test_an_rpm_is_a_lead_a_signature_a_header_and_its_payload :: proc(t: ^testing.T) {
	files := sample_files()
	cpio := rpm_cpio(files)
	payload := transmute([]byte)string("stands in for the compressed archive")
	pkg := rpm_package(sample_info(), files, cpio, payload)

	// the lead: its magic, version 3, a binary package, x86-64 on Linux, the name, a header-style signature
	testing.expect_value(t, string(pkg[:4]), "\xed\xab\xee\xdb")
	testing.expect(t, pkg[4] == 3 && pkg[5] == 0 && pkg[6] == 0 && pkg[7] == 0)
	testing.expect(t, pkg[8] == 0 && pkg[9] == 1)
	testing.expect_value(t, string(pkg[10:10 + len("wild-vex-1.0.1-1") + 1]), "wild-vex-1.0.1-1\x00")
	testing.expect(t, pkg[76] == 0 && pkg[77] == 1 && pkg[78] == 0 && pkg[79] == 5)

	sig := read_rpm_header(t, pkg[96:], RPM_HEADER_SIGNATURES)
	testing.expect(t, sig.ok)
	header_at := 96 + (sig.size + 7) / 8 * 8 // the signature is padded to eight bytes, with zeros
	for b in pkg[96 + sig.size:header_at] {
		testing.expect_value(t, b, 0)
	}
	main := read_rpm_header(t, pkg[header_at:], RPM_HEADER_IMMUTABLE)
	testing.expect(t, main.ok)
	header := pkg[header_at:][:main.size]
	body := pkg[header_at + main.size:]
	testing.expect_value(t, string(body), string(payload))

	// the signature's digests are of the header, and of the header with the payload
	testing.expect_value(t, string(sig.entries[RPM_SIG_SHA256].data), strings.concatenate({sha256_hex(header), "\x00"}, context.temp_allocator))
	sha1 := string(hex.encode(hash.hash_bytes(.Insecure_SHA1, header, context.temp_allocator), context.temp_allocator))
	testing.expect_value(t, string(sig.entries[RPM_SIG_SHA1].data), strings.concatenate({sha1, "\x00"}, context.temp_allocator))
	md5 := hash.hash_bytes(.Insecure_MD5, pkg[header_at:], context.temp_allocator)
	testing.expect_value(t, string(sig.entries[RPM_SIG_MD5].data), string(md5))
	testing.expect_value(t, int(entry_u32(sig.entries[RPM_SIG_SIZE], 0)), main.size + len(payload))
	testing.expect_value(t, int(entry_u32(sig.entries[RPM_SIG_PAYLOAD_SIZE], 0)), len(cpio))

	// what the package is
	e := main.entries
	testing.expect_value(t, entry_strings(e[RPM_TAG_I18N_TABLE])[0], "C")
	testing.expect_value(t, entry_strings(e[RPM_TAG_NAME])[0], "wild-vex")
	testing.expect_value(t, entry_strings(e[RPM_TAG_VERSION])[0], "1.0.1")
	testing.expect_value(t, entry_strings(e[RPM_TAG_RELEASE])[0], "1")
	testing.expect_value(t, e[RPM_TAG_SUMMARY].type, Rpm_Type.I18n_String)
	testing.expect_value(t, entry_strings(e[RPM_TAG_SUMMARY])[0], "A game") // one line
	testing.expect_value(t, entry_strings(e[RPM_TAG_ARCH])[0], "x86_64")
	testing.expect_value(t, entry_strings(e[RPM_TAG_OS])[0], "linux")
	testing.expect_value(t, entry_strings(e[RPM_TAG_SOURCE_RPM])[0], "wild-vex-1.0.1-1.src.rpm")
	testing.expect_value(t, entry_strings(e[RPM_TAG_LICENSE])[0], "Unspecified")
	testing.expect_value(t, entry_strings(e[RPM_TAG_PACKAGER])[0], "Ada <ada@example.org>")
	testing.expect_value(t, entry_strings(e[RPM_TAG_BUILD_HOST])[0], "localhost")
	_, has_url := e[RPM_TAG_URL]
	testing.expect(t, !has_url)
	testing.expect_value(t, entry_u32(e[RPM_TAG_BUILD_TIME], 0), 1700000000)
	testing.expect_value(t, entry_u32(e[RPM_TAG_SIZE], 0), u32(len("../lib/wild-vex/wild-vex") + 6 + 12 + 16))
	testing.expect_value(t, entry_strings(e[RPM_TAG_PAYLOAD_FORMAT])[0], "cpio")
	testing.expect_value(t, entry_strings(e[RPM_TAG_PAYLOAD_COMPRESSOR])[0], "zstd")
	testing.expect_value(t, entry_strings(e[RPM_TAG_PAYLOAD_FLAGS])[0], "19")
	testing.expect_value(t, entry_strings(e[RPM_TAG_ENCODING])[0], "utf-8")
	testing.expect_value(t, entry_strings(e[RPM_TAG_PAYLOAD_DIGEST])[0], sha256_hex(payload))
	testing.expect_value(t, entry_strings(e[RPM_TAG_PAYLOAD_DIGEST_ALT])[0], sha256_hex(cpio))
	testing.expect_value(t, entry_u32(e[RPM_TAG_PAYLOAD_DIGEST_ALGO], 0), RPM_DIGEST_SHA256)
	testing.expect_value(t, entry_u32(e[RPM_TAG_FILE_DIGEST_ALGO], 0), RPM_DIGEST_SHA256)

	// its files: folders with a slash, each file's folder by number, digests of files only, links' targets
	testing.expect_value(t, strings.join(entry_strings(e[RPM_TAG_DIRNAMES]), " ", context.temp_allocator), "/usr/bin/ /usr/lib/ /usr/lib/wild-vex/ /usr/share/applications/")
	testing.expect_value(t, strings.join(entry_strings(e[RPM_TAG_BASENAMES]), " ", context.temp_allocator), "wild-vex wild-vex assets.txt wild-vex org.example.wildvex.desktop")
	indexes := e[RPM_TAG_DIR_INDEXES]
	testing.expect(t, entry_u32(indexes, 0) == 0 && entry_u32(indexes, 1) == 1 && entry_u32(indexes, 2) == 2 && entry_u32(indexes, 3) == 2 && entry_u32(indexes, 4) == 3)
	digests := entry_strings(e[RPM_TAG_FILE_DIGESTS])
	testing.expect(t, digests[0] == "" && digests[1] == "")
	testing.expect_value(t, digests[2], "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03")
	links := entry_strings(e[RPM_TAG_FILE_LINKTOS])
	testing.expect(t, links[0] == "../lib/wild-vex/wild-vex" && links[2] == "")
	modes := e[RPM_TAG_FILE_MODES].data
	testing.expect_value(t, u32(modes[0]) << 8 | u32(modes[1]), RPM_KIND_LINK | 0o777)
	testing.expect_value(t, u32(modes[2]) << 8 | u32(modes[3]), RPM_KIND_FOLDER | 0o755)
	testing.expect_value(t, u32(modes[6]) << 8 | u32(modes[7]), RPM_KIND_FILE | 0o755)
	testing.expect_value(t, e[RPM_TAG_FILE_SIZES].count, 5)
	testing.expect(t, entry_u32(e[RPM_TAG_FILE_SIZES], 0) == 24 && entry_u32(e[RPM_TAG_FILE_SIZES], 1) == 0 && entry_u32(e[RPM_TAG_FILE_SIZES], 2) == 6)
	testing.expect(t, entry_u32(e[RPM_TAG_FILE_INODES], 0) == 1 && entry_u32(e[RPM_TAG_FILE_INODES], 4) == 5)
	testing.expect_value(t, entry_u32(e[RPM_TAG_FILE_VERIFY_FLAGS], 3), 0xffffffff)
	testing.expect_value(t, entry_strings(e[RPM_TAG_FILE_USERNAME])[4], "root")
	testing.expect_value(t, len(entry_strings(e[RPM_TAG_FILE_LANGS])), 5)

	// what it asks for and gives, by name, sense and version
	required := entry_strings(e[RPM_TAG_REQUIRE_NAME])
	testing.expect_value(t, len(required), int(e[RPM_TAG_REQUIRE_FLAGS].count))
	testing.expect_value(t, len(entry_strings(e[RPM_TAG_REQUIRE_VERSION])), len(required))
	provided := entry_strings(e[RPM_TAG_PROVIDE_NAME])
	testing.expect(t, provided[0] == "wild-vex" && provided[1] == "wild-vex(x86-64)")
	testing.expect_value(t, entry_strings(e[RPM_TAG_PROVIDE_VERSION])[1], "1.0.1-1")
	testing.expect_value(t, entry_u32(e[RPM_TAG_PROVIDE_FLAGS], 0), RPM_SENSE_EQUAL)
}

@(test)
test_an_rpm_with_no_files_still_reads :: proc(t: ^testing.T) {
	info := sample_info()
	info.description = "  "
	info.url = "https://example.org"
	info.build_host = "builder"
	info.license = "MIT"
	info.requires = nil
	pkg := rpm_package(info, nil, rpm_cpio(nil), nil)
	sig := read_rpm_header(t, pkg[96:], RPM_HEADER_SIGNATURES)
	main := read_rpm_header(t, pkg[96 + (sig.size + 7) / 8 * 8:], RPM_HEADER_IMMUTABLE)
	testing.expect(t, sig.ok && main.ok)
	_, has_files := main.entries[RPM_TAG_BASENAMES]
	_, has_requires := main.entries[RPM_TAG_REQUIRE_NAME]
	testing.expect(t, !has_files && !has_requires, "an empty list is left out: rpm refuses an entry of no values")
	testing.expect_value(t, entry_strings(main.entries[RPM_TAG_DESCRIPTION])[0], "A game") // a blank description is the summary
	testing.expect_value(t, entry_strings(main.entries[RPM_TAG_URL])[0], "https://example.org")
	testing.expect_value(t, entry_strings(main.entries[RPM_TAG_BUILD_HOST])[0], "builder")
	testing.expect_value(t, entry_strings(main.entries[RPM_TAG_LICENSE])[0], "MIT")
	// a name longer than the lead holds is cut to 65 bytes and still ends in a zero
	long := sample_info()
	long.name = strings.repeat("n", 80, context.temp_allocator)
	lead := rpm_package(long, nil, nil, nil)[:96]
	testing.expect_value(t, lead[74], 'n')
	testing.expect_value(t, lead[75], 0)
	testing.expect(t, rpm_lead("x", 19)[9] == 19)
}

@(test)
test_the_payload_is_a_newc_cpio_archive :: proc(t: ^testing.T) {
	files := sample_files()
	cpio := rpm_cpio(files)
	testing.expect_value(t, len(cpio) % 4, 0)
	at := 0
	names := make([dynamic]string, context.temp_allocator)
	for {
		h := string(cpio[at:][:110])
		testing.expect_value(t, h[:6], "070701")
		field :: proc(h: string, i: int) -> int {
			v, _ := strconv.parse_int(h[6 + 8 * i:][:8], 16)
			return v
		}
		name_size, size := field(h, 11), field(h, 6)
		name := string(cpio[at + 110:][:name_size - 1])
		testing.expect_value(t, cpio[at + 110 + name_size - 1], 0)
		append(&names, name)
		data_at := (at + 110 + name_size + 3) / 4 * 4
		if name == "TRAILER!!!" {
			testing.expect_value(t, field(h, 4), 1) // one link
			testing.expect_value(t, data_at, len(cpio))
			break
		}
		i := len(names) - 1
		testing.expect_value(t, field(h, 0), i + 1) // the inode is its place in the header
		testing.expect_value(t, u32(field(h, 1)), files[i].mode)
		testing.expect_value(t, size, rpm_file_size(files[i]))
		testing.expect_value(t, field(h, 5), 1700000000)
		switch files[i].mode & RPM_KIND_MASK {
		case RPM_KIND_LINK:   testing.expect_value(t, string(cpio[data_at:][:size]), files[i].link)
		case RPM_KIND_FILE:   testing.expect_value(t, string(cpio[data_at:][:size]), string(files[i].data))
		case RPM_KIND_FOLDER: testing.expect_value(t, field(h, 4), 2)
		}
		at = (data_at + size + 3) / 4 * 4
	}
	testing.expect_value(t, strings.join(names[:], " ", context.temp_allocator), "./usr/bin/wild-vex ./usr/lib/wild-vex ./usr/lib/wild-vex/assets.txt ./usr/lib/wild-vex/wild-vex ./usr/share/applications/org.example.wildvex.desktop TRAILER!!!")
	// nothing but the trailer
	testing.expect_value(t, len(rpm_cpio(nil)), 124) // 110 + 11 for the name, padded to 124
}

@(test)
test_what_an_rpm_asks_for_and_gives :: proc(t: ^testing.T) {
	names :: proc(list: []Rpm_Dependency) -> string {
		words := make([dynamic]string, context.temp_allocator)
		for d in list {
			append(&words, d.name)
		}
		return strings.join(words[:], " ", context.temp_allocator)
	}
	all := rpm_requires("2.35", 30)
	testing.expect_value(t, names(all), "libc.so.6()(64bit) libc.so.6(GLIBC_2.35)(64bit) libgcc_s.so.1()(64bit) libm.so.6()(64bit) libstdc++.so.6()(64bit) libstdc++.so.6(GLIBCXX_3.4.30)(64bit) rpmlib(CompressedFileNames) rpmlib(FileDigests) rpmlib(PayloadFilesHavePrefix) rpmlib(PayloadIsZstd)")
	for d in all {
		if strings.has_prefix(d.name, "rpmlib(") {
			testing.expect_value(t, d.flags, RPM_SENSE_RPMLIB | RPM_SENSE_LESS | RPM_SENSE_EQUAL)
			testing.expect(t, d.version != "")
		} else {
			testing.expect(t, d.flags == 0 && d.version == "")
		}
	}
	testing.expect_value(t, rpm_requires("2.35", 30)[9].version, "5.4.18-1")
	testing.expect(t, !strings.contains(names(rpm_requires("", 0)), "GLIBC"), "no promise when the program names no version")
	arm := rpm_provides("circle", "2026.11.22", "1", "aarch64")
	testing.expect_value(t, names(arm), "circle circle(aarch-64)")
	testing.expect_value(t, arm[0].version, "2026.11.22-1")
}

@(test)
test_the_pieces_of_an_rpms_file_list :: proc(t: ^testing.T) {
	dir, base := rpm_split_path("/usr/lib/x/y.png")
	testing.expect(t, dir == "/usr/lib/x/" && base == "y.png")
	dir, base = rpm_split_path("/top")
	testing.expect(t, dir == "/" && base == "top")
	testing.expect_value(t, rpm_file_size(Rpm_File{mode = RPM_KIND_FOLDER | 0o755, data = transmute([]byte)string("ignored")}), 0)
	testing.expect_value(t, rpm_file_size(Rpm_File{mode = RPM_KIND_LINK | 0o777, link = "abc"}), 3)
	testing.expect_value(t, rpm_file_size(Rpm_File{mode = RPM_KIND_FILE | 0o644, data = transmute([]byte)string("abcd")}), 4)
	testing.expect(t, rpm_owns_folder("/usr/lib/circle", "circle"))
	testing.expect(t, rpm_owns_folder("/usr/lib/circle/assets/fonts", "circle"))
	testing.expect(t, rpm_owns_folder("/usr/share/doc/circle", "circle"))
	for other in ([]string{"/usr", "/usr/lib", "/usr/bin", "/usr/share/applications", "/usr/lib/circles", "/usr/share/icons/hicolor/512x512/apps"}) {
		testing.expect(t, !rpm_owns_folder(other, "circle"), other)
	}
	testing.expect(t, rpm_fits(10, 20, 30) && !rpm_fits(0xffffffff, 0, 0) && !rpm_fits(0, 0, 0xffffffff))
	testing.expect_value(t, rpm_alignment(.Int16), 2)
	testing.expect_value(t, rpm_alignment(.Int32), 4)
	testing.expect_value(t, rpm_alignment(.String_Array), 1)
	// a header puts each value on its alignment, after strings of any length
	e := make([dynamic]Rpm_Entry, context.temp_allocator)
	rpm_string(&e, 1001, "abc")
	rpm_int16s(&e, 1002, {7})
	rpm_int32s(&e, 1003, {9})
	rpm_bin(&e, 1000, {1, 2, 3})
	h := read_rpm_header(t, rpm_header(e[:], RPM_HEADER_IMMUTABLE), RPM_HEADER_IMMUTABLE)
	testing.expect(t, h.ok && len(h.entries) == 4)
	testing.expect_value(t, string(h.entries[1000].data), "\x01\x02\x03")
	testing.expect_value(t, entry_u32(h.entries[1003], 0), 9)
}
