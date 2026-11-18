// SPDX-License-Identifier: 0BSD
//
// TCP for C: roci_tcp_connect and roci_tcp_listen make a connection under a label, roci_tcp_send and
// roci_tcp_close use it, and what happens on it comes to roci_on handlers for "tcp open", "tcp" (a line of text) and
// "tcp close" with the label as the argument, as events of kinds 21 to 23 whose `tcp` holds the line.
package roci

import "core:c"

abi_tcp_group :: proc(all: ^[dynamic]Abi_Entry) {
	append(all, abi_entry("roci_tcp_connect", typeid_of(type_of(abi_tcp_connect)), "int roci_tcp_connect(const char *label, const char *host, int port)", "Makes a connection to a computer (a name or a number) and a port, 1 to 65535, under a label of up to 64 letters, as a thread does: nothing waits, and \"tcp open\" says when it is made or \"tcp close\" that it could not be. The same label to the same place is left alone, to another place replaces it. Gives 1 when it is under way, and 0 when the label or the port is not one, the host is unknown or as many connections as a sketch may have are open."))
	append(all, abi_entry("roci_tcp_listen", typeid_of(type_of(abi_tcp_listen)), "int roci_tcp_listen(const char *label, int port)", "Waits for connections on a port, 1 to 65535, under a label: \"tcp open\" says each time a client comes in, numbering clients from 1. Gives 1 when it is listening, and 0 when the label or the port is not one, another program has the port or as many connections as a sketch may have are open."))
	append(all, abi_entry("roci_tcp_send", typeid_of(type_of(abi_tcp_send)), "int roci_tcp_send(const char *label, const void *data, int size, int client)", "Sends `size` bytes on the connection under a label: to the other end of one made by roci_tcp_connect, or for a listener to one client (a number from 1) or to all of them (0). A line of text ends with a newline, which is part of what is sent. Gives 1 when it was given to a connection, and 0 when the label has none, there is nothing to send or nobody is connected."))
	append(all, abi_entry("roci_tcp_close", typeid_of(type_of(abi_tcp_close)), "int roci_tcp_close(const char *label, int client)", "Ends the connection under a label, or a listener and all its clients, or for a listener one client (a number from 1; 0 for all). A connection says \"tcp close\" when it is over. Gives 1 when the label has a connection, and 0 when it has none."))
}

@(private)
tcp_ok :: proc(r: Tcp_Result) -> c.int {
	return 1 if r == .Ok else 0
}

@(export, link_name = "roci_tcp_connect")
abi_tcp_connect :: proc "c" (label, host: cstring, port: c.int) -> c.int {
	context = abi_context()
	return tcp_ok(tcp_connect(text_from_abi(label), text_from_abi(host), f64(port)))
}

@(export, link_name = "roci_tcp_listen")
abi_tcp_listen :: proc "c" (label: cstring, port: c.int) -> c.int {
	context = abi_context()
	return tcp_ok(tcp_listen(text_from_abi(label), f64(port)))
}

@(export, link_name = "roci_tcp_send")
abi_tcp_send :: proc "c" (label: cstring, data: rawptr, size: c.int, client: c.int) -> c.int {
	context = abi_context()
	if data == nil || size <= 0 {
		return 0
	}
	return tcp_ok(tcp_send(text_from_abi(label), ([^]u8)(data)[:size], int(client)))
}

@(export, link_name = "roci_tcp_close")
abi_tcp_close :: proc "c" (label: cstring, client: c.int) -> c.int {
	context = abi_context()
	return tcp_ok(tcp_close(text_from_abi(label), int(client)))
}
