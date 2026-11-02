// SPDX-License-Identifier: 0BSD
package gfx

import "core:os"
import "core:testing"

@(test)
measuring_text_gives_a_size_that_grows_with_the_text_and_the_size :: proc(t: ^testing.T) {
	w1, h1 := measure_typeset(FACE_DEFAULT, 20, .Left, "ab")
	w2, _ := measure_typeset(FACE_DEFAULT, 20, .Left, "abab")
	w3, h3 := measure_typeset(FACE_DEFAULT, 40, .Left, "ab")
	testing.expect(t, w1 > 0 && h1 > 0)
	testing.expect(t, w2 > w1)
	testing.expect(t, w3 > w1 && h3 > h1)
}

@(test)
a_wrapped_text_is_narrower_and_taller_than_the_same_text_on_one_line :: proc(t: ^testing.T) {
	text := "the quick brown fox jumps over the lazy dog"
	w_open, h_open := measure_typeset(FACE_DEFAULT, 20, .Left, text)
	w_wrapped, h_wrapped := measure_typeset(FACE_DEFAULT, 20, .Left, text, 150)
	testing.expect(t, w_wrapped <= 150 && w_wrapped < w_open)
	testing.expect(t, h_wrapped > h_open)
}

@(test)
no_text_and_unknown_faces_measure_as_nothing :: proc(t: ^testing.T) {
	w, h := measure_typeset(FACE_DEFAULT, 20, .Left, "")
	testing.expect(t, w == 0 && h == 0)
	w, h = measure_typeset(500, 20, .Left, "abc")
	testing.expect(t, w == 0 && h == 0)
}

@(test)
a_line_break_makes_a_second_line :: proc(t: ^testing.T) {
	_, h1 := measure_typeset(FACE_DEFAULT, 20, .Left, "ab")
	_, h2 := measure_typeset(FACE_DEFAULT, 20, .Left, "ab\ncd")
	testing.expect(t, h2 > h1 * 3 / 2)
}

@(test)
leading_sets_the_distance_between_lines_as_a_multiple_of_the_size :: proc(t: ^testing.T) {
	_, own := measure_typeset(FACE_DEFAULT, 20, .Left, "a\nb\nc")
	_, tight := measure_typeset(FACE_DEFAULT, 20, .Left, "a\nb\nc", 0, 1)
	_, loose := measure_typeset(FACE_DEFAULT, 20, .Left, "a\nb\nc", 0, 2)
	_, zero := measure_typeset(FACE_DEFAULT, 20, .Left, "a\nb\nc", 0, 0)
	testing.expect_value(t, zero, own) // 0 is the font's own spacing
	testing.expect(t, tight < own && own < loose)
	// two sizes apart: each of the three lines is a box 2 * 20 pixels tall
	testing.expect_value(t, loose, f32(120))
	// a line's box is the leading too, so one line is as tall as that
	_, once := measure_typeset(FACE_DEFAULT, 20, .Left, "a", 0, 2)
	testing.expect_value(t, once, f32(40))
}

@(test)
leading_is_part_of_the_style_and_clamped :: proc(t: ^testing.T) {
	list: Command_List
	defer destroy(&list)
	begin_frame(&list)
	set_leading(&list, 1.5)
	testing.expect_value(t, list.style.leading, f32(1.5))
	set_leading(&list, -3)
	testing.expect_value(t, list.style.leading, f32(0))
	set_leading(&list, 1000)
	testing.expect_value(t, list.style.leading, MAX_LEADING)
	set_leading(&list, 1.25)
	set_leading(&list, max(f32)*max(f32)) // not finite: nothing changes
	testing.expect_value(t, list.style.leading, f32(1.25))
	typeset(&list, "a\nb", 0, 0)
	batcher: Batcher
	defer batcher_destroy(&batcher)
	build(&batcher, &list, {100, 100})
	testing.expect_value(t, batcher.typeset[0].leading, f32(1.25))
	// the same text with another leading is another text
	other := batcher.typeset[0]
	other.leading = 2
	testing.expect(t, text_key(other, 20, 0) != text_key(batcher.typeset[0], 20, 0))
}

@(test)
the_two_built_in_faces_are_there_by_name :: proc(t: ^testing.T) {
	face, ok := find_face("Inter")
	testing.expect(t, ok && face == FACE_DEFAULT)
	face, ok = find_face("Inter Bold")
	testing.expect(t, ok && face == FACE_BOLD)
	_, ok = find_face("Nothing Like It")
	testing.expect(t, !ok)
}

