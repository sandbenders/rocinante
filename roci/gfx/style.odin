// SPDX-License-Identifier: 0BSD
//
// The style a shape is drawn with: what fills it, what
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
	// What real text is set in: the face (fonts.odin), its size in logical pixels
	// and where the lines sit against the text's x.
	font:         u16,
	font_size:    f32,
	align:        Align,
	// The distance between the baselines of a text's lines as a multiple of the size;
	// 0 is the font's own spacing.
	leading:      f32,
	// What pictures are drawn through: their colours are multiplied by it. White changes nothing.
	tint:         maths.Colour,
	// A picture instead of the plain colour: the shape is a mask the picture shows
	// through (imagefill.odin). Not 0 id: it is drawn, and `fill` holds the colour
	// the shape would have if it could not be.
	fill_image:   Image_Fill,
	// A picture instead of the plain colour of the outline: the stroke is the mask
	// (imagefill.odin). Not 0 id: drawn, and `stroke` holds the colour it would have.
	stroke_image: Image_Fill,
	// How what is drawn mixes with what is already there, and the box nothing is drawn
	// outside of: `clip` keeps the box in canvas (logical) pixels as the corners of a
	// rectangle, already carried through the transform that was current (`set_clip`).
	blend:        Blend_Mode,
	clip:         Clip,
}

// How a shape's colours combine with the picture behind it. Normal puts the shape over it;
// the others are the usual ways to mix light and ink.
Blend_Mode :: enum u8 {
	Normal,   // the shape covers what is behind it, by its alpha
	Add,      // the colours are added: light on dark glows
	Multiply, // the colours are multiplied: shadows and ink, never lighter
	Screen,   // the opposite of multiply: never darker
	Subtract, // the shape's colours are taken away from what is behind it
	Lighten,  // each channel keeps the lighter of the two (darken has no such blend: a fixed blend cannot keep the background where a shape is clear)
}

// The rectangle drawing is kept inside, in canvas pixels: from its top left corner to its
// bottom right. Off means no limit.
Clip :: struct {
	on:   bool,
	rect: [4]f32, // x0 y0 x1 y1
}

// How a picture fills a shape.
Image_Fit :: enum u8 {
	Cover,   // scale to cover the shape's box, crop what overflows
	Fit,     // scale to show the whole picture inside the box, empty bands where it does not reach
	Stretch, // scale each side to the box
	Tile,    // repeat at the picture's own size, or `tile` pixels wide
	Center,  // the picture's own size, in the middle
}

Image_Fill :: struct {
	image: Image_Id,  // 0: no picture fills
	fit:   Image_Fit,
	tile:  f32,       // for Tile: the width of one copy in logical pixels (0 is the picture's own); the height follows
	at:    [2]f32,    // for Tile and Center: how far the picture is shifted, in logical pixels
}

// What every frame starts with: black fill, no outline,
// thickness 1, fully opaque, round caps and mitred corners.
DEFAULT_STYLE :: Style{
	fill      = {0, 0, 0, 255},
	fill_on   = true,
	stroke    = {0, 0, 0, 255},
	stroke_on = false,
	thickness = 1,
	alpha     = 255,
	cap       = .Round,
	join      = .Miter,
	font      = FACE_DEFAULT,
	font_size = DEFAULT_FONT_SIZE,
	align     = .Left,
	tint      = {255, 255, 255, 255},
}

// A window's background when nothing sets one: light grey, 230.
DEFAULT_BACKGROUND :: maths.Colour{230, 230, 230, 255}

// A colour as the GPU wants it: 0 to 1 per channel, with the style's alpha folded in.
colour_for_gpu :: proc "contextless" (c: maths.Colour, alpha: f32) -> [4]f32 {
	return {c.r / 255, c.g / 255, c.b / 255, c.a / 255 * (alpha / 255)}
}
