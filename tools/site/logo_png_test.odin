// SPDX-License-Identifier: 0BSD
#+feature dynamic-literals
package site_tool

import "core:image"
import "core:image/png"
import "core:math"
import "core:os"
import "core:testing"

// The logo's PNG pictures are drawn from its one drawing: when the drawing changes,
// `odin run tools/site -- --logo` writes them again. Compared pixel by pixel, a
// channel allowed one step off, so a computer whose last bit of a cosine differs
// does not fail.
@(test)
the_logo_pngs_are_drawn_from_the_logo :: proc(t: ^testing.T) {
	svg, ok := read(LOGO)
	testing.expect(t, ok)
	rgba, drew := logo_pixels(svg, LOGO_PNG_SIZE)
	testing.expect(t, drew)
	if !drew {
		return
	}
	for file in ([]struct {
			path:     string,
			pixels:   []u8,
			channels: int,
		}{{LOGO_PNG, rgba, 4}, {LOGO_PNG_WHITE, on_white(rgba), 3}}) {
		data, err := os.read_entire_file(file.path, context.temp_allocator)
		testing.expectf(t, err == nil, "%s is missing: run odin run tools/site -- --logo", file.path)
		if err != nil {
			continue
		}
		img, decode_err := png.load_from_bytes(data, allocator = context.temp_allocator)
		testing.expectf(t, decode_err == nil, "%s is not a PNG", file.path)
		if decode_err != nil {
			continue
		}
		defer image.destroy(img, context.temp_allocator)
		same := img.width == LOGO_PNG_SIZE && img.height == LOGO_PNG_SIZE && img.channels == file.channels && img.depth == 8 && len(img.pixels) == len(file.pixels)
		if same {
			for b, i in img.pixels {
				if abs(int(b) - int(file.pixels[i])) > 1 {
					same = false
					break
				}
			}
		}
		testing.expectf(t, same, "%s is out of date: run odin run tools/site -- --logo", file.path)
	}
}

@(test)
the_logo_is_drawn_in_the_middle_in_black_and_white :: proc(t: ^testing.T) {
	svg, _ := read(LOGO)
	rgba, drew := logo_pixels(svg, LOGO_PNG_SIZE)
	testing.expect(t, drew)
	if !drew {
		return
	}
	pixel :: proc(rgba: []u8, x, y: int) -> [4]u8 {
		o := (y * LOGO_PNG_SIZE + x) * 4
		return {rgba[o], rgba[o + 1], rgba[o + 2], rgba[o + 3]}
	}
	// Nothing in the corners, the margin left empty, the asterisk's middle white, the dot black.
	testing.expect_value(t, pixel(rgba, 0, 0).a, 0)
	testing.expect_value(t, pixel(rgba, LOGO_PNG_SIZE - 1, LOGO_PNG_SIZE - 1).a, 0)
	for i in 0 ..< LOGO_PNG_SIZE {
		testing.expect(t, pixel(rgba, i, 0).a == 0 && pixel(rgba, 0, i).a == 0 && pixel(rgba, LOGO_PNG_SIZE - 1, i).a == 0)
	}
	// The dot's centre: (1500 - 558, 622) in the drawing's units.
	scale := f64(LOGO_PNG_SIZE - 2 * LOGO_PNG_MARGIN) / 1480
	cx := int(f64(LOGO_PNG_SIZE) / 2 + (942 - 750) * scale)
	cy := int(f64(LOGO_PNG_SIZE) / 2 + (622 - 630) * scale)
	testing.expect_value(t, pixel(rgba, cx, cy), [4]u8{255, 255, 255, 255})
	// Past the end of the asterisk's arm (230 units) and inside the dot (365).
	testing.expect_value(t, pixel(rgba, cx + int(290 * scale), cy), [4]u8{0, 0, 0, 255})
	white := on_white(rgba)
	testing.expect(t, white[0] == 255 && white[1] == 255 && white[2] == 255)
}

