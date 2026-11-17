// SPDX-License-Identifier: 0BSD
//
// The system's dialogs, the clipboard and opening an address, for C and for the interpreter. A dialog does not
// wait: asking gives a number, and each frame the sketch asks for the answer until there is one.
package roci

import "core:c"
import "core:strings"

import "platform"

abi_dialogs_group :: proc(all: ^[dynamic]Abi_Entry) {
	append(all, abi_entry("roci_ask", typeid_of(type_of(abi_ask)), "int roci_ask(const char *kind, const char *types, const char *place)", "Shows the system's dialog for choosing a file (\"file\"), a folder (\"folder\") or a place to save (\"save\"), over the current window, and gives the number of the request, or 0 for a kind it does not know. `types` is the extensions to show, such as \"png jpg\" (\"\" for all), and `place` the folder or file name to start at. The dialog does not wait: ask for the answer with roci_answer."))
	append(all, abi_entry("roci_answer", typeid_of(type_of(abi_answer)), "const char *roci_answer(int request)", "What the player chose for a request of roci_ask: NULL while the dialog is still open, an empty text when it was closed without a choice, and the path chosen otherwise. A request is answered once; after that it is forgotten. The text stays valid until the next function that gives text back."))
	append(all, abi_entry("roci_clipboard", typeid_of(type_of(abi_clipboard)), "const char *roci_clipboard(void)", "The text on the system's clipboard, empty when there is none. The text stays valid until the next function that gives text back."))
	append(all, abi_entry("roci_set_clipboard", typeid_of(type_of(abi_set_clipboard)), "int roci_set_clipboard(const char *text)", "Puts text on the system's clipboard and gives 1 when it was taken."))
	append(all, abi_entry("roci_open", typeid_of(type_of(abi_open)), "int roci_open(const char *address)", "Opens an address (\"https://...\", \"mailto:...\") or a file or folder (\"file:///...\") in the program the system keeps for it, and gives 1 when the system could."))
}

// The dialog kind a word names.
dialog_kind_of :: proc(word: string) -> (kind: platform.Dialog_Kind, ok: bool) {
	switch word {
	case "file":   return .Open_File, true
	case "folder": return .Open_Folder, true
	case "save":   return .Save_File, true
	}
	return {}, false
}

// Shows a dialog over the current window and gives the number of the request. A headless sketch shows none.
ask_dialog :: proc(kind: platform.Dialog_Kind, types := "", place := "") -> int {
	// no window to show it over: the request waits for an answer put in with `platform.dialog_deliver`,
	// which is how the tests play the player
	if the.headless || graphics_refused {
		return platform.dialog_new()
	}
	handle: ^platform.Window
	if w := current_win(); w != nil {
		handle = w.handle
	}
	return platform.dialog_ask(handle, kind, types, place)
}

@(export, link_name = "roci_ask")
abi_ask :: proc "c" (kind, types, place: cstring) -> c.int {
	context = abi_context()
	k, ok := dialog_kind_of(text_from_abi(kind))
	if !ok {
		return 0
	}
	return c.int(ask_dialog(k, text_from_abi(types), text_from_abi(place)))
}

@(export, link_name = "roci_answer")
abi_answer :: proc "c" (request: c.int) -> cstring {
	context = abi_context()
	got := platform.dialog_take(int(request), context.temp_allocator)
	switch got.state {
	case .Waiting: return nil
	case .Closed:  return abi_give_text("")
	case .Chosen:  return abi_give_text(got.path)
	}
	return nil
}

@(export, link_name = "roci_clipboard")
abi_clipboard :: proc "c" () -> cstring {
	context = abi_context()
	return abi_give_text(clipboard(context.temp_allocator))
}

@(export, link_name = "roci_set_clipboard")
abi_set_clipboard :: proc "c" (text: cstring) -> c.int {
	context = abi_context()
	return 1 if set_clipboard(text_from_abi(text)) else 0
}

@(export, link_name = "roci_open")
abi_open :: proc "c" (address: cstring) -> c.int {
	context = abi_context()
	return 1 if open_address(text_from_abi(address)) else 0
}

// What a headless sketch keeps on its clipboard, since there is no system to hold it.
@(thread_local) @(private) held_clipboard: string

// The text on the clipboard.
clipboard :: proc(allocator := context.allocator) -> string {
	if the.headless || graphics_refused {
		return strings.clone(held_clipboard, allocator)
	}
	return platform.clipboard_text(allocator)
}

// Puts text on the clipboard.
set_clipboard :: proc(text: string) -> bool {
	if the.headless || graphics_refused {
		delete(held_clipboard)
		held_clipboard = strings.clone(text)
		return true
	}
	return platform.set_clipboard_text(text)
}

// Forgets what a headless sketch put on its clipboard.
clipboard_stop :: proc() {
	delete(held_clipboard)
	held_clipboard = ""
}

// Opens an address or a file with the system. A headless sketch opens nothing and says so.
open_address :: proc(address: string) -> bool {
	if the.headless || graphics_refused {
		return false
	}
	return platform.open_address(address)
}
