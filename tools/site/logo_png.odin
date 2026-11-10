// SPDX-License-Identifier: 0BSD
//
// The logo as PNG pictures, for places that take no SVG (an avatar, a profile, a
// store): `odin run tools/site -- --logo` draws them from the logo's one drawing and a
// test keeps them the same. They are drawn here on the CPU, not by the renderer, so
// they need no graphics card and come out the same on every computer: the drawing is
// read by a small SVG reader that knows only what the logo uses (groups, paths of
// straight lines and arcs, circles, translate and scale) and says so when it meets
// anything else, the outline is cut into triangles by geom's stroker, and every pixel
// is 16 by 16 samples, each taking the colour of the last shape that covers it
// (nonzero winding), as a browser paints an SVG.
package site_tool

import "core:fmt"
import "core:math"
import "core:slice"
import "core:strconv"
import "core:strings"
import "../../roci/geom"
import sancho "../../vendor/sancho/png_writer"

LOGO_PNG :: "docs/logo/rocinante-logo-192.png"
LOGO_PNG_WHITE :: "docs/logo/rocinante-logo-192-white.png"
LOGO_PNG_SIZE :: 192
// The space left round the drawing's box, in pixels of the picture.
LOGO_PNG_MARGIN :: 4
// Samples along each side of a pixel.
LOGO_SAMPLES :: 16
// How far a flattened arc may stray from the true one, in pixels of the picture.
LOGO_TOLERANCE :: 0.02

Point :: geom.Point

// x' = a x + c y + e, y' = b x + d y + f, as SVG writes a matrix.
Affine :: [6]f64

AFFINE_IDENTITY :: Affine{1, 0, 0, 1, 0, 0}

affine_mul :: proc(m, n: Affine) -> Affine {
	return {
		m[0] * n[0] + m[2] * n[1],
		m[1] * n[0] + m[3] * n[1],
		m[0] * n[2] + m[2] * n[3],
		m[1] * n[2] + m[3] * n[3],
		m[0] * n[4] + m[2] * n[5] + m[4],
		m[1] * n[4] + m[3] * n[5] + m[5],
	}
}

affine_apply :: proc(m: Affine, p: Point) -> Point {
	return {m[0] * p.x + m[2] * p.y + m[4], m[1] * p.x + m[3] * p.y + m[5]}
}

// One painted shape, in pixels of the picture: its outlines (closed, filled by the
// nonzero rule) and its colour.
Logo_Shape :: struct {
	contours: [][]Point,
	colour:   [3]u8,
}

// The drawing as RGBA pixels with straight alpha, `size` pixels square, the viewBox
// fitted inside the margin and centred. Everything is made with the temporary
// allocator. Gives false, having said why, when the SVG uses what the reader does not know.
logo_pixels :: proc(svg: string, size: int) -> (rgba: []u8, ok: bool) {
	shapes := logo_shapes(svg, size) or_return
	n := size * LOGO_SAMPLES
	painted := make([]u8, n * n, context.temp_allocator) // 0 is nothing, i is shapes[i - 1]
	for shape, i in shapes {
		fill_nonzero(painted, n, shape.contours, u8(i + 1))
	}
	rgba = make([]u8, size * size * 4, context.temp_allocator)
	per_pixel :: LOGO_SAMPLES * LOGO_SAMPLES
	for py in 0 ..< size {
		for px in 0 ..< size {
			sum: [3]int
			covered := 0
			for sy in 0 ..< LOGO_SAMPLES {
				row := (py * LOGO_SAMPLES + sy) * n + px * LOGO_SAMPLES
				for sx in 0 ..< LOGO_SAMPLES {
					if s := painted[row + sx]; s != 0 {
						c := shapes[s - 1].colour
						sum += {int(c.r), int(c.g), int(c.b)}
						covered += 1
					}
				}
			}
			o := (py * size + px) * 4
			if covered > 0 {
				for ch in 0 ..< 3 {
					rgba[o + ch] = u8((sum[ch] + covered / 2) / covered)
				}
			}
			rgba[o + 3] = u8((covered * 255 + per_pixel / 2) / per_pixel)
		}
	}
	return rgba, true
}

// RGBA with straight alpha laid over white, as RGB.
on_white :: proc(rgba: []u8) -> []u8 {
	rgb := make([]u8, len(rgba) / 4 * 3, context.temp_allocator)
	for i in 0 ..< len(rgba) / 4 {
		a := int(rgba[i * 4 + 3])
		for ch in 0 ..< 3 {
			rgb[i * 3 + ch] = u8((int(rgba[i * 4 + ch]) * a + 255 * (255 - a) + 127) / 255)
		}
	}
	return rgb
}

