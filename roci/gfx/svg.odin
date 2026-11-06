// SPDX-License-Identifier: 0BSD
//
// A frame as an SVG file: the command list is plain data that describes every shape, its
// style and the transform it was drawn under, so each shape becomes one SVG element
// (circle, ellipse, rect, line, polygon, path or text) with the same style, and the
// transform is carried as the element's own, so an outline's width follows it as it does
// on the screen. Gradients are written as SVG gradients (a linear one and a radial one
// reach the same places as the GPU's; the colours between the stops are taken from the
// baked ramp so Oklab mixing is kept), pictures are embedded as PNG, a clip is a clip
// path and a blend is `mix-blend-mode`.
//
// What a file cannot say is left out or drawn as the nearest thing, and `svg_write` says
// what, so the caller can tell the writer: a conic gradient,
// a picture or shader fill (the fill's own color), the picture of a canvas, an effect
// over the window, the `subtract` blend, a tint, and a text's own font, which the file
// names and the viewer has to have.
package gfx

import "core:encoding/base64"
import "core:math"
import "core:strconv"
import "core:strings"
import ttf "vendor:sdl3/ttf"

import "../maths"

@(private = "file")
Svg :: struct {
	defs:     strings.Builder,
	body:     strings.Builder,
	ids:      int,
	left_out: [dynamic]string,
	pictures: map[Image_Id]string, // the id of each picture already in the defs
	list:     ^Command_List,
}

// The file for a frame whose canvas is `width` by `height` logical pixels, and the things
// in it that could not be said exactly. Both are in `allocator` (the notes are literals,
// only their list is allocated).
svg_write :: proc(list: ^Command_List, width, height: int, allocator := context.allocator) -> (svg: string, left_out: []string) {
	s := Svg{list = list}
	s.defs = strings.builder_make(context.temp_allocator)
	s.body = strings.builder_make(context.temp_allocator)
	s.left_out = make([dynamic]string, context.temp_allocator)
	s.pictures = make(map[Image_Id]string, context.temp_allocator)

	svg_background(&s, width, height)
	for i in 0 ..< len(list.commands) {
		svg_command(&s, command_at(list, i), width, height)
	}
	if len(list.effects) > 0 {
		note(&s, "the effects over the window")
	}

	out := strings.builder_make(allocator)
	strings.write_string(&out, `<?xml version="1.0" encoding="UTF-8"?>` + "\n")
	strings.write_string(&out, `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" width="`)
	number(&out, f32(width))
	strings.write_string(&out, `" height="`)
	number(&out, f32(height))
	strings.write_string(&out, `" viewBox="0 0 `)
	number(&out, f32(width))
	strings.write_byte(&out, ' ')
	number(&out, f32(height))
	strings.write_string(&out, "\">\n")
	if strings.builder_len(s.defs) > 0 {
		strings.write_string(&out, "<defs>\n")
		strings.write_string(&out, strings.to_string(s.defs))
		strings.write_string(&out, "</defs>\n")
	}
	strings.write_string(&out, strings.to_string(s.body))
	strings.write_string(&out, "</svg>\n")

	notes := make([]string, len(s.left_out), allocator)
	copy(notes, s.left_out[:])
	return strings.to_string(out), notes
}

@(private = "file")
note :: proc(s: ^Svg, what: string) {
	for existing in s.left_out {
		if existing == what {
			return
		}
	}
	append(&s.left_out, what)
}

// A number with at most `decimals` decimals (three) and no trailing zeros.
@(private)
number :: proc(b: ^strings.Builder, v: f32, decimals := 3) {
	buf: [48]u8
	text := strconv.write_float(buf[:], f64(v), 'f', decimals, 32)
	text = strings.trim_left(text, "+")
	if strings.contains_rune(text, '.') {
		text = strings.trim_right(text, "0")
		text = strings.trim_right(text, ".")
	}
	if text == "-0" || text == "" {
		text = "0"
	}
	strings.write_string(b, text)
}

@(private = "file")
attr_number :: proc(b: ^strings.Builder, name: string, v: f32) {
	strings.write_byte(b, ' ')
	strings.write_string(b, name)
	strings.write_string(b, `="`)
	number(b, v)
	strings.write_byte(b, '"')
}

@(private = "file")
hex_colour :: proc(b: ^strings.Builder, c: maths.Colour) {
	digits := "0123456789abcdef"
	strings.write_byte(b, '#')
	for v in c.rgb {
		n := int(math.round(clamp(v, 0, 255)))
		strings.write_byte(b, digits[n >> 4])
		strings.write_byte(b, digits[n & 15])
	}
}

