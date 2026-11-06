// SPDX-License-Identifier: 0BSD
//
// A frame as a PDF file: one page, as big as the window (a logical pixel is a point), whose
// content is the command list written as PDF's own drawing operators: paths for the shapes,
// filled and stroked with the style's colors, widths, caps and joins, under the transform
// each was drawn with. Gradients are shading patterns, a clip is a clip path, a blend is a
// blend mode, opacity is a graphics state, pictures are image objects (with their alpha as
// a soft mask) and text is the outlines of its letters (truetype.odin), so the file needs no
// font where it is read. Everything is written by hand, with the deflate compressor from
// sancho for the streams, and no date or random number goes in, so the same frame always
// gives the same bytes.
//
// What a PDF cannot say is drawn as the nearest thing or left out, and `pdf_write` says what,
// as `svg_write` does: a conic gradient (its middle color), a picture or shader fill (the
// fill's color), the picture of a canvas, a picture behind everything, a tint, the `add` and
// `subtract` blends (there is no such mode), transparency inside a gradient, effects, text in
// a font whose outlines cannot be read and characters the font does not have (emoji and the
// scripts a fallback font draws), and, for text, kerning.
package gfx

import "core:math"
import "core:strconv"
import "core:strings"

import "../../vendor/sancho/deflate"
import "../maths"

@(private = "file")
Pdf_Object :: struct {
	id:   int,
	body: []u8,
}

@(private = "file")
Gs_Key :: struct {
	fill, stroke: f32, // opacity, 0 to 1
	blend:        Blend_Mode,
}

@(private = "file")
Pdf :: struct {
	list:     ^Command_List,
	width:    f32,
	height:   f32,
	content:  strings.Builder,
	objects:  [dynamic]Pdf_Object,
	next_id:  int,
	gs:       [dynamic]Gs_Key, // /G1 and up, in order
	gs_ids:   [dynamic]int,
	patterns: [dynamic]int, // object numbers, /P1 and up
	images:   [dynamic]int, // object numbers, /I1 and up
	image_of: map[Image_Id]int, // the /I number of a picture already in
	fonts:    map[u16]Ttf,
	no_font:  map[u16]bool,
	left_out: [dynamic]string,
}

