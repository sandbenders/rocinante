// SPDX-License-Identifier: 0BSD
//
// The values the widgets keep, remembered between runs in `ui.toml` beside the sketch. The file has a
// table for each window, `[ui]` for the first and `[ui2]`, `[ui3]` for the ones after it, and in it a
// line for each widget under its readable name: the panel and tab path and the text. It is read when
// the sketch starts (`ui_persist`), taken by each widget as it is first made, and written when the
// sketch ends and after a pause of a second in the changes, never on every move of a slider, so a
// performance does not leave the working tree dirty.
package roci

import "core:fmt"
import "core:os"
import "core:time"

import "toml"
import "ui"

// How long the values stay still before they are written.
UI_SAVE_AFTER :: time.Second

// Remembers the widgets' values in this file from now on, and takes what it already says. A file that is
// not there is made when there is something to say; one that cannot be read right is said and what can be
// read is used.
ui_persist :: proc(path: string) {
	ui_forget_file()
	the.ui_file = clone_text(path)
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		return
	}
	defer delete(data)
	the.ui_doc = toml.parse(string(data))
	for problem in the.ui_doc.problems {
		fmt.eprintfln("rocinante: %s line %d: %s", path, problem.line, problem.why)
	}
}

// Stops remembering (and forgets the file it read).
ui_forget_file :: proc() {
	delete(the.ui_file)
	the.ui_file = ""
	toml.destroy(&the.ui_doc)
	the.ui_dirty = false
}

// Says a widget's value changed, so the file is written when things have been still for a moment.
@(private)
ui_touch :: proc() {
	if the.ui_file != "" {
		the.ui_dirty = true
		the.ui_changed = time.tick_now()
	}
}

// The table of a window: `ui` for the first window and `ui2` and so on for the rest.
@(private)
ui_table_name :: proc(index: int) -> string {
	if index <= 0 {
		return "ui"
	}
	return fmt.tprintf("ui%d", index + 1)
}

@(private)
window_index :: proc(w: ^Win) -> int {
	for other, i in the.windows {
		if other == w {
			return i
		}
	}
	return 0
}

// Gives a window's interface what the file said about it.
@(private)
ui_remembered :: proc(w: ^Win) {
	if the.ui_file == "" || w.ui == nil {
		return
	}
	table := toml.find_table(&the.ui_doc, ui_table_name(window_index(w)))
	if table == nil {
		return
	}
	entries := make([dynamic]ui.Saved, context.temp_allocator)
	for entry in table.entries {
		switch x in entry.value {
		case bool:
			append(&entries, ui.Saved{entry.key, x})
		case i64:
			append(&entries, ui.Saved{entry.key, f64(x)})
		case f64:
			append(&entries, ui.Saved{entry.key, x})
		case string:
			append(&entries, ui.Saved{entry.key, x})
		case []f64:
			numbers := ui.Numbers{n = min(len(x), 4)}
			for i in 0 ..< numbers.n {
				numbers.v[i] = f32(x[i])
			}
			append(&entries, ui.Saved{entry.key, numbers})
		}
	}
	ui.set_loaded(w.ui, entries[:])
}

// Writes the file now: the table of every window that has an interface is made again from its values,
// and the tables of windows that are not open stay as the file had them.
ui_save :: proc() -> bool {
	if the.ui_file == "" {
		return true
	}
	for w in the.windows {
		if w.ui == nil {
			continue
		}
		name := ui_table_name(window_index(w))
		if table := toml.find_table(&the.ui_doc, name); table != nil {
			for entry in table.entries {
				delete(entry.key)
				switch x in entry.value {
				case string:  delete(x)
				case []f64:   delete(x)
				case bool, i64, f64:
				}
			}
			clear(&table.entries)
		}
		for saved in ui.snapshot(w.ui) {
			switch x in saved.value {
			case f64:
				toml.set(&the.ui_doc, name, saved.key, x)
			case bool:
				toml.set(&the.ui_doc, name, saved.key, x)
			case string:
				toml.set(&the.ui_doc, name, saved.key, x)
			case ui.Numbers:
				numbers := make([]f64, x.n, context.temp_allocator)
				for i in 0 ..< x.n {
					numbers[i] = f64(x.v[i])
				}
				toml.set(&the.ui_doc, name, saved.key, numbers)
			}
		}
	}
	text := toml.write(&the.ui_doc, context.temp_allocator)
	the.ui_dirty = false
	// no file to make for a sketch that remembers nothing
	if text == "" && !os.exists(the.ui_file) {
		return true
	}
	// written beside it and moved over, so a file is never left half written
	partial := fmt.tprintf("%s.part", the.ui_file)
	if os.write_entire_file(partial, transmute([]byte)text) != nil {
		fmt.eprintfln("rocinante: I could not write %s", the.ui_file)
		return false
	}
	if os.rename(partial, the.ui_file) != nil {
		os.remove(partial)
		fmt.eprintfln("rocinante: I could not write %s", the.ui_file)
		return false
	}
	return true
}

// Called every frame: writes the file once the values have been still for a moment.
@(private)
ui_autosave :: proc() {
	if the.ui_dirty && time.tick_since(the.ui_changed) >= UI_SAVE_AFTER {
		ui_save()
	}
}

// Called when the sketch ends: whatever has not been written is.
@(private)
ui_flush :: proc() {
	if the.ui_dirty {
		ui_save()
	}
}
