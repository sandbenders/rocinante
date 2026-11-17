// SPDX-License-Identifier: 0BSD
//
// The vault: the same kept values as `memory.toml` (`remember "levels" 5 in vault`), in a file a player
// cannot change with a text editor. The values are written in a compact binary form and sealed with
// a key, so the file shows no value and any change to it, down to one byte, is noticed. A sealed file
// that does not open (changed, cut short, made with another key) is moved aside to `vault.bad` and the
// sketch starts with an empty vault and says so once; it never stops. The file before the last
// write is kept as `vault.bak`, and is used when the newest one is missing.
//
// This keeps honest players honest and no more: the key has to travel inside the program, so a
// determined person with tools can find it, and an old copy of the file can be put back. Anything that
// must truly be safe belongs on a server.
package roci

import "core:crypto"
import "core:crypto/chacha20poly1305"
import "core:crypto/hkdf"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

import "toml"

VAULT_SAVE_AFTER :: time.Second

@(private)
VAULT_MAGIC :: "RVLT"
@(private)
VAULT_VERSION :: 1
@(private)
VAULT_HEADER :: 4 + 1 + chacha20poly1305.XIV_SIZE

// How a sealed file turned out when it was read.
Vault_Status :: enum {
	Ok,
	Missing,
	Bad, // there, and it does not open
}

// The 32 bytes a sketch's vault is sealed with.
Vault_Key :: [32]byte

// Reads the key of a sketch folder (`vault.key`), making one from the system's random numbers when
// `create` is set and there is none. False when there is no key and none was made (a run that may not
// write files, in a folder that has none).
vault_key_for :: proc(folder: string, create: bool) -> (key: Vault_Key, ok: bool) {
	path := fmt.tprintf("%s/vault.key", folder)
	if data, err := os.read_entire_file(path, context.temp_allocator); err == nil && len(data) == len(key) {
		copy(key[:], data)
		return key, true
	}
	if !create {
		return {}, false
	}
	crypto.rand_bytes(key[:])
	if os.write_entire_file(path, key[:]) != nil {
		fmt.eprintfln("rocinante: I could not write %s", path)
		return {}, false
	}
	return key, true
}

@(private)
vault_subkey :: proc(key: Vault_Key) -> (sub: [32]byte) {
	key := key
	hkdf.extract_and_expand(.SHA256, transmute([]byte)string("rocinante vault"), key[:], transmute([]byte)string("file"), sub[:])
	return
}

// ---- the binary form of the values ----

@(private)
put_u32 :: proc(b: ^[dynamic]byte, n: int) {
	for i in 0 ..< 4 {
		append(b, byte(n >> uint(8 * i)))
	}
}

@(private)
put_u64 :: proc(b: ^[dynamic]byte, n: u64) {
	for i in 0 ..< 8 {
		append(b, byte(n >> uint(8 * i)))
	}
}

@(private)
put_text :: proc(b: ^[dynamic]byte, s: string) {
	put_u32(b, len(s))
	append(b, ..transmute([]byte)s)
}

@(private)
encode_value :: proc(b: ^[dynamic]byte, v: toml.Value) {
	switch x in v {
	case bool:
		append(b, 0, 1 if x else 0)
	case i64:
		append(b, 1)
		put_u64(b, u64(x))
	case f64:
		append(b, 2)
		put_u64(b, transmute(u64)x)
	case string:
		append(b, 3)
		put_text(b, x)
	case []f64:
		append(b, 4)
		put_u32(b, len(x))
		for n in x {
			put_u64(b, transmute(u64)n)
		}
	case []toml.Value:
		append(b, 5)
		put_u32(b, len(x))
		for item in x {
			encode_value(b, item)
		}
	case toml.Inline:
		append(b, 6)
		put_u32(b, len(x))
		for entry in x {
			put_text(b, entry.key)
			encode_value(b, entry.value)
		}
	case:
		append(b, 0, 0)
	}
}

@(private)
Reader :: struct {
	data: []byte,
	at:   int,
	ok:   bool,
}

@(private)
take :: proc(r: ^Reader, n: int) -> []byte {
	if !r.ok || n < 0 || r.at + n > len(r.data) {
		r.ok = false
		return nil
	}
	out := r.data[r.at:r.at + n]
	r.at += n
	return out
}

@(private)
take_u32 :: proc(r: ^Reader) -> int {
	bytes := take(r, 4)
	n := 0
	for byte, i in bytes {
		n |= int(byte) << uint(8 * i)
	}
	return n
}

@(private)
take_u64 :: proc(r: ^Reader) -> u64 {
	bytes := take(r, 8)
	n: u64
	for byte, i in bytes {
		n |= u64(byte) << uint(8 * i)
	}
	return n
}

