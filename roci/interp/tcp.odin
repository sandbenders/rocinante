// SPDX-License-Identifier: 0BSD
//
// TCP in the language: `tcp connect`, `tcp listen`, `tcp send` and `tcp close`, the `on tcp` blocks and the record
// `received` they read. The connections and their threads are `roci`'s.
package interp

import "core:fmt"
import "core:math"
import "core:strings"

import "../"
import "../lang"

// `received`: what an `on tcp` block runs for, as a record of the checker's type.
received_record :: proc(it: ^Interp, type: lang.Type_Id, m: roci.Tcp_Message) -> Value {
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
	set(it, r, shape, "text", strings.clone(m.text, it.alloc))
	set(it, r, shape, "from", strings.clone(m.from, it.alloc))
	set(it, r, shape, "client", f64(m.client))
	return r
}

// Says what went wrong with a request about a connection, at the place that asked. Nothing is done then, and the
// sketch goes on.
@(private)
say_tcp_result :: proc(it: ^Interp, result: roci.Tcp_Result, label, host: string, port: f64, span: lang.Span) {
	switch result {
	case .Ok:
	case .Bad_Name:
		fail(it, .Tcp_Refused, span, "a name", "A connection is named by its label, up to 64 letters, so the sketch can tell it from the others.", "", "tcp connect \"chat\" to \"localhost\" port 9400")
	case .Bad_Port:
		fail(it, .Tcp_Refused, span, "a port from 1 to 65535", "A port is a whole number from 1 to 65535.", "", "tcp connect \"chat\" to \"localhost\" port 9400")
	case .Host_Unknown:
		fail(it, .Tcp_Host_Unknown, span, host, "", "", "tcp connect \"chat\" to \"localhost\" port 9400")
	case .Port_Busy, .Port_Refused:
		fail(it, .Tcp_Port_Busy, span, fmt.tprint(int(port)), "", "", fmt.tprintf("tcp listen \"%s\" port %d", label, int(port) + 1))
	case .Too_Many:
		fail(it, .Tcp_Refused, span, "room", "As many connections and listeners as a sketch may have, eight, are open. Close one first with `tcp close`.", "", "tcp close \"chat\"")
	case .Unknown_Label:
		fail(it, .Tcp_Unknown_Label, span, label, "", "", fmt.tprintf("tcp connect \"%s\" to \"localhost\" port 9400", label))
	case .Empty:
		fail(it, .Tcp_Refused, span, "something to send", "There is nothing in this to send.", "", "tcp send \"chat\" \"hello\"")
	case .Not_Sent:
		fail(it, .Tcp_Refused, span, "someone connected", "Nobody is connected under this label yet, or the connection is over. `on tcp open` says when one is made.", "", "on tcp open \"chat\" [ tcp send \"chat\" \"hello\" ]")
	}
}

// The number an option gives, or 0.
@(private)
tcp_client_option :: proc(it: ^Interp, call: lang.IR_Call) -> int {
	if v, ok := option_value(it, call.options, "to"); ok {
		if n := as_number(v); n >= 0 && n == math.floor(n) {
			return int(n)
		}
	}
	return 0
}

@(private)
tcp_verb :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call, code: Verb_Code) {
	label := as_text(eval(it, call.args[0]))
	#partial switch code {
	case .Tcp_Connect:
		host, port := "", 0.0
		if v, ok := option_value(it, call.options, "to"); ok {
			host = as_text(v)
		}
		if v, ok := option_value(it, call.options, "port"); ok {
			port = as_number(v)
		}
		say_tcp_result(it, roci.tcp_connect(label, host, port), label, host, port, e.span)
	case .Tcp_Listen:
		port := 0.0
		if v, ok := option_value(it, call.options, "port"); ok {
			port = as_number(v)
		}
		say_tcp_result(it, roci.tcp_listen(label, port), label, "", port, e.span)
	case .Tcp_Send:
		client := tcp_client_option(it, call)
		if call.shape == 1 {
			items := as_list(eval(it, call.args[1]))
			bytes := make([dynamic]byte, context.temp_allocator)
			if items != nil {
				for item in items.items {
					number, is_number := item.(f64)
					if !is_number {
						fail(it, .Tcp_Refused, e.span, "numbers to send", "The bytes of a message are numbers from 0 to 255, and this list holds something else.", "", "tcp send \"chat\" [ 1 2 255 ]")
						return
					}
					append(&bytes, byte(clamp(math.round(number), 0, 255)))
				}
			}
			say_tcp_result(it, roci.tcp_send(label, bytes[:], client), label, "", 0, e.span)
		} else {
			line := strings.concatenate({as_text(eval(it, call.args[1])), "\n"}, context.temp_allocator)
			say_tcp_result(it, roci.tcp_send(label, transmute([]byte)line, client), label, "", 0, e.span)
		}
	case .Tcp_Close:
		say_tcp_result(it, roci.tcp_close(label, tcp_client_option(it, call)), label, "", 0, e.span)
	}
}
