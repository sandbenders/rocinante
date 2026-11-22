// SPDX-License-Identifier: 0BSD
package gfx

import "../maths"
import "core:strings"
import "core:testing"

// A placed gradient as the GPU reads it back: each number through the 16-bit halves of its row.
@(private = "file")
as_the_gpu_reads :: proc(g: Gradient) -> Gradient {
	params := gradient_params(g)
	read := g
	for i in 0 ..< 3 {
		for j in 0 ..< 2 {
			high, low := f32(f16(params[1 + i][j * 2])), f32(f16(params[1 + i][j * 2 + 1]))
			read.place[i * 2 + j] = high + low
		}
	}
	read.focus = {f32(f16(params[0][2])), f32(f16(params[0][3]))}
	return read
}

// Compares where the GPU's gradient is with where the picture renderer's is, over a grid on the item's box.
@(private = "file")
expect_same_as_the_picture_renderer :: proc(t: ^testing.T, text: string, loc := #caller_location) {
	d, err := read(text)
	defer svg_destroy(&d)
	if !testing.expect_value(t, err, Svg_Error.None, loc = loc) || !testing.expect(t, len(d.items) > 0, loc = loc) {
		return
	}
	item := d.items[0]
	lo, hi := bounds_of(item)
	box := [4]f32{lo.x, lo.y, hi.x - lo.x, hi.y - lo.y}
	g, ok := svg_gpu_gradient(&d, item.fill_gradient, 1, box)
	if !testing.expect(t, ok, "the gradient is placed", loc = loc) {
		return
	}
	read := as_the_gpu_reads(g)
	sg := d.gradients[item.fill_gradient]
	half := [2]f32{box[2] / 2, box[3] / 2}
	worst := f32(0)
	for j in 0 ..= 20 {
		for i in 0 ..= 20 {
			p := [2]f32{half.x * (f32(i) / 10 - 1), half.y * (f32(j) / 10 - 1)}
			q := [2]f64{f64(box[0] + half.x + p.x), f64(box[1] + half.y + p.y)}
			want := f32(gradient_spread(gradient_place(sg, q), sg.spread))
			got := placed_gradient_at(read, p, half)
			gap := abs(want - got)
			if sg.spread == .Repeat {
				gap = min(gap, 1 - gap) // 0.9999 and 0.0001 are side by side
			}
			worst = max(worst, gap)
		}
	}
	testing.expectf(t, worst < 2e-3, "the GPU's place in the ramp is %v away from the picture renderer's", worst, loc = loc)
}

