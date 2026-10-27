// SPDX-License-Identifier: 0BSD
package gfx

import "core:hash"
import "core:testing"

glyph_pixels :: proc(pixels: []u8, index: int) -> (rows: [8]u8) {
	cell_x, cell_y := (index % ATLAS_COLUMNS) * GLYPH_SIZE, (index / ATLAS_COLUMNS) * GLYPH_SIZE
	for row in 0 ..< GLYPH_SIZE {
		for column in 0 ..< GLYPH_SIZE {
			if pixels[(cell_y + row) * ATLAS_WIDTH + cell_x + column] != 0 {
				rows[row] |= 1 << uint(column)
			}
		}
	}
	return
}

@(test)
test_the_atlas_has_room_for_every_glyph_and_the_missing_box :: proc(t: ^testing.T) {
	testing.expect_value(t, FONT_GLYPHS, 95)
	testing.expect_value(t, ATLAS_WIDTH, 128)
	testing.expect_value(t, ATLAS_HEIGHT, 48)
	testing.expect(t, MISSING_GLYPH < ATLAS_COLUMNS * ATLAS_ROWS)
}

@(test)
test_glyph_index_maps_printable_ascii_and_nothing_else :: proc(t: ^testing.T) {
	testing.expect_value(t, glyph_index(' '), 0)
	testing.expect_value(t, glyph_index('A'), int('A') - 32)
	testing.expect_value(t, glyph_index('~'), 94)
	for r in ([?]rune{0, '\n', 31, 127, 'é', '日', 0x1F600, -1}) {
		testing.expect_value(t, glyph_index(r), MISSING_GLYPH)
	}
}

@(test)
test_the_atlas_picture_holds_each_glyph_as_designed :: proc(t: ^testing.T) {
	pixels := font_atlas_pixels()
	defer delete(pixels)
	testing.expect_value(t, len(pixels), ATLAS_WIDTH * ATLAS_HEIGHT)
	for index in 0 ..< FONT_GLYPHS {
		testing.expect_value(t, glyph_pixels(pixels, index), FONT_8X8[index])
	}
	testing.expect_value(t, glyph_pixels(pixels, MISSING_GLYPH), FONT_MISSING)
}

@(test)
test_pixels_are_either_on_or_off :: proc(t: ^testing.T) {
	pixels := font_atlas_pixels()
	defer delete(pixels)
	for p in pixels {
		testing.expect(t, p == 0 || p == 255)
	}
}

@(test)
test_the_letter_a_is_drawn_with_the_lowest_bit_on_the_left :: proc(t: ^testing.T) {
	// The top row of A is 0x0C: columns 2 and 3, the middle of its six pixels.
	testing.expect_value(t, FONT_8X8[glyph_index('A')][0], u8(0x0C))
	pixels := font_atlas_pixels()
	defer delete(pixels)
	cell_x, cell_y := (glyph_index('A') % ATLAS_COLUMNS) * GLYPH_SIZE, (glyph_index('A') / ATLAS_COLUMNS) * GLYPH_SIZE
	for column in 0 ..< 8 {
		want: u8 = 255 if column == 2 || column == 3 else 0
		testing.expect_value(t, pixels[cell_y * ATLAS_WIDTH + cell_x + column], want)
	}
}

@(test)
test_every_printable_glyph_but_space_draws_something :: proc(t: ^testing.T) {
	for index in 0 ..< FONT_GLYPHS {
		ink := false
		for row in FONT_8X8[index] {
			if row != 0 {ink = true}
		}
		testing.expectf(t, ink == (index != 0), "glyph %d", index)
	}
}

@(test)
test_glyphs_are_all_different :: proc(t: ^testing.T) {
	for a in 0 ..< FONT_GLYPHS {
		for b in a + 1 ..< FONT_GLYPHS {
			testing.expectf(t, FONT_8X8[a] != FONT_8X8[b], "glyphs %d and %d look the same", a, b)
		}
	}
	for g in FONT_8X8 {
		testing.expect(t, g != FONT_MISSING)
	}
}

@(test)
test_the_atlas_is_the_same_every_time :: proc(t: ^testing.T) {
	a, b := font_atlas_pixels(), font_atlas_pixels()
	defer delete(a)
	defer delete(b)
	testing.expect_value(t, hash.crc32(a), hash.crc32(b))
}

// ---- layout ----

laid_out :: proc(text: string, scale: f32) -> (glyphs: [dynamic]Placed_Glyph, w, h: f32) {
	w, h = layout_text(text, scale, &glyphs)
	return
}

