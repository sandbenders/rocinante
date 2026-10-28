// SPDX-License-Identifier: 0BSD
//
// The overlay font: a small built-in bitmap font so
// the error overlay and debug output can put words on the screen before Phase 3
// brings real text. It covers printable ASCII, in 8 x 8 pixel cells
// (glyph pictures in font_data.odin, public domain), and is drawn by the text
// pipeline as one instanced quad per character. It is for English error messages
// and numbers, not for sketches' own text: no accents, no other scripts, no
// smoothing, and it looks right at whole-number sizes.
package gfx

import "core:math"
import "core:unicode/utf8"

GLYPH_SIZE :: 8 // pixels, square

// The glyphs are laid out in a grid on one texture, with the box for a missing
// character after the 95 printable ones.
ATLAS_COLUMNS :: 16
ATLAS_ROWS :: 6
ATLAS_WIDTH :: ATLAS_COLUMNS * GLYPH_SIZE  // 128
ATLAS_HEIGHT :: ATLAS_ROWS * GLYPH_SIZE    // 48
MISSING_GLYPH :: FONT_GLYPHS               // index 95

// Lines are a little further apart than the glyphs are tall, so descenders do not
// touch the next line.
LINE_HEIGHT :: 10 // pixels at size 1

// Tabs go to the next multiple of this many characters.
TAB_WIDTH :: 4

// Where a character's picture is in the atlas: 0 for space up to 94 for tilde;
// anything else (control characters, accents, other scripts) is the missing box.
glyph_index :: proc "contextless" (r: rune) -> int {
	if r >= FONT_FIRST && r <= FONT_LAST {
		return int(r) - int(FONT_FIRST)
	}
	return MISSING_GLYPH
}

// The atlas picture: one byte per pixel, 255 where the glyph is drawn and 0 where
// it is not, rows from the top.
font_atlas_pixels :: proc(allocator := context.allocator) -> []u8 {
	pixels := make([]u8, ATLAS_WIDTH * ATLAS_HEIGHT, allocator)
	for index in 0 ..= FONT_GLYPHS {
		rows := FONT_MISSING if index == MISSING_GLYPH else FONT_8X8[index]
		cell_x, cell_y := (index % ATLAS_COLUMNS) * GLYPH_SIZE, (index / ATLAS_COLUMNS) * GLYPH_SIZE
		for row in 0 ..< GLYPH_SIZE {
			for column in 0 ..< GLYPH_SIZE {
				if rows[row] >> uint(column) & 1 != 0 { // the lowest bit is the leftmost pixel
					pixels[(cell_y + row) * ATLAS_WIDTH + cell_x + column] = 255
				}
			}
		}
	}
	return pixels
}

// A character to draw: its glyph and where its top left corner is, measured from
// the start of the text, in pixels at the size asked for.
Placed_Glyph :: struct {
	x, y:  f32,
	index: int,
}

// Lays out `text` at `scale` times the glyphs' own size, appending the glyphs to
// draw to `out` (spaces and line breaks leave gaps and draw nothing). Characters
// are 8 pixels wide and lines 10 pixels apart, times the scale; `\n` starts a new
// line, `\t` goes to the next multiple of four characters and `\r` is ignored.
// Gives the width of the longest line and the height of all of them.
layout_text :: proc(text: string, scale: f32, out: ^[dynamic]Placed_Glyph) -> (width, height: f32) {
	if len(text) == 0 {
		return 0, 0
	}
	column, line, widest := 0, 0, 0
	for r in text {
		switch r {
		case '\n':
			line += 1
			column = 0
			continue
		case '\r':
			continue
		case '\t':
			column += TAB_WIDTH - column % TAB_WIDTH
		case ' ':
			column += 1
		case:
			index := glyph_index(r)
			if r == utf8.RUNE_ERROR {
				index = MISSING_GLYPH
			}
			append(out, Placed_Glyph{f32(column * GLYPH_SIZE) * scale, f32(line * LINE_HEIGHT) * scale, index})
			column += 1
		}
		widest = max(widest, column)
	}
	return f32(widest * GLYPH_SIZE) * scale, f32(line * LINE_HEIGHT + GLYPH_SIZE) * scale
}

// The size `text` takes at `scale`, without laying it out.
measure_text :: proc(text: string, scale: f32) -> (width, height: f32) {
	glyphs := make([dynamic]Placed_Glyph, context.temp_allocator)
	return layout_text(text, scale, &glyphs)
}

// Whether a text size can be drawn: a positive number that is not absurd.
valid_text_scale :: proc "contextless" (scale: f32) -> bool {
	return scale > 0 && scale <= 256 && !math.is_nan(scale)
}
