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
import "core:math"
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
		switch v in a {
		case f64:
			items[i] = v
		case bool:
			items[i] = v
		case string:
			items[i] = strings.clone(v, it.alloc)
		case oscp.Blob:
			bytes := make([]Value, len(v), context.temp_allocator)
			for b, j in v {
				bytes[j] = f64(b)
			}
			items[i] = new_list(it, ..bytes)
		}
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

// The arguments of an OSC message from the items of a sketch's list: numbers, text, true and false,
// and a list of numbers, which goes as a blob of bytes (each rounded and kept from 0 to 255). What
// else it holds is left out and said.
@(private)
osc_args_of :: proc(it: ^Interp, e: ^lang.IR, items: ^List, from := 0) -> []oscp.Arg {
	args := make([dynamic]oscp.Arg, context.temp_allocator)
	if items == nil {
		return args[:]
	}
	for item, i in items.items {
		if i < from {
			continue
		}
		#partial switch v in item {
		case f64:
			append(&args, v)
		case bool:
			append(&args, v)
		case string:
			append(&args, v)
		case ^List:
			bytes := make([]byte, len(v.items), context.temp_allocator)
			numbers := true
			for b, j in v.items {
				number, is_number := b.(f64)
				numbers &&= is_number
				bytes[j] = byte(clamp(math.round(number), 0, 255))
			}
			if numbers {
				append(&args, oscp.Blob(bytes))
			} else {
				fail(it, .Osc_Unsupported, e.span, "a list that is not numbers", "", "", "osc send \"/data\" [ [ 0 255 128 ] ]")
			}
		case:
			fail(it, .Osc_Unsupported, e.span, osc_value_words(item), "", "", "osc send \"/note\" [ 60 \"hi\" true ]")
		}
	}
	return args[:]
}

// `osc send "/addr" [ args ] to "host" port n`, or `osc send [ [ "/a" 1 ] [ "/b" 2 ] ] to ...` for
// several messages in one bundle.
@(private)
osc_send_verb :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call) {
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
	result: roci.Osc_Result
	bad_address := ""
	if call.shape == 1 {
		outgoing := make([dynamic]oscp.Out_Message, context.temp_allocator)
		messages := as_list(eval(it, call.args[0]))
		if messages != nil {
			for message in messages.items {
				parts, is_list := message.(^List)
				address := ""
				if is_list && len(parts.items) > 0 {
					address, _ = parts.items[0].(string)
				}
				if address == "" || address[0] != '/' {
					bad_address = address
					break
				}
				append(&outgoing, oscp.Out_Message{address = address, args = osc_args_of(it, e, parts, 1)})
			}
		}
		result = .Bad_Address if bad_address != "" || len(outgoing) != (len(messages.items) if messages != nil else 0) else roci.osc_send_bundle(outgoing[:], host, port)
	} else {
		address := as_text(eval(it, call.args[0]))
		bad_address = address
		result = roci.osc_send(address, osc_args_of(it, e, as_list(eval(it, call.args[1]))), host, port)
	}
	switch result {
	case .Sent:
	case .Bad_Address:
		fail(it, .Osc_Address_Bad, e.span, bad_address, "", "", fmt.tprintf("osc send \"/%s\" [ 1 ]", strings.trim_left(bad_address, "/")))
	case .Host_Unknown:
		fail(it, .Osc_Host_Unknown, e.span, host, "", "", "osc send \"/note\" [ 60 ] to \"localhost\" port 9000")
	case .Not_Sent:
		// the network would not take it (no connection, a full buffer): UDP promises nothing, and
		// the next one is tried as usual
	}
}
