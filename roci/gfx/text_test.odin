// SPDX-License-Identifier: 0BSD
package gfx

import "../maths"
import "core:math"
import "core:testing"

@(test)
test_debug_text_records_where_how_big_and_what :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	testing.expect(t, debug_text(&list, "hello", 10, 20, 2))
	testing.expect_value(t, len(list.commands), 1)
	c := command_at(&list, 0)
	testing.expect_value(t, c.kind, Kind.Text)
	// x, y, scale, width, height, offset, length
	testing.expect_value(t, c.args, [8]f32{10, 20, 2, 5 * 8 * 2, 8 * 2, 0, 5, 0})
	testing.expect_value(t, string(list.text[:]), "hello")
}

@(test)
test_the_default_size_is_two :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	debug_text(&list, "x", 0, 0)
	testing.expect_value(t, command_at(&list, 0).args[2], f32(2))
}

@(test)
test_texts_are_stored_end_to_end_and_found_by_offset :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	debug_text(&list, "abc", 0, 0)
	debug_text(&list, "de", 0, 20)
	testing.expect_value(t, string(list.text[:]), "abcde")
	testing.expect_value(t, command_at(&list, 1).args[5], f32(3))
	testing.expect_value(t, command_at(&list, 1).args[6], f32(2))
}

@(test)
test_empty_text_records_nothing_and_is_not_an_error :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	testing.expect(t, debug_text(&list, "", 0, 0))
	testing.expect_value(t, len(list.commands), 0)
}

@(test)
test_text_that_cannot_be_drawn_is_refused :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	nan := math.nan_f32()
	testing.expect(t, !debug_text(&list, "x", nan, 0))
	testing.expect(t, !debug_text(&list, "x", 0, math.inf_f32(1)))
	testing.expect(t, !debug_text(&list, "x", 0, 0, 0))
	testing.expect(t, !debug_text(&list, "x", 0, 0, -2))
	testing.expect(t, !debug_text(&list, "x", 0, 0, nan))
	testing.expect(t, !debug_text(&list, "x", 0, 0, 1000))
	testing.expect_value(t, len(list.commands), 0)
	testing.expect_value(t, len(list.text), 0) // nothing was kept
}

@(test)
test_a_frame_forgets_its_text :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	debug_text(&list, "abc", 0, 0)
	begin_frame(&list)
	testing.expect_value(t, len(list.text), 0)
	debug_text(&list, "z", 0, 0)
	testing.expect_value(t, command_at(&list, 0).args[5], f32(0))
}

@(test)
test_the_hash_follows_the_characters_the_place_and_the_size :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	debug_text(&list, "hello", 0, 0, 2)
	debug_text(&list, "hello", 0, 0, 2)
	debug_text(&list, "hellp", 0, 0, 2) // one character differs
	debug_text(&list, "hello", 1, 0, 2)
	debug_text(&list, "hello", 0, 0, 3)
	base := command_hash(command_at(&list, 0))
	testing.expect_value(t, command_hash(command_at(&list, 1)), base)
	for i in 2 ..< 5 {
		testing.expect(t, command_hash(command_at(&list, i)) != base)
	}
}

@(test)
test_text_shows_in_the_fill_colour_only :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	debug_text(&list, "hi", 0, 0)                // 0: filled by default
	no_fill(&list)
	set_stroke(&list, maths.grey(0))
	set_thickness(&list, 3)
	debug_text(&list, "hi", 0, 0)                // 1: an outline does not show text
	set_fill(&list, maths.grey(0))
	set_alpha(&list, 0)
	debug_text(&list, "hi", 0, 0)                // 2: fully transparent
	want := [?]bool{true, false, false}
	for w, i in want {
		testing.expectf(t, is_visible(command_at(&list, i)) == w, "command %d", i)
	}
}

@(test)
test_text_describes_its_box_and_name :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_fill(&list, maths.rgb(1, 2, 3))
	debug_text(&list, "ab\ncd", 5, 7, 1)
	d := describe(command_at(&list, 0))
	testing.expect_value(t, d.kind, Kind.Text)
	testing.expect_value(t, [4]f32{d.x, d.y, d.width, d.height}, [4]f32{5, 7, 16, 18})
	testing.expect_value(t, d.colour, maths.Colour{1, 2, 3, 255})
	testing.expect(t, d.visible)
	testing.expect_value(t, kind_name(.Text), "text")
}

