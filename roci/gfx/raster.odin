// SPDX-License-Identifier: 0BSD
//
// Painting into pixels with no GPU, for what has to be drawn where there may be no graphics card, such as the app
// icons `roci package` makes in a container: an SVG drawing (`Svg_Drawing`) with its fill rules, gradients, strokes
// and clips, a picture scaled into a rectangle, and masks of shapes. A raster holds premultiplied colors from 0
// to 1 in sRGB, mixed as SVG and the browsers mix them.
//
// A shape's coverage of each pixel is measured on 16 rows inside each pixel row, each crossing the shape's edges at
// exact points: the winding of the edges says what is inside (nonzero or even-odd, as the shape says), and the part
// of each pixel a run inside covers is added exactly across the row. Strokes are turned into triangles by
// `geom.stroke_polyline` (all wound the same way, so their union is the stroke) and covered the same way.
package gfx

import "../geom"
import "../maths"
import "core:math"
import "core:slice"

// How many rows inside a pixel row a coverage is measured on.
RASTER_ROWS :: 16

Raster :: struct {
	width, height: int,
	pixels:        [][4]f32, // premultiplied, 0 to 1, rows from the top
}

raster_make :: proc(width, height: int, allocator := context.allocator) -> Raster {
	w, h := max(width, 0), max(height, 0)
	return Raster{width = w, height = h, pixels = make([][4]f32, w * h, allocator)}
}

raster_destroy :: proc(r: ^Raster, allocator := context.allocator) {
	delete(r.pixels, allocator)
	r^ = {}
}

// The raster as a picture: straight 8-bit RGBA, as PNG files hold it.
raster_to_image :: proc(r: Raster, allocator := context.allocator) -> Image {
	out := make([]u8, r.width * r.height * 4, allocator)
	for p, i in r.pixels {
		a := clamp(p.a, 0, 1)
		if a > 0 {
			for k in 0 ..< 3 {
				out[i * 4 + k] = u8(clamp(p[k] / a, 0, 1) * 255 + 0.5)
			}
		}
		out[i * 4 + 3] = u8(a * 255 + 0.5)
	}
	return Image{width = r.width, height = r.height, pixels = out}
}

// A straight 0 to 255 color put over a pixel, covering `amount` of it (0 to 1).
@(private = "file")
over :: proc(dst: ^[4]f32, colour: maths.Colour, amount: f32) {
	a := clamp(colour.a / 255 * amount, 0, 1)
	if a <= 0 {
		return
	}
	dst^ = {colour.r / 255 * a, colour.g / 255 * a, colour.b / 255 * a, a} + dst^ * (1 - a)
}

// ---- coverage ----

@(private = "file")
Edge :: struct {
	x0, y0, x1, y1: f64, // y0 < y1
	dir:            i32, // +1 going down in the shape's own order, -1 going up
}

@(private = "file")
Crossing :: struct {
	x:   f64,
	dir: i32,
}

@(private = "file")
add_edge :: proc(edges: ^[dynamic]Edge, a, b: [2]f64) {
	if a.y == b.y || !(abs(a.x) < 1e9) || !(abs(b.x) < 1e9) || !(abs(a.y) < 1e9) || !(abs(b.y) < 1e9) {
		return
	}
	if a.y < b.y {
		append(edges, Edge{a.x, a.y, b.x, b.y, 1})
	} else {
		append(edges, Edge{b.x, b.y, a.x, a.y, -1})
	}
}

// Adds `weight` times the part of each pixel the run from xa to xb covers.
@(private = "file")
add_run :: proc(row: []f32, xa, xb: f64, weight: f32) {
	width := len(row)
	a, b := clamp(xa, 0, f64(width)), clamp(xb, 0, f64(width))
	if b <= a {
		return
	}
	ia, ib := int(a), int(b)
	if ia == ib {
		row[ia] += f32(b - a) * weight
		return
	}
	row[ia] += f32(f64(ia + 1) - a) * weight
	for i in ia + 1 ..< ib {
		row[i] += weight
	}
	if ib < width {
		row[ib] += f32(b - f64(ib)) * weight
	}
}