@(test)
test_a_placed_gradient_is_where_the_picture_renderer_puts_it :: proc(t: ^testing.T) {
	// user units, at an angle, mirrored past its ends, on a turned rectangle
	expect_same_as_the_picture_renderer(t, wrap(`<defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="10" y1="5" x2="40" y2="30" spreadMethod="reflect">
		<stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient></defs>
		<rect x="5" y="5" width="80" height="40" transform="rotate(10 50 25)" fill="url(#g)"/>`))
	// the box's units, turned by its own transform, repeating
	expect_same_as_the_picture_renderer(t, wrap(`<defs><linearGradient id="g" x2="0.3" gradientTransform="rotate(30)" spreadMethod="repeat">
		<stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient></defs>
		<rect x="20" y="10" width="60" height="30" fill="url(#g)"/>`))
	// radial with a focal point, sheared
	expect_same_as_the_picture_renderer(t, wrap(`<defs><radialGradient id="g" cx="0.5" cy="0.5" r="0.4" fx="0.3" fy="0.4" gradientTransform="skewX(20)">
		<stop offset="0" stop-color="white"/><stop offset="1" stop-color="black"/></radialGradient></defs>
		<ellipse cx="50" cy="25" rx="40" ry="20" fill="url(#g)"/>`))
	// radial in user units with its focal point outside the circle, pulled back in (behind a focal point at the edge the
	// place in the ramp grows without end, so it is compared padded: repeated, 32-bit numbers part from 64-bit ones there)
	expect_same_as_the_picture_renderer(t, wrap(`<defs><radialGradient id="g" gradientUnits="userSpaceOnUse" cx="50" cy="25" r="10" fx="80" fy="25">
		<stop offset="0" stop-color="white"/><stop offset="1" stop-color="black"/></radialGradient></defs>
		<rect width="100" height="50" fill="url(#g)"/>`))
	// and repeating, mirrored, from a focal point inside
	expect_same_as_the_picture_renderer(t, wrap(`<defs><radialGradient id="g" gradientUnits="userSpaceOnUse" cx="50" cy="25" r="10" fx="53" fy="22" spreadMethod="repeat">
		<stop offset="0" stop-color="white"/><stop offset="1" stop-color="black"/></radialGradient></defs>
		<rect width="100" height="50" fill="url(#g)"/>`))
	expect_same_as_the_picture_renderer(t, wrap(`<defs><radialGradient id="g" r="0.2" fx="0.45" spreadMethod="reflect">
		<stop offset="0" stop-color="white"/><stop offset="1" stop-color="black"/></radialGradient></defs>
		<rect width="100" height="50" fill="url(#g)"/>`))
	// a gradient on a drawing whose view box does not start at 0, 0
	expect_same_as_the_picture_renderer(t, wrap(`<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
		<stop offset="0.2" stop-color="red"/><stop offset="0.8" stop-color="blue"/></linearGradient></defs>
		<circle cx="-20" cy="30" r="15" fill="url(#g)"/>`, `viewBox="-50 0 100 50"`))
}

@(test)
test_drawing_a_drawing_lays_its_gradients_on_the_gpu_mixed_in_rgb :: proc(t: ^testing.T) {
	d, _ := read(wrap(`<defs><linearGradient id="g"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue" stop-opacity="0.5"/></linearGradient>
		<radialGradient id="r"><stop offset="0" stop-color="white"/><stop offset="1" stop-color="black"/></radialGradient></defs>
		<rect width="50" height="50" fill="url(#g)" fill-opacity="0.5" stroke="url(#r)" stroke-width="4"/>`))
	defer svg_destroy(&d)
	list := fresh()
	defer destroy(&list)
	svg_draw(&list, &d, 0, 0, 100, 50)
	if !testing.expect_value(t, len(list.commands), 1) {return}
	c := command_at(&list, 0)
	testing.expect(t, c.style.fill_paint.id != 0 && c.style.stroke_paint.id != 0, "both paints are gradients")
	fill := list.gradients[c.style.fill_paint.id - 1]
	testing.expect_value(t, fill.kind, Gradient_Kind.Placed_Linear)
	testing.expect_value(t, fill.space, maths.Mix_Space.Rgb)
	testing.expect_value(t, fill.count, 2)
	// the opacity is in the colors: 0.5 of each stop's own
	testing.expect_value(t, fill.colours[0], maths.Colour{255, 0, 0, 127.5})
	testing.expect_value(t, fill.colours[1], maths.Colour{0, 0, 255, 63.75})
	testing.expect_value(t, fill.stops[1], f32(100))
	// left to right across the box: the left edge is 0, the right 1
	testing.expect(t, abs(placed_gradient_at(fill, {-25, 0}, {25, 25})) < 1e-5)
	testing.expect(t, abs(placed_gradient_at(fill, {25, 0}, {25, 25}) - 1) < 1e-5)
	stroke := list.gradients[c.style.stroke_paint.id - 1]
	testing.expect_value(t, stroke.kind, Gradient_Kind.Placed_Radial)
	testing.expect(t, abs(placed_gradient_at(stroke, {0, 0}, {25, 25})) < 1e-5, "the middle is the first stop")
	testing.expect(t, abs(placed_gradient_at(stroke, {25, 0}, {25, 25}) - 1) < 1e-5, "the edge is the last")
	testing.expect_value(t, d.lost, bit_set[Svg_Lost]{})
}

