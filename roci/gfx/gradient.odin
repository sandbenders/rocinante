// SPDX-License-Identifier: 0BSD
//
// Gradients: a list of colours in `fill`, `stroke` or
// `background` that shade into each other, linearly, from the middle outwards or
// round a point, mixed in Oklab unless asked otherwise. Positions are fractions
// of the shape's own bounding box, so a gradient fits a circle, a rectangle or a
// line without any arithmetic.
//
// A gradient is turned into a ramp of 256 colours on the CPU (mixing in the chosen
// colour space, so the GPU only has to look a colour up) and kept in a texture
// with the other gradients of the frame; the shader works out where in the ramp
// each pixel is. This file is the CPU half: the description, the ramp, and the
// atlas that gives every distinct gradient a row.
//
// Two more kinds come only from SVG drawings (`svg`), whose gradients are laid by end points, a circle and
// a focal point, and transforms, rather than by the box: `Placed_Linear` and `Placed_Radial` carry the
// transform from the shape's box to the gradient's own space and how the colors go on past its ends.
package gfx

import "../maths"
import "core:math"

MAX_STOPS :: 16
RAMP_WIDTH :: 256

// How many gradients the atlas holds at once. When a frame needs more, the atlas
// starts again with that frame's.
MAX_GRADIENTS :: 256

Gradient_Kind :: enum u8 {
	Linear, // along a line at `angle` (0 runs left to right, angles turn clockwise)
	Radial, // from the middle outwards, reaching the edge of the box on each side
	Conic,  // sweeping round the middle, starting at `angle` (0 is the right)
	Placed_Linear, // SVG's: the place along the way is x in the gradient's own space (`place`)
	Placed_Radial, // SVG's: from the focal point (`focus`) out to the circle of radius 1 round 0, 0 in that space
}

// How many texels of its row a gradient's parameters take: the first holds the kind and three numbers, the
// next three a placed gradient's transform, each number split in two 16-bit halves so it keeps its precision.
PARAM_TEXELS :: 4

Gradient :: struct {
	kind:      Gradient_Kind,
	space:     maths.Mix_Space, // Oklab unless asked (`in rgb`, `in oklch`)
	colours:   [MAX_STOPS]maths.Colour,
	stops:     [MAX_STOPS]f32, // percent along the way; used only when `has_stops`
	count:     int,
	has_stops: bool,           // false spreads the colours evenly
	angle:     f32,            // degrees
	centre:    [2]f32,         // percent of the box, radial and conic; 50, 50 is the middle
	// the placed kinds only
	place:     [6]f32,         // x' = a x + c y + e, y' = b x + d y + f, from the point measured from the middle of the box over its half size
	focus:     [2]f32,         // a placed radial one's focal point, inside the circle
	spread:    Svg_Spread,     // what lies past the ends: the end colors, the ramp mirrored, or the ramp again
}

// A gradient registered with a command list: its number there (1 and up; 0 means
// no gradient) and a hash of what it is, so a command's hash follows the
// gradient's content and not its number.
Gradient_Ref :: struct {
	id:   u32,
	hash: u64,
}

// Builds a gradient from at least one and at most MAX_STOPS colours. `stops`, when
// given, has one percentage per colour. Gives false when the colours or stops do
// not fit, or a number is not a number; nothing is made then.
gradient_make :: proc(colours: []maths.Colour, kind := Gradient_Kind.Linear, angle := f32(0), space := maths.Mix_Space.Oklab, stops: []f32 = nil, centre := [2]f32{50, 50}) -> (g: Gradient, ok: bool) {
	if len(colours) == 0 || len(colours) > MAX_STOPS || (stops != nil && len(stops) != len(colours)) {
		return {}, false
	}
	if !finite(angle, centre.x, centre.y) {
		return {}, false
	}
	for s in stops {
		if !finite(s) {
			return {}, false
		}
	}
	g.kind, g.space, g.count, g.centre = kind, space, len(colours), centre
	g.angle = angle
	copy(g.colours[:], colours)
	if stops != nil {
		copy(g.stops[:], stops)
		g.has_stops = true
	}
	return g, true
}

// The percentage position of each colour: as given (never going backwards, and
// kept between 0 and 100), or spread evenly.
gradient_positions :: proc "contextless" (g: Gradient) -> (positions: [MAX_STOPS]f32) {
	for i in 0 ..< g.count {
		switch {
		case g.has_stops:
			positions[i] = clamp(g.stops[i], 0, 100)
			if i > 0 {
				positions[i] = max(positions[i], positions[i - 1])
			}
		case g.count == 1:
			positions[i] = 0
		case:
			positions[i] = f32(i) / f32(g.count - 1) * 100
		}
	}
	return
}

