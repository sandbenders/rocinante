// SPDX-License-Identifier: 0BSD
//
// Web sockets in the language: `websocket connect`, `websocket send` and `websocket close`, and the `on websocket` blocks, which read
// the record `received` as `on tcp` blocks do. The connections and their threads are `roci`'s.
package interp

import "core:fmt"
import "core:math"

import "../"
import "../lang"

// Says what went wrong with a request about a web socket, at the place that asked. Nothing is done then, and the sketch goes on.
@(private)
say_websocket_result :: proc(it: ^Interp, result: roci.Websocket_Result, label, url: string, span: lang.Span) {
	switch result {
	case .Ok:
	case .Bad_Name:
		fail(it, .Websocket_Refused, span, "a name", "A web socket is named by its label, up to 64 letters, so the sketch can tell it from the others.", "", "websocket connect \"feed\" to \"wss://example.org/live\"")
	case .Bad_Address:
		fail(it, .Websocket_Address_Bad, span, url, "", "", "websocket connect \"feed\" to \"wss://example.org/live\"")
	case .Too_Many:
		fail(it, .Websocket_Refused, span, "room", "As many web sockets as a sketch may have, eight, are open. Close one first with `websocket close`.", "", "websocket close \"feed\"")
	case .Unknown_Label:
		fail(it, .Websocket_Unknown_Label, span, label, "", "", fmt.tprintf("websocket connect \"%s\" to \"wss://example.org/live\"", label))
	case .Empty:
		fail(it, .Websocket_Refused, span, "something to send", "There is nothing in this to send.", "", "websocket send \"feed\" \"hello\"")
	case .Not_Sent:
		fail(it, .Websocket_Refused, span, "an open connection", "The web socket is not open yet, or it is over. `on websocket open` says when it is open.", "", "on websocket open \"feed\" [ websocket send \"feed\" \"hello\" ]")
	}
}

@(private)
websocket_verb :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call, code: Verb_Code) {
	label := as_text(eval(it, call.args[0]))
	#partial switch code {
	case .Websocket_Connect:
		url := ""
		if v, ok := option_value(it, call.options, "to"); ok {
			url = as_text(v)
		}
		say_websocket_result(it, roci.websocket_connect(label, url), label, url, e.span)
	case .Websocket_Send:
		if call.shape == 1 {
			items := as_list(eval(it, call.args[1]))
			bytes := make([dynamic]byte, context.temp_allocator)
			if items != nil {
				for item in items.items {
					number, is_number := item.(f64)
					if !is_number {
						fail(it, .Websocket_Refused, e.span, "numbers to send", "The bytes of a message are numbers from 0 to 255, and this list holds something else.", "", "websocket send \"feed\" [ 1 2 255 ]")
						return
					}
					append(&bytes, byte(clamp(math.round(number), 0, 255)))
				}
			}
			say_websocket_result(it, roci.websocket_send(label, bytes[:], true), label, "", e.span)
		} else {
			text := as_text(eval(it, call.args[1]))
			say_websocket_result(it, roci.websocket_send(label, transmute([]byte)text), label, "", e.span)
		}
	case .Websocket_Close:
		say_websocket_result(it, roci.websocket_close(label), label, "", e.span)
	}
}
