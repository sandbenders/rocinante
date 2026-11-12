// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "../platform"
import "core:testing"

// The ports of Processing's classic examples that only draw: each runs for a while without a
// runtime error and draws something.
@(test)
test_the_processing_ports_that_only_draw_run_without_a_runtime_error :: proc(t: ^testing.T) {
	for name in ([]string{"bounce", "sinewave", "koch", "mandelbrot", "noisewave", "recursion", "colorwheel", "flocking"}) {
		p := run_text(t, example_text(name), 90, untimed = true)
		testing.expectf(t, len(p.errors) == 0, "%s hit a runtime error", name)
		testing.expectf(t, len(roci.recorded(first_window())) > 0, "%s drew too little", name)
		finish(p)
	}
}

// The ball turns round at every edge and never leaves the window.
@(test)
test_the_bounce_example_keeps_the_ball_inside_the_window :: proc(t: ^testing.T) {
	p := run_text(t, example_text("bounce"), 0)
	defer finish(p)
	for _ in 0 ..< 600 {
		roci.step({})
		ball := as_record(global_named(p, "ball")).fields[0]
		pos := as_pair(ball)
		if pos.x < 24 - 1e-9 || pos.x > 456 + 1e-9 || pos.y < 24 - 1e-9 || pos.y > 296 + 1e-9 {
			testing.expectf(t, false, "the ball left the window at %v", pos)
			return
		}
	}
	testing.expect_value(t, len(p.errors), 0)
}

// Every segment stays one length from the one before it, the first from the mouse, and a mouse left
// still for a second stops leading.
@(test)
test_the_rope_example_drags_a_rope_behind_the_mouse :: proc(t: ^testing.T) {
	p := run_text(t, example_text("rope"), 0)
	defer finish(p)
	w := first_window()
	id := platform.Window_Id(w)
	for _ in 0 ..< 3 {
		roci.step({platform.Mouse_Moved{window = id, x = 300, y = 200}})
	}
	rope := as_list(global_named(p, "rope"))
	testing.expect_value(t, len(rope.items), 22)
	head := as_pair(as_record(rope.items[0]).fields[0])
	reach := head - [2]f64{300, 200}
	testing.expect(t, abs(reach.x * reach.x + reach.y * reach.y - 289) < 1e-6, "the first segment is one length from the mouse")
	for i in 1 ..< len(rope.items) {
		before := as_pair(as_record(rope.items[i - 1]).fields[0])
		here := as_pair(as_record(rope.items[i]).fields[0])
		gap := before - here
		testing.expectf(t, abs(gap.x * gap.x + gap.y * gap.y - 289) < 1e-6, "segment %d is not one length from the one before it", i + 1)
	}
	testing.expect_value(t, len(p.errors), 0)

	// Left alone for a second the mouse stops leading: the rope goes round the window by itself.
	for _ in 0 ..< 80 {
		roci.step({})
	}
	led := as_pair(as_record(rope.items[0]).fields[0])
	away := led - [2]f64{300, 200}
	testing.expect(t, away.x * away.x + away.y * away.y > 40 * 40, "the rope leaves the still mouse")
}

// Life: three live cells in a row turn into three in a column after one step, a click brings
// the cells round it to life, and the grid wraps round its edges.
@(test)
test_the_life_example_turns_a_blinker_and_takes_clicks :: proc(t: ^testing.T) {
	p := run_text(t, example_text("life"), 0)
	defer finish(p)
	w := first_window()
	cells := as_list(global_named(p, "cells"))
	testing.expect_value(t, len(cells.items), 48 * 32)
	set :: proc(cells: ^List, column, row: int, alive: bool) {
		as_record(cells.items[row * 48 + column]).fields[0] = alive
	}
	is_alive :: proc(cells: ^List, column, row: int) -> bool {
		alive, _ := as_record(cells.items[row * 48 + column]).fields[0].(bool)
		return alive
	}
	count_alive :: proc(cells: ^List) -> (n: int) {
		for item in cells.items {
			alive, _ := as_record(item).fields[0].(bool)
			n += int(alive)
		}
		return
	}
	for i in 0 ..< len(cells.items) {
		as_record(cells.items[i]).fields[0] = false
	}
	for column in 10 ..= 12 {
		set(cells, column, 10, true)
	}
	step_to_generation(p, 1)
	testing.expect_value(t, as_number(global_named(p, "generation")), 1)
	testing.expect_value(t, count_alive(cells), 3)
	for row in 9 ..= 11 {
		testing.expectf(t, is_alive(cells, 11, row), "the blinker is upright: row %d", row)
	}

	// A click brings the nine cells round the mouse to life.
	for i in 0 ..< len(cells.items) {
		as_record(cells.items[i]).fields[0] = false
	}
	roci.step({platform.Mouse_Moved{window = platform.Window_Id(w), x = 255, y = 155}, click_event(w, 255, 155)})
	testing.expect_value(t, count_alive(cells), 9)
	testing.expect(t, is_alive(cells, 25, 15) && is_alive(cells, 24, 14) && is_alive(cells, 26, 16), "the nine cells")

	// A cell in a corner has neighbors across the edges: three live cells round the corner
	// make it alive.
	for i in 0 ..< len(cells.items) {
		as_record(cells.items[i]).fields[0] = false
	}
	set(cells, 47, 0, true)
	set(cells, 0, 31, true)
	set(cells, 47, 31, true)
	step_to_generation(p, 2)
	testing.expect(t, is_alive(cells, 0, 0), "the corner cell comes alive from its wrapped neighbors")
	testing.expect_value(t, len(p.errors), 0)
}

// Frames until the sketch has worked out this many generations (it steps every four frames).
step_to_generation :: proc(p: ^Interp, generation: f64) {
	for _ in 0 ..< 12 {
		if as_number(global_named(p, "generation")) >= generation {
			return
		}
		roci.step({})
	}
}

// The flock stays inside its speed limits, wraps round the window, and a click scatters it.
@(test)
test_the_flocking_example_wraps_round_and_scatters_on_a_click :: proc(t: ^testing.T) {
	p := run_text(t, example_text("flocking"), 0, untimed = true)
	defer finish(p)
	w := first_window()
	flock := as_list(global_named(p, "flock"))
	testing.expect_value(t, len(flock.items), 60)
	bird_at :: proc(flock: ^List, i: int) -> (pos, vel: [2]f64) {
		record := as_record(flock.items[i])
		return as_pair(record.fields[0]), as_pair(record.fields[1])
	}
	for _ in 0 ..< 60 {
		roci.step({})
	}
	for i in 0 ..< len(flock.items) {
		pos, vel := bird_at(flock, i)
		speed := vel.x * vel.x + vel.y * vel.y
		testing.expectf(t, speed <= 9 + 1e-9 && speed >= 2.25 - 1e-9, "bird %d speed squared %v", i + 1, speed)
		testing.expectf(t, pos.x >= 0 && pos.x <= 480 && pos.y >= 0 && pos.y <= 320, "bird %d left the window at %v", i + 1, pos)
	}
	_, before := bird_at(flock, 0)
	roci.step({platform.Mouse_Moved{window = platform.Window_Id(w), x = 10, y = 10}, click_event(w, 10, 10)})
	_, after := bird_at(flock, 0)
	testing.expect(t, before != after, "a click gives the birds new velocities")
	testing.expect_value(t, len(p.errors), 0)
}