@(test)
test_a_gradient_with_more_stops_than_the_gpu_holds_is_sampled_from_its_first_stop_to_its_last :: proc(t: ^testing.T) {
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `<defs><linearGradient id="g">`)
	for i in 0 ..< 21 {
		strings.write_string(&b, `<stop offset="`)
		strings.write_string(&b, itoa(i * 5))
		strings.write_string(&b, `%" stop-color="`)
		strings.write_string(&b, "red" if i % 2 == 0 else "blue")
		strings.write_string(&b, `"/>`)
	}
	strings.write_string(&b, `</linearGradient></defs><rect width="10" height="10" fill="url(#g)"/>`)
	d, _ := read(wrap(strings.to_string(b)))
	defer svg_destroy(&d)
	g, ok := svg_gpu_gradient(&d, d.items[0].fill_gradient, 1, {0, 0, 10, 10})
	testing.expect(t, ok)
	testing.expect_value(t, g.count, MAX_STOPS)
	testing.expect_value(t, g.stops[0], f32(0))
	testing.expect_value(t, g.stops[MAX_STOPS - 1], f32(100))
	testing.expect_value(t, g.colours[0], maths.Colour{255, 0, 0, 255})
	testing.expect_value(t, g.colours[MAX_STOPS - 1], maths.Colour{255, 0, 0, 255})
}

@(test)
test_a_gradient_with_no_length_is_its_last_color_and_one_too_fine_for_the_gpu_is_its_first :: proc(t: ^testing.T) {
	d, _ := read(wrap(`<defs><linearGradient id="a" gradientUnits="userSpaceOnUse" x1="5" y1="5" x2="5" y2="5"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient>
		<radialGradient id="b" r="0"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></radialGradient>
		<linearGradient id="c" gradientUnits="userSpaceOnUse" x1="0" x2="0.000001"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient></defs>
		<rect width="10" height="10" fill="url(#a)"/><rect width="10" height="10" fill="url(#b)"/><rect width="10" height="10" fill="url(#c)"/>`))
	defer svg_destroy(&d)
	if !testing.expect_value(t, len(d.items), 3) {return}
	box := [4]f32{0, 0, 10, 10}
	for i in 0 ..< 2 {
		g, ok := svg_gpu_gradient(&d, d.items[i].fill_gradient, 1, box)
		testing.expect(t, ok)
		testing.expect_value(t, g.count, 1)
		testing.expect_value(t, g.colours[0], maths.Colour{0, 0, 255, 255})
	}
	_, fine := svg_gpu_gradient(&d, d.items[2].fill_gradient, 1, box)
	testing.expect(t, !fine, "past what 16-bit numbers hold")
	_, none := svg_gpu_gradient(&d, -1, 1, box)
	testing.expect(t, !none)
	// drawn, it falls back to the item's color, the first stop
	list := fresh()
	defer destroy(&list)
	svg_draw(&list, &d, 0, 0, 100, 50)
	last := command_at(&list, 2)
	testing.expect_value(t, last.style.fill_paint.id, u32(0))
	testing.expect_value(t, last.style.fill, maths.Colour{255, 0, 0, 255})
}

@(test)
test_a_placed_gradients_numbers_keep_their_precision_in_16_bit_halves :: proc(t: ^testing.T) {
	g, _ := gradient_make({RED, BLUE}, .Placed_Radial, space = .Rgb)
	g.place = {12.3456789, -0.000123, 3.14159265, 1000.5, -7.77777, 0.1}
	g.focus = {0.25, -0.5}
	g.spread = .Reflect
	params := gradient_params(g)
	testing.expect_value(t, params[0], [4]f32{4, 1, 0.25, -0.5})
	read := as_the_gpu_reads(g)
	for v, i in g.place {
		testing.expectf(t, abs(read.place[i] - v) <= abs(v) * 1e-6 + 1e-7, "%v came back as %v", v, read.place[i])
	}
	// what the atlas bakes is the same numbers
	atlas: Gradient_Atlas
	defer atlas_destroy(&atlas)
	row, _ := atlas_row(&atlas, g)
	testing.expect_value(t, atlas.rows[row].params[1][0], f16(params[1][0]))
	testing.expect_value(t, atlas.rows[row].params[3][3], f16(params[3][3]))
}

