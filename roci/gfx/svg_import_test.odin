// SPDX-License-Identifier: 0BSD
package gfx

import "../geom"
import "core:math"
import "core:testing"

read :: proc(text: string) -> (Svg_Drawing, Svg_Error) {
	return svg_read(transmute([]byte)text)
}

wrap :: proc(inside: string, attributes := `viewBox="0 0 100 50"`) -> string {
	return tprint_svg(attributes, inside)
}

@(private = "file")
tprint_svg :: proc(attributes, inside: string) -> string {
	return concat({`<svg xmlns="http://www.w3.org/2000/svg" `, attributes, ">", inside, "</svg>"})
}

@(private = "file")
concat :: proc(parts: []string) -> string {
	total := 0
	for p in parts {total += len(p)}
	out := make([]byte, total, context.temp_allocator)
	at := 0
	for p in parts {
		copy(out[at:], p)
		at += len(p)
	}
	return string(out)
}

bounds_of :: proc(item: Svg_Item) -> (lo, hi: [2]f32) {
	lo, hi = {max(f32), max(f32)}, {min(f32), min(f32)}
	for contour in item.contours {
		for p in contour.points {
			lo = {min(lo.x, p.x), min(lo.y, p.y)}
			hi = {max(hi.x, p.x), max(hi.y, p.y)}
		}
	}
	return
}

@(test)
test_a_rectangle_is_one_closed_contour_in_its_fill :: proc(t: ^testing.T) {
	d, err := read(wrap(`<rect x="10" y="5" width="20" height="10" fill="#ff8000"/>`))
	defer svg_destroy(&d)
	testing.expect_value(t, err, Svg_Error.None)
	testing.expect_value(t, [2]f32{d.width, d.height}, [2]f32{100, 50})
	if !testing.expect_value(t, len(d.items), 1) {return}
	item := d.items[0]
	testing.expect(t, item.fill_on && !item.stroke_on)
	testing.expect_value(t, item.fill, [4]f32{255, 128, 0, 255})
	lo, hi := bounds_of(item)
	testing.expect_value(t, lo, [2]f32{10, 5})
	testing.expect_value(t, hi, [2]f32{30, 15})
	testing.expect(t, item.contours[0].closed)
}

@(test)
test_the_default_paint_is_a_black_fill_and_none_turns_it_off :: proc(t: ^testing.T) {
	d, _ := read(wrap(`<rect width="10" height="10"/><rect width="10" height="10" fill="none" stroke="red" stroke-width="3"/>`))
	defer svg_destroy(&d)
	if !testing.expect_value(t, len(d.items), 2) {return}
	testing.expect_value(t, d.items[0].fill, [4]f32{0, 0, 0, 255})
	testing.expect(t, !d.items[1].fill_on && d.items[1].stroke_on)
	testing.expect_value(t, d.items[1].width, 3)
	testing.expect_value(t, d.items[1].stroke, [4]f32{255, 0, 0, 255})
}

@(test)
test_a_shape_with_no_fill_and_no_stroke_is_dropped :: proc(t: ^testing.T) {
	d, err := read(wrap(`<rect width="10" height="10" fill="none"/>`))
	defer svg_destroy(&d)
	testing.expect_value(t, err, Svg_Error.Empty)
}

@(test)
test_path_commands_absolute_relative_and_implicit :: proc(t: ^testing.T) {
	d, _ := read(wrap(`<path d="M10 10 L20 10 20 20 H10 v-5 z M50 5 l10 0 m-10 20 l5 5"/>`))
	defer svg_destroy(&d)
	if !testing.expect_value(t, len(d.items), 1) {return}
	c := d.items[0].contours
	if !testing.expect_value(t, len(c), 3) {return}
	testing.expect(t, c[0].closed && !c[1].closed && !c[2].closed)
	testing.expect_value(t, len(c[0].points), 5) // M, L, the implicit L, H, v
	testing.expect_value(t, c[0].points[3], [2]f32{10, 20})
	testing.expect_value(t, c[0].points[4], [2]f32{10, 15})
	testing.expect_value(t, c[1].points[1], [2]f32{60, 5})
	testing.expect_value(t, c[2].points[0], [2]f32{50, 25}) // a moveto after a line starts at the line's end
}

