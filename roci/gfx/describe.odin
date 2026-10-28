// SPDX-License-Identifier: 0BSD
//
// A command describes itself: what it is, where it sits on the canvas, how big
// it is and what colour. Screen readers and the error overlay read this; nothing has to know the shape of
// the drawing code.
package gfx

import "../maths"

Description :: struct {
	kind:          Kind,
	x, y:          f32, // top left of the shape's bounds, in canvas coordinates
	width, height: f32, // of those bounds
	colour:        maths.Colour, // the fill if there is one, else the stroke, else 0
	visible:       bool,
}

kind_name :: proc "contextless" (kind: Kind) -> string {
	switch kind {
	case .Circle:   return "circle"
	case .Ellipse:  return "ellipse"
	case .Rect:     return "rectangle"
	case .Line:     return "line"
	case .Point:    return "point"
	case .Triangle: return "triangle"
	case .Quad:     return "quadrilateral"
	case .Arc:      return "arc"
	case .Text:     return "text"
	}
	return ""
}

// Whether the position of a command is the middle of its shape. Circles,
// ellipses and arcs default to it, as in Processing; the rest start at their
// corner. `as center` and `as corner` override either habit.
is_centred :: proc "contextless" (c: Command) -> bool {
	switch c.origin {
	case .Center: return true
	case .Corner: return false
	case .Default: return c.kind == .Circle || c.kind == .Ellipse || c.kind == .Arc
	}
	return false
}

// The shape's box in the space the command was recorded in, before the
// transform: the top left corner and the size.
local_bounds :: proc "contextless" (c: Command) -> (x, y, w, h: f32) {
	a := c.args
	switch c.kind {
	case .Circle:
		d := a[2] * 2
		x, y = a[0], a[1]
		if is_centred(c) {x, y = a[0] - a[2], a[1] - a[2]}
		return x, y, d, d
	case .Ellipse, .Rect, .Arc:
		x, y = a[0], a[1]
		if is_centred(c) {x, y = a[0] - a[2] / 2, a[1] - a[3] / 2}
		return x, y, a[2], a[3]
	case .Line:
		return min(a[0], a[2]), min(a[1], a[3]), abs(a[2] - a[0]), abs(a[3] - a[1])
	case .Point:
		return a[0], a[1], 0, 0
	case .Triangle:
		lo_x, hi_x := min(a[0], a[2], a[4]), max(a[0], a[2], a[4])
		lo_y, hi_y := min(a[1], a[3], a[5]), max(a[1], a[3], a[5])
		return lo_x, lo_y, hi_x - lo_x, hi_y - lo_y
	case .Quad:
		lo_x, hi_x := min(a[0], a[2], a[4], a[6]), max(a[0], a[2], a[4], a[6])
		lo_y, hi_y := min(a[1], a[3], a[5], a[7]), max(a[1], a[3], a[5], a[7])
		return lo_x, lo_y, hi_x - lo_x, hi_y - lo_y
	case .Text:
		return a[0], a[1], a[3], a[4]
	}
	return
}

// Whether a shape encloses any area. A circle of radius 0, a rectangle with no
// width or height and a triangle whose points are in a line have nothing to
// fill (they can still show an outline).
has_area :: proc "contextless" (c: Command) -> bool {
	a := c.args
	switch c.kind {
	case .Circle:
		return a[2] > 0
	case .Ellipse, .Rect, .Arc:
		return a[2] > 0 && a[3] > 0
	case .Triangle:
		return (a[2] - a[0]) * (a[5] - a[1]) - (a[4] - a[0]) * (a[3] - a[1]) != 0
	case .Quad:
		_, _, w, h := local_bounds(c)
		return w > 0 && h > 0
	case .Text:
		return a[3] > 0 && a[4] > 0
	case .Line, .Point:
		return false
	}
	return false
}

// Whether the command puts anything on the screen: it needs a fill (and some
// area to fill) or an outline of some width to show with. A point and a line
// show only by their stroke.
is_visible :: proc "contextless" (c: Command) -> bool {
	if c.style.alpha <= 0 {
		return false
	}
	has_outline := c.style.stroke_on && c.style.thickness > 0
	switch c.kind {
	case .Point:
		return has_outline && c.style.cap != .Butt // a butt-capped dot has no length to draw
	case .Line:
		return has_outline
	case .Text:
		return c.style.fill_on && has_area(c) // text is drawn in the fill colour
	case .Circle, .Ellipse, .Rect, .Triangle, .Quad, .Arc:
		return (c.style.fill_on && has_area(c)) || has_outline
	}
	return false
}

// Where the shape ends up: its bounds after the transform, as the smallest
// upright box around them.
describe :: proc "contextless" (c: Command) -> Description {
	lx, ly, lw, lh := local_bounds(c)
	corners := [4][2]f32{{lx, ly}, {lx + lw, ly}, {lx, ly + lh}, {lx + lw, ly + lh}}
	lo := [2]f32{max(f32), max(f32)}
	hi := [2]f32{min(f32), min(f32)}
	for corner in corners {
		px, py := transform_apply(c.transform, corner.x, corner.y)
		lo = {min(lo.x, px), min(lo.y, py)}
		hi = {max(hi.x, px), max(hi.y, py)}
	}
	colour: maths.Colour
	switch {
	case c.kind != .Line && c.kind != .Point && c.style.fill_on: colour = c.style.fill
	case c.style.stroke_on: colour = c.style.stroke
	}
	return Description{
		kind = c.kind,
		x = lo.x,
		y = lo.y,
		width = hi.x - lo.x,
		height = hi.y - lo.y,
		colour = colour,
		visible = is_visible(c),
	}
}