// The file for a frame whose canvas is `width` by `height` logical pixels, and the things in
// it that could not be said exactly. Both are in `allocator` (the notes are literals).
pdf_write :: proc(list: ^Command_List, width, height: int, allocator := context.allocator) -> (pdf: []u8, left_out: []string) {
	p := Pdf{list = list, width = f32(width), height = f32(height), next_id = 5}
	p.content = strings.builder_make(context.temp_allocator)
	p.objects = make([dynamic]Pdf_Object, context.temp_allocator)
	p.gs = make([dynamic]Gs_Key, context.temp_allocator)
	p.gs_ids = make([dynamic]int, context.temp_allocator)
	p.patterns = make([dynamic]int, context.temp_allocator)
	p.images = make([dynamic]int, context.temp_allocator)
	p.image_of = make(map[Image_Id]int, context.temp_allocator)
	p.fonts = make(map[u16]Ttf, context.temp_allocator)
	p.no_font = make(map[u16]bool, context.temp_allocator)
	p.left_out = make([dynamic]string, context.temp_allocator)

	// the page is drawn with y down, as every sketch is, so the first thing is to turn it over
	strings.write_string(&p.content, "1 0 0 -1 0 ")
	number(&p.content, p.height)
	strings.write_string(&p.content, " cm\n")
	pdf_background(&p)
	for i in 0 ..< len(list.commands) {
		pdf_command(&p, command_at(list, i))
	}
	if len(list.effects) > 0 {
		pdf_note(&p, "the effects over the window")
	}

	// the content, then the objects it asked for, then the fixed ones
	content_id := 4
	content := compress_stream(strings.to_string(p.content))
	content_body := stream_object("", content)

	out := make([dynamic]u8, allocator)
	offsets := make([dynamic]int, context.temp_allocator)
	put :: proc(out: ^[dynamic]u8, text: string) {
		append(out, ..transmute([]u8)text)
	}
	put(&out, "%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
	object :: proc(out: ^[dynamic]u8, offsets: ^[dynamic]int, id: int, body: []u8) {
		for len(offsets) <= id {
			append(offsets, 0)
		}
		offsets[id] = len(out)
		put(out, itoa(id))
		put(out, " 0 obj\n")
		append(out, ..body)
		put(out, "\nendobj\n")
	}
	{
		catalog := strings.builder_make(context.temp_allocator)
		strings.write_string(&catalog, "<< /Type /Catalog /Pages 2 0 R >>")
		object(&out, &offsets, 1, transmute([]u8)strings.to_string(catalog))
		object(&out, &offsets, 2, transmute([]u8)string("<< /Type /Pages /Kids [3 0 R] /Count 1 >>"))
		page := strings.builder_make(context.temp_allocator)
		strings.write_string(&page, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ")
		number(&page, p.width)
		strings.write_byte(&page, ' ')
		number(&page, p.height)
		strings.write_string(&page, "] /Contents 4 0 R /Group << /S /Transparency /CS /DeviceRGB >> /Resources <<")
		if len(p.gs_ids) > 0 {
			strings.write_string(&page, " /ExtGState <<")
			for id, i in p.gs_ids {
				write_resource(&page, "G", i + 1, id)
			}
			strings.write_string(&page, " >>")
		}
		if len(p.patterns) > 0 {
			strings.write_string(&page, " /Pattern <<")
			for id, i in p.patterns {
				write_resource(&page, "P", i + 1, id)
			}
			strings.write_string(&page, " >>")
		}
		if len(p.images) > 0 {
			strings.write_string(&page, " /XObject <<")
			for id, i in p.images {
				write_resource(&page, "I", i + 1, id)
			}
			strings.write_string(&page, " >>")
		}
		strings.write_string(&page, " >> >>")
		object(&out, &offsets, 3, transmute([]u8)strings.to_string(page))
	}
	object(&out, &offsets, content_id, content_body)
	for o in p.objects {
		object(&out, &offsets, o.id, o.body)
	}
	xref := len(out)
	put(&out, "xref\n0 ")
	put(&out, itoa(p.next_id))
	put(&out, "\n0000000000 65535 f \n")
	for id in 1 ..< p.next_id {
		put(&out, pad10(offsets[id] if id < len(offsets) else 0))
		put(&out, " 00000 n \n")
	}
	put(&out, "trailer\n<< /Size ")
	put(&out, itoa(p.next_id))
	put(&out, " /Root 1 0 R >>\nstartxref\n")
	put(&out, itoa(xref))
	put(&out, "\n%%EOF\n")

	notes := make([]string, len(p.left_out), allocator)
	copy(notes, p.left_out[:])
	return out[:], notes
}

@(private)
itoa :: proc(n: int) -> string {
	buf: [24]u8
	return strings.clone(strconv.write_int(buf[:], i64(n), 10), context.temp_allocator)
}

@(private = "file")
pad10 :: proc(n: int) -> string {
	digits := itoa(n)
	b := strings.builder_make(context.temp_allocator)
	for _ in len(digits) ..< 10 {
		strings.write_byte(&b, '0')
	}
	strings.write_string(&b, digits)
	return strings.to_string(b)
}

@(private = "file")
write_resource :: proc(b: ^strings.Builder, prefix: string, n, id: int) {
	strings.write_string(b, " /")
	strings.write_string(b, prefix)
	strings.write_string(b, itoa(n))
	strings.write_byte(b, ' ')
	strings.write_string(b, itoa(id))
	strings.write_string(b, " 0 R")
}

@(private = "file")
pdf_note :: proc(p: ^Pdf, what: string) {
	for existing in p.left_out {
		if existing == what {
			return
		}
	}
	append(&p.left_out, what)
}

// ---- objects ----

@(private = "file")
compress_stream :: proc(text: string) -> []u8 {
	return deflate.compress_zlib(transmute([]u8)text, context.temp_allocator)
}

@(private = "file")
compress_bytes :: proc(data: []u8) -> []u8 {
	return deflate.compress_zlib(data, context.temp_allocator)
}

// A stream object's body: its dictionary (`extra` is more entries) and the bytes, which are
// already deflated.
@(private = "file")
stream_object :: proc(extra: string, deflated: []u8) -> []u8 {
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, "<< ")
	strings.write_string(&b, extra)
	strings.write_string(&b, " /Filter /FlateDecode /Length ")
	strings.write_string(&b, itoa(len(deflated)))
	strings.write_string(&b, " >>\nstream\n")
	body := make([dynamic]u8, context.temp_allocator)
	append(&body, ..transmute([]u8)strings.to_string(b))
	append(&body, ..deflated)
	append(&body, ..transmute([]u8)string("\nendstream"))
	return body[:]
}

@(private = "file")
add_object :: proc(p: ^Pdf, body: []u8) -> int {
	id := p.next_id
	p.next_id += 1
	append(&p.objects, Pdf_Object{id, body})
	return id
}

@(private = "file")
add_text_object :: proc(p: ^Pdf, b: strings.Builder) -> int {
	return add_object(p, transmute([]u8)strings.to_string(b))
}

// ---- graphics state and colors ----

// The name of the graphics state with these opacities and blend.
@(private = "file")
graphics_state :: proc(p: ^Pdf, fill, stroke: f32, blend: Blend_Mode) -> int {
	key := Gs_Key{fill, stroke, blend}
	for existing, i in p.gs {
		if existing == key {
			return i + 1
		}
	}
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, "<< /Type /ExtGState /ca ")
	number(&b, fill, 4)
	strings.write_string(&b, " /CA ")
	number(&b, stroke, 4)
	switch blend {
	case .Normal, .Add, .Subtract:
	case .Multiply: strings.write_string(&b, " /BM /Multiply")
	case .Screen: strings.write_string(&b, " /BM /Screen")
	case .Lighten: strings.write_string(&b, " /BM /Lighten")
	}
	strings.write_string(&b, " >>")
	append(&p.gs, key)
	append(&p.gs_ids, add_text_object(p, b))
	return len(p.gs)
}