// Measures the coverage of every pixel by the shape the edges bound, in `cover` (width by height, rows from the
// top), and says which rows it wrote: every pixel of them, from `first` up to but not including `last`. Rows
// outside are not touched.
@(private = "file")
cover_edges :: proc(edges: []Edge, nonzero: bool, cover: []f32, width, height: int) -> (first, last: int) {
	if len(edges) == 0 || width <= 0 || height <= 0 {
		return 0, 0
	}
	slice.sort_by(edges, proc(a, b: Edge) -> bool { return a.y0 < b.y0 })
	top, bottom := edges[0].y0, edges[0].y1
	for e in edges {
		bottom = max(bottom, e.y1)
	}
	first = clamp(int(math.floor(top)), 0, height)
	last = clamp(int(math.ceil(bottom)), 0, height)
	active := make([dynamic]int, context.temp_allocator)
	crossings := make([dynamic]Crossing, context.temp_allocator)
	next := 0
	weight := f32(1) / RASTER_ROWS
	for py in first ..< last {
		row := cover[py * width:][:width]
		slice.fill(row, 0)
		for s in 0 ..< RASTER_ROWS {
			ys := f64(py) + (f64(s) + 0.5) / RASTER_ROWS
			for next < len(edges) && edges[next].y0 <= ys {
				append(&active, next)
				next += 1
			}
			clear(&crossings)
			kept := 0
			for i in active {
				e := edges[i]
				if e.y1 <= ys {
					continue
				}
				active[kept] = i
				kept += 1
				if e.y0 <= ys {
					append(&crossings, Crossing{e.x0 + (ys - e.y0) * (e.x1 - e.x0) / (e.y1 - e.y0), e.dir})
				}
			}
			resize(&active, kept)
			slice.sort_by(crossings[:], proc(a, b: Crossing) -> bool { return a.x < b.x })
			winding: i32 = 0
			for c, i in crossings {
				winding += c.dir if nonzero else 1
				inside := winding != 0 if nonzero else winding % 2 == 1
				if inside && i + 1 < len(crossings) {
					add_run(row, c.x, crossings[i + 1].x, weight)
				}
			}
		}
		for &v in row {
			v = min(v, 1)
		}
	}
	return
}

// Where a point of a drawing lands in pixels.
Raster_Place :: struct {
	scale_x, scale_y: f64,
	offset_x, offset_y: f64,
}

@(private = "file")
to_pixels :: proc(place: Raster_Place, p: [2]f32) -> [2]f64 {
	return {f64(p.x) * place.scale_x + place.offset_x, f64(p.y) * place.scale_y + place.offset_y}
}

@(private = "file")
fill_edges :: proc(contours: []Contour, place: Raster_Place) -> [dynamic]Edge {
	edges := make([dynamic]Edge, context.temp_allocator)
	for contour in contours {
		n := len(contour.points)
		if n < 2 {
			continue
		}
		// a fill closes every contour
		for i in 0 ..< n {
			add_edge(&edges, to_pixels(place, contour.points[i]), to_pixels(place, contour.points[(i + 1) % n]))
		}
	}
	return edges
}

@(private = "file")
stroke_edges :: proc(contours: []Contour, place: Raster_Place, width: f64, cap: geom.Cap, join: geom.Join) -> [dynamic]Edge {
	edges := make([dynamic]Edge, context.temp_allocator)
	scale := math.sqrt(abs(place.scale_x * place.scale_y))
	options := geom.Stroke_Options{half_width = width * scale / 2, cap = cap, join = join, tolerance = 0.1}
	if !(options.half_width > 0) {
		return edges
	}
	for contour in contours {
		points := make([]geom.Point, len(contour.points), context.temp_allocator)
		for p, i in contour.points {
			q := to_pixels(place, p)
			points[i] = {q.x, q.y}
		}
		triangles: geom.Triangulation
		triangles.points = make([dynamic]geom.Point, context.temp_allocator)
		triangles.indices = make([dynamic]u32, context.temp_allocator)
		geom.stroke_polyline(points, contour.closed, options, &triangles)
		for i := 0; i + 2 < len(triangles.indices); i += 3 {
			a := triangles.points[triangles.indices[i]]
			b := triangles.points[triangles.indices[i + 1]]
			c := triangles.points[triangles.indices[i + 2]]
			add_edge(&edges, {a.x, a.y}, {b.x, b.y})
			add_edge(&edges, {b.x, b.y}, {c.x, c.y})
			add_edge(&edges, {c.x, c.y}, {a.x, a.y})
		}
	}
	return edges
}

