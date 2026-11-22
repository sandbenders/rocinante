// SPDX-License-Identifier: 0BSD
//
// Reading an SVG file as a drawing the sketch can draw with `svg`: the shapes of the file (paths with
// all their commands, rectangles with rounded corners, circles, ellipses, lines, polylines and polygons,
// in groups and `use`s, under any transform) become items, each some contours of straight pieces (curves
// are cut short at read time) with a fill, a stroke and how wide, capped and joined it is. The XML is
// read by Odin's `core:encoding/xml`. Colors come from the attributes, from `style="..."` and from the
// simple rules of a `<style>` (`tag`, `.class` and `#id`), in the order SVG gives them. A group's
// opacity multiplies down into what it holds. Fills are even-odd, whatever `fill-rule` says.
//
// Linear and radial gradients are read whole (stops, units, `gradientTransform`, focal point, spread,
// `href` chains), and so are fill rules and the clip paths each item is cut by (in user units, any shapes,
// either clip rule). Both renderers draw them: `svg` on the GPU (a placed gradient mixed in RGB as SVG
// mixes; the contours that cover by even-odd nesting what the fill rule covers; a clip shape of the clip
// path's shapes, nested once for each clip), and the picture renderer (`raster.odin`, which draws a
// drawing into pixels with no GPU, for app icons) exactly. What a drawing cannot show is not drawn and
// is counted in `lost` and `raster_lost`: text, embedded pictures, masks, filters, patterns, markers,
// and clips measured by the box or clipped again.
package gfx

import "../geom"
import "../maths"
import "core:encoding/xml"
import "core:math"
import "core:slice"
import "core:strconv"
import "core:strings"

// The most points a file may make; the rest of it is dropped.
SVG_MAX_POINTS :: 4_000_000
SVG_MAX_DEPTH :: 48

Svg_Item :: struct {
	contours:           []Contour, // in the drawing's units, with its top left at 0, 0
	fill_contours:      []Contour, // the ones the GPU fills (even-odd by nesting) to cover what the fill rule covers: `contours` itself, or some of them
	fill_on, stroke_on: bool,
	fill, stroke:       maths.Colour, // with the opacities in their alpha; a gradient's first color
	width:              f32, // of the outline, in the drawing's units
	cap:                geom.Cap,
	join:               geom.Join,
	nonzero:            bool, // the fill rule SVG names
	fill_gradient:      i32, // which of the drawing's gradients fills it, or -1 for its color
	stroke_gradient:    i32,
	fill_alpha:         f32, // what a gradient's colors are multiplied by: the opacities, 0 to 1
	stroke_alpha:       f32,
	clips:              []i32, // the clips it is cut by, all of them
}

Svg_Spread :: enum u8 {
	Pad,
	Reflect,
	Repeat,
}

Svg_Stop :: struct {
	offset: f32, // 0 to 1, never less than the stop before
	colour: maths.Colour,
}

// A gradient as one item uses it: the points it is defined by in its own space, and the transform from the
// drawing's units into that space (the element's transform, its bounding box when the units are the box's,
// and `gradientTransform`, undone).
Svg_Gradient :: struct {
	radial:         bool,
	stops:          []Svg_Stop,
	spread:         Svg_Spread,
	x1, y1, x2, y2: f64, // a linear one: where 0 and 1 are
	cx, cy, r:      f64, // a radial one: the circle where 1 is
	fx, fy:         f64, // and the point where 0 is
	to_gradient:    [6]f64,
}

// A clip: the shapes a clip path holds, in the drawing's units. What is inside any of them is kept.
Svg_Clip_Shape :: struct {
	contours:      []Contour,
	nonzero:       bool,
	fill_contours: []Contour, // as an item's
}

Svg_Clip :: struct {
	shapes: []Svg_Clip_Shape,
}

Svg_Lost :: enum u8 {
	Text,
	Picture,
	Clip,
	Mask,
	Filter,
	Pattern,
	Marker,
}

Svg_Drawing :: struct {
	width, height: f32, // of the drawing: its view box, or its own width and height
	items:         []Svg_Item,
	gradients:     []Svg_Gradient,
	clips:         []Svg_Clip,
	lost:          bit_set[Svg_Lost], // what `svg` does not draw
	raster_lost:   bit_set[Svg_Lost], // what the picture renderer does not draw either
	allocator:     ^Svg_Arena,
}

// What the drawing's memory is kept in, so one call lets it all go.
Svg_Arena :: struct {
	items:       [dynamic]Svg_Item,
	contours:    [dynamic][]Contour,
	points:      [dynamic][][2]f32,
	gradients:   [dynamic]Svg_Gradient,
	stops:       [dynamic][]Svg_Stop,
	clips:       [dynamic]Svg_Clip,
	clip_shapes: [dynamic][]Svg_Clip_Shape,
	clip_lists:  [dynamic][]i32,
}

Svg_Error :: enum u8 {
	None,
	Not_Svg, // not XML, or the first element is not `svg`
	Empty,   // nothing in it can be drawn
}

svg_error_words :: proc(error: Svg_Error) -> string {
	switch error {
	case .None:    return ""
	case .Not_Svg: return "it is not an SVG file"
	case .Empty:   return "there is nothing in it that can be drawn"
	}
	return ""
}

svg_destroy :: proc(d: ^Svg_Drawing) {
	if d.allocator != nil {
		for points in d.allocator.points {
			delete(points)
		}
		for contours in d.allocator.contours {
			delete(contours)
		}
		for stops in d.allocator.stops {
			delete(stops)
		}
		for shapes in d.allocator.clip_shapes {
			delete(shapes)
		}
		for list in d.allocator.clip_lists {
			delete(list)
		}
		delete(d.allocator.points)
		delete(d.allocator.contours)
		delete(d.allocator.items)
		delete(d.allocator.gradients)
		delete(d.allocator.stops)
		delete(d.allocator.clips)
		delete(d.allocator.clip_shapes)
		delete(d.allocator.clip_lists)
		free(d.allocator)
	}
	d^ = {}
}

// ---- affine transforms ----

@(private = "file")
Affine :: [6]f64 // x' = a x + c y + e, y' = b x + d y + f

@(private = "file")
AFFINE_IDENTITY :: Affine{1, 0, 0, 1, 0, 0}

@(private = "file")
affine_mul :: proc(m, n: Affine) -> Affine { 	// m after n
	return {
		m[0] * n[0] + m[2] * n[1],
		m[1] * n[0] + m[3] * n[1],
		m[0] * n[2] + m[2] * n[3],
		m[1] * n[2] + m[3] * n[3],
		m[0] * n[4] + m[2] * n[5] + m[4],
		m[1] * n[4] + m[3] * n[5] + m[5],
	}
}

@(private = "file")
affine_apply :: proc(m: Affine, p: geom.Point) -> geom.Point {
	return {m[0] * p.x + m[2] * p.y + m[4], m[1] * p.x + m[3] * p.y + m[5]}
}

@(private = "file")
affine_scale :: proc(m: Affine) -> f64 {
	return math.sqrt(abs(m[0] * m[3] - m[1] * m[2]))
}

// The transform that undoes `m`; false when `m` flattens everything onto a line.
@(private = "file")
affine_invert :: proc(m: Affine) -> (inverse: Affine, ok: bool) {
	det := m[0] * m[3] - m[1] * m[2]
	if abs(det) < 1e-12 || math.is_nan(det) {
		return {}, false
	}
	a, b, c, d := m[3] / det, -m[1] / det, -m[2] / det, m[0] / det
	return {a, b, c, d, -(a * m[4] + c * m[5]), -(b * m[4] + d * m[5])}, true
}

// ---- scanning numbers ----

@(private = "file")
Scanner :: struct {
	text: string,
	at:   int,
}

@(private = "file")
skip_separators :: proc(s: ^Scanner) {
	for s.at < len(s.text) {
		switch s.text[s.at] {
		case ' ', '\t', '\n', '\r', ',': s.at += 1
		case: return
		}
	}
}

