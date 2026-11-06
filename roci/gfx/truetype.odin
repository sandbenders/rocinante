// SPDX-License-Identifier: 0BSD
//
// The outlines of a TrueType font's glyphs, read straight from the font file's tables, so a
// vector file (pdf.odin) can draw text as shapes and need no font to be installed where it
// is read. Only what that takes: the character map (formats 4 and 12), the advance widths,
// and the `glyf` outlines (simple and composite glyphs). Fonts whose outlines are in a
// `CFF` table (many `.otf` files) are not read; neither are kerning or shaping, so a text
// in a PDF can differ from the screen by a pixel of spacing between some letter pairs.
package gfx

Ttf :: struct {
	data:       []u8,
	units:      int, // font units to the em
	glyphs:     int,
	loca_long:  bool,
	loca:       int, // offsets of the tables, from the start of the data
	glyf:       int,
	hmtx:       int,
	hmetrics:   int, // how many advance widths the `hmtx` table holds
	cmap:       int, // the subtable chosen, 0 for none
	cmap_kind:  int, // its format, 4 or 12
}

// One piece of an outline, in font units with y up. A contour starts with a `Move`, goes
// on with lines and quadratic curves (`Quad`: a control point and an end point) and ends with
// a `Close`.
Outline_Op :: enum u8 {
	Move,
	Line,
	Quad,
	Close,
}

Outline_Segment :: struct {
	op:   Outline_Op,
	x, y: f32, // the point (the end point of a curve)
	cx, cy: f32, // the control point of a `Quad`
}

@(private = "file")
u16_at :: proc(d: []u8, at: int) -> int {
	if at < 0 || at + 2 > len(d) {
		return 0
	}
	return int(d[at]) << 8 | int(d[at + 1])
}

@(private = "file")
i16_at :: proc(d: []u8, at: int) -> int {
	v := u16_at(d, at)
	return v - 0x10000 if v >= 0x8000 else v
}

@(private = "file")
u32_at :: proc(d: []u8, at: int) -> int {
	return u16_at(d, at) << 16 | u16_at(d, at + 2)
}

// Reads the tables of a font file's bytes (the first font of a collection). False for a font
// with no TrueType outlines or a file that is not one. The bytes are kept, not copied.
ttf_open :: proc(data: []u8) -> (f: Ttf, ok: bool) {
	if len(data) < 12 {
		return
	}
	base := 0
	if string(data[:4]) == "ttcf" {
		base = u32_at(data, 12)
	}
	tag := u32_at(data, base)
	if tag != 0x00010000 && string(data[base:base + 4]) != "true" {
		return // CFF fonts begin with "OTTO"
	}
	tables := u16_at(data, base + 4)
	head, maxp, hhea: int
	for i in 0 ..< tables {
		record := base + 12 + i * 16
		if record + 16 > len(data) {
			return
		}
		offset := u32_at(data, record + 8)
		switch string(data[record:record + 4]) {
		case "head": head = offset
		case "maxp": maxp = offset
		case "hhea": hhea = offset
		case "hmtx": f.hmtx = offset
		case "loca": f.loca = offset
		case "glyf": f.glyf = offset
		case "cmap": f.cmap = offset
		}
	}
	if head == 0 || maxp == 0 || hhea == 0 || f.hmtx == 0 || f.loca == 0 || f.glyf == 0 || f.cmap == 0 {
		return
	}
	f.data = data
	f.units = u16_at(data, head + 18)
	f.loca_long = i16_at(data, head + 50) != 0
	f.glyphs = u16_at(data, maxp + 4)
	f.hmetrics = u16_at(data, hhea + 34)
	if f.units <= 0 || f.glyphs <= 0 || f.hmetrics <= 0 {
		return {}, false
	}
	// the best character map: all of Unicode (3, 10), then the basic plane (3, 1 and Unicode's own)
	cmap := f.cmap
	f.cmap = 0
	count := u16_at(data, cmap + 2)
	best := -1
	for i in 0 ..< count {
		record := cmap + 4 + i * 8
		platform, encoding, offset := u16_at(data, record), u16_at(data, record + 2), cmap + u32_at(data, record + 4)
		kind := u16_at(data, offset)
		score := -1
		switch {
		case platform == 3 && encoding == 10 && kind == 12: score = 4
		case platform == 0 && kind == 12: score = 3
		case platform == 3 && encoding == 1 && kind == 4: score = 2
		case platform == 0 && kind == 4: score = 1
		}
		if score > best {
			best, f.cmap, f.cmap_kind = score, offset, kind
		}
	}
	if f.cmap == 0 {
		return {}, false
	}
	return f, true
}

