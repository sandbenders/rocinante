// SPDX-License-Identifier: 0BSD
//
// `ask file`, `ask folder` and `ask save`, `read`, `open` and the clipboard. A dialog never makes the sketch
// wait: asking shows it and keeps the block, and the frame hook looks once a frame for answers; when the player
// has chosen, the block runs with `chosen` the path. The paths players chose are the only ones outside
// `assets/` that `load`, `read` and `open` take, so a sketch cannot read a file the player did not name.
package interp

import "../"
import "../folder"
import "../lang"
import "../platform"
import "core:os"
import "core:strings"

// A dialog that is open, and the block to run when it is answered.
Ask :: struct {
	id:   int,
	body: ^lang.IR_Block,
}

@(private)
ask_verb :: proc(it: ^Interp, call: lang.IR_Call, code: Verb_Code) {
	if len(call.args) == 0 {
		return
	}
	block, is_block := &call.args[len(call.args) - 1].kind.(lang.IR_Block_Value)
	if !is_block {
		return
	}
	text := ""
	if len(call.args) > 1 {
		text = as_text(eval(it, call.args[0]))
	}
	kind: platform.Dialog_Kind
	types, place := "", ""
	#partial switch code {
	case .Ask_File:
		kind, types = .Open_File, text
	case .Ask_Folder:
		kind = .Open_Folder
	case .Ask_Save:
		kind = .Save_File
		place = text
		// the ending of the name says which kind of file to show
		if dot := strings.last_index_byte(text, '.'); dot >= 0 {
			types = text[dot + 1:]
		}
	}
	if len(it.asks) >= MAX_OPEN_DIALOGS {
		return // a sketch that asks every frame gets one dialog at a time, not a pile of them
	}
	id := roci.ask_dialog(kind, types, place)
	append(&it.asks, Ask{id = id, body = &block.block})
}

// How many dialogs a sketch may have open at once.
MAX_OPEN_DIALOGS :: 4

// Called once a frame: runs the block of every dialog the player has answered.
@(private)
run_asks :: proc(p: ^Interp) {
	for i := 0; i < len(p.asks); {
		ask := p.asks[i]
		got := platform.dialog_take(ask.id, context.temp_allocator)
		if got.state == .Waiting {
			i += 1
			continue
		}
		ordered_remove(&p.asks, i)
		if got.state != .Chosen {
			continue
		}
		path := strings.clone(got.path)
		if !(path in p.allowed) {
			p.allowed[path] = true
		} else {
			delete(path)
		}
		p.chosen = got.path
		run_block(p, ask.body)
		p.chosen = ""
	}
}

// Forgets every dialog the sketch left open.
@(private)
drop_asks :: proc(p: ^Interp) {
	for ask in p.asks {
		got := platform.dialog_take(ask.id, context.temp_allocator)
		_ = got
	}
	delete(p.asks)
	for path in p.allowed {
		delete(path)
	}
	delete(p.allowed)
}

// A path the player chose in a dialog.
@(private)
is_chosen :: proc(p: ^Interp, path: string) -> bool {
	return path in p.allowed
}

// The whole path of a file of the assets folder, on the temp allocator.
@(private)
asset_path :: proc(it: ^Interp, name: string) -> (path: string, ok: bool) {
	root, _ := assets_root(it)
	if root == "" {
		return "", false
	}
	found, status, _ := folder.find_asset(root, name, context.temp_allocator)
	if status != .Found {
		return "", false
	}
	return strings.concatenate({root, "/", found}, context.temp_allocator), true
}

// The text of a file of the assets folder or one the player chose.
@(private)
read_text :: proc(it: ^Interp, name: string, span: lang.Span) -> Value {
	path := name
	if !is_chosen(it, name) {
		found, ok := asset_path(it, name)
		if !ok {
			fail(it, .File_Not_Read, span, name, "There is no file of that name in the assets folder, and it is not one the player chose.", "", "x = read \"notes.txt\"")
			return ""
		}
		path = found
	}
	bytes, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		fail(it, .File_Not_Read, span, name, "The file is there but cannot be read.", "", "x = read \"notes.txt\"")
		return ""
	}
	return strings.clone(string(bytes), it.alloc)
}

// `open`: an address goes to the system as it is, a path the player chose or a file of the assets folder as a
// `file://` address.
@(private)
open_verb :: proc(it: ^Interp, name: string, span: lang.Span) {
	target := name
	switch {
	case strings.contains(name, "://"), strings.has_prefix(name, "mailto:"), strings.has_prefix(name, "tel:"):
	case is_chosen(it, name):
		target = strings.concatenate({"file://", name}, context.temp_allocator)
	case:
		found, ok := asset_path(it, name)
		if !ok {
			fail(it, .Open_Failed, span, name, "It is not a web address, and there is no file of that name in the assets folder.", "", "open \"https://rocinante-lang.org\"")
			return
		}
		target = strings.concatenate({"file://", found}, context.temp_allocator)
	}
	if !roci.open_address(target) {
		fail(it, .Open_Failed, span, name, "The computer could not open it.", "", "open \"https://rocinante-lang.org\"")
	}
}