// The next number: a sign, digits, a point, more digits and an exponent, so `1.5.5` is 1.5 and .5 and `1-2` is 1 and -2.
@(private = "file")
scan_number :: proc(s: ^Scanner) -> (value: f64, ok: bool) {
	skip_separators(s)
	start := s.at
	i := s.at
	t := s.text
	if i < len(t) && (t[i] == '+' || t[i] == '-') {
		i += 1
	}
	digits := 0
	for i < len(t) && t[i] >= '0' && t[i] <= '9' {
		i += 1
		digits += 1
	}
	if i < len(t) && t[i] == '.' {
		i += 1
		for i < len(t) && t[i] >= '0' && t[i] <= '9' {
			i += 1
			digits += 1
		}
	}
	if digits == 0 {
		return 0, false
	}
	if i < len(t) && (t[i] == 'e' || t[i] == 'E') {
		j := i + 1
		if j < len(t) && (t[j] == '+' || t[j] == '-') {
			j += 1
		}
		if j < len(t) && t[j] >= '0' && t[j] <= '9' {
			for j < len(t) && t[j] >= '0' && t[j] <= '9' {
				j += 1
			}
			i = j
		}
	}
	number, parsed := strconv.parse_f64(t[start:i])
	if !parsed || math.is_nan(number) || math.is_inf(number) {
		return 0, false
	}
	s.at = i
	return number, true
}

// An arc's flag: one character, 0 or 1, which may touch the next number.
@(private = "file")
scan_flag :: proc(s: ^Scanner) -> (flag: bool, ok: bool) {
	skip_separators(s)
	if s.at < len(s.text) && (s.text[s.at] == '0' || s.text[s.at] == '1') {
		flag = s.text[s.at] == '1'
		s.at += 1
		return flag, true
	}
	return false, false
}

// All the numbers in a text ("0 0 100 50", "10,20").
@(private = "file")
numbers_in :: proc(text: string, allocator := context.temp_allocator) -> []f64 {
	out := make([dynamic]f64, allocator)
	s := Scanner{text = text}
	for {
		value, ok := scan_number(&s)
		if !ok {
			break
		}
		append(&out, value)
	}
	return out[:]
}

// A length: a number, with units a drawing's own units stand for (px, pt, and so on are taken as the same).
@(private = "file")
length_of :: proc(text: string) -> (value: f64, ok: bool) {
	s := Scanner{text = strings.trim_space(text)}
	number, found := scan_number(&s)
	if !found {
		return 0, false
	}
	rest := strings.trim_space(s.text[s.at:])
	switch rest {
	case "", "px", "pt", "pc", "mm", "cm", "in", "em", "ex":
	case:
		return 0, false // a percentage, or something unknown
	}
	switch rest {
	case "pt": number *= 96.0 / 72
	case "pc": number *= 16
	case "mm": number *= 96.0 / 25.4
	case "cm": number *= 96.0 / 2.54
	case "in": number *= 96
	case "em": number *= 16
	case "ex": number *= 8
	}
	return number, true
}

// ---- the path builder ----

@(private = "file")
Builder :: struct {
	contours:  [dynamic][dynamic]geom.Point,
	closed:    [dynamic]bool,
	current:   [dynamic]geom.Point,
	start:     geom.Point,
	at:        geom.Point,
	tolerance: f64,
}

@(private = "file")
builder_finish :: proc(b: ^Builder, closed: bool) {
	if len(b.current) > 0 {
		append(&b.contours, b.current)
		append(&b.closed, closed)
		b.current = make([dynamic]geom.Point, context.temp_allocator)
	}
}

@(private = "file")
builder_move :: proc(b: ^Builder, p: geom.Point) {
	builder_finish(b, false)
	append(&b.current, p)
	b.start, b.at = p, p
}

// Starts a contour at the current place if a close left it without one.
@(private = "file")
builder_ensure :: proc(b: ^Builder) {
	if len(b.current) == 0 {
		append(&b.current, b.at)
		b.start = b.at
	}
}

@(private = "file")
builder_line :: proc(b: ^Builder, p: geom.Point) {
	builder_ensure(b)
	append(&b.current, p)
	b.at = p
}

@(private = "file")
builder_cubic :: proc(b: ^Builder, c1, c2, p: geom.Point) {
	builder_ensure(b)
	geom.flatten_cubic(&b.current, b.at, c1, c2, p, b.tolerance)
	b.at = p
}

@(private = "file")
builder_quadratic :: proc(b: ^Builder, c: geom.Point, p: geom.Point) {
	builder_ensure(b)
	geom.flatten_quadratic(&b.current, b.at, c, p, b.tolerance)
	b.at = p
}

@(private = "file")
builder_close :: proc(b: ^Builder) {
	if len(b.current) > 0 {
		builder_finish(b, true)
	}
	b.at = b.start
}

// An elliptical arc from the current place to `to`, by the endpoint form SVG gives (its F.6.5): the radii, the
// turn of the ellipse in degrees, and the two flags that pick one of the four arcs.
@(private = "file")
builder_arc :: proc(b: ^Builder, radius_x, radius_y, rotation: f64, large, sweep: bool, to: geom.Point) {
	builder_ensure(b)
	from := b.at
	rx, ry := abs(radius_x), abs(radius_y)
	if from == to {
		return
	}
	if rx == 0 || ry == 0 {
		builder_line(b, to)
		return
	}
	phi := rotation * math.PI / 180
	cos_phi, sin_phi := math.cos(phi), math.sin(phi)
	dx, dy := (from.x - to.x) / 2, (from.y - to.y) / 2
	x1 := cos_phi * dx + sin_phi * dy
	y1 := -sin_phi * dx + cos_phi * dy
	lambda := x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
	if lambda > 1 {
		scale := math.sqrt(lambda)
		rx, ry = rx * scale, ry * scale
	}
	numerator := rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
	denominator := rx * rx * y1 * y1 + ry * ry * x1 * x1
	factor := 0.0
	if denominator != 0 {
		factor = math.sqrt(max(numerator / denominator, 0))
	}
	if large == sweep {
		factor = -factor
	}
	cx1 := factor * rx * y1 / ry
	cy1 := -factor * ry * x1 / rx
	cx := cos_phi * cx1 - sin_phi * cy1 + (from.x + to.x) / 2
	cy := sin_phi * cx1 + cos_phi * cy1 + (from.y + to.y) / 2
	angle :: proc(ux, uy, vx, vy: f64) -> f64 {
		return math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
	}
	start := angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
	delta := angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
	if !sweep && delta > 0 {
		delta -= 2 * math.PI
	} else if sweep && delta < 0 {
		delta += 2 * math.PI
	}
	// as many pieces as keep the curve within the tolerance of the arc
	biggest := max(rx, ry)
	step := 2 * math.acos(clamp(1 - b.tolerance / biggest, 0, 0.999999))
	pieces := max(int(math.ceil(abs(delta) / max(step, 1e-3))), 1)
	pieces = min(pieces, 4096)
	for i in 1 ..< pieces {
		theta := start + delta * f64(i) / f64(pieces)
		px := rx * math.cos(theta)
		py := ry * math.sin(theta)
		append(&b.current, geom.Point{cos_phi * px - sin_phi * py + cx, sin_phi * px + cos_phi * py + cy})
	}
	append(&b.current, to)
	b.at = to
}

// ---- reading the file ----

@(private = "file")
Css_Kind :: enum u8 {
	Tag,
	Class,
	Id,
}

@(private = "file")
Css_Rule :: struct {
	kind:         Css_Kind,
	name:         string,
	declarations: string,
}

@(private = "file")
Reader :: struct {
	doc:         ^xml.Document,
	ids:         map[string]xml.Element_ID,
	rules:       [dynamic]Css_Rule,
	gradients:   map[string]maths.Colour,
	templates:   map[string]Gradient_Template,
	viewport:    [2]f64, // what a percentage in user units is of
	arena:       ^Svg_Arena,
	lost:        bit_set[Svg_Lost],
	raster_lost: bit_set[Svg_Lost],
	points:      int,
	tolerance:   f64,
	capture:     ^[dynamic]Svg_Clip_Shape, // while a clip path is read, where its shapes go instead of the items
}

// A gradient element as its `href` chain resolves it, before an item uses it.
@(private = "file")
Gradient_Template :: struct {
	valid:      bool, // it has stops
	radial:     bool,
	stops:      []Svg_Stop, // kept in the arena
	bbox_units: bool,
	transform:  Affine,
	spread:     Svg_Spread,
	x1, y1, x2, y2, cx, cy, r, fx, fy: f64,
}

