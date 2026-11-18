// SPDX-License-Identifier: 0BSD
//
// UDP, the plainest way for programs on a network to talk: each datagram that arrives on a port the sketch
// listens on is a thing that happened in the frame (`Udp`), logged against the window that has the focus (or
// the first), so the language's `on udp 9000` runs once for each; `udp_send` sends one. Nothing is read into
// meaning: the bytes are the packet, and its text is the same bytes read as text. Listening starts when a sketch
// asks for a port (`udp_listen`, or an `on udp` block), never in a headless sketch or a test, which give it
// packets with `feed_udp` and read what was sent with `udp_sent_messages` instead. The sockets are the ones OSC
// listens and sends with (`platform/osc.odin`): a datagram is a datagram.
package roci

import "base:runtime"
import "core:strings"

import "platform"

// The largest datagram UDP carries.
UDP_MAX_BYTES :: platform.OSC_PACKET

// The most ports one sketch listens on, so a loop that asks for a new one each frame cannot open without end.
UDP_MAX_PORTS :: 16

// A datagram that arrived, as a handler reads it: the port it came to, its bytes, the same bytes as text,
// who sent it and the port it was sent from.
Udp_Packet :: struct {
	to:    int,
	data:  []byte,
	text:  string,
	from:  string,
	port:  int,
}

// What became of sending a datagram.
Udp_Result :: enum {
	Sent,
	Bad_Port, // a port is a whole number from 1 to 65535
	Empty, // there is nothing to send
	Too_Big, // more than a datagram holds
	Host_Unknown, // no such computer was found
	Not_Sent, // the system would not send it (no network, a full buffer)
}

// A datagram a headless sketch sent, for tests to read.
Udp_Sent :: struct {
	data: []byte,
	host: string,
	port: int,
}

@(private)
Udp_Fed :: struct {
	to:     int,
	packet: platform.Osc_Packet,
}

@(thread_local) @(private) udp_in: map[int]^platform.Osc_In // the sockets listened on, by port
@(thread_local) @(private) udp_ports: [dynamic]int // the ports listened on, or asked for in a headless sketch
@(thread_local) @(private) udp_out: ^platform.Osc_Out
@(thread_local) @(private) udp_fed: [dynamic]Udp_Fed // what `feed_udp` gave, for the next frame
@(thread_local) @(private) udp_sent: [dynamic]Udp_Sent // what a headless sketch sent
@(thread_local) @(private) udp_pretend_busy: bool // for tests: every port is taken
// The bytes and text of the frame's datagrams: they are read after the frame's own memory is let go of (a test
// reads the log after `step`), so they are kept here until the next frame's datagrams replace them.
@(thread_local) @(private) udp_kept: [dynamic][]byte
@(thread_local) @(private) udp_kept_text: [dynamic]string

// Listens on a port, in a sketch with a window: a headless sketch and a test listen to nothing and just remember
// the port. A port another program has is said by the answer, and nothing listens then; asking again for a port
// already listened on changes nothing.
udp_listen :: proc(port: f64) -> platform.Osc_Problem {
	if port < 1 || port >= 65536 || port != f64(int(port)) {
		return .Port_Refused
	}
	wanted := int(port)
	if udp_is_listening(wanted) {
		return .None
	}
	if len(udp_ports) >= UDP_MAX_PORTS {
		return .Port_Refused
	}
	allocator := osc_allocator()
	if the.headless || graphics_refused {
		if udp_pretend_busy {
			return .Port_Busy
		}
		if udp_ports == nil {
			udp_ports = make([dynamic]int, allocator)
		}
		append(&udp_ports, wanted)
		return .None
	}
	listener := platform.open_osc(wanted, allocator)
	if listener.error != .None {
		problem := listener.error
		platform.close_osc(listener)
		return problem
	}
	if udp_in == nil {
		udp_in = make(map[int]^platform.Osc_In, allocator)
	}
	if udp_ports == nil {
		udp_ports = make([dynamic]int, allocator)
	}
	udp_in[wanted] = listener
	append(&udp_ports, wanted)
	return .None
}

// Whether the sketch listens on a port now (in a headless sketch, has asked to).
udp_is_listening :: proc(port: int) -> bool {
	for p in udp_ports {
		if p == port {
			return true
		}
	}
	return false
}

// A test knob: while it is on, a headless sketch finds every port taken, as it would when another program has
// the one it asks for.
set_udp_port_busy :: proc(busy: bool) {
	udp_pretend_busy = busy
}

// Gives the sketch a datagram as the network would, for the next frame: for tests. `to` is the port it comes to.
feed_udp :: proc(to: int, data: []u8, from := "127.0.0.1", from_port := 50000) {
	allocator := osc_allocator()
	if udp_fed == nil {
		udp_fed = make([dynamic]Udp_Fed, allocator)
	}
	copied := make([]u8, len(data), allocator)
	copy(copied, data)
	append(&udp_fed, Udp_Fed{to = to, packet = platform.Osc_Packet{data = copied, from = strings.clone(from, allocator), port = from_port}})
}