@(test)
nonzero_filling_covers_shapes_and_leaves_holes :: proc(t: ^testing.T) {
	n := 4 * LOGO_SAMPLES
	painted := make([]u8, n * n, context.temp_allocator)
	count :: proc(painted: []u8, mark: u8) -> (c: int) {
		for p in painted {
			c += int(p == mark)
		}
		return
	}
	// A square of two pixels, then one of the same winding over half of it: one union.
	a := []Point{{0, 0}, {2, 0}, {2, 2}, {0, 2}}
	b := []Point{{1, 0}, {3, 0}, {3, 2}, {1, 2}}
	fill_nonzero(painted, n, {a, b}, 1)
	testing.expect_value(t, count(painted, 1), 6 * LOGO_SAMPLES * LOGO_SAMPLES)
	// The other way round inside it is a hole; a later shape paints over an earlier one.
	outer := []Point{{0, 0}, {4, 0}, {4, 4}, {0, 4}}
	hole := []Point{{1, 1}, {1, 3}, {3, 3}, {3, 1}}
	fill_nonzero(painted, n, {outer, hole}, 2)
	testing.expect_value(t, count(painted, 2), 12 * LOGO_SAMPLES * LOGO_SAMPLES)
	testing.expect_value(t, count(painted, 1), 2 * LOGO_SAMPLES * LOGO_SAMPLES)
	// Outside the picture nothing is painted, and nothing breaks.
	fill_nonzero(painted, n, {[]Point{{-5, -5}, {-1, -5}, {-1, -1}}}, 3)
	fill_nonzero(painted, n, {[]Point{{-1, -1}, {9, -1}, {9, 9}, {-1, 9}}}, 4)
	testing.expect_value(t, count(painted, 3), 0)
	testing.expect_value(t, count(painted, 4), n * n)
	fill_nonzero(painted, n, {}, 5)
	testing.expect_value(t, count(painted, 5), 0)
}

@(test)
laying_over_white_mixes_by_alpha :: proc(t: ^testing.T) {
	rgb := on_white([]u8{0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 0, 128, 255, 0, 0, 255})
	testing.expect_value(t, len(rgb), 12)
	testing.expect(t, rgb[0] == 255 && rgb[1] == 255 && rgb[2] == 255, "clear is white")
	testing.expect(t, rgb[3] == 0 && rgb[4] == 0 && rgb[5] == 0, "solid black stays")
	testing.expect(t, rgb[6] == 127 && rgb[7] == 127, "half black is grey")
	testing.expect(t, rgb[9] == 255 && rgb[10] == 0 && rgb[11] == 0, "solid red stays")
}

@(test)
transforms_read_translate_and_scale :: proc(t: ^testing.T) {
	m, ok := svg_transform("translate(1500 0) scale(-1 1)")
	testing.expect(t, ok)
	testing.expect_value(t, affine_apply(m, {558, 622}), Point{942, 622})
	m, ok = svg_transform("translate(3,4)")
	testing.expect(t, ok && affine_apply(m, {1, 1}) == Point{4, 5})
	m, ok = svg_transform("translate(3) scale(2)")
	testing.expect(t, ok && affine_apply(m, {1, 1}) == Point{5, 2})
	m, ok = svg_transform("")
	testing.expect(t, ok && m == AFFINE_IDENTITY)
	_, ok = svg_transform("rotate(45)")
	testing.expect(t, !ok)
	_, ok = svg_transform("translate(1 2 3)")
	testing.expect(t, !ok)
	_, ok = svg_transform("scale(2")
	testing.expect(t, !ok)
	_, ok = svg_transform("scale(x)")
	testing.expect(t, !ok)
}

