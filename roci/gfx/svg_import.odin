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
// What a drawing cannot show is not drawn and is counted in `lost`: text, embedded pictures, clip
// paths, masks, filters, patterns and markers; a gradient is drawn as the first color of its stops.
package gfx

import "../geom"
import "../maths"
import "core:encoding/xml"
import "core:math"
import "core:strconv"
import "core:strings"

// The most points a file may make; the rest of it is dropped.
SVG_MAX_POINTS :: 4_000_000
SVG_MAX_DEPTH :: 48

Svg_Item :: struct {
	contours:           []Contour, // in the drawing's units, with its top left at 0, 0
	fill_on, stroke_on: bool,
	fill, stroke:       maths.Colour,
	width:              f32, // of the outline, in the drawing's units
	cap:                geom.Cap,
	join:               geom.Join,
}

Svg_Lost :: enum u8 {
	Text,
	Picture,
	Gradient,
	Clip,
	Mask,
	Filter,
	Pattern,
	Marker,
}

Svg_Drawing :: struct {
	width, height: f32, // of the drawing: its view box, or its own width and height
	items:         []Svg_Item,
	lost:          bit_set[Svg_Lost],
	allocator:     ^Svg_Arena,
}

// What the drawing's memory is kept in, so one call lets it all go.
Svg_Arena :: struct {
	items:    [dynamic]Svg_Item,
	contours: [dynamic][]Contour,
	points:   [dynamic][][2]f32,
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
		delete(d.allocator.points)
		delete(d.allocator.contours)
		delete(d.allocator.items)
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
	doc:       ^xml.Document,
	ids:       map[string]xml.Element_ID,
	rules:     [dynamic]Css_Rule,
	gradients: map[string]maths.Colour,
	arena:     ^Svg_Arena,
	lost:      bit_set[Svg_Lost],
	points:    int,
	tolerance: f64,
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
read_paint :: proc(r: ^Reader, text: string, state: Paint_State) -> (colour: maths.Colour, on: bool, known: bool) {
	value := strings.trim_space(text)
	switch {
	case value == "none":
		return {}, false, true
	case value == "currentColor" || value == "currentcolor":
		return state.current, true, true
	case strings.has_prefix(value, "url("):
		close := strings.index_byte(value, ')')
		if close < 0 {
			return {}, false, false
		}
		name := strings.trim(value[4:close], " \"'#")
		if g, found := r.gradients[name]; found {
			r.lost += {.Gradient}
			return g, true, true
		}
		// a pattern or a gradient with no stops: left out; the fallback after the url, if any, is not used
		r.lost += {.Pattern}
		return {}, false, true
	}
	c, ok := parse_colour(value)
	if !ok {
		return {}, false, false
	}
	return c, true, true
}

@(private = "file")
update_state :: proc(r: ^Reader, id: xml.Element_ID, state: ^Paint_State) {
	if value, found := property(r, id, "color"); found {
		if c, ok := parse_colour(value); ok {
			state.current = c
		}
	}
	if value, found := property(r, id, "fill"); found {
		if c, on, known := read_paint(r, value, state^); known {
			state.fill, state.fill_on = c, on
		}
	}
	if value, found := property(r, id, "stroke"); found {
		if c, on, known := read_paint(r, value, state^); known {
			state.stroke, state.stroke_on = c, on
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
			r.lost += {name.kind}
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

// Moves a builder's contours onto the drawing and keeps them as an item with the state's paint.
@(private = "file")
emit :: proc(r: ^Reader, b: ^Builder, state: Paint_State, m: Affine) {
	builder_finish(b, false)
	if len(b.contours) == 0 || r.points >= SVG_MAX_POINTS {
		return
	}
	fill_on := state.fill_on && state.fill.a > 0 && state.opacity * state.fill_opacity > 0
	stroke_on := state.stroke_on && state.stroke.a > 0 && state.stroke_width > 0 && state.opacity * state.stroke_opacity > 0
	if !fill_on && !stroke_on {
		return
	}
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
	item := Svg_Item{
		contours  = contours,
		fill_on   = fill_on,
		stroke_on = stroke_on,
		width     = f32(state.stroke_width * affine_scale(m)),
		cap       = state.cap,
		join      = state.join,
	}
	item.fill = state.fill
	item.fill.a *= f32(state.opacity * state.fill_opacity)
	item.stroke = state.stroke
	item.stroke.a *= f32(state.opacity * state.stroke_opacity)
	append(&r.arena.items, item)
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
		if name == "foreignObject" {r.lost += {.Picture}}
		return
	case "text", "tspan", "textPath":
		r.lost += {.Text}
		return
	case "image":
		r.lost += {.Picture}
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
	base := Paint_State{
		fill_on = true, fill = {0, 0, 0, 255}, current = {0, 0, 0, 255},
		stroke_width = 1, fill_opacity = 1, stroke_opacity = 1, opacity = 1, cap = .Butt, join = .Miter,
	}
	// the root's own presentation attributes are read by `draw_element`, so its transform is the view box's alone
	draw_element(&r, root, base, {1, 0, 0, 1, -origin.x, -origin.y}, 0)
	if len(r.arena.items) == 0 {
		empty := Svg_Drawing{allocator = r.arena}
		svg_destroy(&empty)
		return {lost = r.lost}, .Empty
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
		items = r.arena.items[:], lost = r.lost, allocator = r.arena,
	}, .None
}

@(private = "file")
attribute_text :: proc(r: ^Reader, id: xml.Element_ID, name: string) -> string {
	value, _ := attribute(r, id, name)
	return value
}

// Draws a drawing with its top left at (x, y), stretched to `width` by `height`, in the current transform,
// from the drawing's own colors (the current style is not used and is put back afterwards).
svg_draw :: proc(list: ^Command_List, d: ^Svg_Drawing, x, y, width, height: f32) {
	if len(d.items) == 0 || !(d.width > 0) || !(d.height > 0) || !finite(x, y, width, height) {
		return
	}
	push(list, .Style_And_Transform)
	defer pop(list)
	move(list, x, y)
	grow(list, width / d.width, height / d.height)
	for item in d.items {
		if item.fill_on {
			set_fill(list, item.fill)
		} else {
			no_fill(list)
		}
		if item.stroke_on {
			set_stroke(list, item.stroke)
			set_thickness(list, item.width)
			set_caps(list, item.cap)
			set_joins(list, item.join)
		} else {
			no_stroke(list)
		}
		path(list, item.contours)
	}
}

// A file that is not XML is an error the sketch says in words, not a line on the console.
@(private = "file")
silent_xml_errors :: proc(pos: xml.Pos, format: string, args: ..any) {}
