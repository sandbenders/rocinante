// SPDX-License-Identifier: 0BSD
package roci

import "core:c"
import "core:fmt"
import "core:testing"

@(test)
test_web_sockets_are_asked_for_and_refused_by_their_rules :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	testing.expect_value(t, websocket_connect("feed", "wss://example.org/live"), Websocket_Result.Ok)
	testing.expect_value(t, websocket_connect("feed", "wss://example.org/live"), Websocket_Result.Ok) // the same again changes nothing
	testing.expect_value(t, len(websocket_asked_for()), 1)
	testing.expect_value(t, websocket_connect("feed", "ws://other.org/"), Websocket_Result.Ok) // another place replaces it
	testing.expect_value(t, len(websocket_asked_for()), 2)
	testing.expect_value(t, len(websocket_entries), 1)
	testing.expect_value(t, websocket_connect("", "wss://example.org/"), Websocket_Result.Bad_Name)
	testing.expect_value(t, websocket_connect("x", "example.org/live"), Websocket_Result.Bad_Address)
	testing.expect_value(t, websocket_connect("x", "https://example.org/"), Websocket_Result.Bad_Address)
	testing.expect_value(t, websocket_connect("x", "ws://"), Websocket_Result.Bad_Address)
	for i in 2 ..= WEBSOCKET_MAX {
		testing.expect_value(t, websocket_connect(fmt.tprintf("s%d", i), "wss://example.org/"), Websocket_Result.Ok)
	}
	testing.expect_value(t, websocket_connect("one more", "wss://example.org/"), Websocket_Result.Too_Many)
	testing.expect_value(t, websocket_connect("s2", "wss://elsewhere.org/"), Websocket_Result.Ok) // a replacement is not one more
}

@(test)
test_web_socket_sending_and_closing_are_kept_by_a_headless_sketch :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	testing.expect_value(t, websocket_send("ghost", []u8{1}), Websocket_Result.Unknown_Label)
	testing.expect_value(t, websocket_close("ghost"), Websocket_Result.Unknown_Label)
	websocket_connect("feed", "wss://example.org/live")
	testing.expect_value(t, websocket_send("feed", transmute([]u8)string("hello")), Websocket_Result.Ok)
	testing.expect_value(t, websocket_send("feed", []u8{9, 8}, binary = true), Websocket_Result.Ok)
	testing.expect_value(t, websocket_send("feed", nil), Websocket_Result.Empty)
	sent := websocket_sent_messages()
	testing.expect_value(t, len(sent), 2)
	testing.expect_value(t, string(sent[0].data), "hello")
	testing.expect_value(t, sent[0].binary, false)
	testing.expect_value(t, sent[1].binary, true)
	testing.expect(t, websocket_is_open("feed"))
	testing.expect_value(t, websocket_close("feed"), Websocket_Result.Ok)
	websocket_clear_sent()
	testing.expect_value(t, len(websocket_sent_messages()), 0)
}

@(test)
test_web_socket_happenings_come_from_what_is_fed :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	w := window(320, 240)
	step()
	websocket_connect("feed", "wss://example.org/live")
	feed_websocket(.Open, "feed", "")
	feed_websocket(.Line, "feed", "hello", "example.org")
	feed_websocket(.Close, "feed", "the connection was closed")
	step()
	log := happened()
	testing.expect_value(t, len(log), 3)
	testing.expect_value(t, log[0].kind, Happening.Ws_Open)
	testing.expect_value(t, log[0].window, w)
	testing.expect_value(t, log[1].kind, Happening.Ws_Message)
	testing.expect_value(t, log[1].tcp.label, "feed")
	testing.expect_value(t, log[1].tcp.text, "hello")
	testing.expect_value(t, log[1].tcp.from, "example.org")
	testing.expect_value(t, log[2].kind, Happening.Ws_Close)
	step()
	testing.expect_value(t, len(happened()), 0)
}

@(thread_local) @(private = "file") heard_ws: [4]string
@(thread_local) @(private = "file") heard_ws_kinds: [4]c.int
@(thread_local) @(private = "file") heard_ws_count: int

@(private = "file")
remember_ws :: proc "c" (event: ^Abi_Event) {
	context = abi_context()
	if heard_ws_count < len(heard_ws) {
		heard_ws[heard_ws_count] = fmt.tprint(event.tcp.label, fmt.tprint(event.tcp.text), sep = "|")
		heard_ws_kinds[heard_ws_count] = event.kind
		heard_ws_count += 1
	}
}

@(test)
test_abi_web_socket_events_for_a_label_and_the_functions :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	heard_ws_count = 0
	window(100, 100)
	testing.expect_value(t, abi_websocket_connect("feed", "wss://example.org/live"), 1)
	testing.expect_value(t, abi_websocket_connect("", "wss://example.org/live"), 0)
	testing.expect_value(t, abi_websocket_connect("x", "example.org"), 0)
	abi_on(0, "websocket open", "feed", remember_ws)
	abi_on(0, "websocket", "feed", remember_ws)
	abi_on(0, "websocket close", nil, remember_ws)
	feed_websocket(.Open, "feed", "")
	feed_websocket(.Line, "feed", "hi")
	feed_websocket(.Line, "other", "no")
	feed_websocket(.Close, "other", "gone")
	step()
	testing.expect_value(t, heard_ws_count, 3)
	testing.expect_value(t, heard_ws[0], "feed|")
	testing.expect_value(t, heard_ws_kinds[0], c.int(Happening.Ws_Open))
	testing.expect_value(t, heard_ws[1], "feed|hi")
	testing.expect_value(t, heard_ws[2], "other|gone")
	data := [?]u8{1, 2}
	testing.expect_value(t, abi_websocket_send("feed", raw_data(data[:]), 2, 0), 1)
	testing.expect_value(t, abi_websocket_send("feed", raw_data(data[:]), 2, 1), 1)
	testing.expect_value(t, abi_websocket_send("ghost", raw_data(data[:]), 2, 0), 0)
	testing.expect_value(t, abi_websocket_send("feed", nil, 2, 0), 0)
	testing.expect_value(t, abi_websocket_close("feed"), 1)
	testing.expect_value(t, abi_websocket_close("ghost"), 0)
}