// The colour at `percent` along the way, 0 to 100, mixed in the gradient's space.
// Before the first stop it is the first colour, after the last the last.
gradient_colour_at :: proc "contextless" (g: Gradient, percent: f32) -> maths.Colour {
	if g.count == 0 {
		return {}
	}
	positions := gradient_positions(g)
	if percent <= positions[0] {
		return g.colours[0]
	}
	for k in 1 ..< g.count {
		if percent <= positions[k] {
			span := positions[k] - positions[k - 1]
			if span <= 0 {
				return g.colours[k]
			}
			return maths.mix(g.colours[k - 1], g.colours[k], f64((percent - positions[k - 1]) / span), g.space)
		}
	}
	return g.colours[g.count - 1]
}

// The 256 colours of the ramp, 0 to 255 per channel, straight alpha.
gradient_ramp :: proc "contextless" (g: Gradient) -> (ramp: [RAMP_WIDTH]maths.Colour) {
	for i in 0 ..< RAMP_WIDTH {
		ramp[i] = gradient_colour_at(g, f32(i) / f32(RAMP_WIDTH - 1) * 100)
	}
	return
}

// What the shader needs besides the ramp, texel by texel, in the order it reads them: the kind, the angle as a
// fraction of a turn, and the centre as fractions of the box; for a placed one the kind, the spread and the focal
// point, then the six numbers of its transform, each as a 16-bit number and what that leaves over.
gradient_params :: proc "contextless" (g: Gradient) -> (params: [PARAM_TEXELS][4]f32) {
	if g.kind == .Placed_Linear || g.kind == .Placed_Radial {
		params[0] = {f32(g.kind), f32(g.spread), g.focus.x, g.focus.y}
		for i in 0 ..< 3 {
			for j in 0 ..< 2 {
				v := g.place[i * 2 + j]
				high := f32(f16(v))
				params[1 + i][j * 2] = high
				params[1 + i][j * 2 + 1] = v - high
			}
		}
		return
	}
	turns := math.mod(f64(g.angle) / 360, 1)
	if turns < 0 {
		turns += 1
	}
	params[0] = {f32(g.kind), f32(turns), g.centre.x / 100, g.centre.y / 100}
	return
}

// The transform from a shape's own space to a placed gradient's, for a shape whose box is `box` (x, y, width,
// height): the box's middle and half size first, then the gradient's `place`. The vector writers use it.
placed_from_shape :: proc "contextless" (g: Gradient, box: [4]f32) -> Transform {
	half := [2]f32{max(box[2] / 2, 1e-4), max(box[3] / 2, 1e-4)}
	m := g.place
	place := Transform{m[0], m[1], m[2], m[3], m[4], m[5]}
	return transform_mul(place, Transform{1 / half.x, 0, 0, 1 / half.y, -(box[0] + box[2] / 2) / half.x, -(box[1] + box[3] / 2) / half.y})
}

// The transform that undoes `t`, and false when it flattens everything onto a line.
transform_invert :: proc "contextless" (t: Transform) -> (Transform, bool) {
	det := f64(t.a) * f64(t.d) - f64(t.b) * f64(t.c)
	if abs(det) < 1e-20 || math.is_nan(det) {
		return {}, false
	}
	a, b, c, d := f64(t.d) / det, -f64(t.b) / det, -f64(t.c) / det, f64(t.a) / det
	return Transform{f32(a), f32(b), f32(c), f32(d), f32(-(a * f64(t.e) + c * f64(t.f))), f32(-(b * f64(t.e) + d * f64(t.f)))}, true
}

// Where in the ramp (0 to 1) a placed gradient is at the point `p`, measured from the middle of a box whose half
// size is `box_half`: what the shader works out, written here too so it can be tested.
placed_gradient_at :: proc "contextless" (g: Gradient, p, box_half: [2]f32) -> f32 {
	u := [2]f32{p.x / max(box_half.x, 1e-4), p.y / max(box_half.y, 1e-4)}
	m := g.place
	q := [2]f32{m[0] * u.x + m[2] * u.y + m[4], m[1] * u.x + m[3] * u.y + m[5]}
	t := q.x
	if g.kind == .Placed_Radial {
		e := g.focus
		d := q - e
		dd := d.x * d.x + d.y * d.y
		if dd <= 0 {
			t = 0
		} else {
			ed := e.x * d.x + e.y * d.y
			ee := e.x * e.x + e.y * e.y
			k := (-ed + math.sqrt(max(ed * ed - dd * (ee - 1), 0))) / dd
			t = 1 / k if k > 0 else 1
		}
	}
	switch g.spread {
	case .Pad:
		return clamp(t, 0, 1)
	case .Repeat:
		return t - math.floor(t)
	case .Reflect:
		r := math.mod(abs(t), 2)
		return 2 - r if r > 1 else r
	}
	return clamp(t, 0, 1)
}