@(test)
test_numbers_may_run_together_the_way_svg_allows :: proc(t: ^testing.T) {
	d, _ := read(wrap(`<path d="M1.5.5L-2-3e0 1e1,2"/>`))
	defer svg_destroy(&d)
	if !testing.expect_value(t, len(d.items), 1) {return}
	p := d.items[0].contours[0].points
	testing.expect_value(t, p[0], [2]f32{1.5, 0.5})
	testing.expect_value(t, p[1], [2]f32{-2, -3})
	testing.expect_value(t, p[2], [2]f32{10, 2})
}

@(test)
test_curves_are_cut_into_pieces_that_end_where_they_should :: proc(t: ^testing.T) {
	d, _ := read(wrap(`<path fill="none" stroke="black" d="M0 0 C 10 20 30 20 40 0 S 70 -20 80 0 Q 90 10 100 0 T 100 40"/>`))
	defer svg_destroy(&d)
	if !testing.expect_value(t, len(d.items), 1) {return}
	p := d.items[0].contours[0].points
	testing.expect(t, len(p) > 12, "a curve is many pieces")
	testing.expect_value(t, p[len(p) - 1], [2]f32{100, 40})
	// the second cubic's first control point mirrors the first one's second control about the join
	testing.expect(t, abs(p[0].x) < 1e-6)
}

@(test)
test_an_arc_follows_its_circle :: proc(t: ^testing.T) {
	d, _ := read(wrap(`<path fill="none" stroke="black" d="M 60 25 A 10 10 0 0 1 50 35 A 10 10 0 0 1 40 25 A 10 10 0 1 1 60 25"/>`))
	defer svg_destroy(&d)
	if !testing.expect_value(t, len(d.items), 1) {return}
	for p in d.items[0].contours[0].points {
		distance := math.sqrt(f64((p.x - 50) * (p.x - 50) + (p.y - 25) * (p.y - 25)))
		testing.expect(t, abs(distance - 10) < 0.05, "on the circle")
	}
}

@(test)
test_arc_flags_pick_the_arc_and_may_touch_the_numbers_after_them :: proc(t: ^testing.T) {
	// the same half circle, written with flags run into the numbers, over the top (sweep 1) and under (sweep 0)
	over, _ := read(wrap(`<path fill="none" stroke="black" d="M40 25a10 10 0 0110 -10"/>`))
	defer svg_destroy(&over)
	under, _ := read(wrap(`<path fill="none" stroke="black" d="M40 25a10 10 0 0010 10"/>`))
	defer svg_destroy(&under)
	lo, _ := bounds_of(over.items[0])
	testing.expect(t, lo.y < 25 && lo.y >= 15 - 1e-3)
	_, hi := bounds_of(under.items[0])
	testing.expect(t, hi.y > 25 && hi.y <= 35 + 1e-3)
}

@(test)
test_a_group_passes_its_paint_and_transform_down_and_a_child_may_change_the_paint :: proc(t: ^testing.T) {
	d, _ := read(wrap(`<g fill="blue" stroke="white" stroke-width="2" transform="translate(10 20) scale(2)">
	  <rect width="5" height="5"/><rect width="5" height="5" fill="lime" transform="translate(5 0)"/></g>`))
	defer svg_destroy(&d)
	if !testing.expect_value(t, len(d.items), 2) {return}
	lo, hi := bounds_of(d.items[0])
	testing.expect_value(t, lo, [2]f32{10, 20})
	testing.expect_value(t, hi, [2]f32{20, 30})
	testing.expect_value(t, d.items[0].fill, [4]f32{0, 0, 255, 255})
	testing.expect_value(t, d.items[1].fill, [4]f32{0, 255, 0, 255})
	testing.expect_value(t, d.items[0].width, 4) // the stroke is scaled with the shape
	lo2, _ := bounds_of(d.items[1])
	testing.expect_value(t, lo2.x, 20)
}

@(test)
test_rotate_about_a_point_and_matrix_transforms :: proc(t: ^testing.T) {
	d, _ := read(wrap(`<rect x="10" y="10" width="10" height="10" transform="rotate(90 10 10)"/><rect width="1" height="1" transform="matrix(2 0 0 3 4 5)"/>`))
	defer svg_destroy(&d)
	lo, hi := bounds_of(d.items[0])
	testing.expect(t, abs(lo.x - 0) < 1e-4 && abs(hi.x - 10) < 1e-4 && abs(lo.y - 10) < 1e-4 && abs(hi.y - 20) < 1e-4, "a quarter turn about a corner")
	lo, hi = bounds_of(d.items[1])
	testing.expect_value(t, lo, [2]f32{4, 5})
	testing.expect_value(t, hi, [2]f32{6, 8})
}