@(private = "file")
escape :: proc(b: ^strings.Builder, text: string) {
	for r in text {
		switch r {
		case '&': strings.write_string(b, "&amp;")
		case '<': strings.write_string(b, "&lt;")
		case '>': strings.write_string(b, "&gt;")
		case '"': strings.write_string(b, "&quot;")
		case: strings.write_rune(b, r)
		}
	}
}

@(private = "file")
new_id :: proc(s: ^Svg, prefix: string) -> string {
	s.ids += 1
	buf: [24]u8
	digits := strconv.write_int(buf[:], i64(s.ids), 10)
	return strings.concatenate({prefix, digits}, context.temp_allocator)
}

// ---- paints ----

// A gradient written into the defs, for a shape whose own (untransformed) box is given.
// Gives its id, or "" for a conic gradient, which SVG cannot say.
@(private = "file")
gradient_def :: proc(s: ^Svg, ref: Gradient_Ref, box: [4]f32) -> string {
	if ref.id == 0 || int(ref.id) > len(s.list.gradients) {
		return ""
	}
	g := s.list.gradients[ref.id - 1]
	if g.kind == .Conic {
		return ""
	}
	id := new_id(s, "g")
	b := &s.defs
	x, y, w, h := box[0], box[1], max(box[2], 1e-4), max(box[3], 1e-4)
	switch g.kind {
	case .Linear:
		turns := math.to_radians(f64(g.angle))
		dx, dy := f32(math.cos(turns)), f32(math.sin(turns))
		extent := abs(w * dx) + abs(h * dy)
		cx, cy := x + w / 2, y + h / 2
		strings.write_string(b, `<linearGradient id="`)
		strings.write_string(b, id)
		strings.write_string(b, `" gradientUnits="userSpaceOnUse"`)
		attr_number(b, "x1", cx - dx * extent / 2)
		attr_number(b, "y1", cy - dy * extent / 2)
		attr_number(b, "x2", cx + dx * extent / 2)
		attr_number(b, "y2", cy + dy * extent / 2)
	case .Radial:
		strings.write_string(b, `<radialGradient id="`)
		strings.write_string(b, id)
		strings.write_string(b, `" gradientUnits="objectBoundingBox"`)
		attr_number(b, "cx", g.centre.x / 100)
		attr_number(b, "cy", g.centre.y / 100)
		attr_number(b, "r", 0.5)
	case .Conic:
	}
	strings.write_string(b, ">\n")
	// the ramp the GPU reads, sampled, so the mixing in Oklab is kept
	STOPS :: 32
	for i in 0 ..= STOPS {
		percent := f32(i) / STOPS * 100
		c := gradient_colour_at(g, percent)
		strings.write_string(b, `<stop`)
		attr_number(b, "offset", percent / 100)
		strings.write_string(b, ` stop-color="`)
		hex_colour(b, c)
		strings.write_byte(b, '"')
		if c.a < 255 {
			attr_number(b, "stop-opacity", c.a / 255)
		}
		strings.write_string(b, "/>\n")
	}
	strings.write_string(b, g.kind == .Linear ? "</linearGradient>\n" : "</radialGradient>\n")
	return id
}

// The `fill` or `stroke` attributes of an element. `name` is "fill" or "stroke".
@(private = "file")
paint :: proc(s: ^Svg, name: string, colour: maths.Colour, ref: Gradient_Ref, alpha: f32, box: [4]f32, picture, shader: bool) {
	b := &s.body
	strings.write_byte(b, ' ')
	strings.write_string(b, name)
	strings.write_string(b, `="`)
	opacity := alpha / 255
	if ref.id != 0 {
		if id := gradient_def(s, ref, box); id != "" {
			strings.write_string(b, "url(#")
			strings.write_string(b, id)
			strings.write_string(b, `)"`)
			if opacity < 1 {
				attr_number(b, strings.concatenate({name, "-opacity"}, context.temp_allocator), opacity)
			}
			return
		}
		note(s, "a conic gradient")
		c := gradient_colour_at(s.list.gradients[ref.id - 1], 50)
		hex_colour(b, c)
		strings.write_byte(b, '"')
		opacity *= c.a / 255
	} else {
		if picture {
			note(s, "a picture fill")
		}
		if shader {
			note(s, "a shader fill")
		}
		hex_colour(b, colour)
		strings.write_byte(b, '"')
		opacity *= colour.a / 255
	}
	if opacity < 1 {
		attr_number(b, strings.concatenate({name, "-opacity"}, context.temp_allocator), opacity)
	}
}