@(private)
take_text :: proc(r: ^Reader) -> string {
	bytes := take(r, take_u32(r))
	if !r.ok {
		return ""
	}
	return strings.clone(string(bytes))
}

@(private)
decode_value :: proc(r: ^Reader, depth: int) -> toml.Value {
	if depth > 16 {
		r.ok = false
		return nil
	}
	tag := take(r, 1)
	if !r.ok {
		return nil
	}
	switch tag[0] {
	case 0:
		flag := take(r, 1)
		return r.ok && flag[0] != 0
	case 1:
		return i64(take_u64(r))
	case 2:
		return transmute(f64)take_u64(r)
	case 3:
		s := take_text(r)
		if !r.ok {
			delete(s)
			return nil
		}
		return s
	case 4:
		n := take_u32(r)
		if !r.ok || n * 8 > len(r.data) - r.at {
			r.ok = false
			return nil
		}
		out := make([]f64, n)
		for i in 0 ..< n {
			out[i] = transmute(f64)take_u64(r)
		}
		return out
	case 5:
		n := take_u32(r)
		if !r.ok || n > len(r.data) - r.at {
			r.ok = false
			return nil
		}
		out := make([dynamic]toml.Value, 0, n)
		for _ in 0 ..< n {
			item := decode_value(r, depth + 1)
			if !r.ok {
				for it in out {
					toml.free_value(it)
				}
				delete(out)
				return nil
			}
			append(&out, item)
		}
		return out[:]
	case 6:
		n := take_u32(r)
		if !r.ok || n > len(r.data) - r.at {
			r.ok = false
			return nil
		}
		out := make([dynamic]toml.Entry, 0, n)
		for _ in 0 ..< n {
			key := take_text(r)
			item := decode_value(r, depth + 1)
			if !r.ok {
				delete(key)
				for entry in out {
					delete(entry.key)
					toml.free_value(entry.value)
				}
				delete(out)
				return nil
			}
			append(&out, toml.Entry{key = key, value = item})
		}
		return toml.Inline(out[:])
	}
	r.ok = false
	return nil
}

// ---- the sealed file ----

// A document's values sealed with a key and a nonce of 24 bytes: the magic, the version, the nonce, the
// ciphertext and its tag, all of it covered by the tag.
vault_seal :: proc(doc: ^toml.Document, key: Vault_Key, nonce: [chacha20poly1305.XIV_SIZE]byte, allocator := context.allocator) -> []byte {
	plain := make([dynamic]byte, context.temp_allocator)
	table := toml.find_table(doc, "")
	count := 0 if table == nil else len(table.entries)
	put_u32(&plain, count)
	if table != nil {
		for entry in table.entries {
			put_text(&plain, entry.key)
			encode_value(&plain, entry.value)
		}
	}
	out := make([]byte, VAULT_HEADER + len(plain) + chacha20poly1305.TAG_SIZE, allocator)
	copy(out, VAULT_MAGIC)
	out[4] = VAULT_VERSION
	nonce := nonce
	copy(out[5:], nonce[:])
	sub := vault_subkey(key)
	defer crypto.zero_explicit(&sub, len(sub))
	ctx: chacha20poly1305.Context
	chacha20poly1305.init_xchacha(&ctx, sub[:])
	defer chacha20poly1305.reset(&ctx)
	cipher := out[VAULT_HEADER:VAULT_HEADER + len(plain)]
	tag := out[VAULT_HEADER + len(plain):]
	chacha20poly1305.seal(&ctx, cipher, tag, nonce[:], out[:5], plain[:])
	return out
}

// The values of a sealed file, or false when it is not one, was changed, is cut short or was made with
// another key.
vault_open_bytes :: proc(data: []byte, key: Vault_Key) -> (doc: toml.Document, ok: bool) {
	if len(data) < VAULT_HEADER + 4 + chacha20poly1305.TAG_SIZE || string(data[:4]) != VAULT_MAGIC || data[4] != VAULT_VERSION {
		return {}, false
	}
	sub := vault_subkey(key)
	defer crypto.zero_explicit(&sub, len(sub))
	ctx: chacha20poly1305.Context
	chacha20poly1305.init_xchacha(&ctx, sub[:])
	defer chacha20poly1305.reset(&ctx)
	body := len(data) - VAULT_HEADER - chacha20poly1305.TAG_SIZE
	plain := make([]byte, body, context.temp_allocator)
	if !chacha20poly1305.open(&ctx, plain, data[5:VAULT_HEADER], data[:5], data[VAULT_HEADER:VAULT_HEADER + body], data[VAULT_HEADER + body:]) {
		return {}, false
	}
	r := Reader{data = plain, ok = true}
	count := take_u32(&r)
	if !r.ok || count > len(plain) {
		return {}, false
	}
	append(&doc.tables, toml.Table{name = ""})
	table := &doc.tables[0]
	for _ in 0 ..< count {
		key := take_text(&r)
		value := decode_value(&r, 0)
		if !r.ok {
			delete(key)
			toml.destroy(&doc)
			return {}, false
		}
		append(&table.entries, toml.Entry{key = key, value = value})
	}
	if r.at != len(plain) {
		toml.destroy(&doc)
		return {}, false
	}
	return doc, true
}

