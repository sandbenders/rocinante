// SPDX-License-Identifier: 0BSD
package roci

import "core:c"
import "core:fmt"
import "core:testing"

import "platform"

@(test)
test_udp_datagrams_become_happenings :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	w := window(320, 240)
	step()
	testing.expect_value(t, udp_listen(9000), platform.Osc_Problem.None)
	testing.expect_value(t, udp_listen(9000), platform.Osc_Problem.None) // again changes nothing
	testing.expect_value(t, len(udp_ports), 1)
	feed_udp(9000, transmute([]u8)string("hello"), "192.168.0.7", 4242)
	feed_udp(9000, []u8{1, 2, 255})
	step()
	log := happened()
	testing.expect_value(t, len(log), 2)
	testing.expect_value(t, log[0].kind, Happening.Udp)
	testing.expect_value(t, log[0].window, w)
	d := log[0].udp
	testing.expect_value(t, d.to, 9000)
	testing.expect_value(t, d.text, "hello")
	testing.expect_value(t, d.from, "192.168.0.7")
	testing.expect_value(t, d.port, 4242)
	testing.expect_value(t, len(d.data), 5)
	d = log[1].udp
	testing.expect_value(t, len(d.data), 3)
	testing.expect_value(t, d.data[2], 255)
	testing.expect_value(t, d.from, "127.0.0.1")
	// the next frame has none
	step()
	testing.expect_value(t, len(happened()), 0)
	testing.expect(t, len(udp_in) == 0, "a headless sketch opens no socket")
}

@(test)
test_udp_listening_says_why_it_cannot :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	testing.expect_value(t, udp_listen(0), platform.Osc_Problem.Port_Refused)
	testing.expect_value(t, udp_listen(65536), platform.Osc_Problem.Port_Refused)
	testing.expect_value(t, udp_listen(90.5), platform.Osc_Problem.Port_Refused)
	set_udp_port_busy(true)
	testing.expect_value(t, udp_listen(9000), platform.Osc_Problem.Port_Busy)
	set_udp_port_busy(false)
	testing.expect(t, !udp_is_listening(9000))
	// only so many ports
	for port in 1 ..= UDP_MAX_PORTS {
		testing.expect_value(t, udp_listen(f64(9000 + port)), platform.Osc_Problem.None)
	}
	testing.expect_value(t, udp_listen(9999), platform.Osc_Problem.Port_Refused)
}

@(test)
test_udp_sending_is_kept_by_a_headless_sketch_and_refuses_what_cannot_go :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	testing.expect_value(t, udp_send(transmute([]u8)string("hi"), "studio.local", 8000), Udp_Result.Sent)
	testing.expect_value(t, udp_send([]u8{9}, "127.0.0.1", 1), Udp_Result.Sent)
	testing.expect_value(t, udp_send([]u8{9}, "127.0.0.1", 0), Udp_Result.Bad_Port)
	testing.expect_value(t, udp_send([]u8{9}, "127.0.0.1", 65536), Udp_Result.Bad_Port)
	testing.expect_value(t, udp_send(nil, "127.0.0.1", 9000), Udp_Result.Empty)
	big := make([]u8, UDP_MAX_BYTES + 1)
	defer delete(big)
	testing.expect_value(t, udp_send(big, "127.0.0.1", 9000), Udp_Result.Too_Big)
	testing.expect_value(t, udp_send(big[:UDP_MAX_BYTES], "127.0.0.1", 9000), Udp_Result.Sent)
	testing.expect_value(t, udp_send([]u8{1}, "nowhere.invalid", 9000), Udp_Result.Host_Unknown)
	sent := udp_sent_messages()
	testing.expect_value(t, len(sent), 3)
	testing.expect_value(t, string(sent[0].data), "hi")
	testing.expect_value(t, sent[0].host, "studio.local")
	testing.expect_value(t, sent[0].port, 8000)
	udp_clear_sent()
	testing.expect_value(t, len(udp_sent_messages()), 0)
}

@(thread_local) @(private = "file") heard_udp: [4]string
@(thread_local) @(private = "file") heard_udp_info: [4][3]c.int // the port it came to, the port it came from, the size
@(thread_local) @(private = "file") heard_udp_first: [4]u8
@(thread_local) @(private = "file") heard_udp_count: int

@(private = "file")
remember_udp :: proc "c" (event: ^Abi_Event) {
	context = abi_context()
	if heard_udp_count < len(heard_udp) {
		heard_udp[heard_udp_count] = fmt.tprint(event.udp.text)
		heard_udp_info[heard_udp_count] = {event.udp.to, event.udp.port, event.udp.size}
		heard_udp_first[heard_udp_count] = event.udp.data[0]
		heard_udp_count += 1
	}
}

@(test)
test_abi_udp_events_for_a_port_and_sending :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	heard_udp_count = 0
	window(100, 100)
	abi_on(0, "udp", "9000", remember_udp)
	testing.expect(t, udp_is_listening(9000), "roci_on listens on the port it was given")
	feed_udp(9000, transmute([]u8)string("hi"), "10.0.0.2", 777)
	feed_udp(9001, transmute([]u8)string("other"))
	step()
	testing.expect_value(t, heard_udp_count, 1)
	testing.expect_value(t, heard_udp[0], "hi")
	testing.expect_value(t, heard_udp_info[0], [3]c.int{9000, 777, 2})
	testing.expect_value(t, heard_udp_first[0], 'h')
	// sending and listening from C
	bytes := [?]u8{1, 2, 3}
	testing.expect_value(t, abi_udp_send(raw_data(bytes[:]), 3, "studio.local", 8000), 1)
	testing.expect_value(t, abi_udp_send(raw_data(bytes[:]), 3, nil, 8000), 1)
	testing.expect_value(t, abi_udp_send(raw_data(bytes[:]), 3, nil, 0), 0)
	testing.expect_value(t, abi_udp_send(nil, 3, nil, 8000), 0)
	testing.expect_value(t, abi_udp_send(raw_data(bytes[:]), 0, nil, 8000), 0)
	testing.expect_value(t, len(udp_sent_messages()), 2)
	testing.expect_value(t, udp_sent_messages()[1].host, "127.0.0.1")
	testing.expect_value(t, abi_udp_listen(9100), 1)
	testing.expect_value(t, abi_udp_listen(0), 0)
}
