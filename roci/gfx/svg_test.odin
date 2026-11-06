// SPDX-License-Identifier: 0BSD
package gfx

import "../maths"
import "core:strings"
import "core:testing"

svg_of :: proc(list: ^Command_List, width := 200, height := 100) -> (string, []string) {
	return svg_write(list, width, height, context.temp_allocator)
}

has :: proc(text, part: string) -> bool {
	return strings.contains(text, part)
}

@(test)
an_empty_frame_is_a_file_with_the_background_and_the_size_of_the_window :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	svg, notes := svg_of(&list)
	testing.expect(t, strings.has_prefix(svg, `<?xml version="1.0" encoding="UTF-8"?>`))
	testing.expect(t, has(svg, `width="200" height="100" viewBox="0 0 200 100"`))
	testing.expect(t, has(svg, `<rect width="200" height="100" fill="#e6e6e6"/>`), svg)
	testing.expect(t, strings.has_suffix(svg, "</svg>\n"))
	testing.expect_value(t, len(notes), 0)
}

@(test)
a_background_is_the_first_thing_and_a_clear_one_draws_nothing :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	background(&list, maths.rgb(255, 0, 0))
	circle(&list, 50, 50, 10)
	svg, _ := svg_of(&list)
	testing.expect(t, strings.index(svg, `fill="#ff0000"`) < strings.index(svg, "<circle"))
	// a background with no alpha shows the page behind the file
	background(&list, maths.Colour{1, 2, 3, 0})
	svg, _ = svg_of(&list)
	testing.expect(t, !has(svg, `<rect width="200"`))
}

@(test)
shapes_are_elements_with_their_numbers_and_colours :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_fill(&list, maths.rgb(255, 128, 0))
	circle(&list, 50, 40, 20)
	ellipse(&list, 100, 50, 60, 30)
	rect(&list, 10, 20, 30, 40)
	triangle(&list, 0, 0, 10, 0, 5, 8)
	quad(&list, 0, 0, 10, 0, 10, 10, 0, 10)
	svg, notes := svg_of(&list)
	testing.expect(t, has(svg, `<circle cx="50" cy="40" r="20" fill="#ff8000"/>`), svg)
	testing.expect(t, has(svg, `<ellipse cx="100" cy="50" rx="30" ry="15" fill="#ff8000"/>`), svg)
	testing.expect(t, has(svg, `<rect x="10" y="20" width="30" height="40" fill="#ff8000"/>`), svg)
	testing.expect(t, has(svg, `<polygon points="0,0 10,0 5,8" fill="#ff8000"/>`), svg)
	testing.expect(t, has(svg, `<polygon points="0,0 10,0 10,10 0,10" fill="#ff8000"/>`), svg)
	testing.expect_value(t, len(notes), 0)
}

@(test)
a_shape_drawn_from_its_corner_is_placed_by_its_corner :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	circle(&list, 50, 40, 10, .Corner)
	rect(&list, 100, 50, 20, 10, .Center)
	svg, _ := svg_of(&list)
	testing.expect(t, has(svg, `<circle cx="60" cy="50" r="10"`), svg)
	testing.expect(t, has(svg, `<rect x="90" y="45" width="20" height="10"`), svg)
}

@(test)
an_outline_has_its_width_caps_and_joins_and_a_shape_with_no_fill_says_so :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	no_fill(&list)
	set_stroke(&list, maths.rgb(0, 0, 255))
	set_thickness(&list, 3)
	set_caps(&list, .Square)
	set_joins(&list, .Bevel)
	rect(&list, 0, 0, 10, 10)
	svg, _ := svg_of(&list)
	testing.expect(t, has(svg, `fill="none" stroke="#0000ff" stroke-width="3" stroke-linecap="square" stroke-linejoin="bevel"`), svg)
}

@(test)
alpha_is_an_opacity_of_the_fill_and_of_the_outline :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_stroke(&list, maths.rgb(0, 0, 0))
	set_alpha(&list, 127.5)
	circle(&list, 10, 10, 5)
	svg, _ := svg_of(&list)
	testing.expect(t, has(svg, `fill-opacity="0.5"`), svg)
	testing.expect(t, has(svg, `stroke-opacity="0.5"`), svg)
}

