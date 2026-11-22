// SPDX-License-Identifier: 0BSD
package gfx

import "../maths"
import "core:math"
import "core:strings"
import "core:testing"

@(private = "file")
square :: proc(x, y, side: f32, clockwise := true) -> Contour {
	points := make([][2]f32, 4, context.temp_allocator)
	if clockwise {
		points[0], points[1], points[2], points[3] = {x, y}, {x + side, y}, {x + side, y + side}, {x, y + side}
	} else {
		points[0], points[1], points[2], points[3] = {x, y}, {x, y + side}, {x + side, y + side}, {x + side, y}
	}
	return Contour{points, true}
}

@(private = "file")
ONE :: Raster_Place{1, 1, 0, 0}

@(private = "file")
near :: proc(a, b: f32, by: f32 = 0.01) -> bool {
	return abs(a - b) <= by
}

@(test)
test_a_shape_covers_whole_pixels_inside_none_outside_and_part_of_those_its_edge_crosses :: proc(t: ^testing.T) {
	// on pixel boundaries: whole pixels
	mask := raster_contour_mask({square(2, 2, 4)}, ONE, true, 8, 8, context.temp_allocator)
	testing.expect_value(t, mask[3 * 8 + 3], 1)
	testing.expect_value(t, mask[2 * 8 + 2], 1)
	testing.expect_value(t, mask[1 * 8 + 1], 0)
	testing.expect_value(t, mask[6 * 8 + 6], 0)
	total: f32
	for v in mask {
		total += v
	}
	testing.expect(t, near(total, 16), "the area is the shape's")
	// an edge across the middle of a pixel covers half of it, across and down
	half := raster_contour_mask({square(1.5, 1.5, 2)}, ONE, true, 4, 4, context.temp_allocator)
	testing.expect(t, near(half[1 * 4 + 1], 0.25), "a corner pixel is a quarter covered")
	testing.expect(t, near(half[1 * 4 + 2], 0.5), "an edge pixel is half covered")
	testing.expect(t, near(half[2 * 4 + 2], 1), "the one in the middle wholly")
	// a shape partly outside the raster is cut at its edges, and one wholly outside covers nothing
	outside := raster_contour_mask({square(-10, -10, 5)}, ONE, true, 4, 4, context.temp_allocator)
	for v in outside {
		testing.expect_value(t, v, 0)
	}
	edge := raster_contour_mask({square(-2, -2, 4)}, ONE, true, 4, 4, context.temp_allocator)
	testing.expect_value(t, edge[0], 1)
	testing.expect_value(t, edge[3 * 4 + 3], 0)
	// nothing to cover, or no raster, is no work
	testing.expect_value(t, len(raster_contour_mask({}, ONE, true, 4, 4, context.temp_allocator)), 16)
	testing.expect_value(t, len(raster_contour_mask({square(0, 0, 2)}, ONE, true, 0, 0, context.temp_allocator)), 0)
	// a contour of fewer than two points has no edges
	lone := Contour{make([][2]f32, 1, context.temp_allocator), true}
	for v in raster_contour_mask({lone}, ONE, true, 4, 4, context.temp_allocator) {
		testing.expect_value(t, v, 0)
	}
}

@(test)
test_nonzero_fills_a_square_inside_another_wound_the_same_way_and_even_odd_cuts_a_hole :: proc(t: ^testing.T) {
	same := []Contour{square(0, 0, 8), square(2, 2, 4)}
	nonzero := raster_contour_mask(same, ONE, true, 8, 8, context.temp_allocator)
	even_odd := raster_contour_mask(same, ONE, false, 8, 8, context.temp_allocator)
	testing.expect_value(t, nonzero[4 * 8 + 4], 1)
	testing.expect_value(t, even_odd[4 * 8 + 4], 0)
	testing.expect_value(t, even_odd[0], 1)
	// wound the other way, the inner square is a hole for both rules
	opposite := []Contour{square(0, 0, 8), square(2, 2, 4, false)}
	testing.expect_value(t, raster_contour_mask(opposite, ONE, true, 8, 8, context.temp_allocator)[4 * 8 + 4], 0)
	testing.expect_value(t, raster_contour_mask(opposite, ONE, false, 8, 8, context.temp_allocator)[4 * 8 + 4], 0)
}

