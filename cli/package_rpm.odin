// SPDX-License-Identifier: 0BSD
//
// An RPM package (Fedora, openSUSE, RHEL and what comes from them), written byte by byte, as the `.deb` and the Arch package are
// made without `dpkg` or `makepkg`: no `rpmbuild` is needed, so any Linux makes one. The file is RPM's version 4 format, which
// every rpm since 4.14 reads: a lead of 96 bytes, a signature header (the header's SHA-256 and SHA-1, an MD5 of the header and
// payload, and the sizes), the header (the package's name, its files, what it asks for), and the payload, a cpio archive in
// the `newc` form compressed by zstd. The layout follows rpm's own source (`lib/header.c`, `lib/signature.c`, `build/pack.c`,
// `lib/cpio.c`, rpm 4.20.1) and the format pages at https://rpm-software-management.github.io/rpm/manual/format_v4.html.
// Everything here is arithmetic on bytes, so it is tested alone; the compression is the caller's.
package main

import "core:crypto/hash"
import "core:encoding/hex"
import "core:fmt"
import "core:slice"
import "core:strings"

// The kinds of value a header holds, by the numbers rpm gives them.
Rpm_Type :: enum u32 {
	Int16        = 3,
	Int32        = 4,
	String       = 6,
	Bin          = 7,
	String_Array = 8,
	I18n_String  = 9,
}

// The tags this writer uses, by rpm's numbers (`include/rpm/rpmtag.h`).
RPM_HEADER_SIGNATURES :: 62
RPM_HEADER_IMMUTABLE :: 63
RPM_TAG_I18N_TABLE :: 100
RPM_SIG_SHA1 :: 269
RPM_SIG_SHA256 :: 273
RPM_SIG_SIZE :: 1000
RPM_SIG_MD5 :: 1004
RPM_SIG_PAYLOAD_SIZE :: 1007
RPM_TAG_NAME :: 1000
RPM_TAG_VERSION :: 1001
RPM_TAG_RELEASE :: 1002
RPM_TAG_SUMMARY :: 1004
RPM_TAG_DESCRIPTION :: 1005
RPM_TAG_BUILD_TIME :: 1006
RPM_TAG_BUILD_HOST :: 1007
RPM_TAG_SIZE :: 1009
RPM_TAG_LICENSE :: 1014
RPM_TAG_PACKAGER :: 1015
RPM_TAG_GROUP :: 1016
RPM_TAG_URL :: 1020
RPM_TAG_OS :: 1021
RPM_TAG_ARCH :: 1022
RPM_TAG_FILE_SIZES :: 1028
RPM_TAG_FILE_MODES :: 1030
RPM_TAG_FILE_RDEVS :: 1033
RPM_TAG_FILE_MTIMES :: 1034
RPM_TAG_FILE_DIGESTS :: 1035
RPM_TAG_FILE_LINKTOS :: 1036
RPM_TAG_FILE_FLAGS :: 1037
RPM_TAG_FILE_USERNAME :: 1039
RPM_TAG_FILE_GROUPNAME :: 1040
RPM_TAG_SOURCE_RPM :: 1044
RPM_TAG_FILE_VERIFY_FLAGS :: 1045
RPM_TAG_PROVIDE_NAME :: 1047
RPM_TAG_REQUIRE_FLAGS :: 1048
RPM_TAG_REQUIRE_NAME :: 1049
RPM_TAG_REQUIRE_VERSION :: 1050
RPM_TAG_FILE_DEVICES :: 1095
RPM_TAG_FILE_INODES :: 1096
RPM_TAG_FILE_LANGS :: 1097
RPM_TAG_PROVIDE_FLAGS :: 1112
RPM_TAG_PROVIDE_VERSION :: 1113
RPM_TAG_DIR_INDEXES :: 1116
RPM_TAG_BASENAMES :: 1117
RPM_TAG_DIRNAMES :: 1118
RPM_TAG_PAYLOAD_FORMAT :: 1124
RPM_TAG_PAYLOAD_COMPRESSOR :: 1125
RPM_TAG_PAYLOAD_FLAGS :: 1126
RPM_TAG_FILE_DIGEST_ALGO :: 5011
RPM_TAG_ENCODING :: 5062
RPM_TAG_PAYLOAD_DIGEST :: 5092
RPM_TAG_PAYLOAD_DIGEST_ALGO :: 5093
RPM_TAG_PAYLOAD_DIGEST_ALT :: 5097