@(private = "file")
rgb :: proc(b: ^strings.Builder, c: maths.Colour) {
	for v in c.rgb {
		number(b, clamp(v, 0, 255) / 255, 4)
		strings.write_byte(b, ' ')
	}
}

// Sets the fill or the stroke paint (`stroke` says which): a color, or a gradient as a shading
// pattern for the box (the shape's own space) the gradient is laid on. `transform` is how the
// shape's space reaches the page, for the pattern's matrix.
@(private = "file")
set_paint :: proc(p: ^Pdf, stroke: bool, colour: maths.Colour, ref: Gradient_Ref, box: [4]f32, transform: Transform, picture, shader: bool) {
	c := &p.content
	if ref.id != 0 && int(ref.id) <= len(p.list.gradients) {
		if id := gradient_pattern(p, p.list.gradients[ref.id - 1], box, transform); id != 0 {
			strings.write_string(c, "/Pattern ")
			strings.write_string(c, "CS " if stroke else "cs ")
			strings.write_string(c, "/P")
			strings.write_string(c, itoa(id))
			strings.write_string(c, " SCN\n" if stroke else " scn\n")
			return
		}
		pdf_note(p, "a conic gradient")
		g := p.list.gradients[ref.id - 1]
		rgb(c, gradient_colour_at(g, 50))
		strings.write_string(c, "RG\n" if stroke else "rg\n")
		return
	}
	if picture && !stroke {
		pdf_note(p, "a picture fill")
	}
	if picture && stroke {
		pdf_note(p, "a picture fill")
	}
	if shader {
		pdf_note(p, "a shader fill")
	}
	rgb(c, colour)
	strings.write_string(c, "RG\n" if stroke else "rg\n")
}