@(test)
test_opacity_multiplies_into_the_alpha_of_the_paint :: proc(t: ^testing.T) {
	d, _ := read(wrap(`<g opacity="0.5"><rect width="9" height="9" fill="red" fill-opacity="0.5" opacity="0.5"/></g>`))
	defer svg_destroy(&d)
	if !testing.expect_value(t, len(d.items), 1) {return}
	testing.expect(t, abs(d.items[0].fill.a - 255 * 0.125) < 1e-3)
}

@(test)
test_style_attributes_and_style_rules_set_the_paint_in_the_order_svg_gives :: proc(t: ^testing.T) {
	d, _ := read(wrap(`<style>.a { fill: #00ff00; stroke: black } rect { stroke-width: 7 } #b { fill: red }</style>
	  <rect class="a" width="5" height="5" fill="blue"/>
	  <rect id="b" class="a" width="5" height="5" style="stroke: white"/>`))
	defer svg_destroy(&d)
	if !testing.expect_value(t, len(d.items), 2) {return}
	testing.expect_value(t, d.items[0].fill, [4]f32{0, 255, 0, 255}) // a rule beats the attribute
	testing.expect_value(t, d.items[0].width, 7)
	testing.expect_value(t, d.items[1].fill, [4]f32{255, 0, 0, 255}) // the later rule
	testing.expect_value(t, d.items[1].stroke, [4]f32{255, 255, 255, 255}) // style beats the rules
}

@(test)
test_colors_in_every_form :: proc(t: ^testing.T) {
	forms := [?]struct {
		text: string,
		want: [4]f32,
	}{
		{"#f00", {255, 0, 0, 255}},
		{"#f008", {255, 0, 0, 136}},
		{"#00ff0080", {0, 255, 0, 128}},
		{"rgb(10, 20, 30)", {10, 20, 30, 255}},
		{"rgb(100%, 0%, 50%)", {255, 0, 127.5, 255}},
		{"rgba(0,0,255,0.5)", {0, 0, 255, 127.5}},
		{"teal", {0, 128, 128, 255}},
		{"TEAL", {0, 128, 128, 255}},
	}
	for form in forms {
		d, _ := read(wrap(concat({`<rect width="3" height="3" fill="`, form.text, `"/>`})))
		if len(d.items) == 1 {
			testing.expect_value(t, d.items[0].fill, form.want)
		} else {
			testing.expectf(t, false, "%s gave no item", form.text)
		}
		svg_destroy(&d)
	}
	d, _ := read(wrap(`<rect width="3" height="3" fill="notacolor"/>`))
	defer svg_destroy(&d)
	testing.expect_value(t, d.items[0].fill, [4]f32{0, 0, 0, 255}) // a color that cannot be read leaves the one before
}

@(test)
test_current_color_and_hidden_things :: proc(t: ^testing.T) {
	d, _ := read(wrap(`<g color="red"><rect width="3" height="3" fill="currentColor"/></g>
	  <rect width="3" height="3" display="none"/><rect width="3" height="3" visibility="hidden"/>
	  <g display="none"><rect width="3" height="3"/></g>`))
	defer svg_destroy(&d)
	if !testing.expect_value(t, len(d.items), 1) {return}
	testing.expect_value(t, d.items[0].fill, [4]f32{255, 0, 0, 255})
}

@(test)
test_circles_ellipses_lines_polylines_and_polygons :: proc(t: ^testing.T) {
	d, _ := read(wrap(`<circle cx="20" cy="20" r="5"/><ellipse cx="50" cy="20" rx="8" ry="4"/>
	  <line x1="0" y1="0" x2="10" y2="10" stroke="black"/><polyline points="0,0 5,5 10,0" fill="none" stroke="black"/>
	  <polygon points="0 0 10 0 5 8"/>`))
	defer svg_destroy(&d)
	if !testing.expect_value(t, len(d.items), 5) {return}
	lo, hi := bounds_of(d.items[0])
	testing.expect(t, abs(lo.x - 15) < 1e-3 && abs(hi.x - 25) < 1e-3 && abs(lo.y - 15) < 1e-3 && abs(hi.y - 25) < 1e-3)
	lo, hi = bounds_of(d.items[1])
	testing.expect(t, abs(hi.x - lo.x - 16) < 1e-3 && abs(hi.y - lo.y - 8) < 1e-3)
	testing.expect(t, !d.items[2].fill_on && d.items[2].stroke_on, "a line has no inside")
	testing.expect(t, !d.items[3].contours[0].closed)
	testing.expect(t, d.items[4].contours[0].closed)
}

