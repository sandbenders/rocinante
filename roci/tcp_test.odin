// SPDX-License-Identifier: 0BSD
package roci

import "core:c"
import "core:fmt"
import "core:testing"

@(test)
test_tcp_connections_are_asked_for_and_refused_by_their_rules :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	testing.expect_value(t, tcp_connect("chat", "studio.local", 9400), Tcp_Result.Ok)
	testing.expect_value(t, tcp_connect("chat", "studio.local", 9400), Tcp_Result.Ok) // the same again changes nothing
	testing.expect_value(t, len(tcp_asked_for()), 1)
	testing.expect_value(t, tcp_connect("chat", "other.local", 9400), Tcp_Result.Ok) // another place replaces it
	testing.expect_value(t, len(tcp_asked_for()), 2)
	testing.expect_value(t, len(tcp_entries), 1)
	testing.expect_value(t, tcp_connect("", "localhost", 9400), Tcp_Result.Bad_Name)
	testing.expect_value(t, tcp_connect("   ", "localhost", 9400), Tcp_Result.Bad_Name)
	testing.expect_value(t, tcp_connect("x", "localhost", 0), Tcp_Result.Bad_Port)
	testing.expect_value(t, tcp_connect("x", "localhost", 65536), Tcp_Result.Bad_Port)
	testing.expect_value(t, tcp_connect("x", "localhost", 94.5), Tcp_Result.Bad_Port)
	testing.expect_value(t, tcp_connect("x", "nowhere.invalid", 9400), Tcp_Result.Host_Unknown)
	testing.expect_value(t, tcp_connect("x", "", 9400), Tcp_Result.Host_Unknown)
	testing.expect_value(t, tcp_listen("server", 9400), Tcp_Result.Ok)
	testing.expect_value(t, tcp_listen("server", 0), Tcp_Result.Bad_Port)
	set_tcp_port_busy(true)
	testing.expect_value(t, tcp_listen("second", 9500), Tcp_Result.Port_Busy)
	set_tcp_port_busy(false)
	// only so many at once
	for i in 3 ..= TCP_MAX_ENDPOINTS {
		testing.expect_value(t, tcp_connect(fmt.tprintf("c%d", i), "localhost", 9400), Tcp_Result.Ok)
	}
	testing.expect_value(t, tcp_connect("one more", "localhost", 9400), Tcp_Result.Too_Many)
	testing.expect_value(t, tcp_listen("one more", 9401), Tcp_Result.Too_Many)
	testing.expect_value(t, tcp_connect("c3", "localhost", 9401), Tcp_Result.Ok) // a replacement is not one more
}

@(test)
test_tcp_sending_and_closing_are_kept_by_a_headless_sketch :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	testing.expect_value(t, tcp_send("ghost", []u8{1}), Tcp_Result.Unknown_Label)
	testing.expect_value(t, tcp_close("ghost"), Tcp_Result.Unknown_Label)
	tcp_connect("chat", "localhost", 9400)
	tcp_listen("server", 9401)
	testing.expect_value(t, tcp_send("chat", transmute([]u8)string("hello\n")), Tcp_Result.Ok)
	testing.expect_value(t, tcp_send("server", []u8{9, 8}, 2), Tcp_Result.Ok)
	testing.expect_value(t, tcp_send("chat", nil), Tcp_Result.Empty)
	sent := tcp_sent_messages()
	testing.expect_value(t, len(sent), 2)
	testing.expect_value(t, sent[0].label, "chat")
	testing.expect_value(t, string(sent[0].data), "hello\n")
	testing.expect_value(t, sent[1].client, 2)
	testing.expect(t, tcp_is_open("chat") && tcp_is_open("server"))
	testing.expect_value(t, tcp_close("server"), Tcp_Result.Ok)
	testing.expect(t, !tcp_is_open("server"), "a listener is gone when it is closed")
	testing.expect_value(t, tcp_close("chat"), Tcp_Result.Ok)
	tcp_clear_sent()
	testing.expect_value(t, len(tcp_sent_messages()), 0)
}