// rpm's number for SHA-256 among digest algorithms (`PGPHASHALGO_SHA256`).
RPM_DIGEST_SHA256 :: 8

// The senses of a dependency (`include/rpm/rpmds.h`).
RPM_SENSE_LESS :: 1 << 1
RPM_SENSE_EQUAL :: 1 << 3
RPM_SENSE_RPMLIB :: 1 << 24

// One entry of a header: its tag, its kind, how many values, and the values as they are stored (big-endian numbers, strings
// each ending in a zero byte).
Rpm_Entry :: struct {
	tag:   u32,
	type:  Rpm_Type,
	count: u32,
	data:  []byte,
}

rpm_string :: proc(entries: ^[dynamic]Rpm_Entry, tag: u32, value: string, type := Rpm_Type.String) {
	append(entries, Rpm_Entry{tag, type, 1, transmute([]byte)strings.concatenate({value, "\x00"}, context.temp_allocator)})
}

rpm_strings :: proc(entries: ^[dynamic]Rpm_Entry, tag: u32, values: []string) {
	b := strings.builder_make(context.temp_allocator)
	for v in values {
		strings.write_string(&b, v)
		strings.write_byte(&b, 0)
	}
	append(entries, Rpm_Entry{tag, .String_Array, u32(len(values)), b.buf[:]})
}

rpm_int32s :: proc(entries: ^[dynamic]Rpm_Entry, tag: u32, values: []u32) {
	data := make([]byte, 4 * len(values), context.temp_allocator)
	for v, i in values {
		put_u32_be(data[4 * i:], v)
	}
	append(entries, Rpm_Entry{tag, .Int32, u32(len(values)), data})
}

rpm_int16s :: proc(entries: ^[dynamic]Rpm_Entry, tag: u32, values: []u16) {
	data := make([]byte, 2 * len(values), context.temp_allocator)
	for v, i in values {
		data[2 * i] = byte(v >> 8)
		data[2 * i + 1] = byte(v)
	}
	append(entries, Rpm_Entry{tag, .Int16, u32(len(values)), data})
}

rpm_bin :: proc(entries: ^[dynamic]Rpm_Entry, tag: u32, value: []byte) {
	append(entries, Rpm_Entry{tag, .Bin, u32(len(value)), value})
}

put_u32_be :: proc(into: []byte, v: u32) {
	into[0] = byte(v >> 24)
	into[1] = byte(v >> 16)
	into[2] = byte(v >> 8)
	into[3] = byte(v)
}

// How many bytes a value of a kind must start on.
rpm_alignment :: proc(type: Rpm_Type) -> int {
	#partial switch type {
	case .Int16: return 2
	case .Int32: return 4
	}
	return 1
}

// A header as its bytes: the magic, the count of entries and of data bytes, the index sorted by tag with the region's entry first,
// then the data, each value on its alignment, and last the region's trailer, an entry whose offset is minus the size of the index,
// which rpm reads to know the whole header is one signed region. The entries are sorted here; no tag may be given twice.
rpm_header :: proc(entries: []Rpm_Entry, region: u32, allocator := context.temp_allocator) -> []byte {
	sorted := slice.clone(entries, context.temp_allocator)
	slice.sort_by(sorted, proc(a, b: Rpm_Entry) -> bool { return a.tag < b.tag })
	data := make([dynamic]byte, context.temp_allocator)
	offsets := make([]int, len(sorted), context.temp_allocator)
	for e, i in sorted {
		for len(data) % rpm_alignment(e.type) != 0 {
			append(&data, 0)
		}
		offsets[i] = len(data)
		append(&data, ..e.data)
	}
	index_count := len(sorted) + 1
	trailer_at := len(data)
	trailer: [16]byte
	put_u32_be(trailer[0:], region)
	put_u32_be(trailer[4:], u32(Rpm_Type.Bin))
	put_u32_be(trailer[8:], u32(i32(-16 * index_count)))
	put_u32_be(trailer[12:], 16)
	append(&data, ..trailer[:])

	out := make([]byte, 16 + 16 * index_count + len(data), allocator)
	copy(out, []byte{0x8e, 0xad, 0xe8, 0x01, 0, 0, 0, 0})
	put_u32_be(out[8:], u32(index_count))
	put_u32_be(out[12:], u32(len(data)))
	entry :: proc(into: []byte, tag: u32, type: Rpm_Type, offset: int, count: u32) {
		put_u32_be(into[0:], tag)
		put_u32_be(into[4:], u32(type))
		put_u32_be(into[8:], u32(offset))
		put_u32_be(into[12:], count)
	}
	entry(out[16:], region, .Bin, trailer_at, 16)
	for e, i in sorted {
		entry(out[32 + 16 * i:], e.tag, e.type, offsets[i], e.count)
	}
	copy(out[16 + 16 * index_count:], data[:])
	return out
}

