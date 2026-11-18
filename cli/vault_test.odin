// SPDX-License-Identifier: 0BSD
package main

import "../roci"
import "../roci/toml"
import "core:os"
import "core:strings"
import "core:testing"

vault_folder :: proc(name: string) -> string {
	folder := strings.concatenate({"output/tests/", name}, context.temp_allocator)
	os.make_directory("output")
	os.make_directory("output/tests")
	os.make_directory(folder)
	for file in ([]string{"vault.key", "vault.bin", "vault.bin.bak", "vault.bin.part"}) {
		os.remove(strings.concatenate({folder, "/", file}, context.temp_allocator))
	}
	return folder
}

@(test)
test_vault_show_set_and_forget_work_on_a_folders_vault :: proc(t: ^testing.T) {
	folder := vault_folder("cli_vault")
	run :: proc(args: ..string) -> (code: int, out, err: string) {
		o, e: strings.Builder
		strings.builder_init(&o, context.temp_allocator)
		strings.builder_init(&e, context.temp_allocator)
		code = run_vault(args, &o, &e)
		return code, strings.to_string(o), strings.to_string(e)
	}
	// no key: nothing to open
	code: int
	out, err: string
	code, _, err = run("show", "--folder", folder)
	testing.expect_value(t, code, 1)
	testing.expect(t, strings.contains(err, "vault.key"))
	_, made := roci.vault_key_for(folder, true)
	testing.expect(t, made)
	code, out, _ = run("show", "--folder", folder)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.has_prefix(out, "# ") && strings.contains(out, "vault.bin\n"), out)
	testing.expect_value(t, after_place(out), "The vault is empty.\n")
	code, _, _ = run("set", "levels", "7", "--folder", folder)
	testing.expect_value(t, code, 0)
	code, _, _ = run("set", "name", "\"Ana\"", "--folder", folder)
	testing.expect_value(t, code, 0)
	code, _, _ = run("set", "cleared", "[1, 2, 3]", "--folder", folder)
	testing.expect_value(t, code, 0)
	code, out, _ = run("show", "--folder", folder)
	testing.expect_value(t, after_place(out), "levels = 7\nname = \"Ana\"\ncleared = [1.0, 2.0, 3.0]\n")
	// a sketch's own run sees what was set
	key, _ := roci.vault_key_for(folder, false)
	doc, status := roci.vault_read_file(strings.concatenate({folder, "/vault.bin"}, context.temp_allocator), key)
	defer toml.destroy(&doc)
	testing.expect_value(t, status, roci.Vault_Status.Ok)
	// a value that is not one
	code, _, err = run("set", "x", "not a value", "--folder", folder)
	testing.expect_value(t, code, 2)
	testing.expect(t, strings.contains(err, "could not read"))
	code, _, _ = run("forget", "levels", "--folder", folder)
	testing.expect_value(t, code, 0)
	code, _, err = run("forget", "levels", "--folder", folder)
	testing.expect_value(t, code, 1)
	testing.expect(t, strings.contains(err, "keeps nothing"))
	code, out, _ = run("show", "--folder", folder)
	testing.expect_value(t, after_place(out), "name = \"Ana\"\ncleared = [1.0, 2.0, 3.0]\n")
	// the file does not show its values
	data, _ := os.read_entire_file(strings.concatenate({folder, "/vault.bin"}, context.temp_allocator), context.temp_allocator)
	testing.expect(t, !strings.contains(string(data), "Ana"))
}

@(test)
test_vault_says_what_is_wrong_with_its_words_and_its_file :: proc(t: ^testing.T) {
	folder := vault_folder("cli_vault_bad")
	run :: proc(args: ..string) -> (code: int, err: string) {
		o, e: strings.Builder
		strings.builder_init(&o, context.temp_allocator)
		strings.builder_init(&e, context.temp_allocator)
		code = run_vault(args, &o, &e)
		return code, strings.to_string(e)
	}
	code, err := run()
	testing.expect_value(t, code, 2)
	testing.expect(t, strings.contains(err, "roci vault show"))
	code, err = run("burn")
	testing.expect_value(t, code, 2)
	testing.expect(t, strings.contains(err, "do not know"))
	code, _ = run("set", "only-a-name")
	testing.expect_value(t, code, 2)
	code, _ = run("show", "--folder")
	testing.expect_value(t, code, 2)
	// a file that was changed does not open
	_, _ = roci.vault_key_for(folder, true)
	_ = os.write_entire_file(strings.concatenate({folder, "/vault.bin"}, context.temp_allocator), transmute([]byte)string("not sealed"))
	code, err = run("show", "--folder", folder)
	testing.expect_value(t, code, 1)
	testing.expect(t, strings.contains(err, "does not open"))
}

// What `roci vault show` wrote after its first line, which says where the vault is.
after_place :: proc(out: string) -> string {
	if at := strings.index_byte(out, '\n'); at >= 0 && strings.has_prefix(out, "# ") {
		return out[at + 1:]
	}
	return out
}
