// SPDX-License-Identifier: 0BSD
package roci

import "core:os"
import "core:strings"
import "core:testing"

import "toml"

test_key :: proc(seed: byte) -> Vault_Key {
	key: Vault_Key
	for i in 0 ..< len(key) {
		key[i] = seed + byte(i)
	}
	return key
}

fixed_nonce :: proc(seed: byte) -> [24]byte {
	nonce: [24]byte
	for i in 0 ..< len(nonce) {
		nonce[i] = seed ~ byte(i)
	}
	return nonce
}

// A document holding one of every kind of value the binary form has.
sample_document :: proc() -> toml.Document {
	doc: toml.Document
	toml.set(&doc, "", "levels", i64(7))
	toml.set(&doc, "", "ratio", 2.5)
	toml.set(&doc, "", "word", "secret")
	toml.set(&doc, "", "flag", true)
	toml.set(&doc, "", "points", []f64{1, 2.5, 3})
	inner := []toml.Entry{{key = "k", value = "v"}, {key = "n", value = i64(1)}}
	items := []toml.Value{"a", toml.Inline(inner), []f64{4}}
	toml.set(&doc, "", "mixed", items)
	return doc
}

@(test)
test_a_sealed_vault_opens_with_its_key_and_gives_back_every_kind_of_value :: proc(t: ^testing.T) {
	doc := sample_document()
	defer toml.destroy(&doc)
	sealed := vault_seal(&doc, test_key(1), fixed_nonce(9))
	defer delete(sealed)
	back, ok := vault_open_bytes(sealed, test_key(1))
	defer toml.destroy(&back)
	testing.expect(t, ok)
	want := toml.write(&doc, context.temp_allocator, true)
	got := toml.write(&back, context.temp_allocator, true)
	testing.expect_value(t, got, want)
	testing.expect(t, strings.contains(got, "levels = 7"))
	// the values are not to be read in the file
	testing.expect(t, !strings.contains(string(sealed), "secret"))
	testing.expect(t, !strings.contains(string(sealed), "levels"))
}

@(test)
test_an_empty_vault_seals_and_opens :: proc(t: ^testing.T) {
	doc: toml.Document
	defer toml.destroy(&doc)
	sealed := vault_seal(&doc, test_key(1), fixed_nonce(1))
	defer delete(sealed)
	back, ok := vault_open_bytes(sealed, test_key(1))
	defer toml.destroy(&back)
	testing.expect(t, ok)
	testing.expect_value(t, len(back.tables[0].entries), 0)
}

@(test)
test_a_vault_that_was_changed_cut_short_or_sealed_with_another_key_does_not_open :: proc(t: ^testing.T) {
	doc := sample_document()
	defer toml.destroy(&doc)
	sealed := vault_seal(&doc, test_key(1), fixed_nonce(9))
	defer delete(sealed)
	// another key
	_, ok := vault_open_bytes(sealed, test_key(2))
	testing.expect(t, !ok, "another key")
	// every one of the bytes, changed one at a time, in the header, the values and the tag
	for i in 0 ..< len(sealed) {
		copy_of := make([]byte, len(sealed), context.temp_allocator)
		copy(copy_of, sealed)
		copy_of[i] ~= 1
		_, opened := vault_open_bytes(copy_of, test_key(1))
		if !testing.expectf(t, !opened, "byte %d changed and the vault still opened", i) {
			return
		}
	}
	// cut short at every length
	for n in 0 ..< len(sealed) {
		_, opened := vault_open_bytes(sealed[:n], test_key(1))
		if !testing.expectf(t, !opened, "cut at %d and the vault still opened", n) {
			return
		}
	}
	// something that is not a vault at all
	_, text_ok := vault_open_bytes(transmute([]byte)string("levels = 7\n"), test_key(1))
	testing.expect(t, !text_ok)
}

@(test)
test_a_nonce_makes_two_seals_of_the_same_values_differ :: proc(t: ^testing.T) {
	doc := sample_document()
	defer toml.destroy(&doc)
	a := vault_seal(&doc, test_key(1), fixed_nonce(1))
	b := vault_seal(&doc, test_key(1), fixed_nonce(2))
	c := vault_seal(&doc, test_key(1), fixed_nonce(1))
	defer delete(a)
	defer delete(b)
	defer delete(c)
	testing.expect(t, string(a) != string(b))
	testing.expect_value(t, string(a), string(c))
}

@(test)
test_the_vault_file_keeps_the_last_one_as_a_backup_and_uses_it_when_the_newest_is_missing :: proc(t: ^testing.T) {
	os.make_directory("output")
	os.make_directory("output/tests")
	path := "output/tests/vault_backup.bin"
	for suffix in ([]string{"", ".bak", ".part", ".bad"}) {
		os.remove(strings.concatenate({path, suffix}, context.temp_allocator))
	}
	defer for suffix in ([]string{"", ".bak", ".part", ".bad"}) {
		os.remove(strings.concatenate({path, suffix}, context.temp_allocator))
	}
	key := test_key(3)
	_, missing := vault_read_file(path, key)
	testing.expect_value(t, missing, Vault_Status.Missing)
	first: toml.Document
	toml.set(&first, "", "levels", i64(1))
	defer toml.destroy(&first)
	testing.expect(t, vault_write_file(path, &first, key, fixed_nonce(1)))
	testing.expect(t, !os.exists("output/tests/vault_backup.bin.bak"))
	second: toml.Document
	toml.set(&second, "", "levels", i64(2))
	defer toml.destroy(&second)
	testing.expect(t, vault_write_file(path, &second, key, fixed_nonce(2)))
	testing.expect(t, os.exists("output/tests/vault_backup.bin.bak"))
	latest, status := vault_read_file(path, key)
	testing.expect_value(t, status, Vault_Status.Ok)
	value, _ := toml.get(&latest, "", "levels")
	testing.expect_value(t, value.(i64), 2)
	toml.destroy(&latest)
	// the newest one lost: the one before takes its place
	os.remove(path)
	older, from_backup := vault_read_file(path, key)
	testing.expect_value(t, from_backup, Vault_Status.Ok)
	value, _ = toml.get(&older, "", "levels")
	testing.expect_value(t, value.(i64), 1)
	toml.destroy(&older)
	// the newest one ruined: the one before is used too
	_ = os.write_entire_file(path, transmute([]byte)string("nonsense"))
	again, ruined := vault_read_file(path, key)
	testing.expect_value(t, ruined, Vault_Status.Ok)
	toml.destroy(&again)
	// both ruined
	_ = os.write_entire_file("output/tests/vault_backup.bin.bak", transmute([]byte)string("nonsense"))
	_, both := vault_read_file(path, key)
	testing.expect_value(t, both, Vault_Status.Bad)
}

