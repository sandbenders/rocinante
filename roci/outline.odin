// SPDX-License-Identifier: 0BSD
//
// `outline_of`: the outline of the solid part of a picture, as the corners of a polygon
// a collision test can use. The picture's pixels are read from the store in roci/gfx
// and the tracing is roci/geom's; this file turns "more solid than this" into the mask
// and puts the corners where the picture is drawn.
package roci

import "geom"
import "gfx"

// How far, in picture pixels, the outline may stray from the exact edge of the solid
// pixels when the corners are dropped that a straight run can replace.
OUTLINE_TOLERANCE :: 1.0

// The corners of the outline of the biggest solid group of pixels in a picture, in
// order round it, put where the picture is drawn: its top left at `at`, at its own
// size or stretched to `size`. A pixel is solid when its alpha, as a percentage from 0
// to 100, is more than `alpha`; 0 counts every pixel that is not fully clear. Nothing
// for a picture with no solid pixel, a canvas (whose pixels live on the GPU) or a
// number that is no picture. The points are allocated with `allocator`.
outline_of :: proc(picture: Image, alpha := 50.0, at := [2]f64{}, size := Maybe([2]f64){}, allocator := context.allocator) -> [][2]f64 {
	data := gfx.image_data(picture)
	if data == nil || data.pixels == nil || data.width <= 0 || data.height <= 0 {
		return nil
	}
	limit := clamp(alpha, 0, 100) * 255 // compared with the alpha byte times 100
	solid := make([]bool, data.width * data.height, context.temp_allocator)
	for i in 0 ..< data.width * data.height {
		solid[i] = f64(data.pixels[i * 4 + 3]) * 100 > limit
	}
	points := geom.trace_outline(solid, data.width, data.height, OUTLINE_TOLERANCE, allocator)
	scale := [2]f64{1, 1}
	if wanted, given := size.?; given {
		scale = {wanted.x / f64(data.width), wanted.y / f64(data.height)}
	}
	for &p in points {
		p = at + p * scale
	}
	return points
}