// What an element passes on to what it holds.
@(private = "file")
Paint_State :: struct {
	fill_on:        bool,
	fill:           maths.Colour,
	stroke_on:      bool,
	stroke:         maths.Colour,
	current:        maths.Colour, // `currentColor`
	stroke_width:   f64,
	fill_opacity:   f64,
	stroke_opacity: f64,
	opacity:        f64,
	cap:            geom.Cap,
	join:           geom.Join,
	nonzero:        bool, // `fill-rule`
	clip_nonzero:   bool, // `clip-rule`, for the shapes of a clip path
	fill_url:       string, // the gradient the fill names, or ""
	stroke_url:     string,
	clips:          []i32, // the clips of the groups it is in and its own
}

@(private = "file")
local_name :: proc(name: string) -> string {
	if colon := strings.last_index_byte(name, ':'); colon >= 0 {
		return name[colon + 1:]
	}
	return name
}

@(private = "file")
attribute :: proc(r: ^Reader, id: xml.Element_ID, name: string) -> (value: string, found: bool) {
	for a in r.doc.elements[id].attribs {
		if a.key == name {
			return a.val, true
		}
	}
	return "", false
}

// The last value `name` is given in a list of declarations (`fill:red; stroke:blue`).
@(private = "file")
declaration :: proc(text: string, name: string) -> (value: string, found: bool) {
	rest := text
	for len(rest) > 0 {
		end := strings.index_byte(rest, ';')
		piece := rest
		if end >= 0 {
			piece, rest = rest[:end], rest[end + 1:]
		} else {
			rest = ""
		}
		colon := strings.index_byte(piece, ':')
		if colon < 0 {
			continue
		}
		if strings.trim_space(piece[:colon]) == name {
			value, found = strings.trim_space(piece[colon + 1:]), true
		}
	}
	return
}

// A property of an element, from where SVG looks: the `style` attribute, then the rules of a `<style>`, then the attribute.
@(private = "file")
property :: proc(r: ^Reader, id: xml.Element_ID, name: string) -> (value: string, found: bool) {
	if style, has := attribute(r, id, "style"); has {
		if value, found = declaration(style, name); found {
			return
		}
	}
	if len(r.rules) > 0 {
		class, _ := attribute(r, id, "class")
		own_id, _ := attribute(r, id, "id")
		tag := local_name(r.doc.elements[id].ident)
		#reverse for rule in r.rules {
			matches := false
			switch rule.kind {
			case .Tag:   matches = rule.name == tag
			case .Id:    matches = rule.name == own_id
			case .Class:
				rest := class
				for word in strings.fields_iterator(&rest) {
					if word == rule.name {
						matches = true
						break
					}
				}
			}
			if matches {
				if value, found = declaration(rule.declarations, name); found {
					return
				}
			}
		}
	}
	return attribute(r, id, name)
}

@(private = "file")
parse_rules :: proc(r: ^Reader, css: string) {
	text := css
	// comments are taken out first
	cleaned := strings.builder_make(context.temp_allocator)
	for len(text) > 0 {
		open := strings.index(text, "/*")
		if open < 0 {
			strings.write_string(&cleaned, text)
			break
		}
		strings.write_string(&cleaned, text[:open])
		close := strings.index(text[open + 2:], "*/")
		if close < 0 {
			break
		}
		text = text[open + 2 + close + 2:]
	}
	rest := strings.to_string(cleaned)
	for len(rest) > 0 {
		open := strings.index_byte(rest, '{')
		if open < 0 {
			break
		}
		close := strings.index_byte(rest[open:], '}')
		if close < 0 {
			break
		}
		selectors := strings.trim_space(rest[:open])
		body := rest[open + 1:open + close]
		rest = rest[open + close + 1:]
		if strings.has_prefix(selectors, "@") {
			continue
		}
		list := selectors
		for selector in strings.split_iterator(&list, ",") {
			name := strings.trim_space(selector)
			switch {
			case len(name) > 1 && name[0] == '.' && !strings.contains_any(name[1:], " .#>:[+~"):
				append(&r.rules, Css_Rule{.Class, name[1:], body})
			case len(name) > 1 && name[0] == '#' && !strings.contains_any(name[1:], " .#>:[+~"):
				append(&r.rules, Css_Rule{.Id, name[1:], body})
			case len(name) > 0 && !strings.contains_any(name, " .#>:[+~*"):
				append(&r.rules, Css_Rule{.Tag, name, body})
			}
		}
	}
}

// A color: `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, `rgb(...)`, `rgba(...)`, a CSS name or `transparent`.
@(private = "file")
parse_colour :: proc(text: string) -> (colour: maths.Colour, ok: bool) {
	value := strings.trim_space(text)
	if len(value) == 0 {
		return {}, false
	}
	if value[0] == '#' {
		digits := value[1:]
		hex :: proc(c: u8) -> (int, bool) {
			switch c {
			case '0' ..= '9': return int(c - '0'), true
			case 'a' ..= 'f': return int(c - 'a' + 10), true
			case 'A' ..= 'F': return int(c - 'A' + 10), true
			}
			return 0, false
		}
		values: [8]int
		for c, i in transmute([]u8)digits {
			if i >= 8 {return {}, false}
			v, good := hex(c)
			if !good {return {}, false}
			values[i] = v
		}
		switch len(digits) {
		case 3, 4:
			a := f32(255)
			if len(digits) == 4 {a = f32(values[3] * 17)}
			return {f32(values[0] * 17), f32(values[1] * 17), f32(values[2] * 17), a}, true
		case 6, 8:
			a := f32(255)
			if len(digits) == 8 {a = f32(values[6] * 16 + values[7])}
			return {f32(values[0] * 16 + values[1]), f32(values[2] * 16 + values[3]), f32(values[4] * 16 + values[5]), a}, true
		}
		return {}, false
	}
	lower := strings.to_lower(value, context.temp_allocator)
	if strings.has_prefix(lower, "rgb") {
		open := strings.index_byte(lower, '(')
		close := strings.last_index_byte(lower, ')')
		if open < 0 || close < open {
			return {}, false
		}
		inside := lower[open + 1:close]
		parts := make([dynamic]f64, context.temp_allocator)
		percent := make([dynamic]bool, context.temp_allocator)
		s := Scanner{text = inside}
		for {
			number, found := scan_number(&s)
			if !found {
				break
			}
			is_percent := s.at < len(s.text) && s.text[s.at] == '%'
			if is_percent {
				s.at += 1
			}
			append(&parts, number)
			append(&percent, is_percent)
		}
		if len(parts) < 3 {
			return {}, false
		}
		channel :: proc(v: f64, is_percent: bool) -> f32 {
			return f32(clamp(v * 2.55 if is_percent else v, 0, 255))
		}
		a := f32(255)
		if len(parts) >= 4 {
			a = f32(clamp(parts[3] / 100 if percent[3] else parts[3], 0, 1) * 255)
		}
		return {channel(parts[0], percent[0]), channel(parts[1], percent[1]), channel(parts[2], percent[2]), a}, true
	}
	if lower == "transparent" {
		return {0, 0, 0, 0}, true
	}
	return maths.name_lookup(lower)
}

// The element's opacity-like number: 0 to 1, or a percentage.
@(private = "file")
opacity_of :: proc(text: string) -> (value: f64, ok: bool) {
	s := Scanner{text = strings.trim_space(text)}
	number, found := scan_number(&s)
	if !found {
		return 0, false
	}
	if s.at < len(s.text) && s.text[s.at] == '%' {
		number /= 100
	}
	return clamp(number, 0, 1), true
}

// How a paint is read: what it says and whether the element then has it.
@(private = "file")
read_paint :: proc(r: ^Reader, text: string, state: Paint_State) -> (colour: maths.Colour, on: bool, known: bool, url: string) {
	value := strings.trim_space(text)
	switch {
	case value == "none":
		return {}, false, true, ""
	case value == "currentColor" || value == "currentcolor":
		return state.current, true, true, ""
	case strings.has_prefix(value, "url("):
		close := strings.index_byte(value, ')')
		if close < 0 {
			return {}, false, false, ""
		}
		name := strings.trim(value[4:close], " \"'#")
		if g, found := r.gradients[name]; found {
			return g, true, true, name
		}
		// a pattern or a gradient with no stops: left out; the fallback after the url, if any, is not used
		r.lost += {.Pattern}
		r.raster_lost += {.Pattern}
		return {}, false, true, ""
	}
	c, ok := parse_colour(value)
	if !ok {
		return {}, false, false, ""
	}
	return c, true, true, ""
}

