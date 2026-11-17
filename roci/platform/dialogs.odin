// SPDX-License-Identifier: 0BSD
//
// The system's own dialogs for choosing a file, a folder or a place to save, the clipboard, and opening an
// address or a file in the program that owns it. A dialog never waits: `dialog_ask` shows it and gives a
// number, and what the player chose is put in a locked table that `dialog_take` empties one number at a time.
// SDL calls back from whichever thread the system's dialog ran on (the main one on most systems), so the table
// is guarded and each request is taken by its own number; a request that was never taken is thrown away by
// `dialogs_forget`.
package platform

import "base:runtime"
import "core:c"
import "core:strings"
import "core:sync"

import sdl "vendor:sdl3"

Dialog_Kind :: enum u8 {
	Open_File,
	Open_Folder,
	Save_File,
}

// What became of a request.
Dialog_State :: enum u8 {
	Waiting, // the dialog is still open
	Chosen,  // the player chose `path`
	Closed,  // the player closed it without choosing, or the system had none to show
}

Dialog_Result :: struct {
	state: Dialog_State,
	path:  string, // owned, on the allocator `dialog_take` was given
}

@(private)
Pending_Dialog :: struct {
	state: Dialog_State,
	path:  string, // owned, on the heap
}

@(private)
dialog_lock: sync.Mutex
@(private)
dialog_table: map[int]Pending_Dialog
@(private)
dialog_next: int

// What the callback is given to find its request.
@(private)
Dialog_Ticket :: struct {
	id: int,
}

// The extensions of a filter text such as "png jpg", as the pattern SDL wants: "png;jpg". Anything that is not
// a letter, a digit, `-` or `_` is dropped, so `.png` and `*.png` mean the same as `png`. Empty for no filter.
dialog_pattern :: proc(types: string, allocator := context.temp_allocator) -> string {
	out := make([dynamic]u8, allocator)
	word := make([dynamic]u8, context.temp_allocator)
	flush :: proc(out, word: ^[dynamic]u8) {
		if len(word) > 0 {
			if len(out) > 0 {
				append(out, ';')
			}
			append(out, ..word[:])
			clear(word)
		}
	}
	for ch in transmute([]u8)types {
		switch {
		case ch >= 'a' && ch <= 'z', ch >= 'A' && ch <= 'Z', ch >= '0' && ch <= '9', ch == '-', ch == '_':
			append(&word, ch)
		case:
			flush(&out, &word)
		}
	}
	flush(&out, &word)
	return string(out[:])
}

// A request that waits for an answer, with its number.
dialog_new :: proc() -> int {
	sync.mutex_lock(&dialog_lock)
	defer sync.mutex_unlock(&dialog_lock)
	dialog_next += 1
	if dialog_table == nil {
		dialog_table = make(map[int]Pending_Dialog, runtime.heap_allocator())
	}
	dialog_table[dialog_next] = {}
	return dialog_next
}

// Shows a dialog and gives the number of the request. `window` may be nil. `types` is the extensions to show,
// such as "png jpg" (only for a file to open or to save); `place` is the folder or the file name to start at.
dialog_ask :: proc(window: ^Window, kind: Dialog_Kind, types := "", place := "") -> int {
	id := dialog_new()
	ticket := new(Dialog_Ticket, runtime.heap_allocator())
	ticket.id = id
	handle := window.handle if window != nil else nil
	location := strings.clone_to_cstring(place, context.temp_allocator) if place != "" else nil
	pattern := dialog_pattern(types)
	filters: [1]sdl.DialogFileFilter
	count: c.int
	if pattern != "" && kind != .Open_Folder {
		filters[0] = {name = "files", pattern = strings.clone_to_cstring(pattern, context.temp_allocator)}
		count = 1
	}
	switch kind {
	case .Open_File:
		sdl.ShowOpenFileDialog(dialog_done, ticket, handle, raw_data(filters[:]), count, location, false)
	case .Open_Folder:
		sdl.ShowOpenFolderDialog(dialog_done, ticket, handle, location, false)
	case .Save_File:
		sdl.ShowSaveFileDialog(dialog_done, ticket, handle, raw_data(filters[:]), count, location)
	}
	return id
}

@(private)
dialog_done :: proc "c" (userdata: rawptr, filelist: [^]cstring, filter: c.int) {
	context = runtime.default_context()
	ticket := cast(^Dialog_Ticket)userdata
	path := ""
	if filelist != nil && filelist[0] != nil {
		path = string(filelist[0])
	}
	dialog_deliver(ticket.id, path)
	free(ticket, runtime.heap_allocator())
}

// Records what the player chose for a request: a path, or none when they closed the dialog. The system calls
// this; tests call it to play the player.
dialog_deliver :: proc(id: int, path: string) {
	sync.mutex_lock(&dialog_lock)
	defer sync.mutex_unlock(&dialog_lock)
	pending, found := dialog_table[id]
	if !found || pending.state != .Waiting {
		return
	}
	if path == "" {
		pending.state = .Closed
	} else {
		pending.state = .Chosen
		pending.path = strings.clone(path, runtime.heap_allocator())
	}
	dialog_table[id] = pending
}

// What became of a request. A request that is no longer waiting is taken out of the table, and its path is
// copied to `allocator`.
dialog_take :: proc(id: int, allocator := context.allocator) -> Dialog_Result {
	sync.mutex_lock(&dialog_lock)
	defer sync.mutex_unlock(&dialog_lock)
	pending, found := dialog_table[id]
	if !found {
		return {state = .Closed}
	}
	if pending.state == .Waiting {
		return {state = .Waiting}
	}
	result := Dialog_Result{state = pending.state}
	if pending.path != "" {
		result.path = strings.clone(pending.path, allocator)
		delete(pending.path, runtime.heap_allocator())
	}
	delete_key(&dialog_table, id)
	return result
}

// Throws every request away (the player's answers to a sketch that has ended).
dialogs_forget :: proc() {
	sync.mutex_lock(&dialog_lock)
	defer sync.mutex_unlock(&dialog_lock)
	for _, pending in dialog_table {
		delete(pending.path, runtime.heap_allocator())
	}
	delete(dialog_table)
	dialog_table = nil
}

// ---- clipboard and addresses ----

// The text on the system's clipboard, copied to `allocator`; empty when there is none.
clipboard_text :: proc(allocator := context.allocator) -> string {
	if !sdl.HasClipboardText() {
		return ""
	}
	raw := sdl.GetClipboardText()
	if raw == nil {
		return ""
	}
	defer sdl.free(rawptr(raw))
	return strings.clone(string(cstring(raw)), allocator)
}

// Puts text on the system's clipboard. False when the system refused.
set_clipboard_text :: proc(text: string) -> bool {
	return sdl.SetClipboardText(strings.clone_to_cstring(text, context.temp_allocator))
}

// Opens an address (`https://...`, `mailto:...`) or a file or folder (as a `file://` address) in the program
// the system keeps for it. False when the system could not.
open_address :: proc(address: string) -> bool {
	return sdl.OpenURL(strings.clone_to_cstring(address, context.temp_allocator))
}