@(test)
test_characters_are_eight_pixels_apart_and_lines_ten :: proc(t: ^testing.T) {
	glyphs, w, h := laid_out("ab\ncd", 1)
	defer delete(glyphs)
	testing.expect_value(t, len(glyphs), 4)
	testing.expect_value(t, glyphs[0], Placed_Glyph{0, 0, glyph_index('a')})
	testing.expect_value(t, glyphs[1], Placed_Glyph{8, 0, glyph_index('b')})
	testing.expect_value(t, glyphs[2], Placed_Glyph{0, 10, glyph_index('c')})
	testing.expect_value(t, glyphs[3], Placed_Glyph{8, 10, glyph_index('d')})
	testing.expect_value(t, w, f32(16))
	testing.expect_value(t, h, f32(18))
}

@(test)
test_layout_scales_everything :: proc(t: ^testing.T) {
	glyphs, w, h := laid_out("ab\nc", 3)
	defer delete(glyphs)
	testing.expect_value(t, glyphs[1].x, f32(24))
	testing.expect_value(t, glyphs[2].y, f32(30))
	testing.expect_value(t, w, f32(48))
	testing.expect_value(t, h, f32(3 * 18))
}

@(test)
test_spaces_leave_gaps_and_draw_nothing :: proc(t: ^testing.T) {
	glyphs, w, _ := laid_out("a  b", 1)
	defer delete(glyphs)
	testing.expect_value(t, len(glyphs), 2)
	testing.expect_value(t, glyphs[1].x, f32(24))
	testing.expect_value(t, w, f32(32))
}

@(test)
test_tabs_go_to_the_next_multiple_of_four_characters :: proc(t: ^testing.T) {
	glyphs, _, _ := laid_out("a\tb\n\tc\nabcd\te", 1)
	defer delete(glyphs)
	testing.expect_value(t, glyphs[1].x, f32(4 * 8)) // b: after a and the tab
	testing.expect_value(t, glyphs[2].x, f32(4 * 8)) // c: a tab at the start of a line
	testing.expect_value(t, glyphs[len(glyphs) - 1].x, f32(8 * 8)) // e: abcd fills four, the tab goes to eight
}

@(test)
test_carriage_returns_are_ignored :: proc(t: ^testing.T) {
	a, _, _ := laid_out("a\r\nb", 1)
	b, _, _ := laid_out("a\nb", 1)
	defer delete(a)
	defer delete(b)
	testing.expect_value(t, len(a), len(b))
	testing.expect_value(t, a[1], b[1])
}

@(test)
test_characters_the_font_lacks_are_boxes :: proc(t: ^testing.T) {
	glyphs, w, _ := laid_out("é日\x01\xff", 1)
	defer delete(glyphs)
	testing.expect_value(t, len(glyphs), 4)
	for g in glyphs {
		testing.expect_value(t, g.index, MISSING_GLYPH)
	}
	testing.expect_value(t, w, f32(32))
}

@(test)
test_empty_text_has_no_size_and_blank_lines_still_count :: proc(t: ^testing.T) {
	glyphs, w, h := laid_out("", 2)
	defer delete(glyphs)
	testing.expect_value(t, len(glyphs), 0)
	testing.expect_value(t, w, f32(0))
	testing.expect_value(t, h, f32(0))
	glyphs2, w2, h2 := laid_out("\n\n", 1)
	defer delete(glyphs2)
	testing.expect_value(t, len(glyphs2), 0)
	testing.expect_value(t, w2, f32(0))
	testing.expect_value(t, h2, f32(28)) // three lines
}

@(test)
test_measure_text_agrees_with_layout :: proc(t: ^testing.T) {
	w, h := measure_text("hello\nworld!", 2)
	glyphs, lw, lh := laid_out("hello\nworld!", 2)
	defer delete(glyphs)
	testing.expect_value(t, w, lw)
	testing.expect_value(t, h, lh)
	testing.expect_value(t, w, f32(6 * 8 * 2))
}

@(test)
test_which_text_sizes_can_be_drawn :: proc(t: ^testing.T) {
	for s in ([?]f32{1, 0.5, 2, 256}) {
		testing.expect(t, valid_text_scale(s))
	}
	for s in ([?]f32{0, -1, 257, 1e30}) {
		testing.expect(t, !valid_text_scale(s))
	}
	nan := f32(0)
	nan = nan / nan
	testing.expect(t, !valid_text_scale(nan))
}