// The glyph of a character, 0 (the font's "missing" box) when it has none.
ttf_glyph :: proc(f: Ttf, r: rune) -> int {
	d := f.data
	c := int(r)
	switch f.cmap_kind {
	case 4:
		if c > 0xFFFF {
			return 0
		}
		segments := u16_at(d, f.cmap + 6) / 2
		ends := f.cmap + 14
		starts := ends + segments * 2 + 2
		deltas := starts + segments * 2
		ranges := deltas + segments * 2
		for i in 0 ..< segments {
			end := u16_at(d, ends + i * 2)
			if c > end {
				continue
			}
			start := u16_at(d, starts + i * 2)
			if c < start {
				return 0
			}
			delta := u16_at(d, deltas + i * 2)
			offset := u16_at(d, ranges + i * 2)
			if offset == 0 {
				return (c + delta) & 0xFFFF
			}
			g := u16_at(d, ranges + i * 2 + offset + (c - start) * 2)
			return 0 if g == 0 else (g + delta) & 0xFFFF
		}
	case 12:
		groups := u32_at(d, f.cmap + 12)
		lo, hi := 0, groups - 1
		for lo <= hi {
			mid := (lo + hi) / 2
			at := f.cmap + 16 + mid * 12
			start, end := u32_at(d, at), u32_at(d, at + 4)
			switch {
			case c < start: hi = mid - 1
			case c > end: lo = mid + 1
			case: return u32_at(d, at + 8) + c - start
			}
		}
	}
	return 0
}

// How far the pen moves after a glyph, in font units.
ttf_advance :: proc(f: Ttf, glyph: int) -> int {
	i := min(max(glyph, 0), f.hmetrics - 1)
	return u16_at(f.data, f.hmtx + i * 4)
}

// The bytes of a glyph's description, empty for a glyph with no outline (a space).
@(private = "file")
glyph_bytes :: proc(f: Ttf, glyph: int) -> []u8 {
	if glyph < 0 || glyph >= f.glyphs {
		return nil
	}
	a, b: int
	if f.loca_long {
		a, b = u32_at(f.data, f.loca + glyph * 4), u32_at(f.data, f.loca + glyph * 4 + 4)
	} else {
		a, b = u16_at(f.data, f.loca + glyph * 2) * 2, u16_at(f.data, f.loca + glyph * 2 + 2) * 2
	}
	start, end := f.glyf + a, f.glyf + b
	if b <= a || start < 0 || end > len(f.data) {
		return nil
	}
	return f.data[start:end]
}

// A glyph's outline as segments, appended to `out`, moved by `dx`, `dy` and carried through
// the 2 by 2 matrix `m` (a, b, c, d: x' = a x + c y, y' = b x + d y) when it is part of a
// composite glyph.
ttf_outline :: proc(f: Ttf, glyph: int, out: ^[dynamic]Outline_Segment, depth := 0) {
	ttf_outline_into(f, glyph, out, {1, 0, 0, 1}, 0, 0, depth)
}

@(private = "file")
ttf_outline_into :: proc(f: Ttf, glyph: int, out: ^[dynamic]Outline_Segment, m: [4]f32, dx, dy: f32, depth: int) {
	d := glyph_bytes(f, glyph)
	if len(d) < 10 || depth > 6 {
		return
	}
	contours := i16_at(d, 0)
	if contours < 0 {
		composite(f, d, out, m, dx, dy, depth)
		return
	}
	if contours == 0 {
		return
	}
	end_points := make([]int, contours, context.temp_allocator)
	for i in 0 ..< contours {
		end_points[i] = u16_at(d, 10 + i * 2)
	}
	points := end_points[contours - 1] + 1
	at := 10 + contours * 2
	at += 2 + u16_at(d, at) // the instructions
	if points <= 0 || at > len(d) {
		return
	}
	flags := make([]u8, points, context.temp_allocator)
	for i := 0; i < points; {
		if at >= len(d) {
			return
		}
		flag := d[at]
		at += 1
		flags[i] = flag
		i += 1
		if flag & 8 != 0 {
			if at >= len(d) {
				return
			}
			repeat := int(d[at])
			at += 1
			for _ in 0 ..< repeat {
				if i < points {
					flags[i] = flag
					i += 1
				}
			}
		}
	}
	xs := make([]f32, points, context.temp_allocator)
	ys := make([]f32, points, context.temp_allocator)
	// x then y, each a one byte or two byte change, or none when the flag says it repeats
	for axis in 0 ..< 2 {
		short_bit, same_bit := u8(2 if axis == 0 else 4), u8(0x10 if axis == 0 else 0x20)
		value := 0
		for i in 0 ..< points {
			flag := flags[i]
			switch {
			case flag & short_bit != 0:
				if at >= len(d) {
					return
				}
				step := int(d[at])
				at += 1
				value += step if flag & same_bit != 0 else -step
			case flag & same_bit == 0:
				if at + 2 > len(d) {
					return
				}
				value += i16_at(d, at)
				at += 2
			}
			if axis == 0 {
				xs[i] = f32(value)
			} else {
				ys[i] = f32(value)
			}
		}
	}
	first := 0
	for end in end_points {
		if end < first || end >= points {
			return
		}
		contour(out, xs[first:end + 1], ys[first:end + 1], flags[first:end + 1], m, dx, dy)
		first = end + 1
	}
}

