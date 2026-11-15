// SPDX-License-Identifier: 0BSD
package roci

import "core:c"
import "core:fmt"
import "core:testing"

import oscp "osc"
import "platform"

@(private = "file")
packet :: proc(address: string, args: ..oscp.Arg) -> []u8 {
	return oscp.encode(address, args, context.temp_allocator)
}

@(test)
test_osc_becomes_happenings :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	w := window(320, 240)
	step()
	testing.expect_value(t, osc_value("/xy"), 0)
	feed_osc(packet("/xy", f64(10), f64(20.5)), "192.168.0.7")
	feed_osc(packet("/name", "hi", true, false))
	step()
	log := happened()
	testing.expect_value(t, len(log), 2)
	testing.expect_value(t, log[0].kind, Happening.Osc)
	testing.expect_value(t, log[0].window, w)
	m := log[0].osc
	testing.expect_value(t, m.address, "/xy")
	testing.expect_value(t, m.from, "192.168.0.7")
	testing.expect_value(t, m.value, 10)
	testing.expect_value(t, m.text, "")
	testing.expect_value(t, len(m.args), 2)
	testing.expect_value(t, m.args[1].(f64), 20.5)
	m = log[1].osc
	testing.expect_value(t, m.address, "/name")
	testing.expect_value(t, m.text, "hi")
	testing.expect_value(t, m.value, 1) // true is 1
	testing.expect_value(t, len(m.args), 3) // all of them, in order
	testing.expect_value(t, m.args[0].(string), "hi")
	testing.expect_value(t, m.args[1].(bool), true)
	testing.expect_value(t, m.args[2].(bool), false)
	// the latest first number of each address stays
	testing.expect_value(t, osc_value("/xy"), 10)
	testing.expect_value(t, osc_value("/name"), 1)
	testing.expect_value(t, osc_value("/other"), 0)
	// the next frame has none, and the values stay
	step()
	testing.expect_value(t, len(happened()), 0)
	testing.expect_value(t, osc_value("/xy"), 10)
	testing.expect(t, osc_in == nil, "a headless sketch opens no socket")
	// a later message replaces the value
	feed_osc(packet("/xy", f64(3)))
	step()
	testing.expect_value(t, osc_value("/xy"), 3)
}

@(test)
test_osc_message_with_no_number_or_with_left_out_arguments :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	window(100, 100)
	feed_osc(packet("/note"))
	feed_osc(packet("/word", "only"))
	// a blob and a timetag are left out, and named
	feed_osc([]u8{'/', 'b', 0, 0, ',', 'b', 't', 'f', 0, 0, 0, 0, 0, 0, 0, 1, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x40, 0, 0, 0})
	// not OSC at all
	feed_osc([]u8{1, 2, 3})
	step()
	log := happened()
	testing.expect_value(t, len(log), 3)
	testing.expect_value(t, log[0].osc.value, 0)
	testing.expect_value(t, len(log[0].osc.args), 0)
	testing.expect_value(t, log[1].osc.text, "only")
	testing.expect_value(t, log[1].osc.value, 0)
	testing.expect_value(t, log[2].osc.dropped, "t")
	testing.expect_value(t, len(log[2].osc.args), 2)
	testing.expect_value(t, string(cast([]byte)log[2].osc.args[0].(oscp.Blob)), "\x07")
	testing.expect_value(t, log[2].osc.value, 2)
	// a message with no number leaves the address's value alone
	testing.expect_value(t, osc_value("/word"), 0)
	testing.expect_value(t, len(osc_values), 1)
}

// With no window the packets are taken and the values move, but nothing is logged.
@(test)
test_osc_without_a_window :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	feed_osc(packet("/a", f64(7)))
	step()
	testing.expect_value(t, osc_value("/a"), 7)
	testing.expect_value(t, len(happened()), 0)
	shutdown()
	start_headless(1)
	testing.expect_value(t, osc_value("/a"), 0)
}

@(test)
test_osc_remembers_only_so_many_addresses :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	window(100, 100)
	for i in 0 ..< MAX_OSC_ADDRESSES + 50 {
		feed_osc(packet(fmt.tprintf("/n/%d", i), f64(i + 1)))
	}
	step()
	testing.expect_value(t, len(osc_values), MAX_OSC_ADDRESSES)
	testing.expect_value(t, osc_value("/n/0"), 1)
	testing.expect_value(t, osc_value(fmt.tprintf("/n/%d", MAX_OSC_ADDRESSES + 10)), 0)
	// an address already kept still changes
	feed_osc(packet("/n/0", f64(99)))
	step()
	testing.expect_value(t, osc_value("/n/0"), 99)
	// and the messages were all logged, though the values were not all kept
	feed_osc(packet(fmt.tprintf("/n/%d", MAX_OSC_ADDRESSES + 10), f64(1)))
	step()
	testing.expect_value(t, len(happened()), 1)
}

