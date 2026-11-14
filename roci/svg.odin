// SPDX-License-Identifier: 0BSD
package roci

import "core:strings"
import "gfx"

// Draws an SVG drawing (read by `gfx.svg_read`) with its top left at (x, y), stretched to `width` by `height`,
// in its own colors, under the current transform. The sketch's style is untouched.
draw_svg :: proc(drawing: ^gfx.Svg_Drawing, x, y, width, height: f64) {
	gfx.svg_draw(current_list(), drawing, f32(x), f32(y), f32(width), f32(height))
}

// A drawing kept for a program that reads its own files (the C API), found again by its path.
Svg :: distinct u32

@(private)
Svg_Slot :: struct {
	path:    string,
	stamp:   i64,
	drawing: ^gfx.Svg_Drawing,
}

@(private, thread_local)
svg_slots: [dynamic]Svg_Slot

// Reads an SVG drawing (the bytes of a file) and keeps it. `path` and `stamp` (when the file was last changed) are how
// it is told from the others: the same path with a new stamp replaces what was kept, under the same number.
// Gives the drawing, or why it could not be read.
add_svg :: proc(path: string, stamp: i64, bytes: []u8) -> (svg: Svg, error: gfx.Svg_Error) {
	drawing, read_error := gfx.svg_read(bytes)
	if read_error != .None {
		return 0, read_error
	}
	kept := new(gfx.Svg_Drawing)
	kept^ = drawing
	for &slot, i in svg_slots {
		if slot.path == path {
			if slot.drawing != nil {
				gfx.svg_destroy(slot.drawing)
				free(slot.drawing)
			}
			slot.drawing = kept
			slot.stamp = stamp
			return Svg(i + 1), .None
		}
	}
	append(&svg_slots, Svg_Slot{path = strings.clone(path), stamp = stamp, drawing = kept})
	return Svg(len(svg_slots)), .None
}

// The number of the drawing read from `path` when it was last changed at `stamp`, if there is one.
find_svg :: proc(path: string, stamp: i64) -> (Svg, bool) {
	for slot, i in svg_slots {
		if slot.path == path && slot.stamp == stamp && slot.drawing != nil {
			return Svg(i + 1), true
		}
	}
	return 0, false
}

// A kept drawing, or nil for a number that names none.
svg_drawing :: proc(svg: Svg) -> ^gfx.Svg_Drawing {
	if svg == 0 || int(svg) > len(svg_slots) {
		return nil
	}
	return svg_slots[int(svg) - 1].drawing
}

// How big a kept drawing is in its own units, 0 by 0 for none.
svg_size :: proc(svg: Svg) -> [2]f64 {
	if drawing := svg_drawing(svg); drawing != nil {
		return {f64(drawing.width), f64(drawing.height)}
	}
	return {}
}

// Draws a kept drawing with its top left at a place, at its own size.
draw_kept_svg :: proc(svg: Svg, x, y: f64) {
	if drawing := svg_drawing(svg); drawing != nil {
		draw_svg(drawing, x, y, f64(drawing.width), f64(drawing.height))
	}
}

// Draws a kept drawing stretched to a size.
draw_kept_svg_sized :: proc(svg: Svg, x, y, width, height: f64) {
	if drawing := svg_drawing(svg); drawing != nil {
		draw_svg(drawing, x, y, width, height)
	}
}

// What a kept drawing has that cannot be drawn.
svg_lost :: proc(svg: Svg) -> bit_set[gfx.Svg_Lost] {
	if drawing := svg_drawing(svg); drawing != nil {
		return drawing.lost
	}
	return {}
}

// Lets every kept drawing go (`shutdown`).
@(private)
svgs_stop :: proc() {
	for slot in svg_slots {
		if slot.drawing != nil {
			gfx.svg_destroy(slot.drawing)
			free(slot.drawing)
		}
		delete(slot.path)
	}
	delete(svg_slots)
	svg_slots = nil
}