@(test)
test_a_drawing_is_painted_with_its_fills_strokes_gradients_and_clips :: proc(t: ^testing.T) {
	text := `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
		<defs>
			<linearGradient id="g" x1="0" x2="1"><stop offset="0" stop-color="#000"/><stop offset="1" stop-color="#fff"/></linearGradient>
			<clipPath id="c"><rect x="0" y="0" width="5" height="10"/></clipPath>
		</defs>
		<rect width="10" height="10" fill="url(#g)"/>
		<rect width="10" height="2" y="8" fill="#f00" clip-path="url(#c)"/>
		<line x1="0" y1="5" x2="10" y2="5" stroke="#00f" stroke-width="1"/>
	</svg>`
	d, err := svg_read(transmute([]byte)text)
	defer svg_destroy(&d)
	testing.expect_value(t, err, Svg_Error.None)
	testing.expect_value(t, len(d.gradients), 1)
	testing.expect_value(t, len(d.clips), 1)
	testing.expect_value(t, d.raster_lost, bit_set[Svg_Lost]{})
	testing.expect_value(t, d.lost, bit_set[Svg_Lost]{})
	r := raster_make(10, 10, context.temp_allocator)
	raster_svg(&r, &d, 0, 0, 10, 10)
	img := raster_to_image(r, context.temp_allocator)
	px :: proc(img: Image, x, y: int) -> [4]u8 {
		at := (y * img.width + x) * 4
		return {img.pixels[at], img.pixels[at + 1], img.pixels[at + 2], img.pixels[at + 3]}
	}
	// the gradient runs dark to light, left to right, and is fully opaque
	left, right := px(img, 0, 0), px(img, 9, 0)
	testing.expect(t, left.r < 20 && right.r > 235 && left.a == 255, "a gradient from black to white")
	testing.expect(t, abs(int(px(img, 4, 0).r) - 115) < 10, "the middle of it is between")
	// the red band is cut by the clip at half the width
	testing.expect_value(t, px(img, 2, 9), [4]u8{255, 0, 0, 255})
	testing.expect(t, px(img, 7, 9).g > 150, "beyond the clip the gradient shows")
	// the line is a stroke one unit wide, across row 4 and row 5 by halves
	testing.expect(t, px(img, 5, 4).b > 100 && px(img, 5, 5).b > 100, "the stroke straddles its line")
	testing.expect(t, px(img, 5, 2).b < 200, "and is not wider")
	// a raster with no pixels, or a drawing with no size, paints nothing and does not fail
	empty := raster_make(0, 0, context.temp_allocator)
	raster_svg(&empty, &d, 0, 0, 10, 10)
	none := Svg_Drawing{}
	raster_svg(&r, &none, 0, 0, 10, 10)
}

@(test)
test_gradients_are_read_through_their_href_chains_with_their_units_transforms_and_spread :: proc(t: ^testing.T) {
	text := `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 50">
		<defs>
			<linearGradient id="stops"><stop offset="0" stop-color="red"/><stop offset="50%" stop-color="lime" stop-opacity="0.5"/><stop offset="0.2" stop-color="blue"/></linearGradient>
			<linearGradient id="user" href="#stops" gradientUnits="userSpaceOnUse" x1="10%" x2="90%" spreadMethod="reflect" gradientTransform="translate(5 0)"/>
			<radialGradient id="round" xlink:href="#stops" fx="0.3"/>
			<linearGradient id="nothing"/>
			<radialGradient id="one"><stop offset="0" stop-color="#123456"/></radialGradient>
		</defs>
		<rect width="100" height="50" fill="url(#user)"/>
		<rect width="10" height="10" fill="url(#round)" stroke="url(#user)"/>
		<rect width="10" height="10" fill="url(#nothing)"/>
		<rect width="0" height="10" fill="url(#stops)"/>
		<line x1="0" y1="0" x2="10" y2="0" stroke="url(#stops)"/>
		<rect width="10" height="10" fill="url(#one)"/>
	</svg>`
	d, err := svg_read(transmute([]byte)text)
	defer svg_destroy(&d)
	testing.expect_value(t, err, Svg_Error.None)
	// the user-space gradient took its stops from `stops`, its ends from the view's width, and spreads by reflecting
	g := d.gradients[d.items[0].fill_gradient]
	testing.expect(t, !g.radial && g.spread == .Reflect)
	testing.expect_value(t, len(g.stops), 3)
	testing.expect_value(t, g.stops[2].offset, 0.5) // an offset below the one before is raised to it
	testing.expect(t, near(f32(g.stops[1].colour.a), 127.5, 1), "stop-opacity")
	testing.expect(t, near(f32(g.x1), 10) && near(f32(g.x2), 90))
	// the transform maps a drawing point into the gradient's space: translate(5 0) undone
	testing.expect(t, near(f32(g.to_gradient[4]), -5))
	// the radial one is measured by its rectangle: its middle is the box's, and the focal point is its own
	round := d.gradients[d.items[1].fill_gradient]
	testing.expect(t, round.radial && near(f32(round.cx), 0.5) && near(f32(round.r), 0.5) && near(f32(round.fx), 0.3) && near(f32(round.fy), 0.5))
	testing.expect(t, d.items[1].stroke_gradient >= 0, "a stroke takes a gradient too")
	// a gradient with no stops fills nothing; one measured by a box with no width is not placed; a line has no box height
	testing.expect_value(t, len(d.items), 4)
	testing.expect_value(t, d.items[2].fill_gradient, -1)
	// a single stop is painted as that color through the gradient
	testing.expect_value(t, len(d.gradients[d.items[3].fill_gradient].stops), 1)
	// colors along stops
	stops := []Svg_Stop{{0, {0, 0, 0, 255}}, {0.5, {255, 0, 0, 255}}, {0.5, {0, 255, 0, 255}}, {1, {0, 0, 255, 255}}}
	testing.expect_value(t, raster_stop_colour(stops, -1), maths.Colour{0, 0, 0, 255})
	testing.expect_value(t, raster_stop_colour(stops, 0.25), maths.Colour{127.5, 0, 0, 255})
	testing.expect_value(t, raster_stop_colour(stops, 0.5), maths.Colour{255, 0, 0, 255})
	testing.expect_value(t, raster_stop_colour(stops, 0.75), maths.Colour{0, 127.5, 127.5, 255})
	testing.expect_value(t, raster_stop_colour(stops, 2), maths.Colour{0, 0, 255, 255})
	testing.expect_value(t, raster_stop_colour(nil, 0.5), maths.Colour{})
}

