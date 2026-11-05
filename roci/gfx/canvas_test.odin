// SPDX-License-Identifier: 0BSD
package gfx

import "../maths"
import "core:testing"

@(test)
a_canvas_has_a_logical_size_and_no_pixels_of_its_own :: proc(t: ^testing.T) {
	defer images_stop()
	id, ok := image_add_canvas(300, 200, 2)
	testing.expect(t, ok && id != 0)
	w, h := image_size(id)
	testing.expect_value(t, [2]int{w, h}, [2]int{300, 200})
	data := image_data(id)
	testing.expect(t, data != nil && data.pixels == nil && data.canvas != nil)
	testing.expect(t, canvas_of(id) != nil)
	testing.expect_value(t, canvas_of(id).density, f32(2))
	loaded, _ := image_add_pixels(1, 1, {1, 2, 3, 4})
	testing.expect(t, canvas_of(loaded) == nil, "a loaded picture is not a canvas")
	testing.expect(t, canvas_of(0) == nil)
	testing.expect(t, canvas_of(Image_Id(987654)) == nil)
}

@(test)
a_canvas_of_no_size_or_a_silly_density_is_not_made :: proc(t: ^testing.T) {
	defer images_stop()
	for size in ([?][3]f32{{0, 10, 1}, {10, 0, 1}, {-5, 10, 1}, {MAX_IMAGE_SIDE + 1, 10, 1}, {10, 10, 0}, {10, 10, -1}, {10, 10, 9}}) {
		_, ok := image_add_canvas(int(size[0]), int(size[1]), size[2])
		testing.expectf(t, !ok, "%v was made", size)
	}
}

@(test)
a_canvas_texture_has_a_whole_number_of_pixels_that_covers_its_size :: proc(t: ^testing.T) {
	testing.expect_value(t, canvas_pixels(150, 2), u32(300))
	testing.expect_value(t, canvas_pixels(100, 1.5), u32(150))
	testing.expect_value(t, canvas_pixels(101, 1.5), u32(152)) // rounded up so every pixel is covered
	testing.expect_value(t, canvas_pixels(1, 0.4), u32(1))
	testing.expect_value(t, canvas_pixels(0, 2), u32(1))
}

@(test)
starting_to_draw_resets_the_style_and_keeps_what_was_drawn :: proc(t: ^testing.T) {
	defer images_stop()
	id, _ := image_add_canvas(50, 50, 1)
	c := canvas_of(id)
	set_fill(&c.list, {255, 0, 0, 255})
	move(&c.list, 10, 10)
	circle(&c.list, 5, 5, 3)
	c.list.span = Span{file = 1, line = 4}
	canvas_begin(c)
	testing.expect_value(t, c.list.style, DEFAULT_STYLE)
	testing.expect_value(t, c.list.transform, IDENTITY)
	testing.expect_value(t, c.list.span, Span{})
	testing.expect_value(t, len(c.list.commands), 1)
	rect(&c.list, 0, 0, 5, 5)
	testing.expect_value(t, len(c.list.commands), 2)
	testing.expect_value(t, command_at(&c.list, 1).style, DEFAULT_STYLE) // a new look, not the old fill
}

@(test)
a_round_is_closed_only_when_something_was_drawn_and_the_list_starts_empty_again :: proc(t: ^testing.T) {
	defer images_stop()
	id, _ := image_add_canvas(50, 50, 1)
	c := canvas_of(id)
	canvas_close_round(c)
	testing.expect_value(t, len(c.rounds), 0)
	circle(&c.list, 1, 1, 1)
	canvas_touch(c)
	canvas_close_round(c)
	testing.expect_value(t, len(c.rounds), 1)
	testing.expect_value(t, len(c.rounds[0].list.commands), 1)
	testing.expect_value(t, len(c.list.commands), 0)
	testing.expect(t, !c.pending)
	testing.expect_value(t, c.list.background, maths.Colour{0, 0, 0, 0})
	// another frame adds a second round, in order
	rect(&c.list, 1, 1, 1, 1)
	canvas_touch(c)
	canvas_close_round(c)
	testing.expect_value(t, len(c.rounds), 2)
	testing.expect_value(t, command_at(&c.rounds[1].list, 0).kind, Kind.Rect)
}