// Both pictures as PNG files: the logo on nothing, and on white.
logo_pngs :: proc(svg: string) -> (clear, white: []u8, ok: bool) {
	rgba := logo_pixels(svg, LOGO_PNG_SIZE) or_return
	err: sancho.Error
	clear, err = sancho.encode(rgba, LOGO_PNG_SIZE, LOGO_PNG_SIZE, 4, allocator = context.temp_allocator)
	if err != nil {
		return nil, nil, false
	}
	white, err = sancho.encode(on_white(rgba), LOGO_PNG_SIZE, LOGO_PNG_SIZE, 3, allocator = context.temp_allocator)
	return clear, white, err == nil
}

// Paints `mark` into every sample whose centre the contours cover by the nonzero rule.
// The samples are an `n` by `n` square, one pixel of the picture `LOGO_SAMPLES` wide.
fill_nonzero :: proc(painted: []u8, n: int, contours: [][]Point, mark: u8) {
	Crossing :: struct {
		x:   f64,
		dir: int,
	}
	low, high := max(f64), min(f64)
	for c in contours {
		for p in c {
			low, high = min(low, p.y), max(high, p.y)
		}
	}
	scale := f64(LOGO_SAMPLES)
	first := max(int(math.floor(low * scale)), 0)
	last := min(int(math.ceil(high * scale)), n - 1)
	crossings := make([dynamic]Crossing, context.temp_allocator)
	for sy in first ..= last {
		y := (f64(sy) + 0.5) / scale
		clear(&crossings)
		for c in contours {
			for p, i in c {
				q := c[(i + 1) % len(c)]
				if (p.y <= y) != (q.y <= y) {
					append(&crossings, Crossing{p.x + (y - p.y) * (q.x - p.x) / (q.y - p.y), 1 if q.y > p.y else -1})
				}
			}
		}
		slice.sort_by(crossings[:], proc(a, b: Crossing) -> bool { return a.x < b.x })
		winding := 0
		for i in 0 ..< len(crossings) - 1 {
			winding += crossings[i].dir
			if winding == 0 {
				continue
			}
			// The samples whose centres lie between this crossing and the next.
			from := clamp(int(math.ceil(crossings[i].x * scale - 0.5)), 0, n)
			to := clamp(int(math.ceil(crossings[i + 1].x * scale - 0.5)), 0, n)
			for sx in from ..< to {
				painted[sy * n + sx] = mark
			}
		}
	}
}

// ---- reading the SVG ----

// The shapes of the drawing in paint order, in pixels of a `size` square picture.
logo_shapes :: proc(svg: string, size: int) -> (shapes: []Logo_Shape, ok: bool) {
	out := make([dynamic]Logo_Shape, context.temp_allocator)
	stack := make([dynamic]Affine, context.temp_allocator)
	append(&stack, AFFINE_IDENTITY)
	scale := 1.0
	seen_svg := false
	rest := svg
	for {
		open := strings.index_byte(rest, '<')
		if open < 0 {
			break
		}
		close := strings.index_byte(rest[open:], '>')
		if close < 0 {
			return nil, svg_problem("a tag that never closes")
		}
		tag := rest[open + 1:open + close]
		rest = rest[open + close + 1:]
		if strings.has_prefix(tag, "?") || strings.has_prefix(tag, "!") {
			continue
		}
		if strings.has_prefix(tag, "/") {
			if strings.trim_space(tag[1:]) == "g" {
				if len(stack) < 2 {
					return nil, svg_problem("a group closed that was never opened")
				}
				pop(&stack)
			}
			continue
		}
		self_closing := strings.has_suffix(tag, "/")
		if self_closing {
			tag = tag[:len(tag) - 1]
		}
		name, attrs := svg_tag(tag)
		local := svg_transform(attrs["transform"]) or_return
		here := affine_mul(stack[len(stack) - 1], local)
		switch name {
		case "svg":
			box := svg_numbers(attrs["viewBox"]) or_return
			if len(box) != 4 || !(box[2] > 0) || !(box[3] > 0) {
				return nil, svg_problem("an svg element without a viewBox of four numbers")
			}
			// The viewBox fitted inside the margin and centred.
			scale = f64(size - 2 * LOGO_PNG_MARGIN) / max(box[2], box[3])
			offset := Point{(f64(size) - box[2] * scale) / 2, (f64(size) - box[3] * scale) / 2}
			stack[0] = {scale, 0, 0, scale, offset.x - box[0] * scale, offset.y - box[1] * scale}
			seen_svg = true
		case "title":
		case "g":
			if !self_closing {
				append(&stack, here)
			}
		case "path", "circle":
			if !seen_svg {
				return nil, svg_problem("a shape before the svg element")
			}
			subpaths: []Subpath
			if name == "path" {
				subpaths = svg_path(attrs["d"], LOGO_TOLERANCE / scale) or_return
			} else {
				subpaths = svg_circle(attrs, LOGO_TOLERANCE / scale) or_return
			}
			// Into pixels of the picture.
			for &sp in subpaths {
				moved := make([]Point, len(sp.points), context.temp_allocator)
				for p, i in sp.points {
					moved[i] = affine_apply(here, p)
				}
				sp.points = moved
			}
			fill, has_fill := svg_paint(attrs, "fill", "#000") or_return
			if has_fill && len(subpaths) > 0 {
				contours := make([dynamic][]Point, context.temp_allocator)
				for sp in subpaths {
					append(&contours, sp.points)
				}
				append(&out, Logo_Shape{contours[:], fill})
			}
			stroke, has_stroke := svg_paint(attrs, "stroke", "none") or_return
			if has_stroke && len(subpaths) > 0 {
				append(&out, svg_stroke(subpaths, attrs, stroke, here) or_return)
			}
		case:
			return nil, svg_problem(fmt.tprintf("a %s element", name))
		}
	}
	if !seen_svg {
		return nil, svg_problem("no svg element")
	}
	if len(out) > 255 {
		return nil, svg_problem("more than 255 shapes")
	}
	return out[:], true
}

