// SPDX-License-Identifier: 0BSD
//
// Shapes that need a mesh: the ones the signed-distance shader (shapes.hlsl)
// cannot draw exactly as their style says. They are cut into triangles on the
// CPU by package geom: the fill by the triangulator, the outline by the stroker
// (with the caps and joins of the style), and everything is done in the shape's
// own space and moved onto the canvas at the end, so an outline's width follows
// the transform as it does for every other shape. Edges are smoothed by
// multisampling, not by the shader.
//
// Which commands come here (see `needs_mesh`): quads and arcs always; rectangles
// and triangles when their outline has mitred or bevelled corners (the signed
// distance can only round them); and lines and points with butt or square ends.
package gfx

import "../geom"
import "core:math"

// One corner of a triangle: where it is on the canvas and its colour (straight
// alpha; the shader multiplies it in). 24 bytes.
Mesh_Vertex :: struct {
	position: [2]f32,
	colour:   [4]f32,
}
#assert(size_of(Mesh_Vertex) == 24)

Mesh :: struct {
	vertices: [dynamic]Mesh_Vertex,
	indices:  [dynamic]u32,
}

mesh_destroy :: proc(m: ^Mesh) {
	delete(m.vertices)
	delete(m.indices)
	m^ = {}
}

// Whether a command is drawn from a mesh rather than by the shapes shader.
needs_mesh :: proc "contextless" (c: Command) -> bool {
	outline := c.style.stroke_on && c.style.thickness > 0
	switch c.kind {
	case .Quad, .Arc:
		return true
	case .Circle, .Ellipse:
		return false
	case .Rect, .Triangle:
		return outline && c.style.join != .Round
	case .Line, .Point:
		return c.style.cap != .Round
	}
	return false
}

// How much one unit in a shape's own space is on the canvas, on average.
@(private)
scale_of :: proc "contextless" (t: Transform) -> f64 {
	return math.sqrt(abs(f64(t.a) * f64(t.d) - f64(t.b) * f64(t.c)))
}

// Appends the triangles of `tri`, moved onto the canvas, in one colour.
@(private)
add_triangulation :: proc(m: ^Mesh, tri: geom.Triangulation, t: Transform, colour: [4]f32) {
	base := u32(len(m.vertices))
	for p in tri.points {
		x, y := transform_apply(t, f32(p.x), f32(p.y))
		append(&m.vertices, Mesh_Vertex{{x, y}, colour})
	}
	for index in tri.indices {
		append(&m.indices, base + index)
	}
}

// The corners of a command's outline in its own space, and whether it closes.
@(private)
outline_of :: proc(c: Command, tolerance: f64, points: ^[dynamic]geom.Point) -> (closed: bool) {
	a := c.args
	P :: proc(x, y: f32) -> geom.Point {return {f64(x), f64(y)}}
	switch c.kind {
	case .Rect:
		x, y, w, h := local_bounds(c)
		append(points, P(x, y), P(x + w, y), P(x + w, y + h), P(x, y + h))
		return true
	case .Triangle:
		append(points, P(a[0], a[1]), P(a[2], a[3]), P(a[4], a[5]))
		return true
	case .Quad:
		append(points, P(a[0], a[1]), P(a[2], a[3]), P(a[4], a[5]), P(a[6], a[7]))
		return true
	case .Line:
		append(points, P(a[0], a[1]), P(a[2], a[3]))
		return false
	case .Point:
		append(points, P(a[0], a[1]))
		return false
	case .Circle, .Ellipse, .Arc:
		// Not outlines of straight corners; arcs are handled apart.
		return false
	}
	return false
}

// Appends a command's fill and outline to the mesh.
mesh_add_command :: proc(m: ^Mesh, c: Command) {
	style := c.style
	scale := scale_of(c.transform)
	if !(scale > 0) || math.is_inf(scale) {
		return // flattened to nothing, or beyond sense
	}
	tolerance := geom.DEFAULT_TOLERANCE / scale // a tenth of a pixel on the canvas
	fill_colour := colour_for_gpu(style.fill, style.alpha)
	stroke_colour := colour_for_gpu(style.stroke, style.alpha)
	stroke := geom.Stroke_Options{
		half_width = f64(style.thickness) / 2,
		cap        = style.cap,
		join       = style.join,
		tolerance  = tolerance,
	}
	has_outline := style.stroke_on && style.thickness > 0
	tri: geom.Triangulation
	defer geom.triangulation_destroy(&tri)
	points := make([dynamic]geom.Point, context.temp_allocator)

	if c.kind == .Arc {
		arc_into_mesh(m, c, tolerance, fill_colour, stroke_colour, stroke)
		return
	}
	closed := outline_of(c, tolerance, &points)
	if style.fill_on && has_area(c) && closed {
		geom.triangulate({points[:]}, &tri)
		add_triangulation(m, tri, c.transform, fill_colour)
		geom.triangulation_destroy(&tri)
	}
	if has_outline && len(points) > 0 {
		geom.stroke_polyline(points[:], closed, stroke, &tri)
		add_triangulation(m, tri, c.transform, stroke_colour)
	}
}

// An arc is a piece of an ellipse: filled as a slice of pie (the centre and the
// curve), outlined along the curve only, or all the way round when it is the
// whole ellipse.
@(private)
arc_into_mesh :: proc(m: ^Mesh, c: Command, tolerance: f64, fill_colour, stroke_colour: [4]f32, stroke: geom.Stroke_Options) {
	a := c.args
	cx, cy := a[0], a[1]
	if !is_centred(c) {
		cx, cy = a[0] + a[2] / 2, a[1] + a[3] / 2
	}
	rx, ry := f64(a[2]) / 2, f64(a[3]) / 2
	start, stop := f64(a[4]), f64(a[5])
	sweep := stop - start
	if sweep == 0 {
		return
	}
	curve := make([dynamic]geom.Point, context.temp_allocator)
	geom.arc_points(&curve, f64(cx), f64(cy), rx, ry, start, stop, tolerance)
	if len(curve) < 2 {
		return
	}
	whole := abs(sweep) >= 360
	if whole {
		resize(&curve, len(curve) - 1) // the last point repeats the first
	}
	tri: geom.Triangulation
	defer geom.triangulation_destroy(&tri)
	if c.style.fill_on {
		polygon := make([dynamic]geom.Point, context.temp_allocator)
		if !whole {
			append(&polygon, geom.Point{f64(cx), f64(cy)})
		}
		append(&polygon, ..curve[:])
		geom.triangulate({polygon[:]}, &tri)
		add_triangulation(m, tri, c.transform, fill_colour)
		geom.triangulation_destroy(&tri)
	}
	if c.style.stroke_on && c.style.thickness > 0 {
		geom.stroke_polyline(curve[:], whole, stroke, &tri)
		add_triangulation(m, tri, c.transform, stroke_colour)
	}
}