// The lead: 96 bytes rpm still reads first, of which only the magic and the kind of signature matter today. `archnum` is
// rpm's old number for the processor (1 for x86-64, 19 for arm64), and 1 is Linux.
rpm_lead :: proc(name_version_release: string, archnum: u16) -> [96]byte {
	lead: [96]byte
	copy(lead[0:], []byte{0xed, 0xab, 0xee, 0xdb, 3, 0, 0, 0})
	lead[8], lead[9] = byte(archnum >> 8), byte(archnum)
	copy(lead[10:75], name_version_release) // at most 65 bytes, ending in a zero
	lead[77] = 1 // Linux
	lead[79] = 5 // the signature is a header
	return lead
}

// A file, folder or link of the package, as it is put under `/`.
Rpm_File :: struct {
	path:  string, // `/usr/bin/x`
	mode:  u32,    // with its kind: 0o100644 a file, 0o100755 a program, 0o40755 a folder, 0o120777 a link
	data:  []byte, // a file's bytes
	link:  string, // a link's target
	mtime: u32,
}

RPM_KIND_MASK :: 0o170000
RPM_KIND_FILE :: 0o100000
RPM_KIND_FOLDER :: 0o040000
RPM_KIND_LINK :: 0o120000

// What a package says about itself.
Rpm_Dependency :: struct {
	name:    string,
	flags:   u32,
	version: string,
}

Rpm_Info :: struct {
	name:        string,
	version:     string,
	release:     string,
	summary:     string,
	description: string,
	license:     string,
	url:         string,
	packager:    string,
	arch:        string, // x86_64, aarch64
	archnum:     u16,
	build_time:  u32,
	build_host:  string,
	requires:    []Rpm_Dependency,
	provides:    []Rpm_Dependency,
	compressor:  string, // the payload's: zstd
	level:       string, // its level, as rpm writes it in the payload's flags
}

// The payload before it is compressed: a cpio archive in the `newc` form, each file named `./usr/...`, its header and name padded
// to four bytes and its bytes too, ending in the entry `TRAILER!!!`. The numbers of the files (their inodes) are their places in
// the list from 1, as the header says.
rpm_cpio :: proc(files: []Rpm_File, allocator := context.temp_allocator) -> []byte {
	out := make([dynamic]byte, allocator)
	one :: proc(out: ^[dynamic]byte, name: string, inode, mode, mtime: u32, nlink: u32, body: []byte) {
		header := fmt.tprintf("070701%08X%08X%08X%08X%08X%08X%08X%08X%08X%08X%08X%08X%08X", inode, mode, 0, 0, nlink, mtime, len(body), 0, 0, 0, 0, len(name) + 1, 0)
		append(out, header)
		append(out, name)
		append(out, 0)
		for len(out) % 4 != 0 {
			append(out, 0)
		}
		append(out, ..body)
		for len(out) % 4 != 0 {
			append(out, 0)
		}
	}
	for f, i in files {
		body := f.data
		switch f.mode & RPM_KIND_MASK {
		case RPM_KIND_LINK:   body = transmute([]byte)f.link
		case RPM_KIND_FOLDER: body = nil
		}
		one(&out, strings.concatenate({".", f.path}, context.temp_allocator), u32(i + 1), f.mode, f.mtime, 2 if f.mode & RPM_KIND_MASK == RPM_KIND_FOLDER else 1, body)
	}
	one(&out, "TRAILER!!!", 0, 0, 0, 1, nil)
	return out[:]
}