@(private = "file")
update_state :: proc(r: ^Reader, id: xml.Element_ID, state: ^Paint_State) {
	if value, found := property(r, id, "color"); found {
		if c, ok := parse_colour(value); ok {
			state.current = c
		}
	}
	if value, found := property(r, id, "fill"); found {
		if c, on, known, url := read_paint(r, value, state^); known {
			state.fill, state.fill_on, state.fill_url = c, on, url
		}
	}
	if value, found := property(r, id, "stroke"); found {
		if c, on, known, url := read_paint(r, value, state^); known {
			state.stroke, state.stroke_on, state.stroke_url = c, on, url
		}
	}
	if value, found := property(r, id, "fill-rule"); found {
		switch strings.trim_space(value) {
		case "nonzero": state.nonzero = true
		case "evenodd": state.nonzero = false
		}
	}
	if value, found := property(r, id, "clip-rule"); found {
		switch strings.trim_space(value) {
		case "nonzero": state.clip_nonzero = true
		case "evenodd": state.clip_nonzero = false
		}
	}
	if value, found := property(r, id, "stroke-width"); found {
		if w, ok := length_of(value); ok {
			state.stroke_width = max(w, 0)
		}
	}
	if value, found := property(r, id, "fill-opacity"); found {
		if o, ok := opacity_of(value); ok {state.fill_opacity = o}
	}
	if value, found := property(r, id, "stroke-opacity"); found {
		if o, ok := opacity_of(value); ok {state.stroke_opacity = o}
	}
	if value, found := property(r, id, "opacity"); found {
		if o, ok := opacity_of(value); ok {state.opacity *= o}
	}
	if value, found := property(r, id, "stroke-linecap"); found {
		switch strings.trim_space(value) {
		case "butt":   state.cap = .Butt
		case "round":  state.cap = .Round
		case "square": state.cap = .Square
		}
	}
	if value, found := property(r, id, "stroke-linejoin"); found {
		switch strings.trim_space(value) {
		case "miter", "miter-clip", "arcs": state.join = .Miter
		case "round":                       state.join = .Round
		case "bevel":                       state.join = .Bevel
		}
	}
	for name in ([?]struct {
		name: string,
		kind: Svg_Lost,
	}{{"clip-path", .Clip}, {"mask", .Mask}, {"filter", .Filter}, {"marker-start", .Marker}, {"marker-mid", .Marker}, {"marker-end", .Marker}}) {
		if value, found := property(r, id, name.name); found && strings.trim_space(value) != "none" {
			// a clip path is cut by both renderers, read in `draw_element` by `read_clip`, which says when it cannot
			if name.kind != .Clip {
				r.lost += {name.kind}
				r.raster_lost += {name.kind}
			}
		}
	}
}

// A transform attribute: matrix, translate, scale, rotate, skewX and skewY, one after the other.
@(private = "file")
parse_transform :: proc(text: string) -> Affine {
	result := AFFINE_IDENTITY
	rest := strings.trim_space(text)
	for len(rest) > 0 {
		open := strings.index_byte(rest, '(')
		close := strings.index_byte(rest, ')')
		if open < 0 || close < open {
			break
		}
		name := strings.trim(rest[:open], " ,\t\n\r")
		n := numbers_in(rest[open + 1:close])
		rest = strings.trim_left(rest[close + 1:], " ,\t\n\r")
		m := AFFINE_IDENTITY
		switch name {
		case "matrix":
			if len(n) == 6 {m = {n[0], n[1], n[2], n[3], n[4], n[5]}}
		case "translate":
			if len(n) >= 1 {m[4] = n[0]}
			if len(n) >= 2 {m[5] = n[1]}
		case "scale":
			if len(n) >= 1 {
				m[0] = n[0]
				m[3] = n[0]
				if len(n) >= 2 {m[3] = n[1]}
			}
		case "rotate":
			if len(n) >= 1 {
				a := n[0] * math.PI / 180
				c, s := math.cos(a), math.sin(a)
				m = {c, s, -s, c, 0, 0}
				if len(n) >= 3 {
					// about a point: move it to the origin, turn, move it back
					m = affine_mul({1, 0, 0, 1, n[1], n[2]}, affine_mul(m, {1, 0, 0, 1, -n[1], -n[2]}))
				}
			}
		case "skewX":
			if len(n) >= 1 {m[2] = math.tan(n[0] * math.PI / 180)}
		case "skewY":
			if len(n) >= 1 {m[1] = math.tan(n[0] * math.PI / 180)}
		}
		result = affine_mul(result, m)
	}
	return result
}

// Reads the commands of a path's `d`; a mistake ends it there, keeping what was read, as SVG says.
@(private = "file")
parse_path :: proc(b: ^Builder, d: string) {
	s := Scanner{text = d}
	cmd: u8
	cur := geom.Point{}
	last_cubic_control, last_quad_control: geom.Point
	last_was_cubic, last_was_quad := false, false
	for {
		skip_separators(&s)
		if s.at >= len(s.text) {
			return
		}
		c := s.text[s.at]
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') {
			cmd = c
			s.at += 1
			if cmd == 'z' || cmd == 'Z' {
				builder_close(b)
				cur = b.at
				last_was_cubic, last_was_quad = false, false
				continue
			}
		} else if cmd == 0 || cmd == 'z' || cmd == 'Z' {
			return
		} else if cmd == 'M' {
			cmd = 'L' // more pairs after a moveto are lines
		} else if cmd == 'm' {
			cmd = 'l'
		}
		relative := cmd >= 'a'
		upper := cmd - 32 if relative else cmd
		base := cur if relative else geom.Point{}
		next_cubic, next_quad := false, false
		switch upper {
		case 'M', 'L', 'T':
			x, okx := scan_number(&s)
			y, oky := scan_number(&s)
			if !okx || !oky {return}
			p := geom.Point{x, y} + base
			switch upper {
			case 'M': builder_move(b, p)
			case 'L': builder_line(b, p)
			case 'T':
				control := cur
				if last_was_quad {control = cur * 2 - last_quad_control}
				builder_quadratic(b, control, p)
				last_quad_control = control
				next_quad = true
			}
			cur = p
		case 'H':
			x, ok := scan_number(&s)
			if !ok {return}
			cur.x = x + (cur.x if relative else 0)
			builder_line(b, cur)
		case 'V':
			y, ok := scan_number(&s)
			if !ok {return}
			cur.y = y + (cur.y if relative else 0)
			builder_line(b, cur)
		case 'C', 'S':
			n: [6]f64
			count := 6 if upper == 'C' else 4
			for i in 0 ..< count {
				v, ok := scan_number(&s)
				if !ok {return}
				n[i] = v
			}
			c1, c2, p: geom.Point
			if upper == 'C' {
				c1, c2, p = geom.Point{n[0], n[1]} + base, geom.Point{n[2], n[3]} + base, geom.Point{n[4], n[5]} + base
			} else {
				c1 = cur
				if last_was_cubic {c1 = cur * 2 - last_cubic_control}
				c2, p = geom.Point{n[0], n[1]} + base, geom.Point{n[2], n[3]} + base
			}
			builder_cubic(b, c1, c2, p)
			last_cubic_control = c2
			next_cubic = true
			cur = p
		case 'Q':
			n: [4]f64
			for i in 0 ..< 4 {
				v, ok := scan_number(&s)
				if !ok {return}
				n[i] = v
			}
			control, p := geom.Point{n[0], n[1]} + base, geom.Point{n[2], n[3]} + base
			builder_quadratic(b, control, p)
			last_quad_control = control
			next_quad = true
			cur = p
		case 'A':
			rx, ok1 := scan_number(&s)
			ry, ok2 := scan_number(&s)
			rotation, ok3 := scan_number(&s)
			large, ok4 := scan_flag(&s)
			sweep, ok5 := scan_flag(&s)
			x, ok6 := scan_number(&s)
			y, ok7 := scan_number(&s)
			if !(ok1 && ok2 && ok3 && ok4 && ok5 && ok6 && ok7) {return}
			p := geom.Point{x, y} + base
			builder_arc(b, rx, ry, rotation, large, sweep, p)
			cur = p
		case:
			return // a letter that is no command
		}
		last_was_cubic, last_was_quad = next_cubic, next_quad
	}
}