@(test)
test_spread_and_radial_gradients_paint_where_svg_says :: proc(t: ^testing.T) {
	// a gradient over the left half only, repeated, reflected or padded across the whole width
	paint_row :: proc(t: ^testing.T, spread_method: string) -> Image {
		text := strings.concatenate({`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 1"><defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" x2="10" spreadMethod="`, spread_method, `"><stop offset="0" stop-color="#000"/><stop offset="1" stop-color="#fff"/></linearGradient></defs><rect width="20" height="1" fill="url(#g)"/></svg>`}, context.temp_allocator)
		d, _ := svg_read(transmute([]byte)text)
		defer svg_destroy(&d)
		r := raster_make(20, 1, context.temp_allocator)
		raster_svg(&r, &d, 0, 0, 20, 1)
		return raster_to_image(r, context.temp_allocator)
	}
	red :: proc(img: Image, x: int) -> int {
		return int(img.pixels[x * 4])
	}
	pad, repeat, reflect := paint_row(t, "pad"), paint_row(t, "repeat"), paint_row(t, "reflect")
	testing.expect(t, red(pad, 15) > 250, "padding keeps the last color")
	testing.expect(t, red(repeat, 10) < 20, "repeating starts again")
	testing.expect(t, red(reflect, 10) > 230 && red(reflect, 19) < 30, "reflecting comes back")
	// a radial gradient is light at its middle and dark at its edge, and a focal point moves its light
	text := `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><defs>
		<radialGradient id="r"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#000"/></radialGradient>
		<radialGradient id="f" fx="0.2" fy="0.5"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#000"/></radialGradient>
		<radialGradient id="far" fx="5" fy="5"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#000"/></radialGradient>
		<radialGradient id="flat" r="0"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#000"/></radialGradient>
	</defs><rect width="20" height="20" fill="url(#r)"/><rect width="10" height="20" x="20" fill="url(#f)"/><rect width="20" height="20" fill="url(#far)" opacity="0"/><rect width="20" height="20" fill="url(#flat)" opacity="0"/></svg>`
	d, _ := svg_read(transmute([]byte)text)
	defer svg_destroy(&d)
	r := raster_make(20, 20, context.temp_allocator)
	raster_svg(&r, &d, 0, 0, 20, 20)
	img := raster_to_image(r, context.temp_allocator)
	middle, corner := int(img.pixels[(10 * 20 + 10) * 4]), int(img.pixels[0])
	testing.expect(t, middle > 230 && corner < 10, "light in the middle, dark at the corner")
	// the focal point far outside the circle is brought just inside it, and a circle of no size is its last color
	g := Svg_Gradient{radial = true, cx = 0.5, cy = 0.5, r = 0.5, fx = 5, fy = 5, to_gradient = {1, 0, 0, 1, 0, 0}}
	testing.expect(t, gradient_place(g, [2]f64{0.5, 0.5}) < 1)
	testing.expect_value(t, gradient_place(Svg_Gradient{radial = true, to_gradient = {1, 0, 0, 1, 0, 0}}, [2]f64{1, 1}), 1)
	testing.expect_value(t, gradient_place(Svg_Gradient{to_gradient = {1, 0, 0, 1, 0, 0}}, [2]f64{1, 1}), 1) // a linear one of no length
	at_focus := Svg_Gradient{radial = true, cx = 0.5, cy = 0.5, r = 0.5, fx = 0.5, fy = 0.5, to_gradient = {1, 0, 0, 1, 0, 0}}
	testing.expect_value(t, gradient_place(at_focus, [2]f64{0.5, 0.5}), 0)
	testing.expect(t, near(f32(gradient_place(at_focus, [2]f64{1, 0.5})), 1))
	testing.expect(t, near(f32(gradient_spread(-0.25, .Reflect)), 0.25) && near(f32(gradient_spread(1.25, .Repeat)), 0.25) && gradient_spread(-3, .Pad) == 0)
}