@(test)
test_a_rounded_rectangle_is_cut_at_its_corners :: proc(t: ^testing.T) {
	d, _ := read(wrap(`<rect x="0" y="0" width="40" height="20" rx="5"/>`))
	defer svg_destroy(&d)
	if !testing.expect_value(t, len(d.items), 1) {return}
	testing.expect(t, len(d.items[0].contours[0].points) > 12, "the corners are arcs")
	lo, hi := bounds_of(d.items[0])
	testing.expect_value(t, lo, [2]f32{0, 0})
	testing.expect_value(t, hi, [2]f32{40, 20})
}

@(test)
test_the_view_box_gives_the_size_and_moves_the_origin :: proc(t: ^testing.T) {
	d, _ := read(wrap(`<rect x="10" y="20" width="5" height="5"/>`, `viewBox="10 20 30 40" width="300" height="400"`))
	defer svg_destroy(&d)
	testing.expect_value(t, [2]f32{d.width, d.height}, [2]f32{30, 40})
	lo, _ := bounds_of(d.items[0])
	testing.expect_value(t, lo, [2]f32{0, 0})
	d2, _ := read(wrap(`<rect width="5" height="5"/>`, `width="300px" height="12pt"`))
	defer svg_destroy(&d2)
	testing.expect_value(t, [2]f32{d2.width, d2.height}, [2]f32{300, 16})
	d3, _ := read(wrap(`<rect width="5" height="5"/>`, ""))
	defer svg_destroy(&d3)
	testing.expect_value(t, [2]f32{d3.width, d3.height}, [2]f32{5, 5}) // the box round what is drawn
}

@(test)
test_a_use_draws_what_it_names_moved_by_its_x_and_y :: proc(t: ^testing.T) {
	d, _ := read(wrap(`<defs><rect id="r" width="4" height="4" fill="red"/><symbol id="s"><circle cx="2" cy="2" r="2"/></symbol></defs>
	  <use href="#r" x="10" y="10"/><use xlink:href="#r" transform="translate(30 0)"/><use href="#s" x="50"/><use href="#missing"/>`))
	defer svg_destroy(&d)
	if !testing.expect_value(t, len(d.items), 3) {return}
	lo, _ := bounds_of(d.items[0])
	testing.expect_value(t, lo, [2]f32{10, 10})
	lo, _ = bounds_of(d.items[1])
	testing.expect_value(t, lo, [2]f32{30, 0})
	lo, _ = bounds_of(d.items[2])
	testing.expect(t, abs(lo.x - 50) < 1e-3)
}

@(test)
test_a_use_that_names_itself_does_not_run_for_ever :: proc(t: ^testing.T) {
	d, _ := read(wrap(`<g id="g"><rect width="4" height="4"/><use href="#g"/></g>`))
	defer svg_destroy(&d)
	testing.expect(t, len(d.items) >= 1 && len(d.items) < 1000)
}

@(test)
test_a_gradient_is_its_first_color_and_what_cannot_be_drawn_is_counted :: proc(t: ^testing.T) {
	d, _ := read(wrap(`<defs><linearGradient id="g"><stop offset="0" stop-color="#102030"/><stop offset="1" stop-color="red"/></linearGradient>
	  <linearGradient id="h" href="#g"/><pattern id="p"/></defs>
	  <rect width="5" height="5" fill="url(#g)"/><rect width="5" height="5" fill="url(#h)"/><rect width="5" height="5" fill="url(#p)" stroke="black"/>
	  <text x="0" y="5">hello</text><image href="x.png"/><rect width="5" height="5" clip-path="url(#c)" filter="url(#f)" mask="url(#m)" marker-end="url(#e)"/>`))
	defer svg_destroy(&d)
	testing.expect_value(t, d.items[0].fill, [4]f32{16, 32, 48, 255})
	testing.expect_value(t, d.items[1].fill, [4]f32{16, 32, 48, 255}) // a gradient that borrows another's stops
	testing.expect(t, !d.items[2].fill_on, "a pattern is not drawn")
	testing.expect_value(t, d.lost, bit_set[Svg_Lost]{.Gradient, .Pattern, .Text, .Picture, .Clip, .Mask, .Filter, .Marker})
}