// Moves a builder's contours onto the drawing and keeps them as an item with the state's paint, or, while a
// clip path is read, as one of its shapes.
@(private = "file")
emit :: proc(r: ^Reader, b: ^Builder, state: Paint_State, m: Affine) {
	builder_finish(b, false)
	if len(b.contours) == 0 || r.points >= SVG_MAX_POINTS {
		return
	}
	// the box round the shape in its own units, for a gradient measured by it
	lo, hi := [2]f64{max(f64), max(f64)}, [2]f64{-max(f64), -max(f64)}
	for contour in b.contours {
		for p in contour {
			lo = {min(lo.x, p.x), min(lo.y, p.y)}
			hi = {max(hi.x, p.x), max(hi.y, p.y)}
		}
	}
	if r.capture != nil {
		contours := keep_contours(r, b, m)
		append(r.capture, Svg_Clip_Shape{contours = contours, nonzero = state.clip_nonzero, fill_contours = even_odd_contours(r, contours, state.clip_nonzero)})
		return
	}
	fill_gradient, stroke_gradient := i32(-1), i32(-1)
	fill_alpha := f32(state.opacity * state.fill_opacity)
	stroke_alpha := f32(state.opacity * state.stroke_opacity)
	fill_seen := state.fill.a > 0
	if state.fill_on && state.fill_url != "" {
		fill_gradient = instance_gradient(r, state.fill_url, lo, hi, m)
		fill_seen = fill_gradient >= 0 || fill_seen
	}
	stroke_seen := state.stroke.a > 0
	if state.stroke_on && state.stroke_url != "" {
		stroke_gradient = instance_gradient(r, state.stroke_url, lo, hi, m)
		stroke_seen = stroke_gradient >= 0 || stroke_seen
	}
	fill_on := state.fill_on && fill_seen && fill_alpha > 0
	stroke_on := state.stroke_on && stroke_seen && state.stroke_width > 0 && stroke_alpha > 0
	if !fill_on && !stroke_on {
		return
	}
	contours := keep_contours(r, b, m)
	item := Svg_Item{
		contours        = contours,
		fill_contours   = even_odd_contours(r, contours, state.nonzero),
		fill_on         = fill_on,
		stroke_on       = stroke_on,
		width           = f32(state.stroke_width * affine_scale(m)),
		cap             = state.cap,
		join            = state.join,
		nonzero         = state.nonzero,
		fill_gradient   = fill_gradient if fill_on else -1,
		stroke_gradient = stroke_gradient if stroke_on else -1,
		fill_alpha      = fill_alpha,
		stroke_alpha    = stroke_alpha,
	}
	if len(state.clips) > 0 {
		item.clips = make([]i32, len(state.clips))
		copy(item.clips, state.clips)
		append(&r.arena.clip_lists, item.clips)
	}
	item.fill = state.fill
	item.fill.a *= fill_alpha
	item.stroke = state.stroke
	item.stroke.a *= stroke_alpha
	append(&r.arena.items, item)
}

// The builder's contours moved into the drawing's units and kept in the arena.
@(private = "file")
keep_contours :: proc(r: ^Reader, b: ^Builder, m: Affine) -> []Contour {
	contours := make([]Contour, len(b.contours))
	for contour, i in b.contours {
		points := make([][2]f32, len(contour))
		for p, j in contour {
			moved := affine_apply(m, p)
			points[j] = {f32(moved.x), f32(moved.y)}
		}
		r.points += len(points)
		append(&r.arena.points, points)
		contours[i] = {points, b.closed[i]}
	}
	append(&r.arena.contours, contours)
	return contours
}

// The contours the GPU fills by its rule (even-odd by how deeply each sits in the others) so as to cover what `rule`
// covers: all of them for even-odd, and for nonzero those that are edges of the filled area, kept in the arena when
// that leaves some out.
@(private = "file")
even_odd_contours :: proc(r: ^Reader, contours: []Contour, nonzero: bool) -> []Contour {
	if !nonzero || len(contours) < 2 {
		return contours
	}
	points := make([][]geom.Point, len(contours), context.temp_allocator)
	for c, i in contours {
		points[i] = make([]geom.Point, len(c.points), context.temp_allocator)
		for p, j in c.points {
			points[i][j] = {f64(p.x), f64(p.y)}
		}
	}
	kept := geom.nonzero_boundaries(points, context.temp_allocator)
	if len(kept) == len(contours) {
		return contours
	}
	chosen := make([]Contour, len(kept))
	for k, i in kept {
		chosen[i] = contours[k]
	}
	append(&r.arena.contours, chosen)
	return chosen
}

// A coordinate of a gradient: a number, or a percentage of the box (its units) or of the view (user units).
@(private = "file")
gradient_coordinate :: proc(text: string, bbox_units: bool, of: f64) -> (value: f64, ok: bool) {
	trimmed := strings.trim_space(text)
	if strings.has_suffix(trimmed, "%") {
		s := Scanner{text = trimmed[:len(trimmed) - 1]}
		number, found := scan_number(&s)
		if !found {
			return 0, false
		}
		return number / 100 * (1 if bbox_units else of), true
	}
	return length_of(trimmed)
}

// Reads a gradient element, taking what it does not say from the gradients its `href` leads to (its stops
// from the first that has any), as SVG says. Kept, so each gradient is read once.
@(private = "file")
gradient_template :: proc(r: ^Reader, name: string) -> Gradient_Template {
	if t, known := r.templates[name]; known {
		return t
	}
	t := Gradient_Template{transform = AFFINE_IDENTITY, bbox_units = true}
	chain := make([dynamic]xml.Element_ID, context.temp_allocator)
	if first, found := r.ids[name]; found {
		holder := first
		for _ in 0 ..< 8 {
			kind := local_name(r.doc.elements[holder].ident)
			if kind != "linearGradient" && kind != "radialGradient" {
				break
			}
			append(&chain, holder)
			href, has_href := attribute(r, holder, "href")
			if !has_href {
				href, has_href = attribute(r, holder, "xlink:href")
			}
			if !has_href || !strings.has_prefix(href, "#") {
				break
			}
			next, known := r.ids[href[1:]]
			if !known {
				break
			}
			holder = next
		}
	}
	if len(chain) == 0 {
		r.templates[name] = t
		return t
	}
	t.radial = local_name(r.doc.elements[chain[0]].ident) == "radialGradient"
	// the first of the chain that says it
	said :: proc(r: ^Reader, chain: []xml.Element_ID, key: string) -> (value: string, found: bool) {
		for id in chain {
			if value, found = attribute(r, id, key); found {
				return
			}
		}
		return
	}
	if units, found := said(r, chain[:], "gradientUnits"); found {
		t.bbox_units = strings.trim_space(units) != "userSpaceOnUse"
	}
	if text, found := said(r, chain[:], "gradientTransform"); found {
		t.transform = parse_transform(text)
	}
	if text, found := said(r, chain[:], "spreadMethod"); found {
		switch strings.trim_space(text) {
		case "reflect": t.spread = .Reflect
		case "repeat":  t.spread = .Repeat
		}
	}
	diagonal := math.sqrt((r.viewport.x * r.viewport.x + r.viewport.y * r.viewport.y) / 2)
	coordinate :: proc(r: ^Reader, chain: []xml.Element_ID, key: string, otherwise: f64, bbox_units: bool, of: f64) -> f64 {
		if text, found := said(r, chain, key); found {
			if value, ok := gradient_coordinate(text, bbox_units, of); ok {
				return value
			}
		}
		return otherwise
	}
	if t.radial {
		half := 0.5 if t.bbox_units else 0.0
		t.cx = coordinate(r, chain[:], "cx", half if t.bbox_units else r.viewport.x / 2, t.bbox_units, r.viewport.x)
		t.cy = coordinate(r, chain[:], "cy", half if t.bbox_units else r.viewport.y / 2, t.bbox_units, r.viewport.y)
		t.r = coordinate(r, chain[:], "r", half if t.bbox_units else diagonal / 2, t.bbox_units, diagonal)
		t.fx = coordinate(r, chain[:], "fx", t.cx, t.bbox_units, r.viewport.x)
		t.fy = coordinate(r, chain[:], "fy", t.cy, t.bbox_units, r.viewport.y)
	} else {
		t.x1 = coordinate(r, chain[:], "x1", 0, t.bbox_units, r.viewport.x)
		t.y1 = coordinate(r, chain[:], "y1", 0, t.bbox_units, r.viewport.y)
		t.x2 = coordinate(r, chain[:], "x2", 1 if t.bbox_units else r.viewport.x, t.bbox_units, r.viewport.x)
		t.y2 = coordinate(r, chain[:], "y2", 0, t.bbox_units, r.viewport.y)
	}
	stops := make([dynamic]Svg_Stop, context.temp_allocator)
	for id in chain {
		for value in r.doc.elements[id].value {
			child, is_child := value.(xml.Element_ID)
			if !is_child || local_name(r.doc.elements[child].ident) != "stop" {
				continue
			}
			stop := Svg_Stop{colour = {0, 0, 0, 255}}
			if text, found := attribute(r, child, "offset"); found {
				if o, ok := opacity_of(text); ok {
					stop.offset = f32(o)
				}
			}
			if len(stops) > 0 {
				stop.offset = max(stop.offset, stops[len(stops) - 1].offset)
			}
			if text, found := property(r, child, "stop-color"); found {
				if parsed, ok := parse_colour(text); ok {
					stop.colour = parsed
				}
			}
			if text, found := property(r, child, "stop-opacity"); found {
				if o, ok := opacity_of(text); ok {
					stop.colour.a *= f32(o)
				}
			}
			append(&stops, stop)
		}
		if len(stops) > 0 {
			break
		}
	}
	if len(stops) > 0 {
		kept := make([]Svg_Stop, len(stops))
		copy(kept, stops[:])
		append(&r.arena.stops, kept)
		t.stops = kept
		t.valid = true
	}
	r.templates[name] = t
	return t
}

