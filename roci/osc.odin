// SPDX-License-Identifier: 0BSD
//
// OSC, the messages other programs and phones send over a network: each one that arrives is a
// thing that happened in the frame (`Osc`), logged against the window that has the focus (or the
// first), so the language's `on osc` runs once for each; `osc_value` gives the latest first
// number sent to an address at any time, and `osc_send` sends a message. Listening starts the
// first time a sketch asks for it (`start_osc`, or `osc_listen` with a port), never in a
// headless sketch or a test, which give it packets with `feed_osc` and read what was sent with
// `osc_sent_messages` instead. What the bytes of a packet are is `roci/osc`.
package roci

import "base:runtime"
import "core:strings"

import oscp "osc"
import "platform"

// The port a sketch listens on when it asks for none.
DEFAULT_OSC_PORT :: 9000

// The most addresses `osc_value` remembers, so a program sending a new address each time cannot
// make a sketch grow without end.
MAX_OSC_ADDRESSES :: 1024

// A message that arrived, as a handler reads it: the address, who sent it, the first number (true
// counts as 1, false as 0; 0 when there is none), the first text ("" when there is none), every
// number in order, and the types of the arguments that were left out (blobs and timetags).
Osc_Message :: struct {
	address: string,
	from:    string,
	value:   f64,
	text:    string,
	args:    []f64,
	dropped: string,
}

// What became of sending a message.
Osc_Result :: enum {
	Sent,
	Bad_Address, // an address begins with a slash: `/fader/1`
	Host_Unknown, // no such computer was found
	Not_Sent, // the system would not send it
}

// A message a headless sketch sent, for tests to read.
Osc_Sent :: struct {
	address: string,
	args:    []oscp.Arg,
	host:    string,
	port:    int,
}

@(thread_local) @(private) osc_in: ^platform.Osc_In
@(thread_local) @(private) osc_out: ^platform.Osc_Out
@(thread_local) @(private) osc_tried: bool
@(thread_local) @(private) osc_port: int // the port listened on, or asked for in a headless sketch
@(thread_local) @(private) osc_fed: [dynamic]platform.Osc_Packet // what `feed_osc` gave, for the next frame
@(thread_local) @(private) osc_values: map[string]f64 // the latest first number of each address
@(thread_local) @(private) osc_sent: [dynamic]Osc_Sent // what a headless sketch sent
@(thread_local) @(private) osc_pretend_busy: bool // for tests: every port is taken
// The text and numbers of the frame's messages: they are read after the frame's own memory is let go of
// (a test reads the log after `step`), so they are kept here until the next frame's messages replace them.
@(thread_local) @(private) osc_kept_text: [dynamic]string
@(thread_local) @(private) osc_kept_numbers: [dynamic][]f64

@(private)
osc_allocator :: proc() -> runtime.Allocator {
	return the.allocator if the.allocator.procedure != nil else context.allocator
}

// Listens on a port (the start port, 9000, for 0 or less), in a sketch with a window: a headless
// sketch and a test listen to nothing and just remember the port. A port another program has is
// said by the answer, and nothing listens then; asking again for the port in use changes
// nothing.
osc_listen :: proc(port: f64) -> platform.Osc_Problem {
	osc_tried = true
	wanted := int(port) if port >= 1 && port < 65536 else DEFAULT_OSC_PORT
	if the.headless || graphics_refused {
		if osc_pretend_busy {
			osc_port = 0
			return .Port_Busy
		}
		osc_port = wanted
		return .None
	}
	if osc_in != nil && osc_port == wanted {
		return .None
	}
	platform.close_osc(osc_in)
	osc_in = nil
	listener := platform.open_osc(wanted, osc_allocator())
	if listener.error != .None {
		problem := listener.error
		platform.close_osc(listener)
		osc_port = 0
		return problem
	}
	osc_in, osc_port = listener, wanted
	return .None
}

// A test knob: while it is on, a headless sketch finds every port taken, as it would when another
// program has the one it asks for.
set_osc_port_busy :: proc(busy: bool) {
	osc_pretend_busy = busy
}

// Starts listening on the start port the first time it is asked, and says why it could not.
start_osc :: proc() -> platform.Osc_Problem {
	if osc_tried {
		return .None
	}
	return osc_listen(0)
}

// The port the sketch listens on now, 0 when it listens to nothing.
osc_listening :: proc() -> int {
	return osc_port
}

// Gives the sketch a packet as the network would, for the next frame: for tests.
feed_osc :: proc(packet: []u8, from := "127.0.0.1") {
	allocator := osc_allocator()
	if osc_fed == nil {
		osc_fed = make([dynamic]platform.Osc_Packet, allocator)
	}
	copied := make([]u8, len(packet), allocator)
	copy(copied, packet)
	append(&osc_fed, platform.Osc_Packet{data = copied, from = strings.clone(from, allocator)})
}

// The latest first number sent to an address, 0 until one comes. The first call starts listening.
osc_value :: proc(address: string) -> f64 {
	start_osc()
	return osc_values[address]
}