// ---- elements ----

@(private = "file")
svg_background :: proc(s: ^Svg, width, height: int) {
	list := s.list
	b := &s.body
	box := [4]f32{0, 0, f32(width), f32(height)}
	if list.background_paint.id != 0 || list.background.a > 0 {
		strings.write_string(b, "<rect")
		attr_number(b, "width", box[2])
		attr_number(b, "height", box[3])
		paint(s, "fill", list.background, list.background_paint, 255, box, false, false)
		strings.write_string(b, "/>\n")
	}
	if list.background_image.image != 0 {
		note(s, "the picture behind everything")
	}
}

@(private = "file")
write_transform :: proc(b: ^strings.Builder, t: Transform) {
	if t == IDENTITY {
		return
	}
	strings.write_string(b, ` transform="matrix(`)
	values := [6]f32{t.a, t.b, t.c, t.d, t.e, t.f}
	for v, i in values {
		if i > 0 {
			strings.write_byte(b, ' ')
		}
		number(b, v)
	}
	strings.write_string(b, `)"`)
}

// The stroke attributes, or `stroke="none"` when there is no outline.
@(private = "file")
stroke_attrs :: proc(s: ^Svg, c: Command, box: [4]f32) {
	b := &s.body
	st := c.style
	if !(st.stroke_on && st.thickness > 0) {
		return
	}
	paint(s, "stroke", st.stroke, st.stroke_paint, st.alpha, box, st.stroke_image.image != 0, false)
	attr_number(b, "stroke-width", st.thickness)
	switch st.cap {
	case .Butt: strings.write_string(b, ` stroke-linecap="butt"`)
	case .Round: strings.write_string(b, ` stroke-linecap="round"`)
	case .Square: strings.write_string(b, ` stroke-linecap="square"`)
	}
	switch st.join {
	case .Miter: // the default
	case .Round: strings.write_string(b, ` stroke-linejoin="round"`)
	case .Bevel: strings.write_string(b, ` stroke-linejoin="bevel"`)
	}
}

@(private = "file")
fill_attrs :: proc(s: ^Svg, c: Command, box: [4]f32) {
	st := c.style
	if st.fill_on && has_area(c) {
		paint(s, "fill", st.fill, st.fill_paint, st.alpha, box, st.fill_image.image != 0, st.fill_shader.shader != 0)
	} else {
		strings.write_string(&s.body, ` fill="none"`)
	}
}

@(private = "file")
svg_command :: proc(s: ^Svg, c: Command, width, height: int) {
	if !is_visible(c) {
		return
	}
	// a clip or a blend is a group round the element
	st := c.style
	grouped := st.clip.on || st.blend != .Normal
	b := &s.body
	if grouped {
		strings.write_string(b, "<g")
		if st.clip.on {
			id := new_id(s, "c")
			strings.write_string(&s.defs, `<clipPath id="`)
			strings.write_string(&s.defs, id)
			strings.write_string(&s.defs, `"><rect`)
			attr_number(&s.defs, "x", st.clip.rect[0])
			attr_number(&s.defs, "y", st.clip.rect[1])
			attr_number(&s.defs, "width", max(st.clip.rect[2] - st.clip.rect[0], 0))
			attr_number(&s.defs, "height", max(st.clip.rect[3] - st.clip.rect[1], 0))
			strings.write_string(&s.defs, "/></clipPath>\n")
			strings.write_string(b, ` clip-path="url(#`)
			strings.write_string(b, id)
			strings.write_string(b, `)"`)
		}
		switch st.blend {
		case .Normal:
		case .Add: strings.write_string(b, ` style="mix-blend-mode:plus-lighter"`)
		case .Multiply: strings.write_string(b, ` style="mix-blend-mode:multiply"`)
		case .Screen: strings.write_string(b, ` style="mix-blend-mode:screen"`)
		case .Lighten: strings.write_string(b, ` style="mix-blend-mode:lighten"`)
		case .Subtract: note(s, "the subtract blend")
		}
		strings.write_string(b, ">\n")
	}
	svg_shape(s, c)
	if grouped {
		strings.write_string(b, "</g>\n")
	}
}