@(test)
paints_are_colours_or_none :: proc(t: ^testing.T) {
	attrs := map[string]string{"fill" = "#abc", "stroke" = "#102030", "a" = "none", "b" = "white", "c" = "black", "d" = "#12", "e" = "red", "f" = "#zzzzzz"}
	defer delete(attrs)
	c, painted, ok := svg_paint(attrs, "fill", "none")
	testing.expect(t, ok && painted && c == [3]u8{0xaa, 0xbb, 0xcc})
	c, painted, ok = svg_paint(attrs, "stroke", "none")
	testing.expect(t, ok && painted && c == [3]u8{0x10, 0x20, 0x30})
	_, painted, ok = svg_paint(attrs, "a", "#000")
	testing.expect(t, ok && !painted)
	c, painted, ok = svg_paint(attrs, "b", "none")
	testing.expect(t, ok && painted && c == [3]u8{255, 255, 255})
	c, painted, ok = svg_paint(attrs, "c", "none")
	testing.expect(t, ok && painted && c == [3]u8{})
	c, painted, ok = svg_paint(attrs, "missing", "#000")
	testing.expect(t, ok && painted && c == [3]u8{}, "a path is black when it says nothing")
	_, painted, ok = svg_paint(attrs, "missing", "none")
	testing.expect(t, ok && !painted, "and has no outline")
	for key in ([]string{"d", "e", "f"}) {
		_, _, ok = svg_paint(attrs, key, "none")
		testing.expectf(t, !ok, "%s", key)
	}
}

@(test)
arcs_follow_the_svg_rules :: proc(t: ^testing.T) {
	on_circle :: proc(points: []Point, centre: Point, r: f64) -> bool {
		for p in points {
			d := p - centre
			if abs(math.sqrt(d.x * d.x + d.y * d.y) - r) > 1e-9 {
				return false
			}
		}
		return true
	}
	// A half circle from (0, 0) to (2, 0): the sweep says which side it goes round.
	down := make([dynamic]Point, context.temp_allocator)
	arc_flatten(&down, {0, 0}, {2, 0}, 1, 1, 0, false, true, 0.01)
	testing.expect(t, len(down) > 10 && on_circle(down[:], {1, 0}, 1))
	testing.expect_value(t, down[len(down) - 1], Point{2, 0})
	testing.expect(t, down[len(down) / 2].y < 0, "clockwise on the screen goes up first")
	up := make([dynamic]Point, context.temp_allocator)
	arc_flatten(&up, {0, 0}, {2, 0}, 1, 1, 0, false, false, 0.01)
	testing.expect(t, up[len(up) / 2].y > 0)
	// Radii too small to reach are grown until they do.
	grown := make([dynamic]Point, context.temp_allocator)
	arc_flatten(&grown, {0, 0}, {2, 0}, 0.25, 0.25, 0, false, true, 0.01)
	testing.expect(t, on_circle(grown[:], {1, 0}, 1))
	// The large arc of a circle bigger than the gap goes the long way round.
	small, large := make([dynamic]Point, context.temp_allocator), make([dynamic]Point, context.temp_allocator)
	arc_flatten(&small, {0, 0}, {2, 0}, 2, 2, 0, false, true, 0.01)
	arc_flatten(&large, {0, 0}, {2, 0}, 2, 2, 0, true, true, 0.01)
	testing.expect(t, len(large) > 3 * len(small))
	testing.expect(t, on_circle(small[:], {1, math.sqrt(3.0)}, 2) && on_circle(large[:], {1, -math.sqrt(3.0)}, 2))
	// A turned ellipse still ends where it is told.
	turned := make([dynamic]Point, context.temp_allocator)
	arc_flatten(&turned, {0, 0}, {3, 1}, 3, 1, 30, false, true, 0.01)
	testing.expect_value(t, turned[len(turned) - 1], Point{3, 1})
	// A zero radius is a straight line; an arc to where it is draws nothing.
	line := make([dynamic]Point, context.temp_allocator)
	arc_flatten(&line, {0, 0}, {2, 0}, 0, 1, 0, false, true, 0.01)
	testing.expect(t, len(line) == 1 && line[0] == Point{2, 0})
	arc_flatten(&line, {2, 0}, {2, 0}, 1, 1, 0, false, true, 0.01)
	testing.expect_value(t, len(line), 1)
}

