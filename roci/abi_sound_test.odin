// SPDX-License-Identifier: 0BSD
package roci

import "core:c"
import "core:os"
import "core:testing"

@(test)
test_abi_sounds :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	testing.expect_value(t, abi_load_sound(nil, 10), 0)
	testing.expect_value(t, abi_load_sound_file("tests/sounds/none.wav"), 0)
	not_sound := [4]u8{1, 2, 3, 4}
	testing.expect_value(t, abi_load_sound(raw_data(not_sound[:]), 4), 0)
	data, _ := os.read_entire_file_from_path("tests/sounds/tone.mp3", context.temp_allocator)
	from_bytes := abi_load_sound(raw_data(data), c.int(len(data)))
	testing.expect(t, from_bytes != 0)
	s := abi_load_sound_file("tests/sounds/tone.wav")
	testing.expect(t, s != 0 && s != from_bytes)
	testing.expect_value(t, abi_sound_length(s), 0.25)
	testing.expect_value(t, abi_sound_playing(s), 0)
	abi_set_sound_volume(s, 25)
	abi_set_sound_pan(s, -60)
	abi_set_sound_speed(s, 0.5)
	testing.expect_value(t, abi_sound_volume(s), 25)
	testing.expect_value(t, abi_sound_pan(s), -60)
	testing.expect_value(t, abi_sound_speed(s), 0.5)
	abi_loop(s)
	testing.expect_value(t, abi_sound_playing(s), 1)
	testing.expect_value(t, abi_sound_loops(s), 1)
	step(nil, 0.2)
	testing.expectf(t, abs(abi_sound_at(s) - 0.1) < 1e-9, "at %v", abi_sound_at(s))
	abi_forward_sound(s, 0.1)
	abi_rewind_by(s, 0.05)
	testing.expectf(t, abs(abi_sound_at(s) - 0.15) < 1e-9, "at %v", abi_sound_at(s))
	abi_set_sound_at(s, 0.2)
	testing.expectf(t, abs(abi_sound_at(s) - 0.2) < 1e-9, "at %v", abi_sound_at(s))
	abi_rewind(s)
	testing.expect_value(t, abi_sound_at(s), 0)
	abi_set_sound_loop(s, 0)
	testing.expect_value(t, abi_sound_loops(s), 0)
	abi_pause(s)
	testing.expect_value(t, abi_sound_playing(s), 0)
	abi_play(s)
	testing.expect_value(t, abi_sound_playing(s), 1)
	step(nil, 1)
	testing.expect_value(t, abi_sound_playing(s), 0)
	// no sound answers every question with 0
	testing.expect_value(t, abi_sound_length(0), 0)
	testing.expect_value(t, abi_sound_volume(77), 0)
}
