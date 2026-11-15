// SPDX-License-Identifier: 0BSD
package interp

import "core:os"
import "core:testing"

import "../platform"

import "../"
import oscp "../osc"

@(private = "file")
packet :: proc(address: string, args: ..oscp.Arg) -> []u8 {
	return oscp.encode(address, args, context.temp_allocator)
}

// A sketch hears the messages sent to an address (with a star), hears every one in the other block,
// reads the latest value of an address anywhere, and sends a message from its set-up.
@(test)
test_osc_in_a_sketch :: proc(t: ^testing.T) {
	text := `got = ""
total = 0
seen = 0
on osc "/fader/*" [ total = total + osc.value ]
on osc [ got = osc.address + "|" + osc.text + "|" + (count osc.args) ]
draw [ seen = osc value "/fader/1" ]
osc send "/out" [ 1 "two" true ] to "studio.local" port 8000
osc send "/plain" [ ]
`
	p := run_with_sounds(t, "osc_words", text, "tests/sounds", {})
	defer finish(p)
	defer roci.osc_clear_sent()
	sent := roci.osc_sent_messages()
	testing.expect_value(t, len(sent), 2)
	testing.expect_value(t, sent[0].address, "/out")
	testing.expect_value(t, sent[0].host, "studio.local")
	testing.expect_value(t, sent[0].port, 8000)
	testing.expect_value(t, len(sent[0].args), 3)
	testing.expect_value(t, sent[1].host, "127.0.0.1")
	testing.expect_value(t, sent[1].port, roci.DEFAULT_OSC_PORT)
	testing.expect_value(t, roci.osc_listening(), roci.DEFAULT_OSC_PORT)
	roci.feed_osc(packet("/fader/1", f64(5)))
	roci.feed_osc(packet("/fader/2", f64(7)))
	roci.feed_osc(packet("/other", "word", f64(1), f64(2)))
	roci.step()
	testing.expect_value(t, as_number(global_named(p, "total")), 12)
	testing.expect_value(t, as_text(global_named(p, "got")), "/other|word|2")
	roci.step()
	testing.expect_value(t, as_number(global_named(p, "seen")), 5)
	// nothing new comes: nothing runs again
	roci.step()
	testing.expect_value(t, as_number(global_named(p, "total")), 12)
	testing.expect_value(t, len(p.errors), 0)
}

// The record `osc` has all its fields, and the arguments come as a list of numbers.
@(test)
test_the_osc_record :: proc(t: ^testing.T) {
	text := `address = ""
sender = ""
first = 0
second = 0
words = ""
n = 0
on osc [
  address = osc.address
  sender = osc.from
  first = osc.value
  second = item 2 of osc.args
  words = osc.text
  n = count osc.args
]
draw [ background 20 ]
`
	p := run_with_sounds(t, "osc_record", text, "tests/sounds", {})
	defer finish(p)
	roci.feed_osc(packet("/a/b", "hello", f64(3), true), "10.0.0.5")
	roci.step()
	testing.expect_value(t, as_text(global_named(p, "address")), "/a/b")
	testing.expect_value(t, as_text(global_named(p, "sender")), "10.0.0.5")
	testing.expect_value(t, as_number(global_named(p, "first")), 3)
	testing.expect_value(t, as_number(global_named(p, "second")), 1)
	testing.expect_value(t, as_text(global_named(p, "words")), "hello")
	testing.expect_value(t, as_number(global_named(p, "n")), 2)
	testing.expect_value(t, len(p.errors), 0)
}