@(private = "file")
svg_shape :: proc(s: ^Svg, c: Command) {
	b := &s.body
	a := c.args
	lx, ly, lw, lh := local_bounds(c)
	box := [4]f32{lx, ly, lw, lh}
	switch c.kind {
	case .Circle:
		strings.write_string(b, "<circle")
		attr_number(b, "cx", lx + lw / 2)
		attr_number(b, "cy", ly + lh / 2)
		attr_number(b, "r", a[2])
		fill_attrs(s, c, box)
		stroke_attrs(s, c, box)
		write_transform(b, c.transform)
		strings.write_string(b, "/>\n")
	case .Ellipse:
		strings.write_string(b, "<ellipse")
		attr_number(b, "cx", lx + lw / 2)
		attr_number(b, "cy", ly + lh / 2)
		attr_number(b, "rx", lw / 2)
		attr_number(b, "ry", lh / 2)
		fill_attrs(s, c, box)
		stroke_attrs(s, c, box)
		write_transform(b, c.transform)
		strings.write_string(b, "/>\n")
	case .Rect:
		strings.write_string(b, "<rect")
		attr_number(b, "x", lx)
		attr_number(b, "y", ly)
		attr_number(b, "width", lw)
		attr_number(b, "height", lh)
		fill_attrs(s, c, box)
		stroke_attrs(s, c, box)
		write_transform(b, c.transform)
		strings.write_string(b, "/>\n")
	case .Line:
		strings.write_string(b, "<line")
		attr_number(b, "x1", a[0])
		attr_number(b, "y1", a[1])
		attr_number(b, "x2", a[2])
		attr_number(b, "y2", a[3])
		strings.write_string(b, ` fill="none"`)
		stroke_attrs(s, c, box)
		write_transform(b, c.transform)
		strings.write_string(b, "/>\n")
	case .Point:
		// a point is a line of no length: its caps make the dot
		strings.write_string(b, "<line")
		attr_number(b, "x1", a[0])
		attr_number(b, "y1", a[1])
		attr_number(b, "x2", a[0])
		attr_number(b, "y2", a[1])
		strings.write_string(b, ` fill="none"`)
		stroke_attrs(s, c, box)
		write_transform(b, c.transform)
		strings.write_string(b, "/>\n")
	case .Triangle, .Quad:
		corners := 3 if c.kind == .Triangle else 4
		strings.write_string(b, "<polygon points=\"")
		for i in 0 ..< corners {
			if i > 0 {
				strings.write_byte(b, ' ')
			}
			number(b, a[i * 2])
			strings.write_byte(b, ',')
			number(b, a[i * 2 + 1])
		}
		strings.write_byte(b, '"')
		fill_attrs(s, c, box)
		stroke_attrs(s, c, box)
		write_transform(b, c.transform)
		strings.write_string(b, "/>\n")
	case .Arc:
		svg_arc(s, c, box)
	case .Typeset:
		typeset_element(s, c, box)
	case .Text:
		// the overlay's own text, which a sketch never writes
	case .Image:
		image_element(s, c)
	}
}

