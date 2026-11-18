// SPDX-License-Identifier: 0BSD
//
// UDP for C: roci_udp_send sends a datagram, roci_udp_listen starts listening on a port (so does roci_on with
// "udp" and the port as its argument), and what arrives is a roci_event of kind 20 whose `udp` holds it.
package roci

import "core:c"

abi_udp_group :: proc(all: ^[dynamic]Abi_Entry) {
	append(all, abi_entry("roci_udp_send", typeid_of(type_of(abi_udp_send)), "int roci_udp_send(const void *data, int size, const char *host, int port)", "Sends a datagram of `size` bytes to a computer (a name or a number; NULL for this one) and a port, 1 to 65535. Gives 1 when it was sent, and 0 when the port is not one, there is nothing or too much to send (a datagram holds 65507 bytes), the host is unknown or the system would not send it."))
	append(all, abi_entry("roci_udp_listen", typeid_of(type_of(abi_udp_listen)), "int roci_udp_listen(int port)", "Starts listening for datagrams on a port, 1 to 65535, so roci_on with \"udp\" and that port hears them. Gives 1 when it is listening (also when it already was), and 0 when the port is not one, another program has it or a sketch listens on too many already."))
}

@(export, link_name = "roci_udp_send")
abi_udp_send :: proc "c" (data: rawptr, size: c.int, host: cstring, port: c.int) -> c.int {
	context = abi_context()
	if data == nil || size <= 0 {
		return 0
	}
	bytes := ([^]u8)(data)[:size]
	target := text_from_abi(host)
	return 1 if udp_send(bytes, target if target != "" else "127.0.0.1", int(port)) == .Sent else 0
}

@(export, link_name = "roci_udp_listen")
abi_udp_listen :: proc "c" (port: c.int) -> c.int {
	context = abi_context()
	return 1 if udp_listen(f64(port)) == .None else 0
}