@(test)
a_transform_goes_with_the_element_and_the_identity_does_not :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	circle(&list, 1, 1, 1)
	move(&list, 10, 20)
	circle(&list, 1, 1, 1)
	svg, _ := svg_of(&list)
	testing.expect_value(t, strings.count(svg, "transform="), 1)
	testing.expect(t, has(svg, `transform="matrix(1 0 0 1 10 20)"`), svg)
}

@(test)
a_line_and_a_point_are_lines_and_an_outline_is_needed_to_see_them :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	line(&list, 0, 0, 10, 5) // no stroke: not drawn
	set_stroke(&list, maths.rgb(0, 0, 0))
	line(&list, 0, 0, 10, 5)
	point(&list, 4, 4)
	svg, _ := svg_of(&list)
	testing.expect_value(t, strings.count(svg, "<line"), 2)
	testing.expect(t, has(svg, `<line x1="0" y1="0" x2="10" y2="5" fill="none"`), svg)
	testing.expect(t, has(svg, `<line x1="4" y1="4" x2="4" y2="4" fill="none"`), svg)
}

@(test)
an_arc_is_a_pie_for_the_fill_and_the_curve_for_the_outline :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_stroke(&list, maths.rgb(0, 0, 0))
	arc(&list, 50, 50, 40, 40, 0, 90)
	svg, _ := svg_of(&list)
	testing.expect_value(t, strings.count(svg, "<path"), 2)
	// from the right (70, 50) a quarter turn clockwise on the screen to the bottom (50, 70)
	testing.expect(t, has(svg, `<path d="M70 50 A20 20 0 0 1 50 70 L50 50 Z"`), svg)
	testing.expect(t, has(svg, `<path d="M70 50 A20 20 0 0 1 50 70" fill="none"`), svg)
}

@(test)
an_arc_over_half_a_turn_takes_the_long_way_and_a_whole_turn_closes_on_itself :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	arc(&list, 50, 50, 40, 40, 0, 270)
	arc(&list, 50, 50, 40, 40, 0, 360)
	arc(&list, 50, 50, 40, 40, 350, 10) // the short way, across the right side
	arc(&list, 50, 50, 40, 40, 20, 20) // nothing
	svg, _ := svg_of(&list)
	testing.expect(t, has(svg, `A20 20 0 1 1 50 30 L50 50 Z`), svg)
	testing.expect(t, has(svg, `M70 50 A20 20 0 1 1 30 50 A20 20 0 1 1 70 50 Z`), svg)
	testing.expect_value(t, strings.count(svg, "<path"), 3)
}

@(test)
a_linear_gradient_reaches_the_same_places_as_the_shader :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	g, _ := gradient_make({maths.rgb(255, 0, 0), maths.rgb(0, 0, 255)}, .Linear, 0)
	set_fill_gradient(&list, g)
	rect(&list, 0, 0, 100, 50)
	svg, notes := svg_of(&list)
	// left to right along the middle of the box
	testing.expect(t, has(svg, `<linearGradient id="g1" gradientUnits="userSpaceOnUse" x1="0" y1="25" x2="100" y2="25">`), svg)
	testing.expect(t, has(svg, `<stop offset="0" stop-color="#ff0000"/>`), svg)
	testing.expect(t, has(svg, `<stop offset="1" stop-color="#0000ff"/>`), svg)
	testing.expect_value(t, strings.count(svg, "<stop"), 33)
	testing.expect(t, has(svg, `fill="url(#g1)"`), svg)
	testing.expect_value(t, len(notes), 0)
}

@(test)
a_gradient_at_ninety_degrees_runs_down_and_is_as_long_as_the_corners_need :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	g, _ := gradient_make({maths.rgb(255, 0, 0), maths.rgb(0, 0, 255)}, .Linear, 90)
	set_fill_gradient(&list, g)
	rect(&list, 0, 0, 100, 50)
	svg, _ := svg_of(&list)
	testing.expect(t, has(svg, `x1="50" y1="0" x2="50" y2="50"`), svg)
}

@(test)
a_radial_gradient_is_centred_on_its_centre_and_reaches_the_box_edge :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	g, _ := gradient_make({maths.rgb(255, 255, 255), maths.rgb(0, 0, 0)}, .Radial, 0, centre = {30, 40})
	set_fill_gradient(&list, g)
	circle(&list, 50, 50, 20)
	svg, _ := svg_of(&list)
	testing.expect(t, has(svg, `<radialGradient id="g1" gradientUnits="objectBoundingBox" cx="0.3" cy="0.4" r="0.5">`), svg)
}