@(test)
test_a_running_sketch_keeps_its_vault_sealed_and_a_ruined_file_is_moved_aside :: proc(t: ^testing.T) {
	os.make_directory("output")
	os.make_directory("output/tests")
	path := "output/tests/vault_run.bin"
	for suffix in ([]string{"", ".bak", ".part", ".bad"}) {
		os.remove(strings.concatenate({path, suffix}, context.temp_allocator))
	}
	defer for suffix in ([]string{"", ".bak", ".part", ".bad"}) {
		os.remove(strings.concatenate({path, suffix}, context.temp_allocator))
	}
	key := test_key(5)
	start_headless(1)
	the.vault_random = proc(dst: []byte) {
		for i in 0 ..< len(dst) {
			dst[i] = 7
		}
	}
	vault_persist(path, key)
	abi_vault_remember_number("levels", 4)
	testing.expect(t, !os.exists(path), "not written at once")
	shutdown()
	data, err := os.read_entire_file(path, context.temp_allocator)
	testing.expect(t, err == nil)
	testing.expect(t, !strings.contains(string(data), "levels"))
	// the next run reads it
	start_headless(1)
	vault_persist(path, key)
	testing.expect_value(t, abi_vault_recall_number("levels", 0), 4)
	shutdown()
	// a run that may not write reads it and changes nothing
	start_headless(1)
	vault_persist(path, key, false)
	abi_vault_remember_number("levels", 99)
	vault_save()
	shutdown()
	same, _ := os.read_entire_file(path, context.temp_allocator)
	testing.expect_value(t, string(same), string(data))
	// changed by hand: the sketch starts empty, and the file is kept as .bad
	changed := make([]byte, len(data), context.temp_allocator)
	copy(changed, data)
	changed[len(changed) - 1] ~= 1
	_ = os.write_entire_file(path, changed)
	start_headless(1)
	vault_persist(path, key)
	testing.expect_value(t, abi_vault_recall_number("levels", 0), 0)
	testing.expect(t, os.exists("output/tests/vault_run.bin.bad"))
	testing.expect(t, !os.exists(path))
	shutdown()
}

@(test)
test_the_key_of_a_folder_is_made_once_and_read_after :: proc(t: ^testing.T) {
	folder := "output/tests/vault_key_folder"
	os.make_directory("output")
	os.make_directory("output/tests")
	os.make_directory(folder)
	os.remove("output/tests/vault_key_folder/vault.key")
	defer os.remove("output/tests/vault_key_folder/vault.key")
	_, without := vault_key_for(folder, false)
	testing.expect(t, !without, "no key and none to make")
	made, made_ok := vault_key_for(folder, true)
	testing.expect(t, made_ok)
	testing.expect(t, made != Vault_Key{})
	read, read_ok := vault_key_for(folder, false)
	testing.expect(t, read_ok)
	testing.expect_value(t, read, made)
	// a key file of the wrong size is not a key
	_ = os.write_entire_file("output/tests/vault_key_folder/vault.key", transmute([]byte)string("short"))
	_, short := vault_key_for(folder, false)
	testing.expect(t, !short)
}

@(test)
test_the_vault_c_functions_keep_every_kind_of_value :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	abi_vault_remember_number("n", 3)
	abi_vault_remember_text("word", "hi")
	abi_vault_remember_bool("flag", 1)
	numbers := [2]f64{1, 2}
	abi_vault_remember_numbers("list", cast([^]f64)rawptr(raw_data(numbers[:])), 2)
	testing.expect_value(t, abi_vault_recall_number("n", -1), 3)
	testing.expect_value(t, string(abi_vault_recall_text("word", "")), "hi")
	testing.expect_value(t, abi_vault_recall_bool("flag", 0), 1)
	out: [2]f64
	testing.expect_value(t, abi_vault_recall_numbers("list", raw_data(out[:]), 2), 2)
	// the two places are two sets of names
	testing.expect_value(t, abi_recall_number("n", -1), -1)
	abi_vault_forget("n")
	testing.expect_value(t, abi_vault_recall_number("n", 5), 5)
	abi_vault_forget_all()
	testing.expect_value(t, abi_vault_recall_bool("flag", 0), 0)
	key := test_key(1)
	testing.expect_value(t, abi_vault_set_key(nil, raw_data(key[:])), 0)
	testing.expect_value(t, abi_vault_set_key("output/tests/vault_c.bin", nil), 0)
}