@(test)
bytes_that_are_not_a_font_are_not_a_face :: proc(t: ^testing.T) {
	_, ok := add_face("Junk", {1, 2, 3, 4, 5, 6, 7, 8})
	testing.expect(t, !ok)
	_, found := find_face("Junk")
	testing.expect(t, !found)
}

@(test)
a_font_file_can_be_added_as_a_face_and_used :: proc(t: ^testing.T) {
	face, ok := add_face("Inter again", INTER_REGULAR)
	testing.expect(t, ok && face > FACE_BOLD)
	found, was_found := find_face("Inter again")
	testing.expect(t, was_found && found == face)
	w, _ := measure_typeset(face, 20, .Left, "abc")
	w_built_in, _ := measure_typeset(FACE_DEFAULT, 20, .Left, "abc")
	testing.expect_value(t, w, w_built_in)
}

@(test)
typeset_records_a_command_with_its_size_and_the_text_in_the_list :: proc(t: ^testing.T) {
	list: Command_List
	defer destroy(&list)
	begin_frame(&list)
	set_font_size(&list, 30)
	testing.expect(t, typeset(&list, "hello", 10, 20))
	testing.expect_value(t, len(list.commands), 1)
	c := command_at(&list, 0)
	testing.expect_value(t, c.kind, Kind.Typeset)
	testing.expect_value(t, c.args[0], f32(10))
	testing.expect_value(t, c.args[1], f32(20))
	testing.expect(t, c.args[3] > 0 && c.args[4] > 0, "its size is measured when it is recorded")
	testing.expect_value(t, c.style.font_size, f32(30))
	testing.expect_value(t, string(list.text[:]), "hello")
}

@(test)
typeset_of_nothing_or_not_a_number_records_nothing :: proc(t: ^testing.T) {
	list: Command_List
	defer destroy(&list)
	begin_frame(&list)
	testing.expect(t, typeset(&list, "", 0, 0), "empty text is fine")
	testing.expect_value(t, len(list.commands), 0)
	testing.expect(t, !typeset(&list, "x", math_nan(), 0))
	testing.expect(t, !typeset(&list, "x", 0, 0, math_nan()))
	testing.expect_value(t, len(list.commands), 0)
}

math_nan :: proc() -> f32 {
	zero: f32
	return zero / zero
}

@(test)
bad_sizes_are_ignored_and_big_ones_capped :: proc(t: ^testing.T) {
	list: Command_List
	defer destroy(&list)
	begin_frame(&list)
	set_font_size(&list, 0)
	set_font_size(&list, -5)
	set_font_size(&list, math_nan())
	testing.expect_value(t, list.style.font_size, DEFAULT_FONT_SIZE)
	set_font_size(&list, 1e9)
	testing.expect_value(t, list.style.font_size, MAX_FONT_SIZE)
}

@(test)
every_frame_starts_with_the_default_face_size_and_alignment :: proc(t: ^testing.T) {
	list: Command_List
	defer destroy(&list)
	begin_frame(&list)
	set_font(&list, FACE_BOLD)
	set_font_size(&list, 50)
	set_align(&list, .Right)
	begin_frame(&list)
	testing.expect_value(t, list.style.font, FACE_DEFAULT)
	testing.expect_value(t, list.style.font_size, DEFAULT_FONT_SIZE)
	testing.expect_value(t, list.style.align, Align.Left)
}

@(test)
face_size_and_alignment_are_part_of_a_commands_hash :: proc(t: ^testing.T) {
	list: Command_List
	defer destroy(&list)
	begin_frame(&list)
	typeset(&list, "same", 0, 0)
	set_font(&list, FACE_BOLD)
	typeset(&list, "same", 0, 0)
	begin_frame(&list)
	typeset(&list, "same", 0, 0)
	set_font_size(&list, 31)
	typeset(&list, "same", 0, 0)
	begin_frame(&list)
	typeset(&list, "same", 0, 0)
	set_align(&list, .Center)
	typeset(&list, "same", 0, 0)
	// compared per frame through look hashes
	first := command_hash(command_at(&list, 0))
	second := command_hash(command_at(&list, 1))
	testing.expect(t, first != second)
}