@(private = "file")
svg_problem :: proc(what: string) -> bool {
	fmt.eprintfln("site: cannot draw the logo's PNG pictures: %s has %s, and tools/site reads only groups, paths of lines and arcs, circles, colours, translate and scale", LOGO, what)
	return false
}

// A tag's name and its attributes.
svg_tag :: proc(tag: string) -> (name: string, attrs: map[string]string) {
	attrs = make(map[string]string, context.temp_allocator)
	s := strings.trim_space(tag)
	end := 0
	for end < len(s) && !strings.is_space(rune(s[end])) {
		end += 1
	}
	name = s[:end]
	s = s[end:]
	for {
		eq := strings.index_byte(s, '=')
		if eq < 0 {
			break
		}
		key := strings.trim_space(s[:eq])
		s = strings.trim_left_space(s[eq + 1:])
		if len(s) == 0 || (s[0] != '"' && s[0] != '\'') {
			break
		}
		quote := s[0]
		close := strings.index_byte(s[1:], quote)
		if close < 0 {
			break
		}
		attrs[key] = s[1:close + 1]
		s = s[close + 2:]
	}
	return
}

// The numbers in an attribute, apart by spaces or commas.
svg_numbers :: proc(text: string) -> (numbers: []f64, ok: bool) {
	out := make([dynamic]f64, context.temp_allocator)
	fields := strings.fields(strings.trim_space(strings.join(strings.split(text, ",", context.temp_allocator), " ", context.temp_allocator)), context.temp_allocator)
	for f in fields {
		n, parsed := strconv.parse_f64(f)
		if !parsed {
			return nil, svg_problem(fmt.tprintf("the number %q", f))
		}
		append(&out, n)
	}
	return out[:], true
}

// A `transform` attribute of translate and scale steps.
svg_transform :: proc(text: string) -> (m: Affine, ok: bool) {
	m = AFFINE_IDENTITY
	s := strings.trim_space(text)
	for len(s) > 0 {
		open := strings.index_byte(s, '(')
		close := strings.index_byte(s, ')')
		if open < 0 || close < open {
			return m, svg_problem(fmt.tprintf("the transform %q", text))
		}
		kind := strings.trim_space(s[:open])
		args := svg_numbers(s[open + 1:close]) or_return
		step: Affine
		switch {
		case kind == "translate" && len(args) == 1:
			step = {1, 0, 0, 1, args[0], 0}
		case kind == "translate" && len(args) == 2:
			step = {1, 0, 0, 1, args[0], args[1]}
		case kind == "scale" && len(args) == 1:
			step = {args[0], 0, 0, args[0], 0, 0}
		case kind == "scale" && len(args) == 2:
			step = {args[0], 0, 0, args[1], 0, 0}
		case:
			return m, svg_problem(fmt.tprintf("the transform %q", text))
		}
		m = affine_mul(m, step)
		s = strings.trim_left(s[close + 1:], " ,")
	}
	return m, true
}