// One closed curve of on-curve and off-curve points. Two off-curve points in a row have an
// on-curve point halfway between them that the file leaves out.
@(private = "file")
contour :: proc(out: ^[dynamic]Outline_Segment, xs, ys: []f32, flags: []u8, m: [4]f32, dx, dy: f32) {
	n := len(xs)
	if n < 2 {
		return
	}
	place :: proc(m: [4]f32, dx, dy, x, y: f32) -> (f32, f32) {
		return m[0] * x + m[2] * y + dx, m[1] * x + m[3] * y + dy
	}
	on :: proc(flags: []u8, i: int) -> bool {
		return flags[i] & 1 != 0
	}
	// where the contour starts: a point on the curve, or the middle of two off it
	start_x, start_y: f32
	begin: int
	switch {
	case on(flags, 0):
		start_x, start_y = xs[0], ys[0]
		begin = 1
	case on(flags, n - 1):
		start_x, start_y = xs[n - 1], ys[n - 1]
		begin = 0
	case:
		start_x, start_y = (xs[0] + xs[n - 1]) / 2, (ys[0] + ys[n - 1]) / 2
		begin = 0
	}
	px, py := place(m, dx, dy, start_x, start_y)
	append(out, Outline_Segment{op = .Move, x = px, y = py})
	// the points after the start, round to the start again
	pending := false
	pending_x, pending_y: f32
	count := n - 1
	if !on(flags, 0) && !on(flags, n - 1) {
		count = n
	}
	for k in 0 ..< count {
		i := (begin + k) % n
		x, y := xs[i], ys[i]
		if on(flags, i) {
			if pending {
				cx, cy := place(m, dx, dy, pending_x, pending_y)
				ex, ey := place(m, dx, dy, x, y)
				append(out, Outline_Segment{op = .Quad, x = ex, y = ey, cx = cx, cy = cy})
				pending = false
			} else {
				ex, ey := place(m, dx, dy, x, y)
				append(out, Outline_Segment{op = .Line, x = ex, y = ey})
			}
		} else {
			if pending {
				mid_x, mid_y := (pending_x + x) / 2, (pending_y + y) / 2
				cx, cy := place(m, dx, dy, pending_x, pending_y)
				ex, ey := place(m, dx, dy, mid_x, mid_y)
				append(out, Outline_Segment{op = .Quad, x = ex, y = ey, cx = cx, cy = cy})
			}
			pending, pending_x, pending_y = true, x, y
		}
	}
	if pending {
		cx, cy := place(m, dx, dy, pending_x, pending_y)
		append(out, Outline_Segment{op = .Quad, x = px, y = py, cx = cx, cy = cy})
	}
	append(out, Outline_Segment{op = .Close})
}

@(private = "file")
composite :: proc(f: Ttf, d: []u8, out: ^[dynamic]Outline_Segment, m: [4]f32, dx, dy: f32, depth: int) {
	at := 10
	for {
		if at + 4 > len(d) {
			return
		}
		flags := u16_at(d, at)
		part := u16_at(d, at + 2)
		at += 4
		ox, oy: f32
		if flags & 1 != 0 { // the arguments are words
			if flags & 2 != 0 {
				ox, oy = f32(i16_at(d, at)), f32(i16_at(d, at + 2))
			}
			at += 4
		} else {
			if flags & 2 != 0 {
				ox, oy = f32(i8(d[at])), f32(i8(d[at + 1]))
			}
			at += 2
		}
		two :: proc(d: []u8, at: int) -> f32 {
			return f32(i16_at(d, at)) / 16384
		}
		a, b, c, e: f32 = 1, 0, 0, 1
		switch {
		case flags & 0x08 != 0:
			a = two(d, at)
			e = a
			at += 2
		case flags & 0x40 != 0:
			a, e = two(d, at), two(d, at + 2)
			at += 4
		case flags & 0x80 != 0:
			a, b, c, e = two(d, at), two(d, at + 2), two(d, at + 4), two(d, at + 6)
			at += 8
		}
		// the part's matrix first, then the one it is inside
		inner := [4]f32{a, b, c, e}
		combined := [4]f32{
			m[0] * inner[0] + m[2] * inner[1], m[1] * inner[0] + m[3] * inner[1],
			m[0] * inner[2] + m[2] * inner[3], m[1] * inner[2] + m[3] * inner[3],
		}
		px := m[0] * ox + m[2] * oy + dx
		py := m[1] * ox + m[3] * oy + dy
		ttf_outline_into(f, part, out, combined, px, py, depth + 1)
		if flags & 0x20 == 0 {
			return
		}
	}
}

// The length of a text's advance, in font units, for the characters it has glyphs for.
ttf_text_width :: proc(f: Ttf, text: string) -> int {
	total := 0
	for r in text {
		total += ttf_advance(f, ttf_glyph(f, r))
	}
	return total
}