// The coverage of every pixel by closed contours (in the units `place` maps to pixels), with the fill rule
// given: a mask from 0 to 1, width by height, rows from the top.
raster_contour_mask :: proc(contours: []Contour, place: Raster_Place, nonzero: bool, width, height: int, allocator := context.allocator) -> []f32 {
	mask := make([]f32, max(width, 0) * max(height, 0), allocator)
	edges := fill_edges(contours, place)
	cover_edges(edges[:], nonzero, mask, width, height)
	return mask
}

// ---- gradients ----

// Where a point of the drawing falls in a gradient, 0 at its start and 1 at its end, before it is spread.
@(private)
gradient_place :: proc(g: Svg_Gradient, p: [2]f64) -> f64 {
	m := g.to_gradient
	q := [2]f64{m[0] * p.x + m[2] * p.y + m[4], m[1] * p.x + m[3] * p.y + m[5]}
	if !g.radial {
		d := [2]f64{g.x2 - g.x1, g.y2 - g.y1}
		length := d.x * d.x + d.y * d.y
		if length <= 0 {
			return 1 // a gradient whose two ends are one point is its last color
		}
		return ((q.x - g.x1) * d.x + (q.y - g.y1) * d.y) / length
	}
	if !(g.r > 0) {
		return 1
	}
	// the focal point is kept a little inside the circle, as SVG 1.1 says
	f := [2]f64{g.fx, g.fy}
	c := [2]f64{g.cx, g.cy}
	e := f - c
	if e.x * e.x + e.y * e.y > g.r * g.r * 0.99 * 0.99 {
		e *= g.r * 0.99 / math.sqrt(e.x * e.x + e.y * e.y)
		f = c + e
	}
	d := q - f
	dd := d.x * d.x + d.y * d.y
	if dd <= 0 {
		return 0
	}
	// the point on the circle along the ray from the focal point through q: f + k d, |e + k d| = r
	ed := e.x * d.x + e.y * d.y
	ee := e.x * e.x + e.y * e.y
	k := (-ed + math.sqrt(max(ed * ed - dd * (ee - g.r * g.r), 0))) / dd
	return 1 / k if k > 0 else 1
}

@(private)
gradient_spread :: proc(t: f64, how: Svg_Spread) -> f64 {
	switch how {
	case .Pad:
		return clamp(t, 0, 1)
	case .Repeat:
		return t - math.floor(t)
	case .Reflect:
		u := math.mod(abs(t), 2)
		return 2 - u if u > 1 else u
	}
	return clamp(t, 0, 1)
}

// The color at a place of a gradient's stops (straight, 0 to 255).
raster_stop_colour :: proc(stops: []Svg_Stop, t: f64) -> maths.Colour {
	if len(stops) == 0 {
		return {}
	}
	if t <= f64(stops[0].offset) {
		return stops[0].colour
	}
	for i in 1 ..< len(stops) {
		a, b := stops[i - 1], stops[i]
		if t <= f64(b.offset) {
			span := f64(b.offset - a.offset)
			if span <= 0 {
				return b.colour
			}
			k := f32((t - f64(a.offset)) / span)
			return a.colour + (b.colour - a.colour) * k
		}
	}
	return stops[len(stops) - 1].colour
}

// ---- drawings ----

