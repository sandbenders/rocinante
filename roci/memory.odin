// SPDX-License-Identifier: 0BSD
//
// What a sketch remembers between runs: `remember "best score" 1280` and `recall "best score"`, kept in
// `memory.toml` beside the sketch. Values live in memory first; the file is written once they have been
// still for a second, when the sketch ends and when it goes to the background, never on every
// `remember`, so a sketch may call it in `draw`. A file is only written by a sketch that runs in a
// window: headless runs, `roci test` and `--frames` read it and never write it.
package roci

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

import "toml"

// How long the values stay still before they are written.
MEMORY_SAVE_AFTER :: time.Second

// A file past this size is a data set, not a sketch's state: it is said once.
MEMORY_LARGE :: 300 * 1024

MEMORY_HEADER :: "# What sketch.roci remembers. Edit it freely while the sketch isn't running.\n"

// Remembers in this file from now on, and takes what it already says. `writes` is false for a run that
// must never change the file. A file that is not there is made when there is something to say; one that
// cannot be read right is said and what can be read is used.
memory_persist :: proc(path: string, writes := true) {
	memory_forget_file()
	the.memory_file = clone_text(path)
	the.memory_writes = writes
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		return
	}
	defer delete(data)
	the.memory_doc = toml.parse(string(data), true)
	for problem in the.memory_doc.problems {
		fmt.eprintfln("rocinante: %s line %d: %s", path, problem.line, problem.why)
	}
}

// Stops using the file, and forgets what it said and everything remembered since.
memory_forget_file :: proc() {
	delete(the.memory_file)
	the.memory_file = ""
	the.memory_writes = false
	toml.destroy(&the.memory_doc)
	the.memory_dirty = false
	the.memory_warned = false
}

// What is remembered under this key (borrowed), if anything.
memory_get :: proc(key: string) -> (value: toml.Value, found: bool) {
	return toml.get(&the.memory_doc, "", key)
}

// Remembers a value (copied) under a key, and says the file has changed.
memory_put :: proc(key: string, value: toml.Value) {
	toml.set(&the.memory_doc, "", key, value)
	memory_touch()
}

// Forgets one key.
memory_forget :: proc(key: string) {
	table := toml.find_table(&the.memory_doc, "")
	if table == nil {
		return
	}
	for entry, i in table.entries {
		if entry.key == key {
			delete(entry.key)
			toml.free_value(entry.value)
			ordered_remove(&table.entries, i)
			memory_touch()
			return
		}
	}
}

// Forgets everything.
memory_forget_all :: proc() {
	table := toml.find_table(&the.memory_doc, "")
	if table == nil || len(table.entries) == 0 {
		return
	}
	for entry in table.entries {
		delete(entry.key)
		toml.free_value(entry.value)
	}
	clear(&table.entries)
	memory_touch()
}

@(private)
memory_touch :: proc() {
	if the.memory_file != "" && the.memory_writes {
		the.memory_dirty = true
		the.memory_changed = time.tick_now()
	}
}

// Writes the file now.
memory_save :: proc() -> bool {
	if the.memory_file == "" || !the.memory_writes {
		return true
	}
	body := toml.write(&the.memory_doc, context.temp_allocator, true)
	the.memory_dirty = false
	// no file to make for a sketch that remembers nothing
	if body == "" && !os.exists(the.memory_file) {
		return true
	}
	text := strings.concatenate({MEMORY_HEADER, "\n" if body != "" else "", body}, context.temp_allocator)
	if len(text) > MEMORY_LARGE && !the.memory_warned {
		the.memory_warned = true
		fmt.eprintfln("rocinante: %s is getting large; remember is for a sketch's state, and a long list of results is better saved with save \"log.csv\"", the.memory_file)
	}
	// written beside it and moved over, so a file is never left half written
	partial := fmt.tprintf("%s.part", the.memory_file)
	if os.write_entire_file(partial, transmute([]byte)text) != nil {
		fmt.eprintfln("rocinante: I could not write %s", the.memory_file)
		return false
	}
	if os.rename(partial, the.memory_file) != nil {
		os.remove(partial)
		fmt.eprintfln("rocinante: I could not write %s", the.memory_file)
		return false
	}
	return true
}

// Called every frame: writes the file once the values have been still for a moment.
@(private)
memory_autosave :: proc() {
	if the.memory_dirty && time.tick_since(the.memory_changed) >= MEMORY_SAVE_AFTER {
		memory_save()
	}
}

// Writes what has not been written yet: when the sketch ends, goes to the background or shows an error.
memory_flush :: proc() {
	if the.memory_dirty {
		memory_save()
	}
}

// Called by the platform when the program is about to go to the background or be ended by the system.
@(private)
background_flush :: proc "c" () {
	context = abi_context()
	memory_flush()
	ui_flush()
}