@(test)
test_files_that_are_not_svg_and_svg_with_nothing_to_draw :: proc(t: ^testing.T) {
	for text in ([?]string{"", "hello", "<html><body/></html>", "<svg", `<?xml version="1.0"?><png/>`} ) {
		d, err := read(text)
		testing.expectf(t, err == .Not_Svg, "%q is not svg, got %v", text, err)
		svg_destroy(&d)
	}
	d, err := read(wrap(""))
	testing.expect_value(t, err, Svg_Error.Empty)
	svg_destroy(&d)
	testing.expect(t, len(svg_error_words(.Not_Svg)) > 0 && len(svg_error_words(.Empty)) > 0 && svg_error_words(.None) == "")
}

@(test)
test_a_mistake_in_a_path_keeps_what_was_read_before_it :: proc(t: ^testing.T) {
	d, _ := read(wrap(`<path d="M0 0 L10 0 L10 10 X 5 5 L0 10"/>`))
	defer svg_destroy(&d)
	if !testing.expect_value(t, len(d.items), 1) {return}
	testing.expect_value(t, len(d.items[0].contours[0].points), 3)
}

@(test)
test_entities_comments_cdata_and_namespaces_are_read :: proc(t: ^testing.T) {
	d, _ := read(`<?xml version="1.0" encoding="UTF-8"?><!-- a comment --><svg:svg xmlns:svg="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
	  <svg:style><![CDATA[ .k { fill: #112233 } ]]></svg:style><svg:rect class="k" width="4" height="4"/></svg:svg>`)
	defer svg_destroy(&d)
	if !testing.expect_value(t, len(d.items), 1) {return}
	testing.expect_value(t, d.items[0].fill, [4]f32{17, 34, 51, 255})
}

@(test)
test_drawing_a_drawing_records_one_path_for_each_item_under_a_transform_and_leaves_the_style_alone :: proc(t: ^testing.T) {
	d, _ := read(wrap(`<rect width="10" height="10" fill="red" stroke="blue" stroke-width="2" stroke-linecap="round" stroke-linejoin="bevel"/><circle cx="5" cy="5" r="2" fill="none" stroke="green"/>`, `viewBox="0 0 10 10"`))
	defer svg_destroy(&d)
	list := fresh()
	defer destroy(&list)
	set_fill(&list, {1, 2, 3, 255})
	svg_draw(&list, &d, 100, 50, 200, 40)
	if !testing.expect_value(t, len(list.commands), 2) {return}
	first := command_at(&list, 0)
	testing.expect_value(t, first.kind, Kind.Path)
	testing.expect_value(t, first.style.fill, [4]f32{255, 0, 0, 255})
	testing.expect_value(t, first.style.thickness, 2)
	testing.expect_value(t, first.style.cap, geom.Cap.Round)
	testing.expect_value(t, first.style.join, geom.Join.Bevel)
	testing.expect(t, first.style.stroke_on)
	// 10 units across are 200 pixels: a scale of 20 across and 4 down, moved to 100, 50
	x, y := transform_apply(first.transform, 10, 10)
	testing.expect_value(t, [2]f32{x, y}, [2]f32{300, 90})
	second := command_at(&list, 1)
	testing.expect(t, !second.style.fill_on && second.style.stroke_on)
	// the sketch's own style and transform are back
	testing.expect_value(t, list.style.fill, [4]f32{1, 2, 3, 255})
	testing.expect_value(t, list.transform, IDENTITY)
}

@(test)
test_drawing_an_empty_drawing_or_at_no_size_draws_nothing :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	empty: Svg_Drawing
	svg_draw(&list, &empty, 0, 0, 10, 10)
	d, _ := read(wrap(`<rect width="5" height="5"/>`))
	defer svg_destroy(&d)
	svg_draw(&list, &d, math.inf_f32(1), 0, 10, 10)
	testing.expect_value(t, len(list.commands), 0)
}