@(test)
test_tcp_happenings_come_from_what_is_fed :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	w := window(320, 240)
	step()
	tcp_connect("chat", "localhost", 9400)
	feed_tcp(.Open, "chat", "", "10.0.0.2", 1)
	feed_tcp(.Line, "chat", "hello", "10.0.0.2", 1)
	feed_tcp(.Close, "chat", "the connection was closed", "10.0.0.2", 1)
	step()
	log := happened()
	testing.expect_value(t, len(log), 3)
	testing.expect_value(t, log[0].kind, Happening.Tcp_Open)
	testing.expect_value(t, log[0].window, w)
	testing.expect_value(t, log[1].kind, Happening.Tcp_Line)
	testing.expect_value(t, log[1].tcp.label, "chat")
	testing.expect_value(t, log[1].tcp.text, "hello")
	testing.expect_value(t, log[1].tcp.from, "10.0.0.2")
	testing.expect_value(t, log[2].kind, Happening.Tcp_Close)
	testing.expect_value(t, log[2].tcp.text, "the connection was closed")
	step()
	testing.expect_value(t, len(happened()), 0)
}

@(thread_local) @(private = "file") heard_tcp: [4]string
@(thread_local) @(private = "file") heard_tcp_kinds: [4]c.int
@(thread_local) @(private = "file") heard_tcp_client: [4]c.int
@(thread_local) @(private = "file") heard_tcp_count: int

@(private = "file")
remember_tcp :: proc "c" (event: ^Abi_Event) {
	context = abi_context()
	if heard_tcp_count < len(heard_tcp) {
		heard_tcp[heard_tcp_count] = fmt.tprint(event.tcp.label, fmt.tprint(event.tcp.text), sep = "|")
		heard_tcp_kinds[heard_tcp_count] = event.kind
		heard_tcp_client[heard_tcp_count] = event.tcp.client
		heard_tcp_count += 1
	}
}

@(test)
test_abi_tcp_events_for_a_label_and_the_functions :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	heard_tcp_count = 0
	window(100, 100)
	testing.expect_value(t, abi_tcp_connect("chat", "studio.local", 9400), 1)
	testing.expect_value(t, abi_tcp_connect("", "studio.local", 9400), 0)
	testing.expect_value(t, abi_tcp_connect("x", "nowhere.invalid", 9400), 0)
	testing.expect_value(t, abi_tcp_listen("server", 9401), 1)
	testing.expect_value(t, abi_tcp_listen("server2", 0), 0)
	abi_on(0, "tcp open", "chat", remember_tcp)
	abi_on(0, "tcp", "chat", remember_tcp)
	abi_on(0, "tcp close", nil, remember_tcp)
	feed_tcp(.Open, "chat", "")
	feed_tcp(.Line, "chat", "hi", "10.0.0.2", 3)
	feed_tcp(.Line, "other", "no")
	feed_tcp(.Close, "other", "gone")
	step()
	testing.expect_value(t, heard_tcp_count, 3)
	testing.expect_value(t, heard_tcp[0], "chat|")
	testing.expect_value(t, heard_tcp_kinds[0], c.int(Happening.Tcp_Open))
	testing.expect_value(t, heard_tcp[1], "chat|hi")
	testing.expect_value(t, heard_tcp_client[1], 3)
	testing.expect_value(t, heard_tcp[2], "other|gone") // a close handler with no label hears every connection
	data := [?]u8{1, 2}
	testing.expect_value(t, abi_tcp_send("chat", raw_data(data[:]), 2, 0), 1)
	testing.expect_value(t, abi_tcp_send("ghost", raw_data(data[:]), 2, 0), 0)
	testing.expect_value(t, abi_tcp_send("chat", nil, 2, 0), 0)
	testing.expect_value(t, abi_tcp_close("chat", 0), 1)
	testing.expect_value(t, abi_tcp_close("ghost", 0), 0)
}