// A gradient as a shading pattern, its number (from 1), or 0 for a conic one, which PDF has
// no shading for.
@(private = "file")
gradient_pattern :: proc(p: ^Pdf, g: Gradient, box: [4]f32, transform: Transform) -> int {
	if g.kind == .Conic {
		return 0
	}
	x, y, w, h := box[0], box[1], max(box[2], 1e-4), max(box[3], 1e-4)
	// the colors along the way, sampled from the ramp the GPU reads (Oklab mixing kept)
	STOPS :: 33
	samples := make([]u8, STOPS * 3, context.temp_allocator)
	transparent := false
	for i in 0 ..< STOPS {
		c := gradient_colour_at(g, f32(i) / (STOPS - 1) * 100)
		samples[i * 3] = u8(math.round(clamp(c.r, 0, 255)))
		samples[i * 3 + 1] = u8(math.round(clamp(c.g, 0, 255)))
		samples[i * 3 + 2] = u8(math.round(clamp(c.b, 0, 255)))
		transparent ||= c.a < 255
	}
	if transparent {
		pdf_note(p, "transparency inside a gradient")
	}
	function := add_object(p, stream_object("/FunctionType 0 /Domain [0 1] /Range [0 1 0 1 0 1] /Size [33] /BitsPerSample 8", compress_bytes(samples)))
	page := Transform{1, 0, 0, -1, 0, p.height}
	to_page := transform_mul(page, transform)
	b := strings.builder_make(context.temp_allocator)
	function_ref := strings.concatenate({itoa(function), " 0 R"}, context.temp_allocator)
	switch g.kind {
	case .Linear:
		turns := math.to_radians(f64(g.angle))
		dx, dy := f32(math.cos(turns)), f32(math.sin(turns))
		extent := abs(w * dx) + abs(h * dy)
		cx, cy := x + w / 2, y + h / 2
		strings.write_string(&b, "<< /Type /Pattern /PatternType 2 /Matrix ")
		write_matrix(&b, to_page)
		strings.write_string(&b, " /Shading << /ShadingType 2 /ColorSpace /DeviceRGB /Coords [")
		ends := [4]f32{cx - dx * extent / 2, cy - dy * extent / 2, cx + dx * extent / 2, cy + dy * extent / 2}
		for v, i in ends {
			if i > 0 {
				strings.write_byte(&b, ' ')
			}
			number(&b, v)
		}
	case .Radial:
		// a circle of radius 1 in a space stretched over the box, so it reaches the box's edge
		// on each side, from the gradient's centre
		cx, cy := x + w * g.centre.x / 100, y + h * g.centre.y / 100
		stretched := transform_mul(to_page, Transform{w / 2, 0, 0, h / 2, cx, cy})
		strings.write_string(&b, "<< /Type /Pattern /PatternType 2 /Matrix ")
		write_matrix(&b, stretched)
		strings.write_string(&b, " /Shading << /ShadingType 3 /ColorSpace /DeviceRGB /Coords [0 0 0 0 0 1")
	case .Conic:
	}
	strings.write_string(&b, "] /Function ")
	strings.write_string(&b, function_ref)
	strings.write_string(&b, " /Extend [true true] >> >>")
	append(&p.patterns, add_text_object(p, b))
	return len(p.patterns)
}

@(private = "file")
write_matrix :: proc(b: ^strings.Builder, t: Transform) {
	strings.write_byte(b, '[')
	values := [6]f32{t.a, t.b, t.c, t.d, t.e, t.f}
	for v, i in values {
		if i > 0 {
			strings.write_byte(b, ' ')
		}
		number(b, v, 5)
	}
	strings.write_byte(b, ']')
}

// ---- the page ----

@(private = "file")
pdf_background :: proc(p: ^Pdf) {
	list := p.list
	box := [4]f32{0, 0, p.width, p.height}
	c := &p.content
	if list.background_paint.id != 0 || list.background.a > 0 {
		strings.write_string(c, "q\n")
		if list.background.a < 255 && list.background_paint.id == 0 {
			gs := graphics_state(p, list.background.a / 255, 1, .Normal)
			write_gs(c, gs)
		}
		set_paint(p, false, list.background, list.background_paint, box, IDENTITY, false, false)
		write_rect(c, 0, 0, p.width, p.height)
		strings.write_string(c, "f\nQ\n")
	}
	if list.background_image.image != 0 {
		pdf_note(p, "the picture behind everything")
	}
}

@(private = "file")
write_gs :: proc(c: ^strings.Builder, n: int) {
	strings.write_string(c, "/G")
	strings.write_string(c, itoa(n))
	strings.write_string(c, " gs\n")
}