// The size a file takes in the header's list: a file's bytes, a link's target, nothing for a folder.
rpm_file_size :: proc(f: Rpm_File) -> int {
	switch f.mode & RPM_KIND_MASK {
	case RPM_KIND_LINK:   return len(f.link)
	case RPM_KIND_FOLDER: return 0
	}
	return len(f.data)
}

// A path as rpm keeps it: the folder with a slash at the end, and the name.
rpm_split_path :: proc(path: string) -> (dir, base: string) {
	slash := strings.last_index_byte(path, '/')
	return path[:slash + 1], path[slash + 1:]
}

sha256_hex :: proc(data: []byte) -> string {
	return string(hex.encode(hash.hash_bytes(.SHA256, data, context.temp_allocator), context.temp_allocator))
}

// The main header: what the package is, its files (sorted by path, as rpm looks them up), its dependencies, and the payload's
// kind and digests.
rpm_main_header :: proc(info: Rpm_Info, files: []Rpm_File, payload, cpio: []byte, allocator := context.temp_allocator) -> []byte {
	e := make([dynamic]Rpm_Entry, context.temp_allocator)
	rpm_strings(&e, RPM_TAG_I18N_TABLE, {"C"})
	rpm_string(&e, RPM_TAG_NAME, info.name)
	rpm_string(&e, RPM_TAG_VERSION, info.version)
	rpm_string(&e, RPM_TAG_RELEASE, info.release)
	rpm_string(&e, RPM_TAG_SUMMARY, one_line(info.summary), .I18n_String)
	rpm_string(&e, RPM_TAG_DESCRIPTION, info.description if strings.trim_space(info.description) != "" else one_line(info.summary), .I18n_String)
	rpm_int32s(&e, RPM_TAG_BUILD_TIME, {info.build_time})
	rpm_string(&e, RPM_TAG_BUILD_HOST, info.build_host if info.build_host != "" else "localhost")
	installed := 0
	for f in files {
		installed += rpm_file_size(f)
	}
	rpm_int32s(&e, RPM_TAG_SIZE, {u32(installed)})
	rpm_string(&e, RPM_TAG_LICENSE, info.license if info.license != "" else "Unspecified")
	if info.packager != "" {
		rpm_string(&e, RPM_TAG_PACKAGER, info.packager)
	}
	rpm_string(&e, RPM_TAG_GROUP, "Unspecified", .I18n_String)
	if info.url != "" {
		rpm_string(&e, RPM_TAG_URL, info.url)
	}
	rpm_string(&e, RPM_TAG_OS, "linux")
	rpm_string(&e, RPM_TAG_ARCH, info.arch)
	// a binary package names the source package it came from; rpm takes one that does not for a source package
	rpm_string(&e, RPM_TAG_SOURCE_RPM, fmt.tprintf("%s-%s-%s.src.rpm", info.name, info.version, info.release))

	if len(files) > 0 {
		n := len(files)
		sizes := make([]u32, n, context.temp_allocator)
		modes := make([]u16, n, context.temp_allocator)
		rdevs := make([]u16, n, context.temp_allocator)
		mtimes := make([]u32, n, context.temp_allocator)
		digests := make([]string, n, context.temp_allocator)
		links := make([]string, n, context.temp_allocator)
		flags := make([]u32, n, context.temp_allocator)
		users := make([]string, n, context.temp_allocator)
		groups := make([]string, n, context.temp_allocator)
		verify := make([]u32, n, context.temp_allocator)
		devices := make([]u32, n, context.temp_allocator)
		inodes := make([]u32, n, context.temp_allocator)
		langs := make([]string, n, context.temp_allocator)
		dir_indexes := make([]u32, n, context.temp_allocator)
		basenames := make([]string, n, context.temp_allocator)
		dirnames := make([dynamic]string, context.temp_allocator)
		for f, i in files {
			sizes[i] = u32(rpm_file_size(f))
			modes[i] = u16(f.mode)
			mtimes[i] = f.mtime
			digests[i] = sha256_hex(f.data) if f.mode & RPM_KIND_MASK == RPM_KIND_FILE else ""
			links[i] = f.link if f.mode & RPM_KIND_MASK == RPM_KIND_LINK else ""
			users[i], groups[i] = "root", "root"
			verify[i] = 0xffffffff
			devices[i] = 1
			inodes[i] = u32(i + 1)
			dir, base := rpm_split_path(f.path)
			basenames[i] = base
			at := -1
			for d, j in dirnames {
				if d == dir {
					at = j
				}
			}
			if at < 0 {
				at = len(dirnames)
				append(&dirnames, dir)
			}
			dir_indexes[i] = u32(at)
		}
		rpm_int32s(&e, RPM_TAG_FILE_SIZES, sizes)
		rpm_int16s(&e, RPM_TAG_FILE_MODES, modes)
		rpm_int16s(&e, RPM_TAG_FILE_RDEVS, rdevs)
		rpm_int32s(&e, RPM_TAG_FILE_MTIMES, mtimes)
		rpm_strings(&e, RPM_TAG_FILE_DIGESTS, digests)
		rpm_strings(&e, RPM_TAG_FILE_LINKTOS, links)
		rpm_int32s(&e, RPM_TAG_FILE_FLAGS, flags)
		rpm_strings(&e, RPM_TAG_FILE_USERNAME, users)
		rpm_strings(&e, RPM_TAG_FILE_GROUPNAME, groups)
		rpm_int32s(&e, RPM_TAG_FILE_VERIFY_FLAGS, verify)
		rpm_int32s(&e, RPM_TAG_FILE_DEVICES, devices)
		rpm_int32s(&e, RPM_TAG_FILE_INODES, inodes)
		rpm_strings(&e, RPM_TAG_FILE_LANGS, langs)
		rpm_int32s(&e, RPM_TAG_DIR_INDEXES, dir_indexes)
		rpm_strings(&e, RPM_TAG_BASENAMES, basenames)
		rpm_strings(&e, RPM_TAG_DIRNAMES, dirnames[:])
		rpm_int32s(&e, RPM_TAG_FILE_DIGEST_ALGO, {RPM_DIGEST_SHA256})
	}
	dependencies :: proc(e: ^[dynamic]Rpm_Entry, list: []Rpm_Dependency, name_tag, flags_tag, version_tag: u32) {
		if len(list) == 0 {
			return
		}
		names := make([]string, len(list), context.temp_allocator)
		flags := make([]u32, len(list), context.temp_allocator)
		versions := make([]string, len(list), context.temp_allocator)
		for d, i in list {
			names[i], flags[i], versions[i] = d.name, d.flags, d.version
		}
		rpm_strings(e, name_tag, names)
		rpm_int32s(e, flags_tag, flags)
		rpm_strings(e, version_tag, versions)
	}
	dependencies(&e, info.provides, RPM_TAG_PROVIDE_NAME, RPM_TAG_PROVIDE_FLAGS, RPM_TAG_PROVIDE_VERSION)
	dependencies(&e, info.requires, RPM_TAG_REQUIRE_NAME, RPM_TAG_REQUIRE_FLAGS, RPM_TAG_REQUIRE_VERSION)
	rpm_string(&e, RPM_TAG_PAYLOAD_FORMAT, "cpio")
	rpm_string(&e, RPM_TAG_PAYLOAD_COMPRESSOR, info.compressor)
	rpm_string(&e, RPM_TAG_PAYLOAD_FLAGS, info.level)
	rpm_string(&e, RPM_TAG_ENCODING, "utf-8")
	rpm_strings(&e, RPM_TAG_PAYLOAD_DIGEST, {sha256_hex(payload)})
	rpm_int32s(&e, RPM_TAG_PAYLOAD_DIGEST_ALGO, {RPM_DIGEST_SHA256})
	rpm_strings(&e, RPM_TAG_PAYLOAD_DIGEST_ALT, {sha256_hex(cpio)})
	return rpm_header(e[:], RPM_HEADER_IMMUTABLE, allocator)
}