// A gradient for one item: the template placed by the item's box (when its units are the box's) and transform.
// -1 when the gradient cannot be placed: no stops, a box with no width or height, a transform that flattens it.
@(private = "file")
instance_gradient :: proc(r: ^Reader, name: string, lo, hi: [2]f64, m: Affine) -> i32 {
	t := gradient_template(r, name)
	if !t.valid {
		return -1
	}
	place := t.transform
	if t.bbox_units {
		w, h := hi.x - lo.x, hi.y - lo.y
		if !(w > 0) || !(h > 0) {
			return -1
		}
		place = affine_mul({w, 0, 0, h, lo.x, lo.y}, t.transform)
	}
	inverse, ok := affine_invert(affine_mul(m, place))
	if !ok {
		return -1
	}
	append(&r.arena.gradients, Svg_Gradient{
		radial = t.radial, stops = t.stops, spread = t.spread,
		x1 = t.x1, y1 = t.y1, x2 = t.x2, y2 = t.y2,
		cx = t.cx, cy = t.cy, r = t.r, fx = t.fx, fy = t.fy,
		to_gradient = inverse,
	})
	return i32(len(r.arena.gradients) - 1)
}

// The clip a `clip-path` names, read in the units of the element that names it (`m`), as one of the drawing's
// clips. -1 when it names no clip path, or one this cannot cut (measured by the box, or holding no shape).
@(private = "file")
read_clip :: proc(r: ^Reader, text: string, m: Affine, depth: int) -> i32 {
	value := strings.trim_space(text)
	close := strings.index_byte(value, ')')
	if !strings.has_prefix(value, "url(") || close < 0 {
		return -1
	}
	target, known := r.ids[strings.trim(value[4:close], " \"'#")]
	if !known || local_name(r.doc.elements[target].ident) != "clipPath" {
		r.lost += {.Clip}
		r.raster_lost += {.Clip}
		return -1
	}
	if units, has := attribute(r, target, "clipPathUnits"); has && strings.trim_space(units) == "objectBoundingBox" {
		r.lost += {.Clip}
		r.raster_lost += {.Clip}
		return -1
	}
	if _, nested := attribute(r, target, "clip-path"); nested {
		r.lost += {.Clip}
		r.raster_lost += {.Clip} // a clip path cut by another: its own clip is left out
	}
	place := m
	if own, has := attribute(r, target, "transform"); has {
		place = affine_mul(m, parse_transform(own))
	}
	shapes := make([dynamic]Svg_Clip_Shape, context.temp_allocator)
	outer := r.capture
	r.capture = &shapes
	base := Paint_State{
		fill_on = true, fill = {0, 0, 0, 255}, current = {0, 0, 0, 255}, stroke_width = 1,
		fill_opacity = 1, stroke_opacity = 1, opacity = 1, nonzero = true, clip_nonzero = true,
	}
	update_state(r, target, &base)
	for child in r.doc.elements[target].value {
		if id, is_child := child.(xml.Element_ID); is_child {
			draw_element(r, id, base, place, depth + 1)
		}
	}
	r.capture = outer
	if len(shapes) == 0 {
		// an empty clip path hides everything: a clip with no shapes
		append(&r.arena.clips, Svg_Clip{})
		return i32(len(r.arena.clips) - 1)
	}
	kept := make([]Svg_Clip_Shape, len(shapes))
	copy(kept, shapes[:])
	append(&r.arena.clip_shapes, kept)
	append(&r.arena.clips, Svg_Clip{shapes = kept})
	return i32(len(r.arena.clips) - 1)
}

@(private = "file")
number_attr :: proc(r: ^Reader, id: xml.Element_ID, name: string, otherwise := 0.0) -> f64 {
	if value, found := property(r, id, name); found {
		if n, ok := length_of(value); ok {
			return n
		}
	}
	return otherwise
}