@(test)
test_clips_are_read_in_the_units_of_what_names_them_and_what_cannot_be_cut_is_said :: proc(t: ^testing.T) {
	text := `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
		<defs>
			<clipPath id="left" transform="translate(1 0)"><rect width="4" height="10"/><circle cx="8" cy="8" r="1" clip-rule="evenodd"/></clipPath>
			<clipPath id="box" clipPathUnits="objectBoundingBox"><rect width="0.5" height="1"/></clipPath>
			<clipPath id="empty"/>
			<clipPath id="nested" clip-path="url(#left)"><rect width="10" height="10"/></clipPath>
		</defs>
		<g clip-path="url(#left)" transform="translate(1 0)"><rect width="10" height="10" fill="#f00"/><rect width="10" height="10" fill="#0f0"/></g>
		<rect width="10" height="10" fill="#00f" clip-path="url(#box)"/>
		<rect width="10" height="10" fill="#00f" clip-path="url(#empty)"/>
		<rect width="10" height="10" fill="#00f" clip-path="url(#nested)"/>
		<rect width="10" height="10" fill="#00f" clip-path="url(#missing)"/>
		<text>hello</text>
		<image href="x.png"/>
	</svg>`
	d, err := svg_read(transmute([]byte)text)
	defer svg_destroy(&d)
	testing.expect_value(t, err, Svg_Error.None)
	// the group's clip reaches both rectangles, in the group's units (its translate and the clip path's own)
	testing.expect_value(t, len(d.items[0].clips), 1)
	testing.expect_value(t, d.items[0].clips[0], d.items[1].clips[0])
	clip := d.clips[d.items[0].clips[0]]
	testing.expect_value(t, len(clip.shapes), 2)
	testing.expect_value(t, clip.shapes[0].contours[0].points[0], [2]f32{2, 0})
	testing.expect(t, clip.shapes[0].nonzero && !clip.shapes[1].nonzero, "each shape keeps its clip rule")
	// a clip measured by the box, a nested clip, a missing one, text and pictures are what the renderer leaves out
	testing.expect_value(t, d.raster_lost, bit_set[Svg_Lost]{.Clip, .Text, .Picture})
	testing.expect_value(t, len(d.items[2].clips), 0)
	// an empty clip path hides everything
	r := raster_make(10, 10, context.temp_allocator)
	empty_only := `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><defs><clipPath id="e"/></defs><rect width="10" height="10" fill="#f00" clip-path="url(#e)"/></svg>`
	e, _ := svg_read(transmute([]byte)empty_only)
	defer svg_destroy(&e)
	raster_svg(&r, &e, 0, 0, 10, 10)
	for p in r.pixels {
		testing.expect_value(t, p.a, 0)
	}
	// a clip index out of range is passed over
	odd := Svg_Drawing{width = 10, height = 10, items = []Svg_Item{{contours = {square(0, 0, 10)}, fill_on = true, fill = {255, 0, 0, 255}, fill_gradient = -1, fill_alpha = 1, nonzero = true, clips = {7}}}}
	raster_svg(&r, &odd, 0, 0, 10, 10)
	testing.expect(t, near(r.pixels[0].a, 1))
}