// The signature header, padded to eight bytes: the main header's SHA-1 and SHA-256, the MD5 of the header and the payload, their
// size together, and the size of the payload before it was compressed. It holds no key's signature: `rpmsign` can add one.
rpm_signature :: proc(header, payload: []byte, cpio_size: int, allocator := context.temp_allocator) -> []byte {
	e := make([dynamic]Rpm_Entry, context.temp_allocator)
	rpm_string(&e, RPM_SIG_SHA1, string(hex.encode(hash.hash_bytes(.Insecure_SHA1, header, context.temp_allocator), context.temp_allocator)))
	rpm_string(&e, RPM_SIG_SHA256, sha256_hex(header))
	rpm_int32s(&e, RPM_SIG_SIZE, {u32(len(header) + len(payload))})
	whole := make([]byte, len(header) + len(payload), context.temp_allocator)
	copy(whole, header)
	copy(whole[len(header):], payload)
	rpm_bin(&e, RPM_SIG_MD5, hash.hash_bytes(.Insecure_MD5, whole, context.temp_allocator))
	rpm_int32s(&e, RPM_SIG_PAYLOAD_SIZE, {u32(cpio_size)})
	bytes := rpm_header(e[:], RPM_HEADER_SIGNATURES, context.temp_allocator)
	out := make([]byte, (len(bytes) + 7) / 8 * 8, allocator)
	copy(out, bytes)
	return out
}

