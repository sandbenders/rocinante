// SPDX-License-Identifier: 0BSD
//
// The style a shape is drawn with (CLAUDE.md section 5.9): what fills it, what
// outlines it and how thick, and how transparent both are. A command keeps the
// style that was current when it was recorded, so a later change never reaches
// back. Gradients and image fills join the fill in later phases.
package gfx

import "../geom"
import "../maths"

Style :: struct {
	fill:      maths.Colour,
	fill_on:   bool,
	stroke:    maths.Colour,
	stroke_on: bool,
	thickness: f32, // in logical pixels, never negative
	alpha:     f32, // 0-255, multiplies the alpha of fill and stroke
	cap:       geom.Cap,  // how an open line, a line or a point ends
	join:      geom.Join, // how an outline turns a corner
	// A gradient instead of the plain colour (0 id means none); `fill` and `stroke`
	// then hold its first colour, which is what is drawn if the gradient cannot be.
	fill_paint:   Gradient_Ref,
	stroke_paint: Gradient_Ref,
}

// What every frame starts with (section 5.15): white fill, no outline,
// thickness 1, fully opaque, round caps and mitred corners (Processing's defaults).
DEFAULT_STYLE :: Style{
	fill      = {255, 255, 255, 255},
	fill_on   = true,
	stroke    = {0, 0, 0, 255},
	stroke_on = false,
	thickness = 1,
	alpha     = 255,
	cap       = .Round,
	join      = .Miter,
}

// A window's background when nothing sets one: light grey, 230 (section 5.15).
DEFAULT_BACKGROUND :: maths.Colour{230, 230, 230, 255}

// A colour as the GPU wants it: 0 to 1 per channel, with the style's alpha folded in.
colour_for_gpu :: proc "contextless" (c: maths.Colour, alpha: f32) -> [4]f32 {
	return {c.r / 255, c.g / 255, c.b / 255, c.a / 255 * (alpha / 255)}
}