@(test)
a_conic_gradient_is_drawn_in_its_middle_color_and_said :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	g, _ := gradient_make({maths.rgb(0, 0, 0), maths.rgb(255, 255, 255)}, .Conic, 0, .Oklab)
	set_fill_gradient(&list, g)
	circle(&list, 50, 50, 20)
	svg, notes := svg_of(&list)
	testing.expect(t, !has(svg, "Gradient"), svg)
	testing.expect_value(t, len(notes), 1)
	testing.expect(t, has(notes[0], "conic"))
}

@(test)
a_gradient_in_the_background_covers_the_window :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	g, _ := gradient_make({maths.rgb(255, 0, 0), maths.rgb(0, 0, 255)}, .Linear, 0)
	background_gradient(&list, g)
	svg, _ := svg_of(&list)
	testing.expect(t, has(svg, `x1="0" y1="50" x2="200" y2="50"`), svg)
	testing.expect(t, has(svg, `<rect width="200" height="100" fill="url(#g1)"/>`), svg)
}

@(test)
a_clip_and_a_blend_are_a_group_round_the_shape :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_clip(&list, 10, 20, 30, 40)
	set_blend(&list, .Multiply)
	circle(&list, 20, 30, 5)
	no_clip(&list)
	set_blend(&list, .Normal)
	circle(&list, 20, 30, 5)
	svg, notes := svg_of(&list)
	testing.expect(t, has(svg, `<clipPath id="c1"><rect x="10" y="20" width="30" height="40"/></clipPath>`), svg)
	testing.expect(t, has(svg, `<g clip-path="url(#c1)" style="mix-blend-mode:multiply">`), svg)
	testing.expect_value(t, strings.count(svg, "<g "), 1)
	testing.expect_value(t, len(notes), 0)
}

@(test)
every_blend_has_a_css_name_and_subtract_is_said :: proc(t: ^testing.T) {
	names := [?]struct {
		mode: Blend_Mode,
		css:  string,
	}{{.Add, "plus-lighter"}, {.Screen, "screen"}, {.Lighten, "lighten"}}
	for n in names {
		list := fresh()
		set_blend(&list, n.mode)
		circle(&list, 5, 5, 5)
		svg, notes := svg_of(&list)
		testing.expect(t, has(svg, strings.concatenate({"mix-blend-mode:", n.css}, context.temp_allocator)), svg)
		testing.expect_value(t, len(notes), 0)
		destroy(&list)
	}
	list := fresh()
	defer destroy(&list)
	set_blend(&list, .Subtract)
	circle(&list, 5, 5, 5)
	_, notes := svg_of(&list)
	testing.expect_value(t, len(notes), 1)
	testing.expect(t, has(notes[0], "subtract"))
}

@(test)
text_is_a_text_element_with_a_line_for_each_line_and_its_characters_escaped :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_fill(&list, maths.rgb(0, 128, 0))
	typeset(&list, "a < b & \"c\"\nsecond", 10, 20)
	svg, notes := svg_of(&list)
	testing.expect(t, has(svg, `<text font-family="Inter, sans-serif" font-size="20" text-anchor="start" xml:space="preserve" fill="#008000">`), svg)
	testing.expect_value(t, strings.count(svg, "<tspan"), 2)
	testing.expect(t, has(svg, `a &lt; b &amp; &quot;c&quot;</tspan>`), svg)
	testing.expect(t, has(svg, `second</tspan>`), svg)
	testing.expect_value(t, len(notes), 0)
}

@(test)
text_is_anchored_by_its_alignment_and_a_bold_face_is_bold :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_font(&list, FACE_BOLD)
	set_align(&list, .Center)
	typeset(&list, "hi", 0, 0, 100)
	set_align(&list, .Right)
	typeset(&list, "hi", 0, 30, 100)
	svg, _ := svg_of(&list)
	testing.expect(t, has(svg, `font-weight="700" text-anchor="middle"`), svg)
	testing.expect(t, has(svg, `<tspan x="50"`), svg)
	testing.expect(t, has(svg, `text-anchor="end"`), svg)
	testing.expect(t, has(svg, `<tspan x="100"`), svg)
}