@(test)
test_a_picture_scaled_down_keeps_the_average_of_what_each_pixel_covers :: proc(t: ^testing.T) {
	// four pixels: black, white, white, black, see-through and not
	pixels := []u8{0, 0, 0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 0, 0, 0, 255}
	img := Image{width = 2, height = 2, pixels = pixels}
	r := raster_make(1, 1, context.temp_allocator)
	raster_image(&r, img, 0, 0, 1, 1)
	testing.expect(t, near(r.pixels[0].r, 0.5) && near(r.pixels[0].a, 1), "one pixel is the average of four")
	// a rectangle covering half a pixel covers it half
	half := raster_make(1, 1, context.temp_allocator)
	raster_image(&half, img, 0, 0, 0.5, 1)
	testing.expect(t, near(half.pixels[0].a, 0.5))
	// scaled up, each pixel takes the one it falls on
	big := raster_make(4, 4, context.temp_allocator)
	raster_image(&big, img, 0, 0, 4, 4)
	testing.expect(t, near(big.pixels[0].r, 0) && near(big.pixels[3].r, 1))
	// a see-through pixel is averaged by its alpha, so it does not darken the colors beside it
	clear_pixels := []u8{255, 0, 0, 255, 0, 0, 0, 0}
	r2 := raster_make(1, 1, context.temp_allocator)
	raster_image(&r2, Image{width = 2, height = 1, pixels = clear_pixels}, 0, 0, 1, 1)
	out := raster_to_image(r2, context.temp_allocator)
	testing.expect_value(t, out.pixels[0], 255)
	testing.expect(t, abs(int(out.pixels[3]) - 128) <= 1)
	// nothing to draw, or a rectangle of no size or off the raster, changes nothing
	raster_image(&r, Image{}, 0, 0, 1, 1)
	raster_image(&r, img, 0, 0, 0, 1)
	raster_image(&r, img, 5, 5, 1, 1)
	raster_image(&r, Image{width = 2, height = 2, pixels = pixels[:4]}, 0, 0, 1, 1)
	testing.expect(t, near(r.pixels[0].r, 0.5))
}

@(test)
test_masks_edges_and_a_solid_ground :: proc(t: ^testing.T) {
	r := raster_make(4, 4, context.temp_allocator)
	for &p in r.pixels {
		p = {1, 0, 0, 1}
	}
	// a circle in the middle keeps the middle and clears the corners
	mask := raster_contour_mask(raster_circle(2, 2, 2, context.temp_allocator), ONE, true, 4, 4, context.temp_allocator)
	raster_apply_mask(&r, mask)
	testing.expect(t, near(r.pixels[1 * 4 + 1].a, 1, 0.05) && r.pixels[0].a < 0.5)
	// a mask too short clears what it does not reach
	short := raster_make(2, 1, context.temp_allocator)
	short.pixels[1] = {1, 1, 1, 1}
	raster_apply_mask(&short, []f32{1})
	testing.expect_value(t, short.pixels[1].a, 0)
	// a rounded rectangle with no radius is a rectangle, and one too round is a circle's worth
	sharp := raster_rounded_rect(0, 0, 4, 4, 0, context.temp_allocator)
	whole := raster_contour_mask(sharp, ONE, true, 4, 4, context.temp_allocator)
	testing.expect(t, near(whole[0], 1))
	round := raster_contour_mask(raster_rounded_rect(0, 0, 4, 4, 10, context.temp_allocator), ONE, true, 4, 4, context.temp_allocator)
	testing.expect(t, round[0] < 0.5 && near(round[1 * 4 + 1], 1, 0.05))
	// the middle pixel stretched to the edges
	e := raster_make(3, 3, context.temp_allocator)
	e.pixels[4] = {0, 1, 0, 1}
	raster_extend(&e, 1, 1, 2, 2)
	for p in e.pixels {
		testing.expect_value(t, p, [4]f32{0, 1, 0, 1})
	}
	// over a solid ground nothing is see-through
	f := raster_make(1, 1, context.temp_allocator)
	f.pixels[0] = {0.5, 0, 0, 0.5}
	raster_flatten(&f, {255, 255, 255, 255})
	img := raster_to_image(f, context.temp_allocator)
	testing.expect_value(t, img.pixels[3], 255)
	testing.expect(t, abs(int(img.pixels[0]) - 255) <= 1 && abs(int(img.pixels[1]) - 128) <= 1)
	// a raster of no size, and destroying one
	z := raster_make(-1, 3)
	testing.expect_value(t, len(z.pixels), 0)
	raster_destroy(&z)
	testing.expect_value(t, z.width, 0)
	_ = math.PI
}