// The whole package: lead, signature, header and the payload compressed already (`payload`), from the archive before it was
// compressed (`cpio`).
rpm_package :: proc(info: Rpm_Info, files: []Rpm_File, cpio, payload: []byte, allocator := context.temp_allocator) -> []byte {
	header := rpm_main_header(info, files, payload, cpio)
	signature := rpm_signature(header, payload, len(cpio))
	lead := rpm_lead(fmt.tprintf("%s-%s-%s", info.name, info.version, info.release), info.archnum)
	out := make([]byte, len(lead) + len(signature) + len(header) + len(payload), allocator)
	at := copy(out, lead[:])
	at += copy(out[at:], signature)
	at += copy(out[at:], header)
	copy(out[at:], payload)
	return out
}

// Whether a package this big can be written: this writer keeps the 32-bit sizes, which hold up to 4 GB.
rpm_fits :: proc(installed, cpio, payload: int) -> bool {
	return installed < 0xffffffff && cpio < 0xffffffff && payload < 0xffffffff
}

// What an app's package asks for: the features of rpm its file uses, and the C and C++ libraries of the computer, by the names
// Fedora's packages give them (`libc.so.6(GLIBC_2.35)(64bit)`), sorted by name as rpm keeps them.
rpm_requires :: proc(glibc: string, glibcxx: int, allocator := context.temp_allocator) -> []Rpm_Dependency {
	list := make([dynamic]Rpm_Dependency, allocator)
	feature :: proc(list: ^[dynamic]Rpm_Dependency, name, version: string) {
		append(list, Rpm_Dependency{name, RPM_SENSE_RPMLIB | RPM_SENSE_LESS | RPM_SENSE_EQUAL, version})
	}
	feature(&list, "rpmlib(CompressedFileNames)", "3.0.4-1")
	feature(&list, "rpmlib(FileDigests)", "4.6.0-1")
	feature(&list, "rpmlib(PayloadFilesHavePrefix)", "4.0-1")
	feature(&list, "rpmlib(PayloadIsZstd)", "5.4.18-1")
	for name in ([]string{"libc.so.6()(64bit)", "libgcc_s.so.1()(64bit)", "libm.so.6()(64bit)", "libstdc++.so.6()(64bit)"}) {
		append(&list, Rpm_Dependency{name, 0, ""})
	}
	if glibc != "" {
		append(&list, Rpm_Dependency{fmt.tprintf("libc.so.6(GLIBC_%s)(64bit)", glibc), 0, ""})
	}
	if glibcxx > 0 {
		append(&list, Rpm_Dependency{fmt.tprintf("libstdc++.so.6(GLIBCXX_3.4.%d)(64bit)", glibcxx), 0, ""})
	}
	slice.sort_by(list[:], proc(a, b: Rpm_Dependency) -> bool { return a.name < b.name })
	return list[:]
}

// What it gives: its own name, and its name for this processor, as Fedora's packages do (`circle(x86-64)`).
rpm_provides :: proc(name, version, release, arch: string, allocator := context.temp_allocator) -> []Rpm_Dependency {
	isa := "x86-64" if arch == "x86_64" else "aarch-64"
	evr := fmt.tprintf("%s-%s", version, release)
	list := make([]Rpm_Dependency, 2, allocator)
	list[0] = {name, RPM_SENSE_EQUAL, evr}
	list[1] = {fmt.tprintf("%s(%s)", name, isa), RPM_SENSE_EQUAL, evr}
	return list
}