// Sends a datagram to a host (a name or a number, "127.0.0.1" for this computer) and a port. A headless sketch
// sends nothing and keeps the datagram for `udp_sent_messages`.
udp_send :: proc(data: []u8, host: string, port: int) -> Udp_Result {
	if port < 1 || port > 65535 {
		return .Bad_Port
	}
	if len(data) == 0 {
		return .Empty
	}
	if len(data) > UDP_MAX_BYTES {
		return .Too_Big
	}
	// a name ending in .invalid is one that is promised never to exist (RFC 2606), so it is unknown on every
	// network and in a headless sketch too
	if strings.has_suffix(host, ".invalid") {
		return .Host_Unknown
	}
	if the.headless || graphics_refused {
		allocator := osc_allocator()
		if udp_sent == nil {
			udp_sent = make([dynamic]Udp_Sent, allocator)
		}
		copied := make([]u8, len(data), allocator)
		copy(copied, data)
		append(&udp_sent, Udp_Sent{data = copied, host = strings.clone(host, allocator), port = port})
		return .Sent
	}
	if udp_out == nil {
		udp_out = platform.open_osc_out(osc_allocator())
	}
	switch platform.osc_send(udp_out, host, port, data) {
	case .Sent:
		return .Sent
	case .Host_Unknown:
		return .Host_Unknown
	case .Not_Sent:
		return .Not_Sent
	}
	return .Not_Sent
}

// What a headless sketch has sent since `udp_clear_sent`, oldest first.
udp_sent_messages :: proc() -> []Udp_Sent {
	return udp_sent[:]
}

udp_clear_sent :: proc() {
	allocator := osc_allocator()
	for m in udp_sent {
		delete(m.data, allocator)
		delete(m.host, allocator)
	}
	clear(&udp_sent)
}

@(private)
udp_forget_frame :: proc() {
	allocator := osc_allocator()
	for b in udp_kept {
		delete(b, allocator)
	}
	clear(&udp_kept)
	for s in udp_kept_text {
		delete(s, allocator)
	}
	clear(&udp_kept_text)
}

@(private)
udp_keep_text :: proc(s: string) -> string {
	if s == "" {
		return ""
	}
	if udp_kept_text == nil {
		udp_kept_text = make([dynamic]string, osc_allocator())
	}
	copied := strings.clone(s, osc_allocator())
	append(&udp_kept_text, copied)
	return copied
}

// Turns the datagrams that came from the network and from `feed_udp` since the last frame into the frame's
// happenings. Called by `step`.
@(private)
udp_step :: proc() {
	udp_forget_frame()
	if len(udp_in) == 0 && len(udp_fed) == 0 {
		return
	}
	allocator := osc_allocator()
	target := midi_target()
	arrive :: proc(to: int, p: platform.Osc_Packet, target: ^Win, allocator: runtime.Allocator) {
		if target == nil {
			return
		}
		if udp_kept == nil {
			udp_kept = make([dynamic][]byte, allocator)
		}
		bytes := make([]byte, len(p.data), allocator)
		copy(bytes, p.data)
		append(&udp_kept, bytes)
		packet := Udp_Packet{to = to, data = bytes, text = udp_keep_text(string(bytes)), from = udp_keep_text(p.from), port = p.port}
		append(&the.log, Happened{kind = .Udp, window = target.id, udp = packet})
	}
	for port, listener in udp_in {
		taken := make([dynamic]platform.Osc_Packet, context.temp_allocator)
		platform.osc_take(listener, &taken, context.temp_allocator)
		for p in taken {
			arrive(port, p, target, allocator)
		}
	}
	for f in udp_fed {
		arrive(f.to, f.packet, target, allocator)
		delete(f.packet.data, allocator)
		delete(f.packet.from, allocator)
	}
	clear(&udp_fed)
}

// Stops listening and sending and lets go of everything that was kept. Called by `shutdown`.
@(private)
udp_stop :: proc() {
	allocator := osc_allocator()
	for _, listener in udp_in {
		platform.close_osc(listener)
	}
	delete(udp_in)
	udp_in = nil
	delete(udp_ports)
	udp_ports = nil
	platform.close_osc_out(udp_out)
	udp_out = nil
	for f in udp_fed {
		delete(f.packet.data, allocator)
		delete(f.packet.from, allocator)
	}
	delete(udp_fed)
	udp_fed = nil
	udp_forget_frame()
	delete(udp_kept)
	delete(udp_kept_text)
	udp_kept, udp_kept_text = nil, nil
	udp_clear_sent()
	delete(udp_sent)
	udp_sent = nil
}
