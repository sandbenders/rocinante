// SPDX-License-Identifier: 0BSD
//
// OSC in the language: `on osc` blocks and the record `osc` they read, `osc send`, `osc listen` and
// `osc value`. The network, the packets and the address matching are `roci`'s and `roci/osc`'s.
package interp

import "core:fmt"
import "core:strings"

import "../"
import "../lang"
import oscp "../osc"
import "../maths"
import "../platform"

// `osc`: the message an `on osc` block runs for, as a record of the checker's type.
osc_record :: proc(it: ^Interp, type: lang.Type_Id, m: roci.Osc_Message) -> Value {
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
	set(it, r, shape, "address", strings.clone(m.address, it.alloc))
	set(it, r, shape, "from", strings.clone(m.from, it.alloc))
	set(it, r, shape, "text", strings.clone(m.text, it.alloc))
	set(it, r, shape, "value", m.value)
	items := make([]Value, len(m.args), context.temp_allocator)
	for a, i in m.args {
		items[i] = a
	}
	set(it, r, shape, "args", new_list(it, ..items))
	return r
}

// Says why nothing listens, at the place that asked.
@(private)
say_osc_problem :: proc(it: ^Interp, problem: platform.Osc_Problem, port: int, span: lang.Span) {
	switch problem {
	case .None:
	case .Port_Busy, .Port_Refused:
		fail(it, .Osc_Port_Busy, span, fmt.tprint(port), "", "", fmt.tprintf("osc listen %d", port + 1))
	}
}

// The words for what an OSC message carried that was left out, from the letters of its types.
@(private)
osc_dropped_words :: proc(letters: string) -> string {
	words := make([dynamic]string, context.temp_allocator)
	seen: [128]bool
	for ch in transmute([]byte)letters {
		if ch >= 128 || seen[ch] {
			continue
		}
		seen[ch] = true
		switch ch {
		case 'b':
			append(&words, "a blob of bytes")
		case 't':
			append(&words, "a timetag")
		case 'r':
			append(&words, "a color")
		case 'm':
			append(&words, "a MIDI message")
		case 'N':
			append(&words, "nil")
		case 'I':
			append(&words, "infinity")
		case:
			append(&words, "something unknown")
		}
	}
	return strings.join(words[:], ", ", context.temp_allocator)
}

// `osc listen n`.
@(private)
osc_listen_verb :: proc(it: ^Interp, port: f64, span: lang.Span) {
	problem := roci.osc_listen(port)
	shown := int(port) if port >= 1 && port < 65536 else roci.DEFAULT_OSC_PORT
	say_osc_problem(it, problem, shown, span)
}

// What a sketch's list item is called when OSC cannot carry it.
@(private)
osc_value_words :: proc(v: Value) -> string {
	#partial switch _ in v {
	case Vec:
		return "a point"
	case maths.Colour:
		return "a color"
	case ^List:
		return "a list"
	case ^Record:
		return "a record"
	case ^Table:
		return "a table"
	}
	return "a value"
}

// `osc send "/addr" [ args ] to "host" port n`.
@(private)
osc_send_verb :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call) {
	address := as_text(eval(it, call.args[0]))
	items := as_list(eval(it, call.args[1]))
	args := make([dynamic]oscp.Arg, context.temp_allocator)
	if items != nil {
		for item in items.items {
			#partial switch v in item {
			case f64:
				append(&args, v)
			case bool:
				append(&args, v)
			case string:
				append(&args, v)
			case:
				fail(it, .Osc_Unsupported, e.span, osc_value_words(item), "", "", "osc send \"/note\" [ 60 \"hi\" true ]")
			}
		}
	}
	host := "127.0.0.1"
	if v, ok := option_value(it, call.options, "to"); ok {
		host = as_text(v)
	}
	port := roci.DEFAULT_OSC_PORT
	if v, ok := option_value(it, call.options, "port"); ok {
		if number := as_number(v); number >= 1 && number < 65536 {
			port = int(number)
		}
	}
	switch roci.osc_send(address, args[:], host, port) {
	case .Sent:
	case .Bad_Address:
		fail(it, .Osc_Address_Bad, e.span, address, "", "", fmt.tprintf("osc send \"/%s\" [ 1 ]", strings.trim_left(address, "/")))
	case .Host_Unknown:
		fail(it, .Osc_Host_Unknown, e.span, host, "", "", "osc send \"/note\" [ 60 ] to \"localhost\" port 9000")
	case .Not_Sent:
		// the network would not take it (no connection, a full buffer): UDP promises nothing, and
		// the next one is tried as usual
	}
}