@(private = "file")
draw_element :: proc(r: ^Reader, id: xml.Element_ID, parent: Paint_State, parent_transform: Affine, depth: int) {
	if depth > SVG_MAX_DEPTH || r.points >= SVG_MAX_POINTS {
		return
	}
	element := r.doc.elements[id]
	if element.kind != .Element {
		return
	}
	name := local_name(element.ident)
	switch name {
	case "defs", "symbol", "clipPath", "mask", "pattern", "marker", "filter", "linearGradient", "radialGradient", "style", "title", "desc", "metadata", "script", "foreignObject", "view", "font", "cursor":
		if name == "foreignObject" {
			r.lost += {.Picture}
			r.raster_lost += {.Picture}
		}
		return
	case "text", "tspan", "textPath":
		r.lost += {.Text}
		r.raster_lost += {.Text}
		return
	case "image":
		r.lost += {.Picture}
		r.raster_lost += {.Picture}
		return
	}
	if value, found := property(r, id, "display"); found && strings.trim_space(value) == "none" {
		return
	}
	state := parent
	update_state(r, id, &state)
	m := parent_transform
	if value, found := attribute(r, id, "transform"); found {
		m = affine_mul(m, parse_transform(value))
	}
	// a clip path cuts the element and all it holds, in the element's own units; inside a clip path, clips are not read
	if value, found := property(r, id, "clip-path"); found && r.capture == nil && strings.trim_space(value) != "none" {
		state.clips = with_clip(state.clips, read_clip(r, value, m, depth))
	}
	if value, found := property(r, id, "visibility"); found {
		switch strings.trim_space(value) {
		case "hidden", "collapse":
			if name != "g" && name != "svg" && name != "a" {return}
		}
	}
	b := Builder{tolerance = r.tolerance / max(affine_scale(m), 1e-9)}
	b.contours = make([dynamic][dynamic]geom.Point, context.temp_allocator)
	b.closed = make([dynamic]bool, context.temp_allocator)
	b.current = make([dynamic]geom.Point, context.temp_allocator)
	switch name {
	case "svg", "g", "a", "switch":
		for value in element.value {
			if child, is_child := value.(xml.Element_ID); is_child {
				draw_element(r, child, state, m, depth + 1)
			}
		}
	case "use":
		href, found := attribute(r, id, "href")
		if !found {
			href, found = attribute(r, id, "xlink:href")
		}
		if !found || !strings.has_prefix(href, "#") {
			return
		}
		target, known := r.ids[href[1:]]
		if !known {
			return
		}
		moved := affine_mul(m, {1, 0, 0, 1, number_attr(r, id, "x"), number_attr(r, id, "y")})
		target_name := local_name(r.doc.elements[target].ident)
		if target_name == "symbol" || target_name == "svg" {
			for value in r.doc.elements[target].value {
				if child, is_child := value.(xml.Element_ID); is_child {
					draw_element(r, child, state, moved, depth + 1)
				}
			}
		} else {
			draw_element(r, target, state, moved, depth + 1)
		}
	case "path":
		if d, has := attribute(r, id, "d"); has {
			parse_path(&b, d)
			emit(r, &b, state, m)
		}
	case "rect":
		x, y := number_attr(r, id, "x"), number_attr(r, id, "y")
		w, h := number_attr(r, id, "width"), number_attr(r, id, "height")
		if !(w > 0 && h > 0) {
			return
		}
		rx, ry := number_attr(r, id, "rx", -1), number_attr(r, id, "ry", -1)
		if rx < 0 {rx = ry}
		if ry < 0 {ry = rx}
		rx, ry = clamp(max(rx, 0), 0, w / 2), clamp(max(ry, 0), 0, h / 2)
		if rx == 0 || ry == 0 {
			builder_move(&b, {x, y})
			builder_line(&b, {x + w, y})
			builder_line(&b, {x + w, y + h})
			builder_line(&b, {x, y + h})
		} else {
			builder_move(&b, {x + rx, y})
			builder_line(&b, {x + w - rx, y})
			builder_arc(&b, rx, ry, 0, false, true, {x + w, y + ry})
			builder_line(&b, {x + w, y + h - ry})
			builder_arc(&b, rx, ry, 0, false, true, {x + w - rx, y + h})
			builder_line(&b, {x + rx, y + h})
			builder_arc(&b, rx, ry, 0, false, true, {x, y + h - ry})
			builder_line(&b, {x, y + ry})
			builder_arc(&b, rx, ry, 0, false, true, {x + rx, y})
		}
		builder_close(&b)
		emit(r, &b, state, m)
	case "circle", "ellipse":
		cx, cy := number_attr(r, id, "cx"), number_attr(r, id, "cy")
		rx, ry: f64
		if name == "circle" {
			rx = number_attr(r, id, "r")
			ry = rx
		} else {
			rx, ry = number_attr(r, id, "rx"), number_attr(r, id, "ry")
		}
		if !(rx > 0 && ry > 0) {
			return
		}
		builder_move(&b, {cx + rx, cy})
		builder_arc(&b, rx, ry, 0, false, true, {cx, cy + ry})
		builder_arc(&b, rx, ry, 0, false, true, {cx - rx, cy})
		builder_arc(&b, rx, ry, 0, false, true, {cx, cy - ry})
		builder_arc(&b, rx, ry, 0, false, true, {cx + rx, cy})
		builder_close(&b)
		emit(r, &b, state, m)
	case "line":
		builder_move(&b, {number_attr(r, id, "x1"), number_attr(r, id, "y1")})
		builder_line(&b, {number_attr(r, id, "x2"), number_attr(r, id, "y2")})
		state.fill_on = false // a line has no inside
		emit(r, &b, state, m)
	case "polyline", "polygon":
		if value, has := attribute(r, id, "points"); has {
			n := numbers_in(value)
			for i := 0; i + 1 < len(n); i += 2 {
				p := geom.Point{n[i], n[i + 1]}
				if i == 0 {builder_move(&b, p)} else {builder_line(&b, p)}
			}
			if name == "polygon" {
				builder_close(&b)
			}
			emit(r, &b, state, m)
		}
	}
}

// The clips of a group with one more; a clip that could not be read (-1) leaves them as they were.
@(private = "file")
with_clip :: proc(clips: []i32, clip: i32) -> []i32 {
	if clip < 0 {
		return clips
	}
	more := make([]i32, len(clips) + 1, context.temp_allocator)
	copy(more, clips)
	more[len(clips)] = clip
	return more
}

// Reads an SVG file. The drawing's memory is its own; let it go with `svg_destroy`.
svg_read :: proc(bytes: []byte) -> (drawing: Svg_Drawing, error: Svg_Error) {
	doc, err := xml.parse_bytes(bytes, xml.Options{flags = {.Ignore_Unsupported, .Unbox_CDATA, .Decode_SGML_Entities}}, "", silent_xml_errors)
	if err != .None || doc == nil || doc.element_count == 0 {
		if doc != nil {xml.destroy(doc)}
		return {}, .Not_Svg
	}
	defer xml.destroy(doc)
	root: xml.Element_ID = 0
	if local_name(doc.elements[root].ident) != "svg" {
		return {}, .Not_Svg
	}
	r := Reader{doc = doc, arena = new(Svg_Arena), tolerance = 0.02}
	r.ids = make(map[string]xml.Element_ID, context.temp_allocator)
	r.gradients = make(map[string]maths.Colour, context.temp_allocator)
	r.templates = make(map[string]Gradient_Template, context.temp_allocator)
	r.rules = make([dynamic]Css_Rule, context.temp_allocator)
	for element, i in doc.elements {
		for a in element.attribs {
			if a.key == "id" {
				r.ids[a.val] = xml.Element_ID(i)
			}
		}
	}
	for element, _ in doc.elements {
		switch local_name(element.ident) {
		case "style":
			text := strings.builder_make(context.temp_allocator)
			for value in element.value {
				if s, is_text := value.(string); is_text {
					strings.write_string(&text, s)
				}
			}
			parse_rules(&r, strings.to_string(text))
		}
	}
	// the first stop of each gradient is the color it is drawn in, following a `href` to a gradient that has the stops
	for element, i in doc.elements {
		name := local_name(element.ident)
		if name != "linearGradient" && name != "radialGradient" {
			continue
		}
		own_id, has_id := attribute(&r, xml.Element_ID(i), "id")
		if !has_id {
			continue
		}
		holder := xml.Element_ID(i)
		for _ in 0 ..< 8 {
			found_stop := false
			for value in doc.elements[holder].value {
				child, is_child := value.(xml.Element_ID)
				if !is_child || local_name(doc.elements[child].ident) != "stop" {
					continue
				}
				colour := maths.Colour{0, 0, 0, 255}
				if text, found := property(&r, child, "stop-color"); found {
					if parsed, ok := parse_colour(text); ok {
						colour = parsed
					}
				}
				if text, found := property(&r, child, "stop-opacity"); found {
					if o, ok := opacity_of(text); ok {
						colour.a *= f32(o)
					}
				}
				r.gradients[own_id] = colour
				found_stop = true
				break
			}
			if found_stop {
				break
			}
			href, has_href := attribute(&r, holder, "href")
			if !has_href {
				href, has_href = attribute(&r, holder, "xlink:href")
			}
			if !has_href || !strings.has_prefix(href, "#") {
				break
			}
			next, known := r.ids[href[1:]]
			if !known {
				break
			}
			holder = next
		}
	}
	// the size of the drawing: the view box, else the width and height
	origin := [2]f64{}
	width, height := 0.0, 0.0
	if value, found := attribute(&r, root, "viewBox"); found {
		n := numbers_in(value)
		if len(n) == 4 && n[2] > 0 && n[3] > 0 {
			origin = {n[0], n[1]}
			width, height = n[2], n[3]
		}
	}
	if width == 0 {
		w, wok := length_of(attribute_text(&r, root, "width"))
		h, hok := length_of(attribute_text(&r, root, "height"))
		if wok && hok && w > 0 && h > 0 {
			width, height = w, h
		}
	}
	r.viewport = {width, height} if width > 0 else {100, 100}
	base := Paint_State{
		fill_on = true, fill = {0, 0, 0, 255}, current = {0, 0, 0, 255},
		stroke_width = 1, fill_opacity = 1, stroke_opacity = 1, opacity = 1, cap = .Butt, join = .Miter,
		nonzero = true, clip_nonzero = true,
	}
	// the root's own presentation attributes are read by `draw_element`, so its transform is the view box's alone
	draw_element(&r, root, base, {1, 0, 0, 1, -origin.x, -origin.y}, 0)
	if len(r.arena.items) == 0 {
		empty := Svg_Drawing{allocator = r.arena}
		svg_destroy(&empty)
		return {lost = r.lost, raster_lost = r.raster_lost}, .Empty
	}
	if width == 0 {
		// no size at all: the box round what was drawn
		hi := [2]f32{}
		for item in r.arena.items {
			for contour in item.contours {
				for p in contour.points {
					hi = {max(hi.x, p.x), max(hi.y, p.y)}
				}
			}
		}
		width, height = f64(max(hi.x, 1)), f64(max(hi.y, 1))
	}
	return Svg_Drawing{
		width = f32(width), height = f32(height),
		items = r.arena.items[:], gradients = r.arena.gradients[:], clips = r.arena.clips[:],
		lost = r.lost, raster_lost = r.raster_lost, allocator = r.arena,
	}, .None
}