// Sends a message: a list of numbers, text and true and false to an address, to a host (a name or
// a number, "127.0.0.1" for this computer) and a port. A headless sketch sends nothing and keeps
// the message for `osc_sent_messages`.
osc_send :: proc(address: string, args: []oscp.Arg, host := "127.0.0.1", port := DEFAULT_OSC_PORT) -> Osc_Result {
	if len(address) == 0 || address[0] != '/' {
		return .Bad_Address
	}
	// a name ending in .invalid is one that is promised never to exist (RFC 2606), so it is unknown
	// on every network and in a headless sketch too
	if strings.has_suffix(host, ".invalid") {
		return .Host_Unknown
	}
	if the.headless || graphics_refused {
		allocator := osc_allocator()
		if osc_sent == nil {
			osc_sent = make([dynamic]Osc_Sent, allocator)
		}
		copied := make([]oscp.Arg, len(args), allocator)
		for a, i in args {
			if s, is_text := a.(string); is_text {
				copied[i] = strings.clone(s, allocator)
			} else {
				copied[i] = a
			}
		}
		append(&osc_sent, Osc_Sent{address = strings.clone(address, allocator), args = copied, host = strings.clone(host, allocator), port = port})
		return .Sent
	}
	packet := oscp.encode(address, args, context.temp_allocator)
	if osc_out == nil {
		osc_out = platform.open_osc_out(osc_allocator())
	}
	switch platform.osc_send(osc_out, host, port, packet) {
	case .Sent:
		return .Sent
	case .Host_Unknown:
		return .Host_Unknown
	case .Not_Sent:
		return .Not_Sent
	}
	return .Not_Sent
}

// What a headless sketch has sent since `osc_clear_sent`, oldest first.
osc_sent_messages :: proc() -> []Osc_Sent {
	return osc_sent[:]
}

osc_clear_sent :: proc() {
	allocator := osc_allocator()
	for m in osc_sent {
		free_sent(m, allocator)
	}
	clear(&osc_sent)
}

@(private)
free_sent :: proc(m: Osc_Sent, allocator: runtime.Allocator) {
	delete(m.address, allocator)
	for a in m.args {
		if s, is_text := a.(string); is_text {
			delete(s, allocator)
		}
	}
	delete(m.args, allocator)
	delete(m.host, allocator)
}

// Turns the packets that came from the network and from `feed_osc` since the last frame into the
// frame's happenings and the addresses' latest values. Called by `step`.
@(private)
osc_forget_frame :: proc() {
	allocator := osc_allocator()
	for s in osc_kept_text {
		delete(s, allocator)
	}
	clear(&osc_kept_text)
	for n in osc_kept_numbers {
		delete(n, allocator)
	}
	clear(&osc_kept_numbers)
}

@(private)
osc_keep :: proc(s: string) -> string {
	if s == "" {
		return ""
	}
	if osc_kept_text == nil {
		osc_kept_text = make([dynamic]string, osc_allocator())
	}
	copied := strings.clone(s, osc_allocator())
	append(&osc_kept_text, copied)
	return copied
}

@(private)
osc_step :: proc() {
	osc_forget_frame()
	if osc_in == nil && len(osc_fed) == 0 {
		return
	}
	packets := make([dynamic]platform.Osc_Packet, context.temp_allocator)
	if osc_in != nil {
		platform.osc_take(osc_in, &packets, context.temp_allocator)
	}
	append(&packets, ..osc_fed[:])
	allocator := osc_allocator()
	target := midi_target()
	for p in packets {
		messages, _ := oscp.parse(p.data, context.temp_allocator)
		for m in messages {
			message := Osc_Message{address = osc_keep(m.address), from = osc_keep(p.from), dropped = osc_keep(m.dropped)}
			args := make([dynamic]f64, context.temp_allocator)
			have_value, have_text := false, false
			for a in m.args {
				switch v in a {
				case f64:
					append(&args, v)
				case bool:
					append(&args, f64(1) if v else f64(0))
				case string:
					if !have_text {
						message.text, have_text = osc_keep(v), true
					}
				}
			}
			if len(args) > 0 {
				kept := make([]f64, len(args), allocator)
				copy(kept, args[:])
				if osc_kept_numbers == nil {
					osc_kept_numbers = make([dynamic][]f64, allocator)
				}
				append(&osc_kept_numbers, kept)
				message.args = kept
			}
			if len(args) > 0 {
				message.value, have_value = args[0], true
			}
			if have_value {
				if _, known := osc_values[m.address]; known || len(osc_values) < MAX_OSC_ADDRESSES {
					if osc_values == nil {
						osc_values = make(map[string]f64, allocator)
					}
					if known {
						osc_values[m.address] = message.value
					} else {
						osc_values[strings.clone(m.address, allocator)] = message.value
					}
				}
			}
			if target != nil {
				append(&the.log, Happened{kind = .Osc, window = target.id, osc = message})
			}
		}
	}
	for p in osc_fed {
		delete(p.data, allocator)
		delete(p.from, allocator)
	}
	clear(&osc_fed)
}

// Stops listening and sending and lets go of everything that was kept. Called by `shutdown`.
@(private)
osc_stop :: proc() {
	allocator := osc_allocator()
	platform.close_osc(osc_in)
	platform.close_osc_out(osc_out)
	osc_in, osc_out = nil, nil
	osc_tried, osc_port = false, 0
	for p in osc_fed {
		delete(p.data, allocator)
		delete(p.from, allocator)
	}
	delete(osc_fed)
	osc_fed = nil
	for address in osc_values {
		delete(address, osc_values.allocator)
	}
	delete(osc_values)
	osc_values = nil
	osc_forget_frame()
	delete(osc_kept_text)
	delete(osc_kept_numbers)
	osc_kept_text, osc_kept_numbers = nil, nil
	osc_clear_sent()
	delete(osc_sent)
	osc_sent = nil
}
