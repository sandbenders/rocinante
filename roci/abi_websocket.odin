// SPDX-License-Identifier: 0BSD
//
// Web sockets for C: roci_websocket_connect makes a connection under a label, roci_websocket_send and roci_websocket_close use
// it, and what happens on it comes to roci_on handlers for "websocket open", "websocket" (a message) and "websocket close" with the
// label as the argument, as events of kinds 24 to 26 whose `tcp` holds the message (the same struct a TCP connection's events use).
package roci

import "core:c"

abi_websocket_group :: proc(all: ^[dynamic]Abi_Entry) {
	append(all, abi_entry("roci_websocket_connect", typeid_of(type_of(abi_websocket_connect)), "int roci_websocket_connect(const char *label, const char *address)", "Makes a connection to a web socket address (ws:// or wss://) under a label of up to 64 letters, as a thread does: nothing waits, and \"websocket open\" says when it is made or \"websocket close\" why it could not be. The same label to the same address is left alone, to another address replaces it. Gives 1 when it is under way, and 0 when the label or the address is not valid or as many web sockets as a sketch may have are open."))
	append(all, abi_entry("roci_websocket_send", typeid_of(type_of(abi_websocket_send)), "int roci_websocket_send(const char *label, const void *data, int size, int binary)", "Sends a message on the web socket under a label: `size` bytes as text, or as binary bytes when `binary` is not 0. Gives 1 when it was given to the connection, and 0 when the label has none, there is nothing to send or the connection is over."))
	append(all, abi_entry("roci_websocket_close", typeid_of(type_of(abi_websocket_close)), "int roci_websocket_close(const char *label)", "Closes the web socket under a label: it sends the close message and \"websocket close\" comes when it is over. Gives 1 when the label has a connection, and 0 when it has none."))
}

@(private)
websocket_ok :: proc(r: Websocket_Result) -> c.int {
	return 1 if r == .Ok else 0
}

@(export, link_name = "roci_websocket_connect")
abi_websocket_connect :: proc "c" (label, address: cstring) -> c.int {
	context = abi_context()
	return websocket_ok(websocket_connect(text_from_abi(label), text_from_abi(address)))
}

@(export, link_name = "roci_websocket_send")
abi_websocket_send :: proc "c" (label: cstring, data: rawptr, size: c.int, binary: c.int) -> c.int {
	context = abi_context()
	if data == nil || size <= 0 {
		return 0
	}
	return websocket_ok(websocket_send(text_from_abi(label), ([^]u8)(data)[:size], binary != 0))
}

@(export, link_name = "roci_websocket_close")
abi_websocket_close :: proc "c" (label: cstring) -> c.int {
	context = abi_context()
	return websocket_ok(websocket_close(text_from_abi(label)))
}
