// SPDX-License-Identifier: 0BSD
package platform

import "core:sync"
import "core:testing"
import "core:time"

// What a test's stand-in for a device was sent, with a lock, since the clock sends from its own thread.
@(private = "file")
Heard :: struct {
	lock:  sync.Mutex,
	bytes: [dynamic]u8,
	ticks: int,
}

@(private = "file")
hear :: proc(data: rawptr, bytes: []u8) {
	heard := (^Heard)(data)
	sync.guard(&heard.lock)
	append(&heard.bytes, ..bytes)
	for b in bytes {
		if b == 0xF8 {
			heard.ticks += 1
		}
	}
}

@(private = "file")
listening :: proc(heard: ^Heard) -> ^Midi_Out {
	out := open_midi_out()
	out.sink = hear
	out.sink_data = heard
	return out
}

@(test)
test_midi_pick_chooses_an_output_by_part_of_its_name :: proc(t: ^testing.T) {
	names := []string{"IAC Driver Bus 1", "Roland Digital Piano", "microKEY-25"}
	testing.expect_value(t, midi_pick(names, ""), 0) // the first when none is named
	testing.expect_value(t, midi_pick(names, "roland"), 1) // any case, any part
	testing.expect_value(t, midi_pick(names, "KEY"), 2)
	testing.expect_value(t, midi_pick(names, "bus 1"), 0)
	testing.expect_value(t, midi_pick(names, "i"), 0) // the first that holds it
	testing.expect_value(t, midi_pick(names, "yamaha"), -1)
	testing.expect_value(t, midi_pick(nil, ""), -1)
	testing.expect_value(t, midi_pick(nil, "x"), -1)
}

@(test)
test_midi_messages_go_to_the_device_whole :: proc(t: ^testing.T) {
	heard: Heard
	defer delete(heard.bytes)
	out := listening(&heard)
	defer close_midi_out(out)
	testing.expect_value(t, midi_send(out, "", {0x90, 60, 100}), Midi_Send_Result.Sent)
	testing.expect_value(t, midi_send(out, "", {0xC0, 5}), Midi_Send_Result.Sent)
	testing.expect_value(t, midi_send(out, "", {0xFA}), Midi_Send_Result.Sent)
	testing.expect_value(t, string(heard.bytes[:]), "\x90\x3c\x64\xc0\x05\xfa")
	// nothing, and more than a short message, is refused
	testing.expect_value(t, midi_send(out, "", nil), Midi_Send_Result.Not_Sent)
	testing.expect_value(t, midi_send(out, "", {1, 2, 3, 4}), Midi_Send_Result.Not_Sent)
	testing.expect_value(t, len(heard.bytes), 6)
}

@(test)
test_midi_clock_ticks_24_a_beat_at_the_tempo_given :: proc(t: ^testing.T) {
	heard: Heard
	defer delete(heard.bytes)
	out := listening(&heard)
	defer close_midi_out(out)
	testing.expect(t, !midi_clock_running(out))
	// 150 beats a minute is 60 ticks a second
	midi_clock_start(out, "", 150)
	testing.expect(t, midi_clock_running(out))
	time.sleep(500 * time.Millisecond)
	midi_clock_stop(out)
	testing.expect(t, !midi_clock_running(out))
	sync.lock(&heard.lock)
	ticks := heard.ticks
	first, last := heard.bytes[0], heard.bytes[len(heard.bytes) - 1]
	sync.unlock(&heard.lock)
	testing.expectf(t, ticks >= 26 && ticks <= 33, "half a second at 150 is 30 ticks: %d", ticks)
	testing.expect_value(t, first, u8(0xFA)) // Start first
	testing.expect_value(t, last, u8(0xFC)) // Stop last
	// stopped, no more come
	time.sleep(100 * time.Millisecond)
	sync.lock(&heard.lock)
	testing.expect_value(t, heard.ticks, ticks)
	sync.unlock(&heard.lock)
	// stopping what does not run sends nothing
	before := len(heard.bytes)
	midi_clock_stop(out)
	testing.expect_value(t, len(heard.bytes), before)
}

@(test)
test_midi_clock_changes_tempo_while_it_runs_and_keeps_it_in_range :: proc(t: ^testing.T) {
	heard: Heard
	defer delete(heard.bytes)
	out := listening(&heard)
	defer close_midi_out(out)
	midi_clock_start(out, "", 60) // 24 ticks a second
	time.sleep(300 * time.Millisecond)
	midi_clock_start(out, "", 240) // starting again only changes the tempo: 96 ticks a second
	time.sleep(500 * time.Millisecond)
	midi_clock_stop(out)
	sync.lock(&heard.lock)
	ticks := heard.ticks
	starts := 0
	for b in heard.bytes {
		starts += int(b == 0xFA)
	}
	sync.unlock(&heard.lock)
	// about 7 ticks of the slow part and 48 of the fast one
	testing.expectf(t, ticks >= 45 && ticks <= 65, "ticks %d", ticks)
	testing.expect_value(t, starts, 1)
	// the tempo is kept from 20 to 300, and a number that is not one is 120
	midi_clock_tempo(out, 5)
	testing.expect_value(t, transmute(f64)sync.atomic_load(&out.clock.tempo), 20.0)
	midi_clock_tempo(out, 9000)
	testing.expect_value(t, transmute(f64)sync.atomic_load(&out.clock.tempo), 300.0)
	nan := 0.0
	nan /= nan
	midi_clock_tempo(out, nan)
	testing.expect_value(t, transmute(f64)sync.atomic_load(&out.clock.tempo), 120.0)
}

@(test)
test_a_clock_is_ended_with_the_output_that_made_it :: proc(t: ^testing.T) {
	for _ in 0 ..< 5 {
		heard: Heard
		out := listening(&heard)
		midi_clock_start(out, "x", 200)
		time.sleep(20 * time.Millisecond)
		close_midi_out(out) // joins the thread before anything is freed
		delete(heard.bytes)
	}
}

@(test)
test_midi_out_with_no_device_says_so :: proc(t: ^testing.T) {
	out := open_midi_out()
	defer close_midi_out(out)
	// no output is named like this one, whatever the computer has
	testing.expect_value(t, midi_send(out, "no such output at all 7f3a", {0x90, 60, 100}), Midi_Send_Result.No_Device)
	names := midi_out_names(out)
	defer {
		for n in names {
			delete(n)
		}
		delete(names)
	}
	for n in names {
		testing.expect(t, n != "no such output at all 7f3a")
	}
}