@(private = "file")
write_rect :: proc(c: ^strings.Builder, x, y, w, h: f32) {
	values := [4]f32{x, y, w, h}
	for v in values {
		number(c, v)
		strings.write_byte(c, ' ')
	}
	strings.write_string(c, "re\n")
}

@(private = "file")
write_cm :: proc(c: ^strings.Builder, t: Transform) {
	if t == IDENTITY {
		return
	}
	values := [6]f32{t.a, t.b, t.c, t.d, t.e, t.f}
	for v in values {
		number(c, v, 5)
		strings.write_byte(c, ' ')
	}
	strings.write_string(c, "cm\n")
}

@(private = "file")
pdf_command :: proc(p: ^Pdf, c: Command) {
	if !is_visible(c) {
		return
	}
	st := c.style
	out := &p.content
	strings.write_string(out, "q\n")
	if st.clip.on {
		write_rect(out, st.clip.rect[0], st.clip.rect[1], max(st.clip.rect[2] - st.clip.rect[0], 0), max(st.clip.rect[3] - st.clip.rect[1], 0))
		strings.write_string(out, "W n\n")
	}
	blend := st.blend
	switch blend {
	case .Add: pdf_note(p, "the add blend"); blend = .Normal
	case .Subtract: pdf_note(p, "the subtract blend"); blend = .Normal
	case .Normal, .Multiply, .Screen, .Lighten:
	}
	fill_opacity := st.alpha / 255
	stroke_opacity := st.alpha / 255
	if st.fill_paint.id == 0 {
		fill_opacity *= st.fill.a / 255
	}
	if st.stroke_paint.id == 0 {
		stroke_opacity *= st.stroke.a / 255
	}
	if c.kind == .Image {
		fill_opacity = st.tint.a / 255 * st.alpha / 255
	}
	if fill_opacity < 1 || stroke_opacity < 1 || blend != .Normal {
		write_gs(out, graphics_state(p, fill_opacity, stroke_opacity, blend))
	}
	pdf_shape(p, c)
	strings.write_string(out, "Q\n")
}

// Strokes and fills, by what the style has: the operator to end a path with.
@(private = "file")
paint_ops :: proc(p: ^Pdf, c: Command, box: [4]f32, closed_fill := true) -> (op: string) {
	st := c.style
	filled := st.fill_on && has_area(c)
	stroked := st.stroke_on && st.thickness > 0
	if filled {
		set_paint(p, false, st.fill, st.fill_paint, box, c.transform, st.fill_image.image != 0, st.fill_shader.shader != 0)
	}
	if stroked {
		set_paint(p, true, st.stroke, st.stroke_paint, box, c.transform, st.stroke_image.image != 0, false)
		out := &p.content
		number(out, st.thickness)
		strings.write_string(out, " w ")
		switch st.cap {
		case .Butt: strings.write_string(out, "0 J ")
		case .Round: strings.write_string(out, "1 J ")
		case .Square: strings.write_string(out, "2 J ")
		}
		switch st.join {
		case .Miter: strings.write_string(out, "0 j 4 M\n")
		case .Round: strings.write_string(out, "1 j\n")
		case .Bevel: strings.write_string(out, "2 j\n")
		}
	}
	switch {
	case filled && stroked: return "B"
	case filled: return "f"
	case stroked: return "S"
	}
	return "n"
}

// An ellipse as four cubic curves.
@(private = "file")
write_ellipse :: proc(c: ^strings.Builder, cx, cy, rx, ry: f32) {
	K :: f32(0.5522847498)
	pt :: proc(c: ^strings.Builder, x, y: f32) {
		number(c, x)
		strings.write_byte(c, ' ')
		number(c, y)
		strings.write_byte(c, ' ')
	}
	pt(c, cx + rx, cy)
	strings.write_string(c, "m\n")
	curves := [4][6]f32{
		{cx + rx, cy + ry * K, cx + rx * K, cy + ry, cx, cy + ry},
		{cx - rx * K, cy + ry, cx - rx, cy + ry * K, cx - rx, cy},
		{cx - rx, cy - ry * K, cx - rx * K, cy - ry, cx, cy - ry},
		{cx + rx * K, cy - ry, cx + rx, cy - ry * K, cx + rx, cy},
	}
	for curve in curves {
		pt(c, curve[0], curve[1])
		pt(c, curve[2], curve[3])
		pt(c, curve[4], curve[5])
		strings.write_string(c, "c\n")
	}
	strings.write_string(c, "h\n")
}