@(test)
a_round_that_starts_over_lets_go_of_the_rounds_before_it :: proc(t: ^testing.T) {
	defer images_stop()
	id, _ := image_add_canvas(50, 50, 1)
	c := canvas_of(id)
	for _ in 0 ..< 3 {
		circle(&c.list, 1, 1, 1)
		canvas_touch(c)
		canvas_close_round(c)
	}
	testing.expect_value(t, len(c.rounds), 3)
	background(&c.list, {10, 20, 30, 255})
	circle(&c.list, 2, 2, 2)
	canvas_touch(c)
	canvas_close_round(c)
	testing.expect_value(t, len(c.rounds), 1)
	testing.expect(t, c.rounds[0].list.background_set)
	testing.expect_value(t, c.rounds[0].list.background, maths.Colour{10, 20, 30, 255})
	testing.expect(t, !c.list.background_set, "the next round has set nothing yet")
	// `clear` starts over too
	clear_window(&c.list)
	canvas_touch(c)
	canvas_close_round(c)
	testing.expect_value(t, len(c.rounds), 1)
}

@(test)
the_old_picture_is_put_first_unless_the_round_starts_over :: proc(t: ^testing.T) {
	defer images_stop()
	id, _ := image_add_canvas(80, 60, 1)
	list: Command_List
	defer destroy(&list)
	circle(&list, 1, 1, 1)
	canvas_prepend_previous(&list, id, 80, 60)
	if testing.expect_value(t, len(list.commands), 2) {
		first := command_at(&list, 0)
		testing.expect_value(t, first.kind, Kind.Image)
		testing.expect_value(t, [4]f32{first.args[0], first.args[1], first.args[2], first.args[3]}, [4]f32{0, 0, 80, 60})
		testing.expect_value(t, Image_Id(first.args[4]), id)
		testing.expect_value(t, first.style, DEFAULT_STYLE)
		testing.expect_value(t, command_at(&list, 1).kind, Kind.Circle)
	}
	over: Command_List
	defer destroy(&over)
	background(&over, {0, 0, 0, 255})
	circle(&over, 1, 1, 1)
	canvas_prepend_previous(&over, id, 80, 60)
	testing.expect_value(t, len(over.commands), 1)
}

@(test)
the_background_is_set_by_background_a_gradient_and_clear_and_a_new_frame_forgets_it :: proc(t: ^testing.T) {
	list: Command_List
	defer destroy(&list)
	testing.expect(t, !list.background_set)
	background(&list, {1, 2, 3, 255})
	testing.expect(t, list.background_set)
	begin_frame(&list)
	testing.expect(t, !list.background_set)
	g := Gradient{count = 2}
	g.colours[0], g.colours[1] = {255, 0, 0, 255}, {0, 0, 255, 255}
	background_gradient(&list, g)
	testing.expect(t, list.background_set)
	begin_frame(&list)
	clear_window(&list)
	testing.expect(t, list.background_set)
	testing.expect_value(t, list.background, maths.Colour{0, 0, 0, 0})
}

@(test)
a_canvas_is_drawn_as_a_premultiplied_picture_and_a_loaded_one_is_not :: proc(t: ^testing.T) {
	defer images_stop()
	list: Command_List
	defer destroy(&list)
	batcher: Batcher
	defer batcher_destroy(&batcher)
	begin_frame(&list)
	canvas, _ := image_add_canvas(20, 20, 1)
	loaded, _ := image_add_pixels(1, 1, {9, 9, 9, 255})
	draw_image(&list, canvas, 0, 0, 20, 20)
	draw_image(&list, loaded, 0, 0, 20, 20)
	build(&batcher, &list, {100, 100})
	testing.expect_value(t, len(batcher.typeset), 2)
	testing.expect(t, batcher.typeset[0].premultiplied)
	testing.expect(t, !batcher.typeset[1].premultiplied)
}

@(test)
letting_go_of_the_pictures_lets_go_of_the_canvases_too :: proc(t: ^testing.T) {
	id, _ := image_add_canvas(10, 10, 1)
	c := canvas_of(id)
	circle(&c.list, 1, 1, 1)
	canvas_touch(c)
	canvas_close_round(c)
	circle(&c.list, 1, 1, 1)
	images_stop()
	testing.expect(t, canvas_of(id) == nil)
}
