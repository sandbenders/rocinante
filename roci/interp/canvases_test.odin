// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "../gfx"
import "../lang"
import "core:testing"

@(test)
test_a_canvas_is_drawn_into_and_shown_like_a_picture :: proc(t: ^testing.T) {
	p := run_text(t, "c = canvas 160 120\ndraw into c [\n  circle at 10 10 radius 5\n  rect at 0 0 size 20 20\n]\nimage c at 30 40\nprint c.width\nprint c.height")
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, printed(p), "160\n120")
	picture := as_image(p.globals[0].value)
	canvas := gfx.canvas_of(picture)
	if testing.expect(t, canvas != nil) {
		testing.expect_value(t, len(canvas.list.commands), 2)
		testing.expect(t, canvas.pending)
	}
	found := image_commands()
	defer delete(found)
	if testing.expect_value(t, len(found), 1) {
		testing.expect_value(t, [4]f32{found[0].args[0], found[0].args[1], found[0].args[2], found[0].args[3]}, [4]f32{30, 40, 160, 120})
		testing.expect_value(t, gfx.Image_Id(found[0].args[4]), picture)
	}
	testing.expect_value(t, len(roci.recorded(first_window())), 1) // the window got only the image
}

@(test)
test_width_and_height_are_the_canvas_inside_draw_into_and_the_window_outside :: proc(t: ^testing.T) {
	p := run_text(t, "c = canvas 50 40\ndraw into c [ print width  print height ]\nprint (width > 100)")
	defer finish(p)
	testing.expect_value(t, printed(p), "50\n40\ntrue")
}

@(test)
test_a_canvas_keeps_what_each_frame_draws_into_it :: proc(t: ^testing.T) {
	p := run_text(t, "c = canvas 100 100\ndraw [ draw into c [ circle at (frame * 10) 50 radius 4 ] ]", 3)
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	picture := as_image(p.globals[0].value)
	// each frame's drawing is a round that waits for the graphics (a step closes it)
	testing.expect_value(t, len(gfx.canvas_of(picture).rounds), 3)
}

@(test)
test_each_draw_into_starts_from_the_default_style :: proc(t: ^testing.T) {
	p := run_text(t, "c = canvas 100 100\ndraw into c [ fill red  circle at 5 5 radius 2 ]\ndraw into c [ circle at 9 9 radius 2 ]")
	defer finish(p)
	canvas := gfx.canvas_of(as_image(p.globals[0].value))
	if testing.expect_value(t, len(canvas.list.commands), 2) {
		testing.expect_value(t, gfx.command_at(&canvas.list, 0).style.fill, roci.Colour{255, 0, 0, 255})
		testing.expect_value(t, gfx.command_at(&canvas.list, 1).style.fill, gfx.DEFAULT_STYLE.fill)
	}
}

@(test)
test_background_and_clear_inside_a_canvas_start_it_over_and_do_not_touch_the_window :: proc(t: ^testing.T) {
	p := run_text(t, "c = canvas 100 100\ndraw into c [ background 40 ]\ndraw into c [ clear ]")
	defer finish(p)
	canvas := gfx.canvas_of(as_image(p.globals[0].value))
	testing.expect(t, canvas.list.background_set)
	testing.expect_value(t, canvas.list.background, roci.Colour{0, 0, 0, 0})
	testing.expect(t, !the_window_list_has_background_set())
}

the_window_list_has_background_set :: proc() -> bool {
	windows := roci.open_windows()
	return len(windows) > 0 && roci.window_background_set(windows[0])
}

@(test)
test_a_picture_from_a_file_and_a_canvas_inside_a_canvas_cannot_be_drawn_into :: proc(t: ^testing.T) {
	p := run_text(t, "c = canvas 100 100\ndraw into c [ draw into c [ circle at 1 1 radius 1 ] ]\nd = canvas 10 10\nimage d at 0 0")
	defer finish(p)
	if testing.expect_value(t, len(p.errors), 1) {
		testing.expect_value(t, p.errors[0].id, lang.Message_Id.Not_A_Canvas)
		testing.expect(t, len(p.errors[0].args[1]) > 0)
	}
	// the outer block still ran and the sketch carried on
	testing.expect_value(t, len(image_commands()), 1)
}

@(test)
test_a_canvas_of_no_size_is_an_empty_picture_and_a_message :: proc(t: ^testing.T) {
	p := run_text(t, "c = canvas 0 100\nimage c at 0 0\ndraw into c [ circle at 1 1 radius 1 ]\nprint c.width")
	defer finish(p)
	ids: [dynamic]lang.Message_Id
	defer delete(ids)
	for e in p.errors {
		append(&ids, e.id)
	}
	testing.expect(t, len(ids) >= 1 && ids[0] == .Canvas_Size)
	found := image_commands()
	defer delete(found)
	testing.expect_value(t, len(found), 0)
}
