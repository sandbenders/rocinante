// SPDX-License-Identifier: 0BSD
package interp

import "core:fmt"
import "core:testing"

import "../"

// A sketch opens a web socket from its set-up, sends when it is open and reads each message.
@(test)
test_web_sockets_in_a_sketch :: proc(t: ^testing.T) {
	text := `heard = ""
opened = 0
closed = ""
websocket connect "feed" to "wss://example.org/live"
on websocket open "feed" [
  opened = opened + 1
  websocket send "feed" "hello"
]
on websocket "feed" [ heard = received.text + " from " + received.from ]
on websocket close "feed" [ closed = received.text ]
draw [ background 0 ]
`
	p := run_text(t, text)
	defer finish(p)
	defer roci.websocket_clear_sent()
	asked := roci.websocket_asked_for()
	if testing.expect_value(t, len(asked), 1) {
		testing.expect_value(t, asked[0].url, "wss://example.org/live")
	}
	roci.feed_websocket(.Open, "feed", "")
	roci.feed_websocket(.Line, "feed", "welcome", "example.org")
	roci.feed_websocket(.Line, "other", "nobody listens to this")
	roci.step()
	testing.expect_value(t, as_number(global_named(p, "opened")), 1)
	testing.expect_value(t, as_text(global_named(p, "heard")), "welcome from example.org")
	sent := roci.websocket_sent_messages()
	if testing.expect_value(t, len(sent), 1) {
		testing.expect_value(t, string(sent[0].data), "hello")
		testing.expect_value(t, sent[0].binary, false)
	}
	roci.feed_websocket(.Close, "feed", "the connection was lost")
	roci.step()
	testing.expect_value(t, as_text(global_named(p, "closed")), "the connection was lost")
	testing.expect_value(t, len(p.errors), 0)
}

// A list of numbers goes as a binary message, and a close is asked for.
@(test)
test_web_socket_send_takes_bytes_and_close_ends_a_connection :: proc(t: ^testing.T) {
	p := run_text(t, "websocket connect \"feed\" to \"ws://localhost/x\"\nwebsocket send \"feed\" [ 1 2 300 ]\nwebsocket close \"feed\"\ndraw [ background 0 ]\n")
	defer finish(p)
	defer roci.websocket_clear_sent()
	sent := roci.websocket_sent_messages()
	if !testing.expect_value(t, len(sent), 1) {
		return
	}
	testing.expect_value(t, sent[0].binary, true)
	testing.expect_value(t, sent[0].data[2], 255) // kept from 0 to 255
	testing.expect_value(t, len(p.errors), 0)
}

// Mistakes are said and the sketch goes on.
@(test)
test_web_socket_mistakes_are_said_and_the_sketch_goes_on :: proc(t: ^testing.T) {
	text := "websocket connect \"x\" to \"example.org\"\nwebsocket connect \"\" to \"wss://example.org/\"\nwebsocket send \"ghost\" \"hi\"\nwebsocket close \"ghost\"\nwebsocket connect \"y\" to \"wss://example.org/\"\nwebsocket send \"y\" [ ]\nwebsocket send \"y\" [ 1 \"a\" ]\ndraw [ background 0 ]\n"
	p := run_text(t, text)
	defer finish(p)
	testing.expect_value(t, len(p.errors), 6)
}

// The web socket example lists what arrives, and a click sends.
@(test)
test_the_web_socket_example_lists_what_arrives_and_a_click_sends :: proc(t: ^testing.T) {
	p := run_text(t, example_text("websocket"), 2)
	defer finish(p)
	defer roci.websocket_clear_sent()
	roci.feed_websocket(.Open, "feed", "")
	for i in 1 ..= 9 {
		roci.feed_websocket(.Line, "feed", fmt.tprintf("message %d", i))
	}
	roci.step()
	testing.expect_value(t, as_text(global_named(p, "status")), "open, click to send a message")
	news := as_list(global_named(p, "news"))
	if !testing.expect(t, news != nil && len(news.items) == 7) {
		return
	}
	testing.expect_value(t, as_text(news.items[0]), "message 3")
	testing.expect_value(t, as_text(news.items[6]), "message 9")
	roci.step({click_event(roci.open_windows()[0], 40, 50)})
	sent := roci.websocket_sent_messages()
	if testing.expect_value(t, len(sent), 1) {
		testing.expect_value(t, string(sent[0].data), "click at 40,50")
	}
	roci.feed_websocket(.Close, "feed", "the connection was closed")
	roci.step()
	testing.expect_value(t, as_text(global_named(p, "status")), "closed: the connection was closed")
	testing.expect_value(t, len(p.errors), 0)
}