@(private = "file")
pdf_shape :: proc(p: ^Pdf, c: Command) {
	out := &p.content
	a := c.args
	lx, ly, lw, lh := local_bounds(c)
	box := [4]f32{lx, ly, lw, lh}
	switch c.kind {
	case .Circle, .Ellipse:
		op := paint_ops(p, c, box)
		write_cm(out, c.transform)
		write_ellipse(out, lx + lw / 2, ly + lh / 2, lw / 2, lh / 2)
		strings.write_string(out, op)
		strings.write_byte(out, '\n')
	case .Rect:
		op := paint_ops(p, c, box)
		write_cm(out, c.transform)
		write_rect(out, lx, ly, lw, lh)
		strings.write_string(out, op)
		strings.write_byte(out, '\n')
	case .Line:
		op := paint_ops(p, c, box)
		if op == "B" || op == "f" {
			op = "S"
		}
		write_cm(out, c.transform)
		write_points(out, {a[0], a[1], a[2], a[3]}, 2, false)
		strings.write_string(out, op)
		strings.write_byte(out, '\n')
	case .Point:
		// a dot: a circle of the stroke's color as wide as the stroke, or a square for square caps
		st := c.style
		set_paint(p, false, st.stroke, st.stroke_paint, box, c.transform, st.stroke_image.image != 0, false)
		write_cm(out, c.transform)
		r := st.thickness / 2
		if st.cap == .Square {
			write_rect(out, a[0] - r, a[1] - r, r * 2, r * 2)
		} else {
			write_ellipse(out, a[0], a[1], r, r)
		}
		strings.write_string(out, "f\n")
	case .Triangle, .Quad:
		op := paint_ops(p, c, box)
		write_cm(out, c.transform)
		corners := 3 if c.kind == .Triangle else 4
		write_points(out, a[:corners * 2], corners, true)
		strings.write_string(out, op)
		strings.write_byte(out, '\n')
	case .Arc:
		pdf_arc(p, c, box)
	case .Typeset:
		pdf_text(p, c, box)
	case .Text:
	case .Image:
		pdf_image(p, c)
	}
}

// A polygon or a line from its numbers, x then y for each point.
@(private = "file")
write_points :: proc(c: ^strings.Builder, xy: []f32, count: int, close: bool) {
	for i in 0 ..< count {
		number(c, xy[i * 2])
		strings.write_byte(c, ' ')
		number(c, xy[i * 2 + 1])
		strings.write_string(c, " m\n" if i == 0 else " l\n")
	}
	if close {
		strings.write_string(c, "h\n")
	}
}

// ---- arcs ----

// The cubic curves of an elliptical arc from `start` through `sweep` degrees, each at most a
// quarter turn, written from the arc's first point on with `m` or, when `join` is set, `l`.
@(private = "file")
write_arc_curves :: proc(c: ^strings.Builder, cx, cy, rx, ry: f32, start, sweep: f64, join: bool) {
	pt :: proc(c: ^strings.Builder, x, y: f32) {
		number(c, x)
		strings.write_byte(c, ' ')
		number(c, y)
		strings.write_byte(c, ' ')
	}
	pieces := max(int(math.ceil(abs(sweep) / 90)), 1)
	step := math.to_radians(sweep) / f64(pieces)
	angle := math.to_radians(start)
	k := f32(4.0 / 3.0 * math.tan(step / 4))
	for i in 0 ..< pieces {
		a0, a1 := angle, angle + step
		c0, s0, c1, s1 := f32(math.cos(a0)), f32(math.sin(a0)), f32(math.cos(a1)), f32(math.sin(a1))
		if i == 0 {
			pt(c, cx + rx * c0, cy + ry * s0)
			strings.write_string(c, "l\n" if join else "m\n")
		}
		pt(c, cx + rx * (c0 - k * s0), cy + ry * (s0 + k * c0))
		pt(c, cx + rx * (c1 + k * s1), cy + ry * (s1 - k * c1))
		pt(c, cx + rx * c1, cy + ry * s1)
		strings.write_string(c, "c\n")
		angle = a1
	}
}