// A colour, or none. A missing attribute is `otherwise`, SVG's default for it.
svg_paint :: proc(attrs: map[string]string, key, otherwise: string) -> (colour: [3]u8, painted: bool, ok: bool) {
	text := attrs[key] or_else otherwise
	switch text {
	case "none":
		return {}, false, true
	case "black":
		return {0, 0, 0}, true, true
	case "white":
		return {255, 255, 255}, true, true
	}
	digits := text[1:] if strings.has_prefix(text, "#") else ""
	if len(digits) == 3 {
		digits = strings.concatenate({digits[0:1], digits[0:1], digits[1:2], digits[1:2], digits[2:3], digits[2:3]}, context.temp_allocator)
	}
	if len(digits) == 6 {
		value, parsed := strconv.parse_u64_of_base(digits, 16)
		if parsed {
			return {u8(value >> 16), u8(value >> 8), u8(value)}, true, true
		}
	}
	return {}, false, svg_problem(fmt.tprintf("the colour %q", text))
}

// A run of points from a move to the next move, closed when it ends with Z.
Subpath :: struct {
	points: []Point,
	closed: bool,
}

// A path's `d` of absolute moves, lines, arcs and closes, flattened in its own units.
svg_path :: proc(d: string, tolerance: f64) -> (subpaths: []Subpath, ok: bool) {
	out := make([dynamic]Subpath, context.temp_allocator)
	points := make([dynamic]Point, context.temp_allocator)
	finish :: proc(out: ^[dynamic]Subpath, points: ^[dynamic]Point, closed: bool) {
		if len(points) > 1 {
			append(out, Subpath{slice.clone(points[:], context.temp_allocator), closed})
		}
		clear(points)
	}
	// The commands and numbers, one word each.
	words := make([dynamic]string, context.temp_allocator)
	i := 0
	for i < len(d) {
		c := d[i]
		switch {
		case c == ' ' || c == ',' || c == '\n' || c == '\t' || c == '\r':
			i += 1
		case (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'):
			append(&words, d[i:i + 1])
			i += 1
		case:
			start := i
			i += 1
			for i < len(d) && ((d[i] >= '0' && d[i] <= '9') || d[i] == '.') {
				i += 1
			}
			append(&words, d[start:i])
		}
	}
	command := byte(0)
	current: Point
	w := 0
	number :: proc(words: []string, w: ^int) -> (f64, bool) {
		if w^ >= len(words) {
			return 0, false
		}
		n, ok := strconv.parse_f64(words[w^])
		w^ += 1
		return n, ok
	}
	for w < len(words) {
		word := words[w]
		if c := word[0]; (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') {
			command = c
			w += 1
			if command == 'Z' {
				finish(&out, &points, true)
				continue
			}
		}
		switch command {
		case 'M', 'L':
			x, okx := number(words[:], &w)
			y, oky := number(words[:], &w)
			if !okx || !oky {
				return nil, svg_problem(fmt.tprintf("the path %q", d))
			}
			if command == 'M' {
				finish(&out, &points, false)
				command = 'L' // more pairs after a move are lines
			}
			current = {x, y}
			append(&points, current)
		case 'A':
			arc: [7]f64
			for k in 0 ..< 7 {
				n, okn := number(words[:], &w)
				if !okn {
					return nil, svg_problem(fmt.tprintf("the path %q", d))
				}
				arc[k] = n
			}
			to := Point{arc[5], arc[6]}
			arc_flatten(&points, current, to, arc[0], arc[1], arc[2], arc[3] != 0, arc[4] != 0, tolerance)
			current = to
		case 0:
			return nil, svg_problem(fmt.tprintf("the path %q, which does not start with a command", d))
		case:
			return nil, svg_problem(fmt.tprintf("the path command %c", command))
		}
	}
	finish(&out, &points, false)
	return out[:], true
}

// An elliptical arc from `from` to `to` as SVG writes it, appended without its first
// point (SVG 1.1, implementation notes F.6.5 and F.6.6: radii too small are grown,
// radii of zero make a straight line).
arc_flatten :: proc(out: ^[dynamic]Point, from, to: Point, radius_x, radius_y, rotation: f64, large, sweep: bool, tolerance: f64) {
	rx, ry := abs(radius_x), abs(radius_y)
	if from == to {
		return
	}
	if rx == 0 || ry == 0 {
		append(out, to)
		return
	}
	phi := math.to_radians(rotation)
	cos_phi, sin_phi := math.cos(phi), math.sin(phi)
	half := (from - to) / 2
	p := Point{cos_phi * half.x + sin_phi * half.y, -sin_phi * half.x + cos_phi * half.y}
	if lambda := p.x * p.x / (rx * rx) + p.y * p.y / (ry * ry); lambda > 1 {
		rx, ry = rx * math.sqrt(lambda), ry * math.sqrt(lambda)
	}
	num := rx * rx * ry * ry - rx * rx * p.y * p.y - ry * ry * p.x * p.x
	den := rx * rx * p.y * p.y + ry * ry * p.x * p.x
	k := math.sqrt(max(num / den, 0))
	if large == sweep {
		k = -k
	}
	cp := Point{k * rx * p.y / ry, -k * ry * p.x / rx}
	mid := (from + to) / 2
	centre := Point{cos_phi * cp.x - sin_phi * cp.y + mid.x, sin_phi * cp.x + cos_phi * cp.y + mid.y}
	angle :: proc(u, v: Point) -> f64 {
		return math.atan2(u.x * v.y - u.y * v.x, u.x * v.x + u.y * v.y)
	}
	start := angle({1, 0}, {(p.x - cp.x) / rx, (p.y - cp.y) / ry})
	delta := angle({(p.x - cp.x) / rx, (p.y - cp.y) / ry}, {(-p.x - cp.x) / rx, (-p.y - cp.y) / ry})
	if !sweep && delta > 0 {
		delta -= math.TAU
	} else if sweep && delta < 0 {
		delta += math.TAU
	}
	// A chord of angle a on a circle of radius r strays r(1 - cos(a/2)) from the arc.
	step := max(2 * math.acos(clamp(1 - tolerance / max(rx, ry), -1, 1)), 1e-3)
	segments := max(int(math.ceil(abs(delta) / step)), 1)
	for s in 1 ..< segments {
		t := start + delta * f64(s) / f64(segments)
		e := Point{rx * math.cos(t), ry * math.sin(t)}
		append(out, Point{cos_phi * e.x - sin_phi * e.y + centre.x, sin_phi * e.x + cos_phi * e.y + centre.y})
	}
	append(out, to) // the end exactly where the path says
}

svg_circle :: proc(attrs: map[string]string, tolerance: f64) -> (subpaths: []Subpath, ok: bool) {
	values: [3]f64
	for key, i in ([]string{"cx", "cy", "r"}) {
		n, parsed := strconv.parse_f64(attrs[key] or_else "0")
		if !parsed {
			return nil, svg_problem(fmt.tprintf("a circle's %s of %q", key, attrs[key]))
		}
		values[i] = n
	}
	if !(values[2] > 0) {
		return nil, true
	}
	points := make([dynamic]Point, context.temp_allocator)
	geom.arc_points(&points, values[0], values[1], values[2], values[2], 0, 360, tolerance)
	pop(&points) // the last repeats the first
	out := make([]Subpath, 1, context.temp_allocator)
	out[0] = {points[:], true}
	return out, true
}

// The outline of the subpaths, already in pixels, as triangles that each count as a contour.
svg_stroke :: proc(subpaths: []Subpath, attrs: map[string]string, colour: [3]u8, m: Affine) -> (shape: Logo_Shape, ok: bool) {
	width, parsed := strconv.parse_f64(attrs["stroke-width"] or_else "1")
	limit, parsed_limit := strconv.parse_f64(attrs["stroke-miterlimit"] or_else "4")
	if !parsed || !parsed_limit {
		return {}, svg_problem("a stroke width or miter limit that is not a number")
	}
	// The transforms the logo uses keep shapes as they are, so a width scales by one number.
	stretch := math.sqrt(abs(m[0] * m[3] - m[1] * m[2]))
	options := geom.Stroke_Options{half_width = width * stretch / 2, miter_limit = limit, tolerance = LOGO_TOLERANCE}
	switch attrs["stroke-linejoin"] or_else "miter" {
	case "miter": options.join = .Miter
	case "round": options.join = .Round
	case "bevel": options.join = .Bevel
	case:         return {}, svg_problem(fmt.tprintf("the line join %q", attrs["stroke-linejoin"]))
	}
	switch attrs["stroke-linecap"] or_else "butt" {
	case "butt":   options.cap = .Butt
	case "round":  options.cap = .Round
	case "square": options.cap = .Square
	case:          return {}, svg_problem(fmt.tprintf("the line cap %q", attrs["stroke-linecap"]))
	}
	mesh := geom.Triangulation{points = make([dynamic]Point, context.temp_allocator), indices = make([dynamic]u32, context.temp_allocator)}
	for sp in subpaths {
		geom.stroke_polyline(sp.points, sp.closed, options, &mesh)
	}
	contours := make([][]Point, len(mesh.indices) / 3, context.temp_allocator)
	for &c, t in contours {
		c = make([]Point, 3, context.temp_allocator)
		for k in 0 ..< 3 {
			c[k] = mesh.points[mesh.indices[t * 3 + k]]
		}
	}
	return {contours, colour}, true
}
