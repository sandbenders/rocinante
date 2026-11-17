// SPDX-License-Identifier: 0BSD
//
// `roci vault`: look into the sealed vault of a sketch folder, and change it. The vault is the file a
// sketch keeps values in with `remember "levels" 5 in vault`; it holds nothing a text editor can read,
// so this is how its maker tests a game: show what a player's file holds, or set a value to try a level.
package main

import "../roci"
import "../roci/toml"
import "core:crypto"
import "core:fmt"
import "core:strings"

VAULT_USAGE :: `roci vault show [--folder path]
roci vault set <name> <value> [--folder path]
roci vault forget <name> [--folder path]

  show    write what the vault holds, one name = value on a line
  set     keep a value under a name; the value is written as it is in a file:
          12, "text", true, [1, 2, 3]
  forget  take a name out of the vault

The folder is this one unless --folder says another. Its key is vault.key, which roci run makes
the first time a sketch uses the vault.`

run_vault :: proc(args: []string, out, err: ^strings.Builder) -> int {
	words := make([dynamic]string, context.temp_allocator)
	folder := "."
	i := 0
	for i < len(args) {
		if args[i] == "--folder" {
			if i + 1 >= len(args) {
				fmt.sbprintf(err, "--folder needs the folder after it.\n\n%s\n", VAULT_USAGE)
				return 2
			}
			folder = args[i + 1]
			i += 2
			continue
		}
		append(&words, args[i])
		i += 1
	}
	if len(words) == 0 {
		fmt.sbprintf(err, "%s\n", VAULT_USAGE)
		return 2
	}
	needed := 0
	switch words[0] {
	case "show":   needed = 1
	case "set":    needed = 3
	case "forget": needed = 2
	case:
		fmt.sbprintf(err, "I do not know `roci vault %s`.\n\n%s\n", words[0], VAULT_USAGE)
		return 2
	}
	if len(words) != needed {
		fmt.sbprintf(err, "`roci vault %s` is written differently.\n\n%s\n", words[0], VAULT_USAGE)
		return 2
	}
	key, key_ok := roci.vault_key_for(folder, false)
	if !key_ok {
		fmt.sbprintf(err, "There is no vault.key in %s, so there is no vault to open. Run the sketch once, with roci run, and it makes one.\n", folder)
		return 1
	}
	path := fmt.tprintf("%s/vault.bin", folder)
	doc, status := roci.vault_read_file(path, key)
	defer toml.destroy(&doc)
	if status == .Bad {
		fmt.sbprintf(err, "%s does not open with this folder's vault.key: it was changed, or sealed with another key.\n", path)
		return 1
	}
	switch words[0] {
	case "show":
		text := toml.write(&doc, context.temp_allocator, true)
		if text == "" {
			fmt.sbprintf(out, "The vault is empty.\n")
		} else {
			fmt.sbprintf(out, "%s", text)
		}
		return 0
	case "set":
		parsed := toml.parse(fmt.tprintf("v = %s\n", words[2]), true)
		defer toml.destroy(&parsed)
		value, found := toml.get(&parsed, "", "v")
		if len(parsed.problems) > 0 || !found {
			fmt.sbprintf(err, "I could not read `%s` as a value. Write it as it is in a file: 12, \"text\" (with the quotes), true or [1, 2, 3].\n", words[2])
			return 2
		}
		toml.set(&doc, "", words[1], value)
	case "forget":
		table := toml.find_table(&doc, "")
		if table == nil {
			fmt.sbprintf(err, "The vault keeps nothing under `%s`.\n", words[1])
			return 1
		}
		at := -1
		for entry, n in table.entries {
			if entry.key == words[1] {
				at = n
			}
		}
		if at < 0 {
			fmt.sbprintf(err, "The vault keeps nothing under `%s`.\n", words[1])
			return 1
		}
		delete(table.entries[at].key)
		toml.free_value(table.entries[at].value)
		ordered_remove(&table.entries, at)
	}
	nonce: [24]byte
	crypto.rand_bytes(nonce[:])
	if !roci.vault_write_file(path, &doc, key, nonce) {
		fmt.sbprintf(err, "I could not write %s.\n", path)
		return 1
	}
	fmt.sbprintf(out, "Done.\n")
	return 0
}