@(private = "file")
pdf_arc :: proc(p: ^Pdf, c: Command, box: [4]f32) {
	out := &p.content
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
	sweep = min(sweep, 360)
	whole := sweep >= 360
	st := c.style
	filled := st.fill_on && has_area(c)
	stroked := st.stroke_on && st.thickness > 0
	if filled {
		// the pie, filled on its own, with no outline of its own
		strings.write_string(out, "q\n")
		set_paint(p, false, st.fill, st.fill_paint, box, c.transform, st.fill_image.image != 0, st.fill_shader.shader != 0)
		write_cm(out, c.transform)
		if !whole {
			number(out, cx)
			strings.write_byte(out, ' ')
			number(out, cy)
			strings.write_string(out, " m\n")
		}
		write_arc_curves(out, cx, cy, rx, ry, start, sweep, !whole)
		strings.write_string(out, "h f\nQ\n")
	}
	if stroked {
		// the curve alone, closed only when it goes all the way round
		set_paint(p, true, st.stroke, st.stroke_paint, box, c.transform, st.stroke_image.image != 0, false)
		number(out, st.thickness)
		strings.write_string(out, " w ")
		switch st.cap {
		case .Butt: strings.write_string(out, "0 J ")
		case .Round: strings.write_string(out, "1 J ")
		case .Square: strings.write_string(out, "2 J ")
		}
		switch st.join {
		case .Miter: strings.write_string(out, "0 j 4 M\n")
		case .Round: strings.write_string(out, "1 j\n")
		case .Bevel: strings.write_string(out, "2 j\n")
		}
		write_cm(out, c.transform)
		write_arc_curves(out, cx, cy, rx, ry, start, sweep, false)
		strings.write_string(out, "h S\n" if whole else "S\n")
	}
}

// ---- text ----

@(private = "file")
face_font :: proc(p: ^Pdf, face: u16) -> (Ttf, bool) {
	if f, found := p.fonts[face]; found {
		return f, true
	}
	if p.no_font[face] || int(face) >= len(fonts.faces) {
		return {}, false
	}
	f, ok := ttf_open(fonts.faces[face].data, fonts.faces[face].index)
	if !ok {
		p.no_font[face] = true
		return {}, false
	}
	p.fonts[face] = f
	return f, true
}

@(private = "file")
pdf_text :: proc(p: ^Pdf, c: Command, box: [4]f32) {
	out := &p.content
	a := c.args
	st := c.style
	offset, length := int(a[5]), int(a[6])
	if offset < 0 || offset + length > len(p.list.text) || !st.fill_on {
		return
	}
	font, ok := face_font(p, st.font)
	if !ok {
		pdf_note(p, "text in a font whose letters cannot be read")
		return
	}
	text := string(p.list.text[offset:offset + length])
	wrap := a[2]
	lines := text_lines(c, text, wrap)
	ascent, line_height := font_vertical(st)
	scale := st.font_size / f32(font.units)

	set_paint(p, false, st.fill, st.fill_paint, box, c.transform, st.fill_image.image != 0, st.fill_shader.shader != 0)
	write_cm(out, c.transform)
	outline := make([dynamic]Outline_Segment, context.temp_allocator)
	missing := false
	for line, row in lines {
		line_width := f32(ttf_text_width(font, line)) * scale
		// the text's point is where its lines are aligned to, as the renderer places it
		x := a[0]
		switch st.align {
		case .Left:
		case .Center: x -= line_width / 2
		case .Right: x -= line_width
		}
		baseline := a[1] + ascent + f32(row) * line_height
		pen := f32(0)
		for r in line {
			glyph := ttf_glyph(font, r)
			if glyph == 0 && r != ' ' {
				missing = true
			} else {
				clear(&outline)
				ttf_outline(font, glyph, &outline)
				write_glyph(out, outline[:], x + pen * scale, baseline, scale)
			}
			pen += f32(ttf_advance(font, glyph))
		}
	}
	if missing {
		pdf_note(p, "characters the font does not have")
	}
	strings.write_string(out, "f\n")
}