// An arc: the pie is the fill, the curve alone the outline, all the way round when the
// sweep is a whole turn.
@(private = "file")
svg_arc :: proc(s: ^Svg, c: Command, box: [4]f32) {
	b := &s.body
	a := c.args
	cx, cy := box[0] + box[2] / 2, box[1] + box[3] / 2
	rx, ry := box[2] / 2, box[3] / 2
	start, stop := f64(a[4]), f64(a[5])
	sweep := stop - start
	if sweep == 0 || rx <= 0 || ry <= 0 {
		return
	}
	for sweep < 0 {
		sweep += 360
	}
	whole := sweep >= 360
	point :: proc(cx, cy, rx, ry: f32, degrees: f64) -> [2]f32 {
		r := math.to_radians(degrees)
		return {cx + rx * f32(math.cos(r)), cy + ry * f32(math.sin(r))}
	}
	path := strings.builder_make(context.temp_allocator)
	p0 := point(cx, cy, rx, ry, start)
	if whole {
		// two half turns, since one arc command cannot start and end at the same place
		pm := point(cx, cy, rx, ry, start + 180)
		strings.write_string(&path, "M")
		number(&path, p0.x)
		strings.write_byte(&path, ' ')
		number(&path, p0.y)
		ends := [2][2]f32{pm, p0}
		for p in ends {
			strings.write_string(&path, " A")
			number(&path, rx)
			strings.write_byte(&path, ' ')
			number(&path, ry)
			strings.write_string(&path, " 0 1 1 ")
			number(&path, p.x)
			strings.write_byte(&path, ' ')
			number(&path, p.y)
		}
		strings.write_string(&path, " Z")
	} else {
		p1 := point(cx, cy, rx, ry, start + sweep)
		strings.write_string(&path, "M")
		number(&path, p0.x)
		strings.write_byte(&path, ' ')
		number(&path, p0.y)
		strings.write_string(&path, " A")
		number(&path, rx)
		strings.write_byte(&path, ' ')
		number(&path, ry)
		strings.write_string(&path, sweep > 180 ? " 0 1 1 " : " 0 0 1 ")
		number(&path, p1.x)
		strings.write_byte(&path, ' ')
		number(&path, p1.y)
	}
	curve := strings.to_string(path)
	if c.style.fill_on && has_area(c) {
		strings.write_string(b, `<path d="`)
		strings.write_string(b, curve)
		if !whole {
			strings.write_string(b, " L")
			number(b, cx)
			strings.write_byte(b, ' ')
			number(b, cy)
			strings.write_string(b, " Z")
		}
		strings.write_byte(b, '"')
		fill_attrs(s, c, box)
		write_transform(b, c.transform)
		strings.write_string(b, "/>\n")
	}
	if c.style.stroke_on && c.style.thickness > 0 {
		strings.write_string(b, `<path d="`)
		strings.write_string(b, curve)
		strings.write_string(b, `" fill="none"`)
		stroke_attrs(s, c, box)
		write_transform(b, c.transform)
		strings.write_string(b, "/>\n")
	}
}

// ---- text ----

// How far a text's first baseline is below its top, and the distance between baselines, in
// logical pixels, as the renderer lays the text out.
@(private)
font_vertical :: proc(st: Style) -> (ascent, line_height: f32) {
	ascent = st.font_size * 0.96875 // Inter's own, until the font says
	line_height = st.font_size * 1.21
	if font := font_for(st.font, st.font_size, st.align, st.leading); font != nil {
		ascent = f32(ttf.GetFontAscent(font))
		line_height = f32(ttf.GetFontLineSkip(font))
	}
	return
}

// The lines of a text: broken where it has line breaks, and, when `wrap` is above 0, where
// the renderer breaks a line wider than `wrap` pixels (SDL_ttf says where, so a file breaks
// its lines exactly as the window does; a text with emoji, which the renderer sets with
// spaces in their place, is broken at spaces by measure instead).
@(private)
text_lines :: proc(c: Command, text: string, wrap: f32) -> []string {
	lines := make([dynamic]string, context.temp_allocator)
	st := c.style
	if wrap > 0 {
		if broken, ok := sdl_lines(c, text, wrap); ok {
			return broken
		}
	}
	for paragraph in strings.split(text, "\n", context.temp_allocator) {
		if wrap <= 0 {
			append(&lines, paragraph)
			continue
		}
		line := ""
		for word in strings.split(paragraph, " ", context.temp_allocator) {
			candidate := word if line == "" else strings.concatenate({line, " ", word}, context.temp_allocator)
			w, _ := measure_typeset(st.font, st.font_size, st.align, candidate)
			if w > wrap && line != "" {
				append(&lines, line)
				line = word
			} else {
				line = candidate
			}
		}
		append(&lines, line)
	}
	return lines[:]
}

// The lines SDL_ttf breaks a text into at a wrap width, or false when it cannot say (no font,
// or emoji in the text).
@(private = "file")
sdl_lines :: proc(c: Command, text: string, wrap: f32) -> ([]string, bool) {
	st := c.style
	if swapped, _ := split_emoji(text, context.temp_allocator); swapped != text {
		return nil, false
	}
	font := font_for(st.font, st.font_size, st.align, st.leading)
	if font == nil || len(text) == 0 {
		return nil, false
	}
	laid := ttf.CreateText(nil, font, raw_data(text), uint(len(text)))
	if laid == nil {
		return nil, false
	}
	defer ttf.DestroyText(laid)
	ttf.SetTextWrapWidth(laid, i32(wrap))
	lines := make([dynamic]string, context.temp_allocator)
	for i in 0 ..< 1000 {
		piece: ttf.SubString
		if !ttf.GetTextSubStringForLine(laid, i32(i), &piece) {
			break
		}
		start, end := int(piece.offset), int(piece.offset) + int(piece.length)
		if start < 0 || end > len(text) {
			return nil, false
		}
		append(&lines, strings.trim_right(text[start:end], " \n"))
		if end >= len(text) {
			break // the last line: asked past it, SDL_ttf gives the last one again
		}
	}
	if len(lines) == 0 {
		return nil, false
	}
	return lines[:], true
}