@(test)
paths_read_moves_lines_arcs_and_closes :: proc(t: ^testing.T) {
	subpaths, ok := svg_path("M 0 0 L 10 0 10,10 Z M -5 -5 L -1 -1", 0.1)
	testing.expect(t, ok)
	testing.expect_value(t, len(subpaths), 2)
	if len(subpaths) == 2 {
		testing.expect(t, subpaths[0].closed && len(subpaths[0].points) == 3 && subpaths[0].points[2] == Point{10, 10})
		testing.expect(t, !subpaths[1].closed && subpaths[1].points[0] == Point{-5, -5})
	}
	// More pairs after a move are lines; an arc ends at its point.
	subpaths, ok = svg_path("M0 0 5 0 A 5 5 0 0 1 5 10", 0.1)
	testing.expect(t, ok && len(subpaths) == 1)
	if len(subpaths) == 1 {
		testing.expect_value(t, subpaths[0].points[1], Point{5, 0})
		testing.expect_value(t, subpaths[0].points[len(subpaths[0].points) - 1], Point{5, 10})
	}
	// A lone point is no outline.
	subpaths, ok = svg_path("M 1 1", 0.1)
	testing.expect(t, ok && len(subpaths) == 0)
	for bad in ([]string{"m 0 0 l 1 1", "M 0 0 C 1 1 2 2 3 3", "0 0 L 1 1", "M 0", "M 0 0 A 1 1 0 0 1", "M 1e3 0"}) {
		_, ok = svg_path(bad, 0.1)
		testing.expectf(t, !ok, "%q", bad)
	}
}

@(test)
the_svg_reader_says_what_it_cannot_draw :: proc(t: ^testing.T) {
	good := `<?xml version="1.0"?><!-- a square --><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><title>t</title><g transform="translate(1 1)"><path d="M 0 0 L 8 0 L 8 8 Z"/><g/></g><circle cx="5" cy="5" r="2" fill="#fff" stroke="#000" stroke-width="1" stroke-linejoin="round" stroke-linecap="round"/><circle r="0"/></svg>`
	shapes, ok := logo_shapes(good, 20)
	testing.expect(t, ok)
	testing.expect_value(t, len(shapes), 3)
	if len(shapes) == 3 {
		testing.expect_value(t, shapes[0].colour, [3]u8{})
		// The group's translate and the fit to 20 pixels with a margin of 4: 1.2 a unit.
		testing.expect_value(t, shapes[0].contours[0][0], Point{4 + 1.2, 4 + 1.2})
		testing.expect_value(t, shapes[1].colour, [3]u8{255, 255, 255})
		testing.expect(t, len(shapes[2].contours) > 10, "the outline is triangles")
	}
	for bad in ([]string{
		`<path d="M 0 0 L 1 1"/>`,
		`<svg viewBox="0 0 10"><path d="M 0 0 L 1 1"/></svg>`,
		`<svg viewBox="0 0 10 10"><rect width="1" height="1"/></svg>`,
		`<svg viewBox="0 0 10 10"></g></svg>`,
		`<svg viewBox="0 0 10 10"><path d="M 0 0 L 1 1"`,
		`<svg viewBox="0 0 10 10"><path d="M 0 0 L 1 1" fill="red"/></svg>`,
		`<svg viewBox="0 0 10 10"><path d="M 0 0 L 1 1" fill="none" stroke="#000" stroke-linejoin="arcs"/></svg>`,
		`<svg viewBox="0 0 10 10"><path d="M 0 0 L 1 1" fill="none" stroke="#000" stroke-linecap="pointed"/></svg>`,
		`<svg viewBox="0 0 10 10"><path d="M 0 0 L 1 1" fill="none" stroke="#000" stroke-width="thin"/></svg>`,
		`<svg viewBox="0 0 10 10"><circle cx="a" r="1"/></svg>`,
		`<svg viewBox="0 0 10 10"><g transform="skewX(10)"></g></svg>`,
		`no drawing at all`,
	}) {
		_, ok = logo_shapes(bad, 20)
		testing.expectf(t, !ok, "%q", bad)
	}
}

@(test)
tags_give_their_name_and_attributes :: proc(t: ^testing.T) {
	name, attrs := svg_tag(`circle cx="1" r='2' broken="3`)
	testing.expect_value(t, name, "circle")
	testing.expect(t, attrs["cx"] == "1" && attrs["r"] == "2" && len(attrs) == 2)
	name, attrs = svg_tag(`g`)
	testing.expect(t, name == "g" && len(attrs) == 0)
	name, attrs = svg_tag(`path d=x`)
	testing.expect(t, name == "path" && len(attrs) == 0)
}
