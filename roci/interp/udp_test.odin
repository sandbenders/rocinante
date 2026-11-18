// SPDX-License-Identifier: 0BSD
package interp

import "core:fmt"
import "core:testing"

import "../"

// A sketch listens on the ports its blocks name, reads the datagram in `packet`, and sends from its set-up.
@(test)
test_udp_in_a_sketch :: proc(t: ^testing.T) {
	text := `got = ""
total = 0
other = ""
on udp 9000 [ got = packet.text + "|" + packet.from + "|" + packet.port + "|" + (count packet.bytes) ]
on udp 9000 [ total = total + 1 ]
on udp 9001 [ other = packet.text ]
udp send "hello" to "studio.local" port 8000
udp send [ 1 2 300 ] port 8001
draw [ background 0 ]
`
	p := run_text(t, text)
	defer finish(p)
	sent := roci.udp_sent_messages()
	testing.expect_value(t, len(sent), 2)
	testing.expect_value(t, string(sent[0].data), "hello")
	testing.expect_value(t, sent[0].host, "studio.local")
	testing.expect_value(t, sent[0].port, 8000)
	testing.expect_value(t, len(sent[1].data), 3)
	testing.expect_value(t, sent[1].data[2], 255) // kept from 0 to 255
	testing.expect_value(t, sent[1].host, "127.0.0.1")
	testing.expect(t, roci.udp_is_listening(9000) && roci.udp_is_listening(9001))
	roci.feed_udp(9000, transmute([]u8)string("abc"), "10.1.1.1", 5000)
	roci.feed_udp(9001, transmute([]u8)string("xyz"))
	roci.step()
	testing.expect_value(t, as_text(global_named(p, "got")), "abc|10.1.1.1|5000|3")
	testing.expect_value(t, as_number(global_named(p, "total")), 1)
	testing.expect_value(t, as_text(global_named(p, "other")), "xyz")
	// a datagram to a port nobody named runs nothing, and nothing new comes: nothing runs again
	roci.feed_udp(9002, transmute([]u8)string("lost"))
	roci.step()
	roci.step()
	testing.expect_value(t, as_number(global_named(p, "total")), 1)
	testing.expect_value(t, len(p.errors), 0)
}

// The record `packet` holds the bytes as a list of numbers.
@(test)
test_the_packet_record_has_its_bytes_and_text :: proc(t: ^testing.T) {
	text := `first = 0
last = 0
size = 0
on udp 9000 [
  first = item 1 of packet.bytes
  last = item (count packet.bytes) of packet.bytes
  size = count packet.bytes
]
draw [ background 0 ]
`
	p := run_text(t, text)
	defer finish(p)
	roci.feed_udp(9000, []u8{7, 8, 200})
	roci.step()
	testing.expect_value(t, as_number(global_named(p, "first")), 7)
	testing.expect_value(t, as_number(global_named(p, "last")), 200)
	testing.expect_value(t, as_number(global_named(p, "size")), 3)
}

// Mistakes are said once, and the sketch goes on.
@(test)
test_udp_mistakes_are_said_and_the_sketch_goes_on :: proc(t: ^testing.T) {
	p := run_text(t, "udp send \"x\" to \"nowhere.invalid\" port 9000\nudp send \"\" port 9000\nudp send \"x\" port 70000\nudp send [ 1 \"a\" ] port 9000\non udp 99999 [ print 1 ]\n")
	defer finish(p)
	testing.expect_value(t, len(p.errors), 5)
	testing.expect_value(t, len(roci.udp_sent_messages()), 0)
}

// The udp example listens on its port, lists what arrives (the last seven), counts it, and a click sends a ping.
@(test)
test_the_udp_example_lists_what_arrives_and_a_click_sends :: proc(t: ^testing.T) {
	p := run_text(t, example_text("udp"), 2)
	defer finish(p)
	testing.expect(t, roci.udp_is_listening(9200))
	for i in 1 ..= 9 {
		roci.feed_udp(9200, transmute([]u8)fmt.tprintf("ping %d", i), "10.0.0.5", 6000 + i)
	}
	roci.step()
	testing.expect_value(t, as_number(global_named(p, "arrived")), 9)
	news := as_list(global_named(p, "news"))
	if !testing.expect(t, news != nil && len(news.items) == 7) {
		return
	}
	testing.expect_value(t, as_text(news.items[0]), "ping 3   from 10.0.0.5:6003")
	testing.expect_value(t, as_text(news.items[6]), "ping 9   from 10.0.0.5:6009")
	testing.expect_value(t, len(p.errors), 0)
	// a click sends a ping to this computer, port 9200
	w := roci.open_windows()[0]
	roci.step({click_event(w, 40, 50)})
	sent := roci.udp_sent_messages()
	if testing.expect_value(t, len(sent), 1) {
		testing.expect_value(t, string(sent[0].data), "ping 40,50")
		testing.expect_value(t, sent[0].port, 9200)
	}
}