// ---- the glyphs ----

@(test)
test_the_batcher_makes_one_glyph_per_visible_character :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_fill(&list, maths.rgb(255, 0, 0))
	set_alpha(&list, 127.5)
	debug_text(&list, "a b\nc", 10, 20, 2)
	b: Batcher
	defer batcher_destroy(&b)
	build(&b, &list)
	testing.expect_value(t, len(b.glyphs), 3) // the space draws nothing
	testing.expect_value(t, b.stats.glyphs, 3)
	testing.expect_value(t, len(b.batches), 1)
	testing.expect_value(t, b.batches[0].pipeline, Pipeline.Text)
	testing.expect_value(t, b.batches[0].count, 3)
	testing.expect_value(t, b.glyphs[0].glyph, u32(glyph_index('a')))
	testing.expect_value(t, b.glyphs[1].glyph, u32(glyph_index('b')))
	testing.expect_value(t, b.glyphs[2].glyph, u32(glyph_index('c')))
	testing.expect_value(t, b.glyphs[0].colour, [4]f32{1, 0, 0, 0.5})
	// a: the text's own place, with glyph pixels twice as big as the canvas's.
	testing.expect_value(t, b.glyphs[0].transform, [6]f32{2, 0, 0, 2, 10, 20})
	// b: two character cells along (2 * 2 * 8 = 32), c: a line down (10 * 2).
	testing.expect_value(t, b.glyphs[1].transform, [6]f32{2, 0, 0, 2, 10 + 32, 20})
	testing.expect_value(t, b.glyphs[2].transform, [6]f32{2, 0, 0, 2, 10, 20 + 20})
}

@(test)
test_the_transform_in_force_carries_the_text_with_it :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	move(&list, 100, 50)
	turn(&list, 90)
	debug_text(&list, "a", 0, 0, 1)
	b: Batcher
	defer batcher_destroy(&b)
	build(&b, &list)
	// Turned a quarter: the glyph's right is down on the canvas.
	testing.expect_value(t, b.glyphs[0].transform, [6]f32{0, 1, -1, 0, 100, 50})
}

@(test)
test_text_between_shapes_keeps_painting_order :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	circle(&list, 0, 0, 5)
	debug_text(&list, "hi", 0, 0)
	circle(&list, 0, 0, 5)
	b: Batcher
	defer batcher_destroy(&b)
	build(&b, &list)
	testing.expect_value(t, len(b.batches), 3)
	testing.expect_value(t, b.batches[1].pipeline, Pipeline.Text)
	testing.expect_value(t, b.batches[1].first, 0)
	testing.expect_value(t, b.batches[1].count, 2)
	testing.expect_value(t, b.batches[2].first, 1) // the second circle is the second instance
}

@(test)
test_a_text_of_only_spaces_is_skipped :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	debug_text(&list, "   \n ", 0, 0)
	b: Batcher
	defer batcher_destroy(&b)
	build(&b, &list)
	testing.expect_value(t, len(b.batches), 0)
	testing.expect_value(t, b.stats.skipped, 1)
}

@(test)
test_consecutive_texts_share_a_batch :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	debug_text(&list, "one", 0, 0)
	debug_text(&list, "two", 0, 20)
	b: Batcher
	defer batcher_destroy(&b)
	build(&b, &list)
	testing.expect_value(t, len(b.batches), 1)
	testing.expect_value(t, b.batches[0].count, 6)
}

@(test)
test_a_command_whose_text_is_not_there_makes_no_glyphs :: proc(t: ^testing.T) {
	out: [dynamic]Glyph_Instance
	defer delete(out)
	c := Command{kind = .Text, args = {0, 0, 1, 8, 8, 5, 3, 0}, style = DEFAULT_STYLE}
	glyphs_add_command(&out, c, transmute([]u8)string("abc")) // offset 5 is past the end
	c.args[5] = -1
	glyphs_add_command(&out, c, transmute([]u8)string("abc"))
	c.args[5], c.args[6] = 0, 0
	glyphs_add_command(&out, c, transmute([]u8)string("abc"))
	testing.expect_value(t, len(out), 0)
}

@(test)
test_the_glyph_instance_is_48_bytes :: proc(t: ^testing.T) {
	testing.expect_value(t, size_of(Glyph_Instance), 48)
}