@(test)
a_wrapped_text_is_broken_into_lines_that_fit :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	text := "the quick brown fox jumps over the lazy dog"
	typeset(&list, text, 0, 0, 150)
	svg, _ := svg_of(&list)
	lines := strings.count(svg, "<tspan")
	testing.expect(t, lines > 1)
	// no line is longer than the width it was wrapped to
	rest := svg
	for {
		start := strings.index(rest, "<tspan")
		if start < 0 {
			break
		}
		rest = rest[start:]
		open := strings.index_byte(rest, '>')
		close := strings.index(rest, "</tspan>")
		w, _ := measure_typeset(FACE_DEFAULT, DEFAULT_FONT_SIZE, .Left, rest[open + 1:close])
		testing.expect(t, w <= 150)
		rest = rest[close:]
	}
}

@(test)
a_picture_is_embedded_once_and_placed_in_its_box :: proc(t: ^testing.T) {
	defer images_stop()
	pixels := []u8{255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255}
	id, _ := image_add_pixels(2, 2, pixels)
	list := fresh()
	defer destroy(&list)
	draw_image(&list, id, 10, 20, 40, 60)
	draw_image(&list, id, 100, 20, 20, 20)
	svg, notes := svg_of(&list)
	testing.expect_value(t, strings.count(svg, "<image "), 1)
	testing.expect(t, has(svg, `xlink:href="data:image/png;base64,iVBORw0KGgo`), svg)
	testing.expect_value(t, strings.count(svg, "<use "), 2)
	// 2 by 2 pixels into 40 by 60, at 10, 20
	testing.expect(t, has(svg, `transform="matrix(20 0 0 30 10 20)"`), svg)
	testing.expect_value(t, len(notes), 0)
}

@(test)
a_tint_keeps_only_its_alpha_and_says_so :: proc(t: ^testing.T) {
	defer images_stop()
	id, _ := image_add_pixels(1, 1, []u8{1, 2, 3, 255})
	list := fresh()
	defer destroy(&list)
	set_tint(&list, maths.Colour{255, 0, 0, 255})
	draw_image(&list, id, 0, 0, 10, 10)
	svg, notes := svg_of(&list)
	testing.expect(t, has(svg, "<use "))
	testing.expect_value(t, len(notes), 1)
	testing.expect(t, has(notes[0], "tint"))
}

@(test)
a_canvas_and_a_picture_fill_and_an_effect_are_said_not_drawn :: proc(t: ^testing.T) {
	defer images_stop()
	canvas, _ := image_add_canvas(10, 10, 1)
	photo, _ := image_add_pixels(1, 1, []u8{1, 2, 3, 255})
	list := fresh()
	defer destroy(&list)
	draw_image(&list, canvas, 0, 0, 10, 10)
	set_fill_image(&list, Image_Fill{image = photo})
	circle(&list, 30, 30, 10)
	append(&list.effects, Effect{})
	svg, notes := svg_of(&list)
	testing.expect(t, !has(svg, "<use "), svg)
	testing.expect_value(t, len(notes), 3)
	joined := strings.join(notes, "|", context.temp_allocator)
	testing.expect(t, has(joined, "canvas"))
	testing.expect(t, has(joined, "picture fill"))
	testing.expect(t, has(joined, "effects"))
}

@(test)
shapes_that_show_nothing_are_left_out :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	no_fill(&list)
	circle(&list, 5, 5, 5) // no fill and no outline
	set_alpha(&list, 0)
	set_fill(&list, maths.rgb(0, 0, 0))
	rect(&list, 0, 0, 5, 5) // fully see-through
	svg, _ := svg_of(&list)
	testing.expect(t, !has(svg, "<circle"), svg)
	testing.expect(t, !has(svg, "<rect x"), svg)
}

@(test)
numbers_are_short_and_never_negative_zero :: proc(t: ^testing.T) {
	b := strings.builder_make(context.temp_allocator)
	for v in ([?]f32{0, -0, 1, -1, 0.5, 1.2345678, 100, -0.0001, 2.50}) {
		number(&b, v)
		strings.write_byte(&b, ' ')
	}
	testing.expect_value(t, strings.to_string(b), "0 0 1 -1 0.5 1.235 100 0 2.5 ")
}
