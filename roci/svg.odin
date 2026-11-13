// SPDX-License-Identifier: 0BSD
package roci

import "gfx"

// Draws an SVG drawing (read by `gfx.svg_read`) with its top left at (x, y), stretched to `width` by `height`,
// in its own colors, under the current transform. The sketch's style is untouched.
draw_svg :: proc(drawing: ^gfx.Svg_Drawing, x, y, width, height: f64) {
	gfx.svg_draw(current_list(), drawing, f32(x), f32(y), f32(width), f32(height))
}