@(test)
test_osc_send_in_a_headless_sketch_is_kept_for_the_test :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	testing.expect_value(t, osc_send("/note", {f64(60), "hi", true}), Osc_Result.Sent)
	testing.expect_value(t, osc_send("/x", {}, "studio.local", 8000), Osc_Result.Sent)
	testing.expect_value(t, osc_send("note", {}), Osc_Result.Bad_Address)
	testing.expect_value(t, osc_send("", {}), Osc_Result.Bad_Address)
	sent := osc_sent_messages()
	testing.expect_value(t, len(sent), 2)
	testing.expect_value(t, sent[0].address, "/note")
	testing.expect_value(t, sent[0].host, "127.0.0.1")
	testing.expect_value(t, sent[0].port, DEFAULT_OSC_PORT)
	testing.expect_value(t, len(sent[0].args), 3)
	testing.expect_value(t, sent[0].args[1].(string), "hi")
	testing.expect_value(t, sent[1].host, "studio.local")
	testing.expect_value(t, sent[1].port, 8000)
	osc_clear_sent()
	testing.expect_value(t, len(osc_sent_messages()), 0)
	testing.expect(t, osc_out == nil, "a headless sketch opens no socket")
}

@(test)
test_osc_listen_remembers_the_port_in_a_headless_sketch :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	testing.expect_value(t, osc_listening(), 0)
	testing.expect_value(t, osc_listen(8000), platform_none)
	testing.expect_value(t, osc_listening(), 8000)
	osc_listen(0)
	testing.expect_value(t, osc_listening(), DEFAULT_OSC_PORT)
	osc_listen(70000)
	testing.expect_value(t, osc_listening(), DEFAULT_OSC_PORT)
	osc_listen(-5)
	testing.expect_value(t, osc_listening(), DEFAULT_OSC_PORT)
	// the first ask starts listening on the start port, unless a port was chosen already
	shutdown()
	start_headless(1)
	start_osc()
	testing.expect_value(t, osc_listening(), DEFAULT_OSC_PORT)
	osc_listen(8001)
	start_osc()
	testing.expect_value(t, osc_listening(), 8001)
}

@(private = "file")
platform_none :: platform.Osc_Problem.None

@(thread_local) @(private = "file") heard_osc: [4]Abi_Osc
@(thread_local) @(private = "file") heard_osc_addresses: [4]string
@(thread_local) @(private = "file") heard_osc_texts: [4]string
@(thread_local) @(private = "file") heard_osc_args: [4]f64
@(thread_local) @(private = "file") heard_osc_kinds: [4][3]Abi_Value_Kind
@(thread_local) @(private = "file") heard_osc_blob: [4][2]f64 // the count and the last byte of a blob that is the third argument
@(thread_local) @(private = "file") heard_osc_count: int

@(private = "file")
remember_osc :: proc "c" (event: ^Abi_Event) {
	context = abi_context()
	if heard_osc_count < len(heard_osc) {
		heard_osc[heard_osc_count] = event.osc
		heard_osc_addresses[heard_osc_count] = fmt.tprint(event.osc.address)
		heard_osc_texts[heard_osc_count] = fmt.tprint(event.osc.text)
		heard_osc_args[heard_osc_count] = event.osc.args[1].number if event.osc.arg_count > 1 else -1
		for i in 0 ..< min(3, int(event.osc.arg_count)) {
			heard_osc_kinds[heard_osc_count][i] = event.osc.args[i].kind
		}
		if event.osc.arg_count > 2 && event.osc.args[2].kind == .List {
			blob := event.osc.args[2]
			heard_osc_blob[heard_osc_count] = {f64(blob.count), blob.items[blob.count - 1].number}
		}
		heard_osc_count += 1
	}
	_ = c.int(0)
}

@(test)
test_abi_osc_events_with_an_address_filter :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	heard_osc_count = 0
	window(100, 100)
	abi_on(0, "osc", "/fader/*", remember_osc)
	feed_osc(packet("/fader/1", f64(5), f64(6)))
	feed_osc(packet("/other", f64(1)))
	feed_osc(packet("/fader/2/x", f64(1)))
	feed_osc(packet("/fader/3", "word"))
	step()
	testing.expect_value(t, heard_osc_count, 2)
	testing.expect_value(t, heard_osc_addresses[0], "/fader/1")
	testing.expect_value(t, heard_osc[0].value, 5)
	testing.expect_value(t, heard_osc[0].arg_count, 2)
	testing.expect_value(t, heard_osc_args[0], 6)
	testing.expect_value(t, heard_osc_addresses[1], "/fader/3")
	testing.expect_value(t, heard_osc_texts[1], "word")
	// no address: every message
	heard_osc_count = 0
	abi_on(0, "osc", nil, remember_osc)
	feed_osc(packet("/other", f64(1)))
	step()
	testing.expect_value(t, heard_osc_count, 1)
}

