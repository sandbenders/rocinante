// SPDX-License-Identifier: 0BSD
package interp

import "core:fmt"
import "core:testing"

import "../"

// A sketch makes its connections from its set-up, answers what a server hears, and reads `received`.
@(test)
test_tcp_in_a_sketch :: proc(t: ^testing.T) {
	text := `heard = ""
who = 0
opened = 0
closed = ""
tcp listen "server" port 9400
tcp connect "chat" to "studio.local" port 9500
on tcp open "chat" [ opened = opened + 1 ]
on tcp "server" [
  heard = received.text
  who = received.client
  tcp send "server" ("echo " + received.text) to received.client
]
on tcp close "chat" [ closed = received.text ]
draw [ background 0 ]
`
	p := run_text(t, text)
	defer finish(p)
	defer roci.tcp_clear_sent()
	asked := roci.tcp_asked_for()
	testing.expect_value(t, len(asked), 2)
	testing.expect_value(t, asked[0].server, true)
	testing.expect_value(t, asked[0].port, 9400)
	testing.expect_value(t, asked[1].host, "studio.local")
	testing.expect_value(t, asked[1].port, 9500)
	roci.feed_tcp(.Open, "chat", "")
	roci.feed_tcp(.Line, "server", "hello", "10.1.1.1", 4)
	roci.feed_tcp(.Line, "other", "nobody listens to this")
	roci.step()
	testing.expect_value(t, as_number(global_named(p, "opened")), 1)
	testing.expect_value(t, as_text(global_named(p, "heard")), "hello")
	testing.expect_value(t, as_number(global_named(p, "who")), 4)
	sent := roci.tcp_sent_messages()
	if testing.expect_value(t, len(sent), 1) {
		testing.expect_value(t, sent[0].label, "server")
		testing.expect_value(t, string(sent[0].data), "echo hello\n") // a text goes as a line
		testing.expect_value(t, sent[0].client, 4)
	}
	roci.feed_tcp(.Close, "chat", "the connection was lost")
	roci.step()
	testing.expect_value(t, as_text(global_named(p, "closed")), "the connection was lost")
	testing.expect_value(t, len(p.errors), 0)
}

// Bytes go as exactly those bytes, `to` names a client, and a close is asked for.
@(test)
test_tcp_send_takes_bytes_and_a_client_and_close_ends_a_connection :: proc(t: ^testing.T) {
	text := `tcp connect "chat" to "localhost" port 9500
tcp send "chat" [ 1 2 300 ]
tcp send "chat" "plain"
tcp listen "server" port 9400
tcp send "server" "to two" to 2
tcp close "chat"
draw [ background 0 ]
`
	p := run_text(t, text)
	defer finish(p)
	defer roci.tcp_clear_sent()
	sent := roci.tcp_sent_messages()
	if !testing.expect_value(t, len(sent), 3) {
		return
	}
	testing.expect_value(t, len(sent[0].data), 3)
	testing.expect_value(t, sent[0].data[2], 255) // kept from 0 to 255
	testing.expect_value(t, string(sent[1].data), "plain\n")
	testing.expect_value(t, sent[2].client, 2)
	testing.expect_value(t, len(p.errors), 0)
}

// Mistakes are said and the sketch goes on.
@(test)
test_tcp_mistakes_are_said_and_the_sketch_goes_on :: proc(t: ^testing.T) {
	text := "tcp connect \"x\" to \"nowhere.invalid\" port 9400\ntcp connect \"x\" to \"localhost\" port 70000\ntcp connect \"\" to \"localhost\" port 9400\ntcp send \"ghost\" \"hi\"\ntcp close \"ghost\"\ntcp connect \"y\" to \"localhost\" port 9400\ntcp send \"y\" [ ]\ntcp send \"y\" [ 1 \"a\" ]\ndraw [ background 0 ]\n"
	p := run_text(t, text)
	defer finish(p)
	testing.expect_value(t, len(p.errors), 7)
}

// The tcp example talks to itself: a click goes out on the connection, the server's line and the echo are listed.
@(test)
test_the_tcp_example_lists_what_it_hears_and_a_click_sends :: proc(t: ^testing.T) {
	p := run_text(t, example_text("tcp"), 2)
	defer finish(p)
	defer roci.tcp_clear_sent()
	roci.feed_tcp(.Open, "chat", "")
	for i in 1 ..= 8 {
		roci.feed_tcp(.Line, "chat", fmt.tprintf("line %d", i))
	}
	roci.feed_tcp(.Line, "server", "from outside", "10.0.0.7", 2)
	roci.step()
	testing.expect_value(t, as_text(global_named(p, "status")), "connected, click to send a line")
	talk := as_list(global_named(p, "talk"))
	if !testing.expect(t, talk != nil && len(talk.items) == 7) {
		return
	}
	testing.expect_value(t, as_text(talk.items[0]), "chat heard: line 3")
	testing.expect_value(t, as_text(talk.items[6]), "server heard: from outside (client 2)")
	sent := roci.tcp_sent_messages()
	if testing.expect_value(t, len(sent), 1) {
		testing.expect_value(t, string(sent[0].data), "echo from outside\n")
		testing.expect_value(t, sent[0].client, 2)
	}
	roci.step({click_event(roci.open_windows()[0], 40, 50)})
	sent = roci.tcp_sent_messages()
	if testing.expect_value(t, len(sent), 2) {
		testing.expect_value(t, sent[1].label, "chat")
		testing.expect_value(t, string(sent[1].data), "click at 40,50\n")
	}
	roci.feed_tcp(.Close, "chat", "the connection was closed")
	roci.step()
	testing.expect_value(t, as_text(global_named(p, "status")), "closed: the connection was closed")
	testing.expect_value(t, len(p.errors), 0)
}
