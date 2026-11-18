// SPDX-License-Identifier: 0BSD
//
// UDP in the language: `on udp` blocks and the record `packet` they read, and `udp send`. The sockets
// are `roci`'s.
package interp

import "core:fmt"
import "core:math"
import "core:strings"

import "../"
import "../lang"
import "../platform"

// `packet`: the datagram an `on udp` block runs for, as a record of the checker's type.
packet_record :: proc(it: ^Interp, type: lang.Type_Id, d: roci.Udp_Packet) -> Value {
	shape := lang.shape_of(it.types, type)
	if shape < 0 {
		return nil
	}
	r := new_record(it, shape)
	set :: proc(it: ^Interp, r: ^Record, shape: int, name: string, value: Value) {
		if at := field_index(it, shape, name); at >= 0 {
			r.fields[at] = value
		}
	}
	set(it, r, shape, "text", strings.clone(d.text, it.alloc))
	set(it, r, shape, "from", strings.clone(d.from, it.alloc))
	set(it, r, shape, "port", f64(d.port))
	items := make([]Value, len(d.data), context.temp_allocator)
	for b, i in d.data {
		items[i] = f64(b)
	}
	set(it, r, shape, "bytes", new_list(it, ..items))
	return r
}

// Says why nothing listens, at the place that asked.
@(private)
say_udp_problem :: proc(it: ^Interp, problem: platform.Osc_Problem, port: f64, span: lang.Span) {
	switch problem {
	case .None:
	case .Port_Busy:
		fail(it, .Udp_Port_Busy, span, fmt.tprint(int(port)), "", "", fmt.tprintf("on udp %d [ print packet.text ]", int(port) + 1))
	case .Port_Refused:
		if port >= 1 && port < 65536 && port == math.floor(port) {
			fail(it, .Udp_Port_Busy, span, fmt.tprint(int(port)), "", "", fmt.tprintf("on udp %d [ print packet.text ]", int(port) + 1))
		} else {
			fail(it, .Udp_Data_Bad, span, "a port from 1 to 65535", "A port is a whole number from 1 to 65535.", "", "on udp 9000 [ print packet.text ]")
		}
	}
}

// Starts listening for an `on udp` block, once its port is known.
@(private)
udp_register :: proc(it: ^Interp, k: ^lang.IR_On) {
	if len(k.args) == 0 {
		return
	}
	port := as_number(eval(it, k.args[0]))
	say_udp_problem(it, roci.udp_listen(port), port, k.body.span)
}

// `udp send "text" to "host" port n` and `udp send [ bytes ] to "host" port n`.
@(private)
udp_send_verb :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call) {
	host := "127.0.0.1"
	if v, ok := option_value(it, call.options, "to"); ok {
		host = as_text(v)
	}
	port := 0
	if v, ok := option_value(it, call.options, "port"); ok {
		if number := as_number(v); number >= 1 && number < 65536 && number == math.floor(number) {
			port = int(number)
		}
	}
	data: []byte
	if call.shape == 1 {
		items := as_list(eval(it, call.args[0]))
		bytes := make([dynamic]byte, context.temp_allocator)
		if items != nil {
			for item in items.items {
				number, is_number := item.(f64)
				if !is_number {
					fail(it, .Udp_Data_Bad, e.span, "a list of numbers", "The bytes of a datagram are numbers from 0 to 255, and this list holds something else.", "", "udp send [ 1 2 255 ] port 9000")
					return
				}
				append(&bytes, byte(clamp(math.round(number), 0, 255)))
			}
		}
		data = bytes[:]
	} else {
		data = transmute([]byte)as_text(eval(it, call.args[0]))
	}
	switch roci.udp_send(data, host, port) {
	case .Sent:
	case .Bad_Port:
		fail(it, .Udp_Data_Bad, e.span, "a port from 1 to 65535", "A port is a whole number from 1 to 65535, so a datagram can find the program listening there.", "", "udp send \"hello\" port 9000")
	case .Empty:
		fail(it, .Udp_Data_Bad, e.span, "something to send", "There is nothing in this datagram.", "", "udp send \"hello\" port 9000")
	case .Too_Big:
		fail(it, .Udp_Data_Bad, e.span, "no more than 65507 bytes", "A datagram holds at most 65507 bytes. Send it in several.", "", "udp send \"hello\" port 9000")
	case .Host_Unknown:
		fail(it, .Udp_Host_Unknown, e.span, host, "", "", "udp send \"hello\" to \"localhost\" port 9000")
	case .Not_Sent:
		// the network would not take it (no connection, a full buffer): UDP promises nothing, and
		// the next one is tried as usual
	}
}
