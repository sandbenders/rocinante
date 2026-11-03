// SPDX-License-Identifier: 0BSD
//
// Shapes filled with a picture. The shape is a mask: its fill is cut into triangles
// in its own space (the same flattening and triangulation the mesh uses), each
// corner is given the place in the picture that lies under it, and the triangles are
// drawn through the typeset pipeline as a textured mesh, so a picture fill keeps its
// order among shapes and text. The shader clips what falls outside the picture (`fit`,
// `center`) and repeats it (`tile`). The edge of the shape is smoothed by
// multisampling, as for every mesh. The outline, when there is one, is drawn after the
// fill by the ordinary pipelines.
package gfx

import "../geom"
import "core:math"
import sdl "vendor:sdl3"

// Whether a kind of shape can be filled with a picture. Lines and points have no
// inside; text and pictures are drawn by their own rules.
image_fillable :: proc "contextless" (kind: Kind) -> bool {
	switch kind {
	case .Circle, .Ellipse, .Rect, .Triangle, .Quad, .Arc:
		return true
	case .Line, .Point, .Text, .Typeset, .Image:
		return false
	}
	return false
}

// The item for the fill of a shape: the shape, how the picture sits in it, and the
// tint with the style's alpha.
fill_item :: proc(c: Command) -> Typeset_Item {
	return Typeset_Item{
		image         = c.style.fill_image.image,
		premultiplied = canvas_of(c.style.fill_image.image) != nil,
		filled        = true,
		shape         = c,
		fill          = c.style.fill_image,
		colour        = colour_for_gpu(c.style.tint, c.style.alpha),
		transform     = c.transform,
		content       = c.content,
	}
}

// Where the picture's corners are, as a fraction of the shape's box, for the way it
// fills: the picture's top left corner and its size, in the box's own units, with the
// box's top left corner as the origin.
@(private)
picture_placement :: proc "contextless" (fill: Image_Fill, box_w, box_h, picture_w, picture_h: f32) -> (x, y, w, h: f32) {
	switch fill.fit {
	case .Stretch:
		return 0, 0, box_w, box_h
	case .Cover, .Fit:
		s := max(box_w / picture_w, box_h / picture_h) if fill.fit == .Cover else min(box_w / picture_w, box_h / picture_h)
		w, h = picture_w * s, picture_h * s
		return (box_w - w) / 2, (box_h - h) / 2, w, h
	case .Center:
		return (box_w - picture_w) / 2 + fill.at.x, (box_h - picture_h) / 2 + fill.at.y, picture_w, picture_h
	case .Tile:
		w = fill.tile if fill.tile > 0 else picture_w
		h = picture_h * w / picture_w
		return fill.at.x, fill.at.y, w, h
	}
	return 0, 0, box_w, box_h
}

// The place in the picture under a point of the shape's own space, as a fraction of
// the picture (0 to 1 across it).
picture_uv :: proc "contextless" (fill: Image_Fill, box: [4]f32, picture_w, picture_h: f32, px, py: f32) -> [2]f32 {
	x, y, w, h := picture_placement(fill, box[2], box[3], picture_w, picture_h)
	return {(px - box[0] - x) / w, (py - box[1] - y) / h}
}

// The polygon a shape's fill covers, in its own space. False for a shape with
// nothing to fill.
@(private)
fill_polygon :: proc(c: Command, tolerance: f64, points: ^[dynamic]geom.Point) -> bool {
	a := c.args
	P :: proc(x, y: f32) -> geom.Point {return {f64(x), f64(y)}}
	switch c.kind {
	case .Rect, .Triangle, .Quad:
		return outline_of(c, tolerance, points)
	case .Circle, .Ellipse:
		x, y, w, h := local_bounds(c)
		geom.arc_points(points, f64(x + w / 2), f64(y + h / 2), f64(w) / 2, f64(h) / 2, 0, 360, tolerance)
		if len(points) < 3 {
			return false
		}
		resize(points, len(points) - 1) // the last point repeats the first
		return true
	case .Arc:
		x, y, w, h := local_bounds(c)
		cx, cy := f64(x + w / 2), f64(y + h / 2)
		start, stop := f64(a[4]), f64(a[5])
		if start == stop {
			return false
		}
		whole := abs(stop - start) >= 360
		curve := make([dynamic]geom.Point, context.temp_allocator)
		geom.arc_points(&curve, cx, cy, f64(w) / 2, f64(h) / 2, start, stop, tolerance)
		if len(curve) < 2 {
			return false
		}
		if whole {
			resize(&curve, len(curve) - 1)
		} else {
			append(points, geom.Point{cx, cy})
		}
		append(points, ..curve[:])
		return true
	case .Line, .Point, .Text, .Typeset, .Image:
	}
	return false
}

// Adds the triangles of a shape filled with a picture to the frame.
@(private)
image_fill_vertices :: proc(r: ^Renderer, commands: ^sdl.GPUCommandBuffer, item_index: int, item: Typeset_Item) {
	s := &r.typeset
	data := image_data(item.image)
	texture := image_texture(r, commands, item.image)
	if texture == nil || data == nil {
		return
	}
	scale := scale_of(item.transform)
	if !(scale > 0) || math.is_inf(scale) {
		return
	}
	points := make([dynamic]geom.Point, context.temp_allocator)
	if !fill_polygon(item.shape, geom.DEFAULT_TOLERANCE / scale, &points) {
		return
	}
	tri: geom.Triangulation
	defer geom.triangulation_destroy(&tri)
	geom.triangulate({points[:]}, &tri)
	if len(tri.indices) == 0 {
		return
	}
	bx, by, bw, bh := local_bounds(item.shape)
	picture_w, picture_h := f32(data.width), f32(data.height)
	// 2 for a picture, plus 1 for a premultiplied one, 2 for clipping what the picture does
	// not reach and 4 for repeating it (typeset.hlsl)
	coloured := f32(2)
	if item.premultiplied {coloured += 1}
	switch item.fill.fit {
	case .Fit, .Center: coloured += 2
	case .Tile:         coloured += 4
	case .Cover, .Stretch:
	}
	base := u32(len(s.vertices))
	first := u32(len(s.indices))
	for p in tri.points {
		x, y := transform_apply(item.transform, f32(p.x), f32(p.y))
		uv := picture_uv(item.fill, {bx, by, bw, bh}, picture_w, picture_h, f32(p.x), f32(p.y))
		append(&s.vertices, Typeset_Vertex{{x, y}, uv, item.colour, coloured})
	}
	for index in tri.indices {
		append(&s.indices, base + index)
	}
	append(&s.draws, Typeset_Draw{item_index, texture, first, u32(len(s.indices)) - first})
}