@(test)
text_is_drawn_by_the_typeset_pipeline_one_item_for_each_command :: proc(t: ^testing.T) {
	list: Command_List
	defer destroy(&list)
	batcher: Batcher
	defer batcher_destroy(&batcher)
	begin_frame(&list)
	set_fill(&list, {200, 100, 50, 255})
	typeset(&list, "one", 5, 6)
	typeset(&list, "two", 7, 8, 100)
	build(&batcher, &list, {200, 100})
	testing.expect_value(t, len(batcher.batches), 1)
	testing.expect_value(t, batcher.batches[0].pipeline, Pipeline.Typeset)
	testing.expect_value(t, batcher.batches[0].count, 2)
	testing.expect_value(t, len(batcher.typeset), 2)
	item := batcher.typeset[1]
	testing.expect_value(t, item.text, "two")
	testing.expect_value(t, item.wrap, f32(100))
	testing.expect_value(t, item.colour[0], f32(200) / 255)
}

@(test)
transparent_or_unfilled_text_draws_nothing :: proc(t: ^testing.T) {
	list: Command_List
	defer destroy(&list)
	batcher: Batcher
	defer batcher_destroy(&batcher)
	begin_frame(&list)
	no_fill(&list)
	typeset(&list, "invisible", 0, 0)
	set_fill(&list, {0, 0, 0, 255})
	set_alpha(&list, 0)
	typeset(&list, "gone", 0, 0)
	build(&batcher, &list, {100, 100})
	testing.expect_value(t, len(batcher.typeset), 0)
	testing.expect_value(t, batcher.stats.skipped, 2)
}

@(test)
system_fallback_fonts_that_exist_are_added_and_the_rest_are_skipped :: proc(t: ^testing.T) {
	testing.expect(t, fonts_start())
	any_there := false
	for file in FALLBACK_FONT_FILES {
		any_there ||= os.exists(file)
	}
	testing.expect_value(t, len(fonts.fallback_paths) > 0, any_there)
	// a character Inter has not is still measured, with a fallback's glyph or the empty box
	w, h := measure_typeset(FACE_DEFAULT, 20, .Left, "\xe6\x97\xa5")
	testing.expect(t, w > 0 && h > 0)
}

@(test)
emoji_are_swapped_for_an_em_space_with_their_joiners_and_flags_kept_whole :: proc(t: ^testing.T) {
	testing.expect(t, fonts_start())
	plain, none := split_emoji("no emoji here", context.temp_allocator)
	testing.expect_value(t, plain, "no emoji here")
	testing.expect_value(t, len(none), 0)

	// a face, a thumbs up with a skin tone, a family joined by joiners, a flag
	text := "a\U0001F642b\U0001F44D\U0001F3FDc\U0001F468‍\U0001F469‍\U0001F467d\U0001F1EF\U0001F1F5e"
	swapped, clusters := split_emoji(text, context.temp_allocator)
	testing.expect_value(t, len(clusters), 4)
	testing.expect_value(t, swapped, "a b c d e")
	testing.expect_value(t, clusters[1].characters, "\U0001F44D\U0001F3FD")
	testing.expect_value(t, clusters[2].characters, "\U0001F468‍\U0001F469‍\U0001F467")
	testing.expect_value(t, clusters[3].characters, "\U0001F1EF\U0001F1F5")
	// the offsets point at the spaces in the new text
	for c in clusters {
		testing.expect_value(t, swapped[c.offset:][:3], " ")
	}
}

@(test)
a_symbol_inter_has_stays_text_and_a_stray_joiner_is_left_alone :: proc(t: ^testing.T) {
	testing.expect(t, fonts_start())
	// arrows are in Inter; a lone zero width joiner is not an emoji
	same, clusters := split_emoji("→ ‍", context.temp_allocator)
	testing.expect_value(t, same, "→ ‍")
	testing.expect_value(t, len(clusters), 0)
}

@(test)
an_emoji_measures_as_one_em_whatever_size_its_font_is_made_in :: proc(t: ^testing.T) {
	testing.expect(t, fonts_start())
	space_w, _ := measure_typeset(FACE_DEFAULT, 20, .Left, " ")
	w, h := measure_typeset(FACE_DEFAULT, 20, .Left, "\U0001F642")
	testing.expect_value(t, w, space_w)
	testing.expect(t, h < 40)
	w2, _ := measure_typeset(FACE_DEFAULT, 20, .Left, "\U0001F642\U0001F642")
	testing.expect_value(t, w2, space_w * 2)
}