// A glyph's outline as path operators, with its origin at the pen and the size scaled down from
// font units (y up in the font, down on the page).
@(private = "file")
write_glyph :: proc(c: ^strings.Builder, outline: []Outline_Segment, x, baseline, scale: f32) {
	px :: proc(c: ^strings.Builder, ox, oy, scale, sx, sy: f32) {
		number(c, ox + sx * scale)
		strings.write_byte(c, ' ')
		number(c, oy - sy * scale)
		strings.write_byte(c, ' ')
	}
	cur_x, cur_y: f32 // in font units, where the pen is, for raising a quadratic curve to a cubic
	for s in outline {
		switch s.op {
		case .Move:
			px(c, x, baseline, scale, s.x, s.y)
			strings.write_string(c, "m\n")
			cur_x, cur_y = s.x, s.y
		case .Line:
			px(c, x, baseline, scale, s.x, s.y)
			strings.write_string(c, "l\n")
			cur_x, cur_y = s.x, s.y
		case .Quad:
			// a quadratic curve is the cubic whose control points are two thirds of the way to its one
			px(c, x, baseline, scale, cur_x + (s.cx - cur_x) * 2 / 3, cur_y + (s.cy - cur_y) * 2 / 3)
			px(c, x, baseline, scale, s.x + (s.cx - s.x) * 2 / 3, s.y + (s.cy - s.y) * 2 / 3)
			px(c, x, baseline, scale, s.x, s.y)
			strings.write_string(c, "c\n")
			cur_x, cur_y = s.x, s.y
		case .Close:
			strings.write_string(c, "h\n")
		}
	}
}

// ---- pictures ----

@(private = "file")
pdf_image :: proc(p: ^Pdf, c: Command) {
	out := &p.content
	id := Image_Id(c.args[4])
	data := image_data(id)
	if data == nil {
		return
	}
	if data.canvas != nil || data.pixels == nil {
		pdf_note(p, "a canvas shown with image")
		return
	}
	lx, ly, lw, lh := local_bounds(c)
	if lw <= 0 || lh <= 0 {
		return
	}
	if c.style.tint != (maths.Colour{255, 255, 255, 255}) {
		pdf_note(p, "a tint on a picture")
	}
	n, known := p.image_of[id]
	if !known {
		pixels := data.width * data.height
		rgb_bytes := make([]u8, pixels * 3, context.temp_allocator)
		alpha_bytes := make([]u8, pixels, context.temp_allocator)
		translucent := false
		for i in 0 ..< pixels {
			copy(rgb_bytes[i * 3:i * 3 + 3], data.pixels[i * 4:i * 4 + 3])
			alpha_bytes[i] = data.pixels[i * 4 + 3]
			translucent ||= alpha_bytes[i] != 255
		}
		size := strings.concatenate({"/Type /XObject /Subtype /Image /Width ", itoa(data.width), " /Height ", itoa(data.height), " /BitsPerComponent 8 /Interpolate true"}, context.temp_allocator)
		mask := 0
		if translucent {
			mask = add_object(p, stream_object(strings.concatenate({size, " /ColorSpace /DeviceGray"}, context.temp_allocator), compress_bytes(alpha_bytes)))
		}
		extra := strings.concatenate({size, " /ColorSpace /DeviceRGB"}, context.temp_allocator)
		if mask != 0 {
			extra = strings.concatenate({extra, " /SMask ", itoa(mask), " 0 R"}, context.temp_allocator)
		}
		append(&p.images, add_object(p, stream_object(extra, compress_bytes(rgb_bytes))))
		n = len(p.images)
		p.image_of[id] = n
	}
	write_cm(out, c.transform)
	// the picture is a unit square, its first row at the top: scaled into its box
	write_cm(out, Transform{lw, 0, 0, -lh, lx, ly + lh})
	strings.write_string(out, "/I")
	strings.write_string(out, itoa(n))
	strings.write_string(out, " Do\n")
}