@(test)
test_abi_osc_send_value_and_listen :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	args := [?]Abi_Value{{kind = .Number, number = 60}, {kind = .Text, text = "hi"}, {kind = .Boolean, number = 1}, {kind = .Vec2}, {kind = .List}}
	testing.expect_value(t, abi_osc_send("/note", raw_data(args[:]), 5, nil, 0), 1)
	testing.expect_value(t, abi_osc_send("/to", nil, 0, "studio.local", 8000), 1)
	testing.expect_value(t, abi_osc_send("bad", nil, 0, nil, 0), 0)
	sent := osc_sent_messages()
	testing.expect_value(t, len(sent), 2)
	testing.expect_value(t, len(sent[0].args), 4) // a point cannot go, and a list is a blob of bytes
	testing.expect_value(t, len(sent[0].args[3].(oscp.Blob)), 0)
	testing.expect_value(t, sent[0].args[2].(bool), true)
	testing.expect_value(t, sent[0].host, "127.0.0.1")
	testing.expect_value(t, sent[0].port, DEFAULT_OSC_PORT)
	testing.expect_value(t, sent[1].host, "studio.local")
	testing.expect_value(t, sent[1].port, 8000)
	// several messages together are one bundle: a list of lists whose first item is the address
	bytes := [?]Abi_Value{{kind = .Number, number = 1}, {kind = .Number, number = 300}, {kind = .Number, number = -4}}
	first := [?]Abi_Value{{kind = .Text, text = "/a"}, {kind = .Number, number = 7}, {kind = .List, items = raw_data(bytes[:]), count = 3}}
	second := [?]Abi_Value{{kind = .Text, text = "/b"}}
	bundle := [?]Abi_Value{{kind = .List, items = raw_data(first[:]), count = 3}, {kind = .List, items = raw_data(second[:]), count = 1}}
	osc_clear_sent()
	testing.expect_value(t, abi_osc_send_bundle(raw_data(bundle[:]), 2, "studio.local", 8001), 1)
	sent = osc_sent_messages()
	testing.expect_value(t, len(sent), 2)
	testing.expect(t, sent[0].bundled && sent[1].bundled)
	testing.expect_value(t, sent[1].address, "/b")
	testing.expect_value(t, sent[0].host, "studio.local")
	testing.expect_value(t, sent[0].port, 8001)
	testing.expect_value(t, string(cast([]byte)sent[0].args[1].(oscp.Blob)), "\x01\xff\x00") // rounded and kept from 0 to 255
	// a message with no address, or a bundle of none, is refused
	noname := [?]Abi_Value{{kind = .List, items = raw_data(bytes[:]), count = 3}}
	testing.expect_value(t, abi_osc_send_bundle(raw_data(noname[:]), 1, nil, 0), 0)
	testing.expect_value(t, abi_osc_send_bundle(nil, 0, nil, 0), 1)
	abi_osc_listen(8123)
	testing.expect_value(t, osc_listening(), 8123)
	window(100, 100)
	feed_osc(packet("/v", f64(42)))
	step()
	testing.expect_value(t, abi_osc_value("/v"), 42)
	testing.expect_value(t, abi_osc_value("/nope"), 0)
}

@(test)
test_osc_blobs_arrive_and_go_as_bytes :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	window(100, 100)
	feed_osc(packet("/data", oscp.Blob{0, 127, 255}, f64(5)))
	step()
	m := happened()[0].osc
	testing.expect_value(t, len(m.args), 2)
	testing.expect_value(t, string(cast([]byte)m.args[0].(oscp.Blob)), "\x00\x7f\xff")
	testing.expect_value(t, m.value, 5) // the first number, not counting the blob
	testing.expect_value(t, m.dropped, "")
}

@(test)
test_osc_send_bundle_keeps_each_message_and_refuses_a_bad_one :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	good := []oscp.Out_Message{{"/a", {f64(1), "x"}}, {"/b", {}}}
	testing.expect_value(t, osc_send_bundle(good), Osc_Result.Sent)
	sent := osc_sent_messages()
	testing.expect_value(t, len(sent), 2)
	testing.expect(t, sent[0].bundled && sent[1].bundled)
	testing.expect_value(t, sent[0].args[1].(string), "x")
	testing.expect_value(t, osc_send_bundle([]oscp.Out_Message{{"/a", {}}, {"b", {}}}), Osc_Result.Bad_Address)
	testing.expect_value(t, osc_send_bundle(good, "nowhere.invalid"), Osc_Result.Host_Unknown)
	testing.expect_value(t, osc_send_bundle(nil), Osc_Result.Sent)
	testing.expect_value(t, len(osc_sent_messages()), 2) // the refused ones were not kept
	// a single message is not bundled
	osc_send("/c", {})
	testing.expect(t, !osc_sent_messages()[2].bundled)
}

@(test)
test_abi_osc_event_carries_every_argument :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	heard_osc_count = 0
	window(100, 100)
	abi_on(0, "osc", nil, remember_osc)
	feed_osc(packet("/x", "word", f64(2), oscp.Blob{9, 8}))
	step()
	testing.expect_value(t, heard_osc_count, 1)
	testing.expect_value(t, heard_osc[0].arg_count, 3)
	testing.expect_value(t, heard_osc_kinds[0], [3]Abi_Value_Kind{.Text, .Number, .List})
	testing.expect_value(t, heard_osc_blob[0], [2]f64{2, 8})
}