// Reads a vault file. When the newest one is missing, or does not open, the one before it
// (`.bak`) is tried. `Missing` is a vault never written, `Bad` one there that cannot be read.
vault_read_file :: proc(path: string, key: Vault_Key) -> (doc: toml.Document, status: Vault_Status) {
	status = .Missing
	for candidate in ([]string{path, fmt.tprintf("%s.bak", path)}) {
		data, err := os.read_entire_file(candidate, context.temp_allocator)
		if err != nil {
			continue
		}
		if opened, ok := vault_open_bytes(data, key); ok {
			return opened, .Ok
		}
		status = .Bad
	}
	return {}, status
}

// Writes a vault file beside itself and moves it over, keeping the one before as `.bak`.
vault_write_file :: proc(path: string, doc: ^toml.Document, key: Vault_Key, nonce: [chacha20poly1305.XIV_SIZE]byte) -> bool {
	sealed := vault_seal(doc, key, nonce, context.temp_allocator)
	partial := fmt.tprintf("%s.part", path)
	if os.write_entire_file(partial, sealed) != nil {
		return false
	}
	if os.exists(path) {
		os.rename(path, fmt.tprintf("%s.bak", path))
	}
	if os.rename(partial, path) != nil {
		os.remove(partial)
		return false
	}
	return true
}

// ---- the vault of a running sketch ----

// Keeps the vault in this file, sealed with this key, from now on, and takes what it already holds. A
// file that does not open is said once; a run that may write moves it aside to `.bad` and starts empty.
vault_persist :: proc(path: string, key: Vault_Key, writes := true) {
	vault_forget_file()
	the.vault_file = clone_text(path)
	the.vault_key = key
	the.vault_has_key = true
	the.vault_writes = writes
	doc, status := vault_read_file(path, key)
	switch status {
	case .Ok:
		the.vault_doc = doc
	case .Missing:
	case .Bad:
		fmt.eprintfln("rocinante: %s was changed or is not this sketch's, so the vault starts empty", path)
		if writes {
			bad := fmt.tprintf("%s.bad", path)
			os.remove(bad)
			os.rename(path, bad)
			os.remove(fmt.tprintf("%s.bak", path))
		}
	}
}

vault_forget_file :: proc() {
	delete(the.vault_file)
	the.vault_file = ""
	the.vault_writes = false
	the.vault_has_key = false
	the.vault_key = {}
	toml.destroy(&the.vault_doc)
	the.vault_dirty = false
}

vault_get :: proc(key: string) -> (value: toml.Value, found: bool) {
	return toml.get(&the.vault_doc, "", key)
}

vault_put :: proc(key: string, value: toml.Value) {
	toml.set(&the.vault_doc, "", key, value)
	vault_touch()
}

vault_forget :: proc(key: string) {
	if table := toml.find_table(&the.vault_doc, ""); table != nil {
		if drop_entry(table, key) {
			vault_touch()
		}
	}
}

vault_forget_all :: proc() {
	if table := toml.find_table(&the.vault_doc, ""); table != nil && len(table.entries) > 0 {
		for entry in table.entries {
			delete(entry.key)
			toml.free_value(entry.value)
		}
		clear(&table.entries)
		vault_touch()
	}
}

@(private)
vault_touch :: proc() {
	if the.vault_has_key && the.vault_writes && the.vault_file != "" {
		the.vault_dirty = true
		the.vault_changed = time.tick_now()
	}
}

vault_save :: proc() -> bool {
	if !the.vault_has_key || !the.vault_writes || the.vault_file == "" {
		return true
	}
	the.vault_dirty = false
	nonce: [chacha20poly1305.XIV_SIZE]byte
	if the.vault_random != nil {
		the.vault_random(nonce[:])
	} else {
		crypto.rand_bytes(nonce[:])
	}
	if !vault_write_file(the.vault_file, &the.vault_doc, the.vault_key, nonce) {
		fmt.eprintfln("rocinante: I could not write %s", the.vault_file)
		return false
	}
	return true
}

@(private)
vault_autosave :: proc() {
	if the.vault_dirty && time.tick_since(the.vault_changed) >= VAULT_SAVE_AFTER {
		vault_save()
	}
}

vault_flush :: proc() {
	if the.vault_dirty {
		vault_save()
	}
}