// Paints a drawing with its view stretched over the rectangle from (x, y), `width` by `height` pixels.
raster_svg :: proc(r: ^Raster, d: ^Svg_Drawing, x, y, width, height: f64) {
	if r.width <= 0 || r.height <= 0 || !(d.width > 0) || !(d.height > 0) {
		return
	}
	place := Raster_Place{width / f64(d.width), height / f64(d.height), x, y}
	cover := make([]f32, r.width * r.height, context.temp_allocator)
	clip_masks := make(map[i32][]f32, len(d.clips), context.temp_allocator)
	for item in d.items {
		// the clips the item is cut by, each measured once
		masks := make([dynamic][]f32, context.temp_allocator)
		for c in item.clips {
			if int(c) >= len(d.clips) {
				continue
			}
			mask, made := clip_masks[c]
			if !made {
				mask = make([]f32, r.width * r.height, context.temp_allocator)
				for shape in d.clips[c].shapes {
					one := raster_contour_mask(shape.contours, place, shape.nonzero, r.width, r.height, context.temp_allocator)
					for v, i in one {
						mask[i] = max(mask[i], v)
					}
				}
				clip_masks[c] = mask
			}
			append(&masks, mask)
		}
		if item.fill_on {
			edges := fill_edges(item.contours, place)
			first, last := cover_edges(edges[:], item.nonzero, cover, r.width, r.height)
			paint(r, d, cover, first, last, masks[:], place, item.fill, item.fill_gradient, item.fill_alpha)
		}
		if item.stroke_on {
			edges := stroke_edges(item.contours, place, f64(item.width), item.cap, item.join)
			first, last := cover_edges(edges[:], true, cover, r.width, r.height)
			paint(r, d, cover, first, last, masks[:], place, item.stroke, item.stroke_gradient, item.stroke_alpha)
		}
	}
}

// Puts an item's paint over the pixels its coverage reaches, cut by its clips.
@(private = "file")
paint :: proc(r: ^Raster, d: ^Svg_Drawing, cover: []f32, first, last: int, masks: [][]f32, place: Raster_Place, colour: maths.Colour, gradient: i32, alpha: f32) {
	has_gradient := gradient >= 0 && int(gradient) < len(d.gradients)
	for py in first ..< last {
		for px in 0 ..< r.width {
			i := py * r.width + px
			amount := cover[i]
			if amount <= 0 {
				continue
			}
			for m in masks {
				amount *= m[i]
			}
			if amount <= 0 {
				continue
			}
			c := colour
			if has_gradient {
				g := d.gradients[gradient]
				p := [2]f64{(f64(px) + 0.5 - place.offset_x) / place.scale_x, (f64(py) + 0.5 - place.offset_y) / place.scale_y}
				c = raster_stop_colour(g.stops, gradient_spread(gradient_place(g, p), g.spread))
				c.a *= alpha
			}
			over(&r.pixels[i], c, amount)
		}
	}
}

// ---- pictures and masks ----

// Puts a picture (straight 8-bit RGBA) over the raster, scaled into the rectangle from (x, y), `width` by `height`
// pixels: each pixel is the average of the part of the picture it covers, so a large picture made small keeps its
// detail instead of flickering, and a pixel the rectangle covers only partly is covered only partly.
raster_image :: proc(r: ^Raster, img: Image, x, y, width, height: f64) {
	if img.width <= 0 || img.height <= 0 || !(width > 0) || !(height > 0) || len(img.pixels) < img.width * img.height * 4 {
		return
	}
	sx := f64(img.width) / width
	sy := f64(img.height) / height
	x0, y0 := max(int(math.floor(x)), 0), max(int(math.floor(y)), 0)
	x1, y1 := min(int(math.ceil(x + width)), r.width), min(int(math.ceil(y + height)), r.height)
	for py in y0 ..< y1 {
		top, bottom := max(f64(py), y), min(f64(py + 1), y + height)
		if bottom <= top {
			continue
		}
		for px in x0 ..< x1 {
			left, right := max(f64(px), x), min(f64(px + 1), x + width)
			if right <= left {
				continue
			}
			// the part of the picture this part of the pixel covers, in its own pixels
			a0, a1 := (left - x) * sx, (right - x) * sx
			b0, b1 := (top - y) * sy, (bottom - y) * sy
			sum: [4]f64
			area := 0.0
			for qy in int(b0) ..< min(int(math.ceil(b1)), img.height) {
				hy := min(f64(qy + 1), b1) - max(f64(qy), b0)
				if hy <= 0 {
					continue
				}
				for qx in int(a0) ..< min(int(math.ceil(a1)), img.width) {
					hx := min(f64(qx + 1), a1) - max(f64(qx), a0)
					if hx <= 0 {
						continue
					}
					k := hx * hy
					at := (qy * img.width + qx) * 4
					alpha := f64(img.pixels[at + 3]) / 255
					sum += {f64(img.pixels[at]) / 255 * alpha, f64(img.pixels[at + 1]) / 255 * alpha, f64(img.pixels[at + 2]) / 255 * alpha, alpha} * k
					area += k
				}
			}
			if area <= 0 {
				continue
			}
			// premultiplied, scaled by how much of the pixel the rectangle covers
			part := (right - left) * (bottom - top)
			src := [4]f32{f32(sum[0] / area * part), f32(sum[1] / area * part), f32(sum[2] / area * part), f32(sum[3] / area * part)}
			i := py * r.width + px
			r.pixels[i] = src + r.pixels[i] * (1 - src.a)
		}
	}
}