@(private = "file")
typeset_element :: proc(s: ^Svg, c: Command, box: [4]f32) {
	b := &s.body
	a := c.args
	offset, length := int(a[5]), int(a[6])
	if offset < 0 || offset + length > len(s.list.text) {
		return
	}
	text := string(s.list.text[offset:offset + length])
	st := c.style
	wrap := a[2]
	lines := text_lines(c, text, wrap)

	family, bold := "Inter", false
	if int(st.font) < len(fonts.faces) {
		name := fonts.faces[st.font].name
		if strings.has_suffix(name, " Bold") {
			family, bold = name[:len(name) - 5], true
		} else {
			family = name
		}
	}
	ascent, line_height := font_vertical(st)
	// the text's point is where its lines are aligned to: its left edge, its middle or its right
	// edge, as the renderer places it
	x := a[0]
	anchor := "start"
	switch st.align {
	case .Left:
	case .Center: anchor = "middle"
	case .Right: anchor = "end"
	}

	strings.write_string(b, "<text")
	strings.write_string(b, ` font-family="`)
	escape(b, family)
	strings.write_string(b, `, sans-serif"`)
	attr_number(b, "font-size", st.font_size)
	if bold {
		strings.write_string(b, ` font-weight="700"`)
	}
	strings.write_string(b, ` text-anchor="`)
	strings.write_string(b, anchor)
	strings.write_string(b, `" xml:space="preserve"`)
	if st.fill_on {
		paint(s, "fill", st.fill, st.fill_paint, st.alpha, box, st.fill_image.image != 0, st.fill_shader.shader != 0)
	}
	write_transform(b, c.transform)
	strings.write_string(b, ">")
	for line, i in lines {
		strings.write_string(b, "<tspan")
		attr_number(b, "x", x)
		attr_number(b, "y", a[1] + ascent + f32(i) * line_height)
		strings.write_string(b, ">")
		escape(b, line)
		strings.write_string(b, "</tspan>")
	}
	strings.write_string(b, "</text>\n")
}

// ---- pictures ----

@(private = "file")
image_element :: proc(s: ^Svg, c: Command) {
	b := &s.body
	a := c.args
	id := Image_Id(a[4])
	data := image_data(id)
	if data == nil {
		return
	}
	if data.canvas != nil || data.pixels == nil {
		note(s, "a canvas shown with image")
		return
	}
	ref, known := s.pictures[id]
	if !known {
		png, ok := png_encode(Image{data.width, data.height, data.pixels}, context.temp_allocator)
		if !ok {
			note(s, "a picture that could not be turned into a PNG")
			return
		}
		encoded := base64.encode(png, allocator = context.temp_allocator)
		ref = new_id(s, "p")
		strings.write_string(&s.defs, `<image id="`)
		strings.write_string(&s.defs, ref)
		strings.write_string(&s.defs, `" width="`)
		number(&s.defs, f32(data.width))
		strings.write_string(&s.defs, `" height="`)
		number(&s.defs, f32(data.height))
		strings.write_string(&s.defs, `" preserveAspectRatio="none" xlink:href="data:image/png;base64,`)
		strings.write_string(&s.defs, encoded)
		strings.write_string(&s.defs, "\"/>\n")
		s.pictures[id] = ref
	}
	lx, ly, lw, lh := local_bounds(c)
	if lw <= 0 || lh <= 0 {
		return
	}
	if c.style.tint != (maths.Colour{255, 255, 255, 255}) {
		note(s, "a tint on a picture")
	}
	opacity := c.style.tint.a / 255 * c.style.alpha / 255
	strings.write_string(b, `<use xlink:href="#`)
	strings.write_string(b, ref)
	strings.write_byte(b, '"')
	if opacity < 1 {
		attr_number(b, "opacity", opacity)
	}
	// the picture is its own size at the origin: scaled and moved into its box, then carried by the transform
	t := transform_mul(c.transform, Transform{lw / f32(data.width), 0, 0, lh / f32(data.height), lx, ly})
	write_transform(b, t)
	strings.write_string(b, "/>\n")
}
