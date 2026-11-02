// SPDX-License-Identifier: 0BSD
//
// Text: `text` draws words with their top at a point, in the current font, size and
// alignment; `font`, `align` and `measure` are the verbs around it. The shaping and the
// drawing are roci/gfx's (fonts.odin, typeset.odin); this file only puts the current
// window's list in front of them.
package roci

import "gfx"

Align :: gfx.Align

// Text with its top at (x, y). The left, middle or right of each line is at x,
// by the alignment; lines break at line breaks and, when `wrap` is above 0, so
// no line is wider than `wrap` pixels.
text_xy :: proc(content: string, x, y: f64, look := Look{}, wrap := f64(0)) {
	list := current_list()
	opened := begin_look(list, look)
	gfx.typeset(list, content, f32(x), f32(y), f32(wrap))
	end_look(list, opened)
}

text_v :: proc(content: string, position: [2]f64, look := Look{}, wrap := f64(0)) {
	text_xy(content, position.x, position.y, look, wrap)
}

text :: proc{text_xy, text_v}

// Sets the font of the text drawn from now on, and its size when `size` is above 0.
// The built-in faces are "Inter" and "Inter Bold"; a face added with `add_font` is
// found by the name it was added under. Gives false, changing nothing, when there is
// no such font.
font :: proc(name: string, size := f64(0)) -> bool {
	face, found := gfx.find_face(name)
	if !found {
		return false
	}
	list := current_list()
	gfx.set_font(list, face)
	if size > 0 {
		gfx.set_font_size(list, f32(size))
	}
	return true
}

// Sets the size of the text drawn from now on, in pixels.
font_size :: proc(pixels: f64) {
	gfx.set_font_size(current_list(), f32(pixels))
}

// Sets where each line of a text sits against its point: its left, middle or right.
align :: proc(side: Align) {
	gfx.set_align(current_list(), side)
}

// Sets the distance between the lines of the text drawn from now on, as a multiple of
// its size (1.5 puts the baselines one and a half sizes apart). 0 is the font's own.
leading :: proc(multiple: f64) {
	gfx.set_leading(current_list(), f32(multiple))
}

// How big a text is in the current font, size and alignment: its width and height
// in pixels, with line breaks making lines. Empty text, or a font that cannot be
// opened, is 0 by 0.
measure :: proc(content: string, wrap := f64(0)) -> [2]f64 {
	style := current_list().style
	w, h := gfx.measure_typeset(style.font, style.font_size, style.align, content, f32(wrap), style.leading)
	return {f64(w), f64(h)}
}

// Makes a font from the bytes of a font file (TrueType or OpenType), known from now on
// by `name`. The bytes are copied. Gives false when they are not a font.
add_font :: proc(name: string, bytes: []u8) -> bool {
	_, ok := gfx.add_face(name, bytes)
	return ok
}

// Whether a font of this name is there.
has_font :: proc(name: string) -> bool {
	_, ok := gfx.find_face(name)
	return ok
}