// Multiplies every pixel by a mask (0 to 1, the raster's size): what is outside the mask is cleared.
raster_apply_mask :: proc(r: ^Raster, mask: []f32) {
	for &p, i in r.pixels {
		p *= mask[i] if i < len(mask) else 0
	}
}

// Fills every pixel outside the rectangle from (x0, y0) to (x1, y1) with the nearest pixel inside it, so a picture
// placed in the middle seems to go on to the edges.
raster_extend :: proc(r: ^Raster, x0, y0, x1, y1: int) {
	ax, ay := clamp(x0, 0, r.width - 1), clamp(y0, 0, r.height - 1)
	bx, by := clamp(x1 - 1, ax, r.width - 1), clamp(y1 - 1, ay, r.height - 1)
	for py in 0 ..< r.height {
		for px in 0 ..< r.width {
			if px >= ax && px <= bx && py >= ay && py <= by {
				continue
			}
			r.pixels[py * r.width + px] = r.pixels[clamp(py, ay, by) * r.width + clamp(px, ax, bx)]
		}
	}
}

// Puts the raster over a solid color, so no pixel is see-through.
raster_flatten :: proc(r: ^Raster, colour: maths.Colour) {
	base := [4]f32{colour.r / 255, colour.g / 255, colour.b / 255, 1}
	for &p in r.pixels {
		p = p + base * (1 - p.a)
	}
}

// The corners of a rectangle with rounded corners, as one closed contour.
raster_rounded_rect :: proc(x, y, width, height, radius: f64, allocator := context.allocator) -> []Contour {
	points := make([dynamic][2]f32, allocator)
	rr := clamp(radius, 0, min(width, height) / 2)
	corners := [4][3]f64{{x + width - rr, y + rr, -math.PI / 2}, {x + width - rr, y + height - rr, 0}, {x + rr, y + height - rr, math.PI / 2}, {x + rr, y + rr, math.PI}}
	for c in corners {
		steps := 16 if rr > 0 else 1
		for k in 0 ..= steps {
			angle := c[2] + math.PI / 2 * f64(k) / f64(steps)
			append(&points, [2]f32{f32(c[0] + rr * math.cos(angle)), f32(c[1] + rr * math.sin(angle))})
		}
	}
	contours := make([]Contour, 1, allocator)
	contours[0] = {points[:], true}
	return contours
}

// A circle as one closed contour.
raster_circle :: proc(cx, cy, radius: f64, allocator := context.allocator) -> []Contour {
	steps := 128
	points := make([][2]f32, steps, allocator)
	for k in 0 ..< steps {
		angle := 2 * math.PI * f64(k) / f64(steps)
		points[k] = {f32(cx + radius * math.cos(angle)), f32(cy + radius * math.sin(angle))}
	}
	contours := make([]Contour, 1, allocator)
	contours[0] = {points, true}
	return contours
}
