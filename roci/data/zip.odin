// SPDX-License-Identifier: 0BSD
//
// A zip file read whole from memory: the entries of its central directory and their contents, stored or
// deflated. Excel and OpenDocument files are zips of XML. Only what those need is read: no encryption, no
// zip64, no splitting over several files; each is a problem in words, and a file that claims to be larger
// than it is allowed to be is refused before anything is made of it (`MAX_UNPACKED`).
package data

import "core:compress/deflate"
import "core:encoding/endian"
import "core:hash"
import "core:strings"

// The most one entry may unpack to, and the most all the entries read from one file may: a file made to fill
// the memory with a few kilobytes of zeros is a problem, not a crash.
MAX_UNPACKED :: 256 * 1024 * 1024

Zip_Entry :: struct {
	name:             string,
	method:           u16, // 0 stored, 8 deflated
	compressed_size:  int,
	unpacked_size:    int,
	crc:              u32,
	offset:           int, // of the local header
}

Zip :: struct {
	bytes:   []byte,
	entries: []Zip_Entry,
	unpacked: int, // how much has been unpacked so far
}

@(private)
u16_at :: proc(b: []byte, at: int) -> (v: u16, ok: bool) {
	if at < 0 || at + 2 > len(b) {
		return 0, false
	}
	return endian.get_u16(b[at:at + 2], .Little)
}

@(private)
u32_at :: proc(b: []byte, at: int) -> (v: u32, ok: bool) {
	if at < 0 || at + 4 > len(b) {
		return 0, false
	}
	return endian.get_u32(b[at:at + 4], .Little)
}

// Opens a zip held in memory. The entries' names are copied; the bytes are borrowed and must outlive the zip.
zip_open :: proc(content: []byte, allocator := context.allocator) -> (z: Zip, why: string) {
	NOT_ZIP :: "this is not a zip file, which Excel and OpenDocument files are (was it saved in another format, or cut short?)"
	if len(content) < 22 {
		return {}, NOT_ZIP
	}
	// the end record is the last thing in the file, followed only by a comment of up to 65535 bytes
	eocd := -1
	for i := len(content) - 22; i >= 0 && i >= len(content) - 22 - 65535; i -= 1 {
		if sig, ok := u32_at(content, i); ok && sig == 0x06054b50 {
			eocd = i
			break
		}
	}
	if eocd < 0 {
		return {}, NOT_ZIP
	}
	count16, _ := u16_at(content, eocd + 10)
	dir_size, _ := u32_at(content, eocd + 12)
	dir_at, _ := u32_at(content, eocd + 16)
	if count16 == 0xffff || dir_size == 0xffffffff || dir_at == 0xffffffff {
		return {}, "this zip needs zip64, which I do not read"
	}
	entries := make([dynamic]Zip_Entry, allocator)
	at := int(dir_at)
	for _ in 0 ..< int(count16) {
		sig, sig_ok := u32_at(content, at)
		if !sig_ok || sig != 0x02014b50 {
			delete(entries)
			return {}, "the list of files in this zip is damaged"
		}
		flags, _ := u16_at(content, at + 8)
		method, _ := u16_at(content, at + 10)
		crc, _ := u32_at(content, at + 16)
		compressed, _ := u32_at(content, at + 20)
		unpacked, _ := u32_at(content, at + 24)
		name_len, name_ok := u16_at(content, at + 28)
		extra_len, _ := u16_at(content, at + 30)
		comment_len, _ := u16_at(content, at + 32)
		offset, _ := u32_at(content, at + 42)
		if !name_ok || at + 46 + int(name_len) > len(content) {
			delete(entries)
			return {}, "the list of files in this zip is damaged"
		}
		if flags & 1 != 0 {
			delete(entries)
			return {}, "this zip is protected by a password, which I cannot open"
		}
		append(&entries, Zip_Entry{
			name = strings.clone(string(content[at + 46:at + 46 + int(name_len)]), allocator),
			method = method,
			compressed_size = int(compressed),
			unpacked_size = int(unpacked),
			crc = crc,
			offset = int(offset),
		})
		at += 46 + int(name_len) + int(extra_len) + int(comment_len)
	}
	return Zip{bytes = content, entries = entries[:]}, ""
}

zip_close :: proc(z: ^Zip, allocator := context.allocator) {
	for e in z.entries {
		delete(e.name, allocator)
	}
	delete(z.entries, allocator)
	z^ = {}
}

// Whether the zip has an entry of this name.
zip_has :: proc(z: ^Zip, name: string) -> bool {
	for e in z.entries {
		if e.name == name {
			return true
		}
	}
	return false
}

// The contents of an entry, unpacked and checked against its stored checksum.
zip_read :: proc(z: ^Zip, name: string, allocator := context.allocator) -> (content: []byte, why: string) {
	entry: Zip_Entry
	found := false
	for e in z.entries {
		if e.name == name {
			entry, found = e, true
			break
		}
	}
	if !found {
		return nil, strings.concatenate({"the zip has no file called ", name}, context.temp_allocator)
	}
	DAMAGED :: "a file inside this zip is damaged"
	sig, sig_ok := u32_at(z.bytes, entry.offset)
	if !sig_ok || sig != 0x04034b50 {
		return nil, DAMAGED
	}
	name_len, _ := u16_at(z.bytes, entry.offset + 26)
	extra_len, _ := u16_at(z.bytes, entry.offset + 28)
	start := entry.offset + 30 + int(name_len) + int(extra_len)
	end := start + entry.compressed_size
	if start < 0 || end > len(z.bytes) || end < start {
		return nil, DAMAGED
	}
	if entry.unpacked_size > MAX_UNPACKED || z.unpacked + entry.unpacked_size > MAX_UNPACKED {
		return nil, "this zip unpacks to more than I will read: a file this large is not a spreadsheet or a document"
	}
	packed := z.bytes[start:end]
	switch entry.method {
	case 0:
		content = make([]byte, len(packed), allocator)
		copy(content, packed)
	case 8:
		out := make([dynamic]byte, allocator)
		err := deflate.inflate_raw_from_bytes(&out, packed, entry.unpacked_size, MAX_UNPACKED, allocator)
		if err != nil {
			delete(out)
			return nil, DAMAGED
		}
		content = out[:]
	case:
		return nil, "a file inside this zip is packed in a way I do not read"
	}
	if len(content) != entry.unpacked_size || hash.crc32(content) != entry.crc {
		delete(content, allocator)
		return nil, DAMAGED
	}
	z.unpacked += len(content)
	return content, ""
}