// What a sketch cannot use, or does wrong, is said once and the sketch goes on.
@(test)
test_osc_problems_are_said_and_the_sketch_goes_on :: proc(t: ^testing.T) {
	text := `heard = 0
on osc [ heard = heard + 1 ]
osc send "note" [ 1 ]
osc send "/x" [ { 1, 2 } "ok" ]
osc send "/y" [ 1 ] to "nowhere.invalid"
`
	p := run_with_sounds(t, "osc_problems", text, "tests/sounds", {})
	defer finish(p)
	defer roci.osc_clear_sent()
	// only the second was sent: the first has no slash, the third no such computer; the point is left out
	testing.expect_value(t, len(roci.osc_sent_messages()), 1)
	testing.expect_value(t, len(roci.osc_sent_messages()[0].args), 1)
	ids := make([dynamic]string, context.temp_allocator)
	for e in p.errors {
		append(&ids, e.id == .Osc_Address_Bad ? "address" : e.id == .Osc_Unsupported ? "unsupported" : e.id == .Osc_Host_Unknown ? "host" : "other")
	}
	testing.expect_value(t, len(ids), 3)
	// a blob in a message that arrives is said at the handler, once, and the message still runs it
	roci.feed_osc([]u8{'/', 'b', 0, 0, ',', 'b', 'f', 0, 0, 0, 0, 3, 1, 2, 3, 0, 0x40, 0, 0, 0})
	roci.window(100, 100)
	roci.step()
	roci.step()
	testing.expect_value(t, as_number(global_named(p, "heard")), 1)
	said := 0
	for e in p.errors {
		if e.id == .Osc_Unsupported {
			said += 1
		}
	}
	testing.expect_value(t, said, 2) // the point, and the blob
	roci.feed_osc([]u8{'/', 'b', 0, 0, ',', 'b', 'f', 0, 0, 0, 0, 3, 1, 2, 3, 0, 0x40, 0, 0, 0})
	roci.step()
	said = 0
	for e in p.errors {
		if e.id == .Osc_Unsupported {
			said += 1
		}
	}
	testing.expect_value(t, said, 2) // not said again
}

// A port another program has is said where the sketch asked, and the sketch goes on.
@(test)
test_osc_port_busy_is_said :: proc(t: ^testing.T) {
	roci.set_osc_port_busy(true)
	defer roci.set_osc_port_busy(false)
	p := run_with_sounds(t, "osc_busy", "on osc [ print 1 ]\nosc listen 8000\n", "tests/sounds", {})
	defer finish(p)
	busy := 0
	for e in p.errors {
		if e.id == .Osc_Port_Busy {
			busy += 1
		}
	}
	testing.expect_value(t, busy, 2) // the implicit start on 9000, and the port asked for
	testing.expect_value(t, roci.osc_listening(), 0)
}

// The OSC example: dots are where `/xy` says, sized and colored by `/size` and `/hue`, and a click
// sends `/xy` to itself.
@(test)
test_the_osc_example_draws_what_arrives :: proc(t: ^testing.T) {
	text, read := os.read_entire_file("examples/osc/sketch.roci", context.temp_allocator)
	testing.expect(t, read == nil)
	p := run_with_sounds(t, "osc_example", string(text), "examples/osc", {})
	defer finish(p)
	defer roci.osc_clear_sent()
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, len(as_list(global_named(p, "dots")).items), 3)
	roci.feed_osc(packet("/size", f64(60)))
	roci.feed_osc(packet("/hue", f64(100)))
	roci.feed_osc(packet("/xy", f64(10), f64(90)))
	roci.feed_osc(packet("/xy", f64(10))) // one number is not a place
	roci.step()
	testing.expect_value(t, as_number(global_named(p, "size_now")), 60)
	testing.expectf(t, abs(as_number(global_named(p, "hue_now")) - 255) < 1e-9, "%v", as_number(global_named(p, "hue_now")))
	dots := as_list(global_named(p, "dots"))
	testing.expect_value(t, len(dots.items), 4)
	testing.expect(t, as_text(global_named(p, "last")) != "nothing has come yet")
	// a click sends the place back to the sketch itself
	w := roci.open_windows()[0]
	roci.step({platform.Mouse_Moved{window = platform.Window_Id(w), x = 320, y = 210}, click_event(w, 320, 210)})
	sent := roci.osc_sent_messages()
	testing.expect_value(t, len(sent), 1)
	testing.expect_value(t, sent[0].address, "/xy")
	testing.expect_value(t, sent[0].host, "localhost")
	testing.expect_value(t, sent[0].args[0].(f64), 50)
	testing.expect_value(t, sent[0].args[1].(f64), 50)
	// the dots fade away
	for _ in 0 ..< 151 {
		roci.step()
	}
	testing.expect_value(t, len(as_list(global_named(p, "dots")).items), 0)
	testing.expect_value(t, len(p.errors), 0)
}
