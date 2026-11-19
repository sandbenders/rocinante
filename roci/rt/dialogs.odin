// SPDX-License-Identifier: 0BSD
//
// `ask file`, `ask folder` and `ask save`, `read`, `open` and the clipboard in a compiled sketch: a dialog never makes the
// sketch wait, the procedure of its block runs once a frame when the player has chosen, with `chosen` the path, and the
// paths players chose are the only ones outside `assets/` that `load`, `read` and `open` take.
package rt

import "core:fmt"
import "core:os"
import "core:strings"
import "../"
import "../folder"
import "../platform"

@(private)
Ask :: struct {
	id:   int,
	body: proc(),
}

@(thread_local) @(private) asks: [dynamic]Ask
@(thread_local) @(private) allowed: map[string]bool
@(thread_local) chosen_path: string

MAX_OPEN_DIALOGS :: 4

// `ask file "png jpg" [ ... ]`, `ask folder [ ... ]`, `ask save "name.png" [ ... ]`: `kind` is 0, 1 or 2.
ask :: proc(kind: int, text: string, body: proc()) {
	if len(asks) >= MAX_OPEN_DIALOGS {
		return
	}
	k: platform.Dialog_Kind
	types, place := "", ""
	switch kind {
	case 0:
		k, types = .Open_File, text
	case 1:
		k = .Open_Folder
	case 2:
		k = .Save_File
		place = text
		if dot := strings.last_index_byte(text, '.'); dot >= 0 {
			types = text[dot + 1:]
		}
	}
	append(&asks, Ask{id = roci.ask_dialog(k, types, place), body = body})
}

// Once a frame: runs the block of every dialog the player has answered.
step_asks :: proc() {
	for i := 0; i < len(asks); {
		pending := asks[i]
		got := platform.dialog_take(pending.id, context.temp_allocator)
		if got.state == .Waiting {
			i += 1
			continue
		}
		ordered_remove(&asks, i)
		if got.state != .Chosen {
			continue
		}
		if allowed == nil {
			allowed = make(map[string]bool)
		}
		if !(got.path in allowed) {
			allowed[strings.clone(got.path)] = true
		}
		chosen_path = keep(got.path)
		pending.body()
		chosen_path = ""
	}
}

// Whether a path is one the player chose.
is_chosen :: proc(path: string) -> bool {
	return path in allowed
}

@(private)
asset_path :: proc(name: string) -> (path: string, ok: bool) {
	found, status, _ := folder.find_asset(ASSETS_ROOT, name, context.temp_allocator)
	if status != .Found {
		return "", false
	}
	return strings.concatenate({ASSETS_ROOT, "/", found}, context.temp_allocator), true
}

// `read "notes.txt"`: the text of a file of the assets folder or one the player chose.
read :: proc(name: string) -> string {
	path := name
	if !is_chosen(name) {
		found, ok := asset_path(name)
		if !ok {
			say_once(name, fmt.tprintf("I could not read `%s`: there is no file of that name in the assets folder, and it is not one the player chose.", name))
			return ""
		}
		path = found
	}
	bytes, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		say_once(name, fmt.tprintf("I could not read `%s`: the file is there but cannot be read.", name))
		return ""
	}
	return keep(string(bytes))
}

// `open "https://..."`: an address goes to the system as it is, a file as a `file://` address.
open :: proc(name: string) {
	target := name
	switch {
	case strings.contains(name, "://"), strings.has_prefix(name, "mailto:"), strings.has_prefix(name, "tel:"):
	case is_chosen(name):
		target = strings.concatenate({"file://", name}, context.temp_allocator)
	case:
		found, ok := asset_path(name)
		if !ok {
			say_once(name, fmt.tprintf("I could not open `%s`: it is not a web address, and there is no file of that name in the assets folder.", name))
			return
		}
		target = strings.concatenate({"file://", found}, context.temp_allocator)
	}
	if !roci.open_address(target) {
		say_once(name, fmt.tprintf("I could not open `%s`: the computer could not open it.", name))
	}
}

// The names of the MIDI outputs and of the cameras, as lists of text.
text_list :: proc(names: []string) -> ^List(string) {
	out := new_list(string, mark_text)
	for n in names {
		add(keep(n), out)
	}
	return out
}
