// SPDX-License-Identifier: 0BSD
package roci

import "core:testing"
import "gfx"

@(test)
test_a_canvas_is_made_at_the_density_of_a_headless_sketch_and_a_silly_size_is_refused :: proc(t: ^testing.T) {
	begin()
	defer finish()
	c, ok := canvas(300, 200)
	testing.expect(t, ok && c != 0)
	testing.expect_value(t, image_size(c), [2]f64{300, 200})
	testing.expect_value(t, gfx.canvas_of(c).density, HEADLESS_CANVAS_DENSITY)
	_, bad := canvas(0, 10)
	testing.expect(t, !bad)
	_, bad = canvas(10, 99999)
	testing.expect(t, !bad)
}

@(test)
test_drawing_into_a_canvas_records_onto_it_and_not_onto_the_window :: proc(t: ^testing.T) {
	begin()
	defer finish()
	c, _ := canvas(100, 80)
	circle(1, 1, 1) // the window
	testing.expect(t, begin_into(c))
	testing.expect(t, is_drawing_into())
	rect(0, 0, 10, 10)
	fill(Colour{255, 0, 0, 255})
	circle(5, 5, 2)
	end_into()
	testing.expect(t, !is_drawing_into())
	circle(2, 2, 2) // the window again
	list := &the.windows[0].list
	testing.expect_value(t, len(list.commands), 2)
	inside := gfx.canvas_of(c)
	testing.expect_value(t, len(inside.list.commands), 2)
	testing.expect_value(t, gfx.command_at(&inside.list, 1).style.fill, Colour{255, 0, 0, 255})
	testing.expect(t, inside.pending, "something was drawn, so the canvas has a round to draw")
}

@(test)
test_each_draw_into_starts_from_the_default_style_and_a_canvas_keeps_its_commands :: proc(t: ^testing.T) {
	begin()
	defer finish()
	c, _ := canvas(100, 80)
	testing.expect(t, begin_into(c))
	fill(Colour{255, 0, 0, 255})
	move(30, 30)
	rect(0, 0, 5, 5)
	end_into()
	testing.expect(t, begin_into(c))
	rect(0, 0, 5, 5)
	end_into()
	inside := gfx.canvas_of(c)
	testing.expect_value(t, len(inside.list.commands), 2)
	second := gfx.command_at(&inside.list, 1)
	testing.expect_value(t, second.style, gfx.DEFAULT_STYLE)
	testing.expect_value(t, second.transform, gfx.IDENTITY)
}

@(test)
test_only_a_canvas_can_be_drawn_into_and_never_from_inside_another_draw_into :: proc(t: ^testing.T) {
	begin()
	defer finish()
	loaded, _ := add_image_pixels(2, 2, make([]u8, 16, context.temp_allocator))
	testing.expect(t, !begin_into(loaded))
	testing.expect(t, !begin_into(Image(0)))
	testing.expect(t, !begin_into(Image(31337)))
	a, _ := canvas(10, 10)
	b, _ := canvas(10, 10)
	testing.expect(t, begin_into(a))
	testing.expect(t, !begin_into(b))
	testing.expect(t, !begin_into(a))
	end_into()
	testing.expect(t, begin_into(b))
	end_into()
}

@(test)
test_draw_into_runs_a_block_with_the_canvas_as_the_surface :: proc(t: ^testing.T) {
	begin()
	defer finish()
	c, _ := canvas(120, 90)
	testing.expect_value(t, width(), f64(DEFAULT_WIDTH))
	seen: [2]f64
	@(static) size_inside: ^[2]f64
	size_inside = &seen
	ran := draw_into(c, proc() {
		size_inside^ = {width(), height()}
		circle(1, 1, 1)
	})
	testing.expect(t, ran)
	testing.expect_value(t, seen, [2]f64{120, 90})
	testing.expect_value(t, width(), f64(DEFAULT_WIDTH))
	loaded, _ := add_image_pixels(1, 1, {1, 2, 3, 4})
	testing.expect(t, !draw_into(loaded, proc() {}))
}

@(test)
test_a_canvas_nothing_was_drawn_into_has_no_round_and_headless_rounds_wait_to_be_drawn :: proc(t: ^testing.T) {
	begin()
	defer finish()
	c, _ := canvas(40, 40)
	testing.expect(t, begin_into(c))
	end_into()
	testing.expect(t, !gfx.canvas_of(c).pending)
	testing.expect(t, begin_into(c))
	circle(1, 1, 1)
	end_into()
	flush_canvases(nil) // no graphics: the round is closed and kept
	inside := gfx.canvas_of(c)
	testing.expect_value(t, len(inside.rounds), 1)
	testing.expect_value(t, len(inside.list.commands), 0)
	testing.expect(t, begin_into(c))
	clear_window()
	end_into()
	flush_canvases(nil)
	testing.expect_value(t, len(inside.rounds), 1) // starting over lets the earlier round go
}

@(test)
test_a_step_closes_the_rounds_of_a_headless_sketch :: proc(t: ^testing.T) {
	begin()
	defer finish()
	c, _ := canvas(40, 40)
	circle(5, 5, 5)
	draw(proc() {})
	_ = draw_into(c, proc() {circle(1, 1, 1)})
	step()
	testing.expect_value(t, len(gfx.canvas_of(c).rounds), 1)
}

@(test)
test_the_c_functions_for_canvases :: proc(t: ^testing.T) {
	begin()
	defer finish()
	c := abi_canvas(64, 48)
	testing.expect(t, c != 0)
	testing.expect_value(t, abi_image_width(c), f64(64))
	testing.expect_value(t, abi_canvas(0, 5), i32(0))
	testing.expect_value(t, abi_begin_into(c), i32(1))
	testing.expect_value(t, abi_begin_into(c), i32(0))
	abi_circle(5, 5, 2)
	abi_end_into()
	testing.expect_value(t, len(gfx.canvas_of(Image(c)).list.commands), 1)
	testing.expect_value(t, abi_begin_into(0), i32(0))
}