// A hash of everything that shapes the gradient's look.
gradient_hash :: proc "contextless" (g: Gradient) -> u64 {
	h := hash_u64(FNV_OFFSET, u64(g.kind) | u64(g.space) << 8 | u64(g.count) << 16 | u64(g.has_stops) << 24)
	h = hash_f32(h, g.angle)
	h = hash_f32(h, g.centre.x)
	h = hash_f32(h, g.centre.y)
	if g.kind == .Placed_Linear || g.kind == .Placed_Radial {
		for v in g.place {
			h = hash_f32(h, v)
		}
		h = hash_f32(h, g.focus.x)
		h = hash_f32(h, g.focus.y)
		h = hash_u64(h, u64(g.spread))
	}
	positions := gradient_positions(g)
	for i in 0 ..< g.count {
		for v in g.colours[i] {
			h = hash_f32(h, v)
		}
		h = hash_f32(h, positions[i])
	}
	return h
}

// Whether two gradients look the same: what `gradient_hash` takes into account (the colours
// and stops past `count`, and the stops of one that spreads its colours evenly, are not
// part of it), compared exactly.
gradient_same :: proc "contextless" (a, b: Gradient) -> bool {
	if a.kind != b.kind || a.space != b.space || a.count != b.count || a.has_stops != b.has_stops {
		return false
	}
	if a.angle != b.angle || a.centre != b.centre {
		return false
	}
	if (a.kind == .Placed_Linear || a.kind == .Placed_Radial) && (a.place != b.place || a.focus != b.focus || a.spread != b.spread) {
		return false
	}
	pa, pb := gradient_positions(a), gradient_positions(b)
	for i in 0 ..< a.count {
		if a.colours[i] != b.colours[i] || pa[i] != pb[i] {
			return false
		}
	}
	return true
}

// ---- the atlas ----

// One baked gradient, as the texture holds it: a row of colours and a row of
// parameters, in 16-bit floats from 0 to 1.
Baked_Gradient :: struct {
	ramp:   [RAMP_WIDTH][4]f16,
	params: [PARAM_TEXELS][4]f16,
}

// Every distinct gradient of the frames drawn so far, baked and numbered. Row `n`
// of the texture is the ramp of gradient n, row `n` + 1 its parameters (so the
// texture is twice as tall as it has gradients).
Gradient_Atlas :: struct {
	rows:    [dynamic]Baked_Gradient,
	lookup:  map[u64]int,
	version: u64, // changes whenever the contents do, so the GPU copy knows to follow
}

atlas_destroy :: proc(a: ^Gradient_Atlas) {
	delete(a.rows)
	delete(a.lookup)
	a^ = {}
}

// The number of the gradient's row (from 0), baking it when it is new. When the
// atlas is full and `may_reset` is set it starts again, so every row number handed
// out earlier in the frame is stale: `reset` reports that, and the batcher then
// begins the frame over. When it is full and `may_reset` is not set, the answer
// is -1 and the gradient is not drawn.
atlas_row :: proc(a: ^Gradient_Atlas, g: Gradient, may_reset := true) -> (row: int, reset: bool) {
	h := gradient_hash(g)
	if existing, found := a.lookup[h]; found {
		return existing, false
	}
	if len(a.rows) >= MAX_GRADIENTS {
		if !may_reset {
			return -1, false
		}
		clear(&a.rows)
		clear(&a.lookup)
		reset = true
	}
	baked: Baked_Gradient
	ramp := gradient_ramp(g)
	for c, i in ramp {
		baked.ramp[i] = {f16(c.r / 255), f16(c.g / 255), f16(c.b / 255), f16(c.a / 255)}
	}
	for texel, i in gradient_params(g) {
		baked.params[i] = {f16(texel[0]), f16(texel[1]), f16(texel[2]), f16(texel[3])}
	}
	append(&a.rows, baked)
	if a.lookup == nil {
		a.lookup = make(map[u64]int)
	}
	a.lookup[h] = len(a.rows) - 1
	a.version += 1
	return len(a.rows) - 1, reset
}
