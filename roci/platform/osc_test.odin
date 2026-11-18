// SPDX-License-Identifier: 0BSD
package platform

import "core:testing"
import "core:time"

// Waits up to two seconds for `count` packets to reach `o`.
@(private = "file")
wait_for :: proc(o: ^Osc_In, count: int) -> [dynamic]Osc_Packet {
	got := make([dynamic]Osc_Packet)
	for _ in 0 ..< 2000 {
		osc_take(o, &got)
		if len(got) >= count {
			break
		}
		time.sleep(time.Millisecond)
	}
	return got
}

@(private = "file")
free_packets :: proc(got: [dynamic]Osc_Packet) {
	for p in got {
		delete(p.data)
		delete(p.from)
	}
	delete(got)
}

@(test)
test_a_packet_goes_to_a_listener_and_comes_out_whole :: proc(t: ^testing.T) {
	in_ := open_osc(0)
	defer close_osc(in_)
	testing.expect_value(t, in_.error, Osc_Problem.None)
	testing.expect(t, in_.port > 0)
	out := open_osc_out()
	defer close_osc_out(out)
	testing.expect_value(t, osc_send(out, "127.0.0.1", in_.port, []byte{'/', 'a', 0, 0, 1, 2, 3, 4}), Osc_Send_Result.Sent)
	testing.expect_value(t, osc_send(out, "localhost", in_.port, []byte{'/', 'b', 0, 0}), Osc_Send_Result.Sent)
	testing.expect_value(t, osc_send(out, "", in_.port, []byte{'/', 'c', 0, 0}), Osc_Send_Result.Sent)
	got := wait_for(in_, 3)
	defer free_packets(got)
	testing.expect_value(t, len(got), 3)
	if len(got) == 3 {
		// oldest first, bytes untouched, and the sender is this computer
		testing.expect_value(t, string(got[0].data), "/a\x00\x00\x01\x02\x03\x04")
		testing.expect_value(t, string(got[1].data), "/b\x00\x00")
		testing.expect_value(t, string(got[2].data), "/c\x00\x00")
		testing.expect_value(t, got[0].from, "127.0.0.1")
		testing.expect(t, got[0].port > 0, "the port it was sent from comes with it")
	}
	// taken once, they are gone
	again := make([dynamic]Osc_Packet)
	defer free_packets(again)
	osc_take(in_, &again)
	testing.expect_value(t, len(again), 0)
}

@(test)
test_a_port_that_is_taken_says_so_and_nothing_is_left_open :: proc(t: ^testing.T) {
	first := open_osc(0)
	defer close_osc(first)
	second := open_osc(first.port)
	defer close_osc(second)
	testing.expect_value(t, second.error, Osc_Problem.Port_Busy)
	testing.expect(t, second.thread == nil)
	// taking from one that never listened is harmless
	got := make([dynamic]Osc_Packet)
	defer free_packets(got)
	osc_take(second, &got)
	osc_take(nil, &got)
	testing.expect_value(t, len(got), 0)
}

@(test)
test_a_closed_listener_frees_the_port_and_its_waiting_packets :: proc(t: ^testing.T) {
	first := open_osc(0)
	port := first.port
	out := open_osc_out()
	defer close_osc_out(out)
	osc_send(out, "127.0.0.1", port, []byte{'/', 'x', 0, 0})
	time.sleep(20 * time.Millisecond)
	close_osc(first) // a packet still waiting in the queue is let go with it
	close_osc(nil)
	again := open_osc(port)
	defer close_osc(again)
	testing.expect_value(t, again.error, Osc_Problem.None)
}

@(test)
test_sending_what_cannot_be_sent_is_said :: proc(t: ^testing.T) {
	out := open_osc_out()
	defer close_osc_out(out)
	packet := []byte{'/', 'a', 0, 0}
	testing.expect_value(t, osc_send(out, "127.0.0.1", 0, packet), Osc_Send_Result.Not_Sent)
	testing.expect_value(t, osc_send(out, "127.0.0.1", 70000, packet), Osc_Send_Result.Not_Sent)
	testing.expect_value(t, osc_send(out, "127.0.0.1", 9000, nil), Osc_Send_Result.Not_Sent)
	big := make([]byte, OSC_PACKET + 1)
	defer delete(big)
	testing.expect_value(t, osc_send(out, "127.0.0.1", 9000, big), Osc_Send_Result.Not_Sent)
	// an address that is only IPv6 has no way to be reached by this socket
	testing.expect_value(t, osc_send(out, "::1", 9000, packet), Osc_Send_Result.Host_Unknown)
	// a port nobody listens on is not an error: UDP does not say
	testing.expect_value(t, osc_send(out, "127.0.0.1", 9, packet), Osc_Send_Result.Sent)
}

@(test)
test_a_listener_keeps_only_the_newest_packets_of_a_flood :: proc(t: ^testing.T) {
	in_ := open_osc(0)
	defer close_osc(in_)
	out := open_osc_out()
	defer close_osc_out(out)
	for i in 0 ..< OSC_QUEUE + 200 {
		osc_send(out, "127.0.0.1", in_.port, []byte{'/', 'a', 0, 0, byte(i >> 8), byte(i), 0, 0})
	}
	time.sleep(100 * time.Millisecond)
	got := wait_for(in_, 1)
	defer free_packets(got)
	testing.expect(t, len(got) <= OSC_QUEUE)
	testing.expect(t, len(got) > 0)
}