@(private = "file")
attribute_text :: proc(r: ^Reader, id: xml.Element_ID, name: string) -> string {
	value, _ := attribute(r, id, name)
	return value
}

// Draws a drawing with its top left at (x, y), stretched to `width` by `height`, in the current transform,
// from the drawing's own colors and gradients (the current style is not used and is put back afterwards).
svg_draw :: proc(list: ^Command_List, d: ^Svg_Drawing, x, y, width, height: f32) {
	if len(d.items) == 0 || !(d.width > 0) || !(d.height > 0) || !finite(x, y, width, height) {
		return
	}
	push(list, .Style_And_Transform)
	defer pop(list)
	move(list, x, y)
	grow(list, width / d.width, height / d.height)
	outside := list.style.clip // the sketch's own clip, which every item's clips are made inside
	// the clip made for each list of clips (by its bytes), so items cut by the same ones, or by more inside them, share it
	made := make(map[string]Clip, 16, context.temp_allocator)
	for item in d.items {
		// from the longest start of its clips made already, the rest made inside it
		list.style.clip = outside
		start := 0
		for k := len(item.clips); k > 0; k -= 1 {
			if clip, known := made[string(slice.to_bytes(item.clips[:k]))]; known {
				list.style.clip, start = clip, k
				break
			}
		}
		for i in start ..< len(item.clips) {
			set_svg_clip(list, d, item.clips[i])
			made[string(slice.to_bytes(item.clips[:i + 1]))] = list.style.clip
		}
		list.look_changed = true
		box := contours_box(item.contours)
		if item.fill_on {
			if g, ok := svg_gpu_gradient(d, item.fill_gradient, item.fill_alpha, box); ok {
				set_fill_gradient(list, g)
			} else {
				set_fill(list, item.fill)
			}
		} else {
			no_fill(list)
		}
		if item.stroke_on {
			if g, ok := svg_gpu_gradient(d, item.stroke_gradient, item.stroke_alpha, box); ok {
				set_stroke_gradient(list, g)
			} else {
				set_stroke(list, item.stroke)
			}
			set_thickness(list, item.width)
			set_caps(list, item.cap)
			set_joins(list, item.join)
		} else {
			no_stroke(list)
		}
		if item.fill_on && item.stroke_on && len(item.fill_contours) != len(item.contours) {
			// the fill leaves some contours out and the outline does not: one shape for each
			stroke_on := list.style.stroke_on
			list.style.stroke_on = false
			path(list, item.fill_contours)
			list.style.stroke_on, list.style.fill_on = stroke_on, false
			list.look_changed = true
			path(list, item.contours)
		} else if item.fill_on {
			path(list, item.fill_contours)
		} else {
			path(list, item.contours)
		}
	}
}

// Keeps what is drawn next inside an SVG clip path as well as the clip in force: the union of its shapes, each by its
// own rule; one with no shapes hides everything.
@(private = "file")
set_svg_clip :: proc(list: ^Command_List, d: ^Svg_Drawing, index: i32) {
	if index < 0 || int(index) >= len(d.clips) {
		return
	}
	clip := d.clips[index]
	parts := make([][]Contour, len(clip.shapes), context.temp_allocator)
	for shape, i in clip.shapes {
		parts[i] = shape.fill_contours if len(shape.fill_contours) > 0 else shape.contours
	}
	set_clip_union(list, parts)
}

// The box round some contours, as `path` measures it for the shape it makes: x, y, width and height.
@(private = "file")
contours_box :: proc(contours: []Contour) -> [4]f32 {
	lo := [2]f32{max(f32), max(f32)}
	hi := [2]f32{min(f32), min(f32)}
	for c in contours {
		for p in c.points {
			lo = {min(lo.x, p.x), min(lo.y, p.y)}
			hi = {max(hi.x, p.x), max(hi.y, p.y)}
		}
	}
	if lo.x > hi.x {
		return {}
	}
	return {lo.x, lo.y, hi.x - lo.x, hi.y - lo.y}
}

// One of a drawing's gradients as the GPU draws it on a shape whose box (in the drawing's units) is `box`: a placed
// gradient whose transform starts from the box, with its colors' alpha multiplied by `alpha`. False for no gradient
// (-1) or one whose numbers the GPU cannot hold; the item's color is drawn then.
svg_gpu_gradient :: proc(d: ^Svg_Drawing, index: i32, alpha: f32, box: [4]f32) -> (g: Gradient, ok: bool) {
	if index < 0 || int(index) >= len(d.gradients) {
		return {}, false
	}
	sg := d.gradients[index]
	if len(sg.stops) == 0 {
		return {}, false
	}
	// the stops, at most MAX_STOPS of them: a gradient with more is sampled evenly between its first and last stop
	colours: [MAX_STOPS]maths.Colour
	offsets: [MAX_STOPS]f32
	count := len(sg.stops)
	if count <= MAX_STOPS {
		for stop, i in sg.stops {
			colours[i], offsets[i] = stop.colour, stop.offset * 100
		}
	} else {
		count = MAX_STOPS
		first, last := sg.stops[0].offset, sg.stops[len(sg.stops) - 1].offset
		for i in 0 ..< MAX_STOPS {
			at := first + (last - first) * f32(i) / (MAX_STOPS - 1)
			colours[i], offsets[i] = raster_stop_colour(sg.stops, f64(at)), at * 100
		}
	}
	for i in 0 ..< count {
		colours[i].a *= clamp(alpha, 0, 1)
	}
	g, ok = gradient_make(colours[:count], .Placed_Linear, space = .Rgb, stops = offsets[:count])
	if !ok {
		return {}, false
	}
	g.spread = sg.spread
	// from the point measured from the middle of the box over its half size, to the drawing's units, to the
	// gradient's own space, and on to the space the shader measures in
	half := [2]f64{max(f64(box[2]) / 2, 1e-4), max(f64(box[3]) / 2, 1e-4)}
	from_box := Affine{half.x, 0, 0, half.y, f64(box[0]) + f64(box[2]) / 2, f64(box[1]) + f64(box[3]) / 2}
	to_gradient := affine_mul(sg.to_gradient, from_box)
	finish: Affine
	dx, dy := sg.x2 - sg.x1, sg.y2 - sg.y1
	length := dx * dx + dy * dy
	if (!sg.radial && !(length > 0)) || (sg.radial && !(sg.r > 0)) {
		// two ends at one point, or a circle of no size: the last color everywhere
		g.colours[0], g.stops[0], g.count = g.colours[count - 1], 0, 1
		g.place = {1, 0, 0, 1, 0, 0}
		return g, true
	}
	if !sg.radial {
		// x along the way from the first end (0) to the second (1), y across it, so the transform can be undone
		finish = {dx / length, -dy / length, dy / length, dx / length, -(sg.x1 * dx + sg.y1 * dy) / length, (sg.x1 * dy - sg.y1 * dx) / length}
	} else {
		g.kind = .Placed_Radial
		finish = {1 / sg.r, 0, 0, 1 / sg.r, -sg.cx / sg.r, -sg.cy / sg.r}
		// the focal point is kept a little inside the circle, as SVG 1.1 says
		focus := [2]f64{(sg.fx - sg.cx) / sg.r, (sg.fy - sg.cy) / sg.r}
		if reach := math.sqrt(focus.x * focus.x + focus.y * focus.y); reach > 0.99 {
			focus *= 0.99 / reach
		}
		g.focus = {f32(focus.x), f32(focus.y)}
	}
	place := affine_mul(finish, to_gradient)
	for v, i in place {
		if !(abs(v) < 60000) {
			return {}, false // past what the GPU's 16-bit numbers hold
		}
		g.place[i] = f32(v)
	}
	return g, true
}

// A file that is not XML is an error the sketch says in words, not a line on the console.
@(private = "file")
silent_xml_errors :: proc(pos: xml.Pos, format: string, args: ..any) {}