@(test)
test_placed_gradients_differ_by_their_transform_focal_point_and_spread :: proc(t: ^testing.T) {
	a, _ := gradient_make({RED, BLUE}, .Placed_Linear, space = .Rgb)
	a.place = {1, 0, 0, 1, 0, 0}
	b := a
	testing.expect(t, gradient_same(a, b) && gradient_hash(a) == gradient_hash(b))
	b.place[4] = 0.5
	testing.expect(t, !gradient_same(a, b) && gradient_hash(a) != gradient_hash(b))
	b = a
	b.spread = .Repeat
	testing.expect(t, !gradient_same(a, b) && gradient_hash(a) != gradient_hash(b))
	b = a
	b.focus = {0.1, 0}
	testing.expect(t, !gradient_same(a, b) && gradient_hash(a) != gradient_hash(b))
	// the spreads, at 1.25 along the way
	a.place = {1.25, 0, 0, 0, 0, 0}
	testing.expect_value(t, placed_gradient_at(a, {1, 0}, {1, 1}), f32(1))
	a.spread = .Repeat
	testing.expect(t, abs(placed_gradient_at(a, {1, 0}, {1, 1}) - 0.25) < 1e-6)
	a.spread = .Reflect
	testing.expect(t, abs(placed_gradient_at(a, {1, 0}, {1, 1}) - 0.75) < 1e-6)
	// a box of no height: the point is measured by what it has
	testing.expect(t, abs(placed_gradient_at(a, {1, 0}, {1, 0}) - 0.75) < 1e-6)
}

@(test)
test_a_drawings_gradient_is_saved_into_svg_and_pdf_files_where_it_was :: proc(t: ^testing.T) {
	d, _ := read(wrap(`<defs><linearGradient id="g" spreadMethod="reflect" x2="0.5"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient>
		<radialGradient id="r" fx="0.3"><stop offset="0" stop-color="white"/><stop offset="1" stop-color="black"/></radialGradient></defs>
		<rect width="50" height="50" fill="url(#g)"/><rect x="50" width="50" height="50" fill="url(#r)"/>`))
	defer svg_destroy(&d)
	list := fresh()
	defer destroy(&list)
	svg_draw(&list, &d, 0, 0, 100, 50)
	svg, notes := svg_of(&list)
	testing.expect(t, has(svg, `<linearGradient id="g1" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="1" y2="0" spreadMethod="reflect" gradientTransform="matrix(25 0 0 25 0 0)">`), svg)
	testing.expect(t, has(svg, `<radialGradient id="g2" gradientUnits="userSpaceOnUse" cx="0" cy="0" r="1" fx="-0.4" fy="0" gradientTransform="matrix(25 0 0 25 75 25)">`), svg)
	testing.expect_value(t, len(notes), 0)
	pdf, pdf_notes := pdf_of(&list)
	text := string(pdf)
	testing.expect(t, has(text, "/ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 1 0]"), "the linear one")
	testing.expect(t, has(text, "/ShadingType 3 /ColorSpace /DeviceRGB /Coords [-0.4 0 0 0 0 1]"), "the radial one, from its focal point")
	testing.expect_value(t, len(pdf_notes), 1)
	if len(pdf_notes) == 1 {
		testing.expect_value(t, pdf_notes[0], "a gradient that repeats or reflects past its ends")
	}
}
