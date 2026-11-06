// SPDX-License-Identifier: 0BSD
package gfx

import "../maths"
import "core:bytes"
import "core:compress/zlib"
import "core:strconv"
import "core:strings"
import "core:testing"

pdf_of :: proc(list: ^Command_List, width := 200, height := 100) -> (pdf: []u8, notes: []string) {
	return pdf_write(list, width, height, context.temp_allocator)
}

// The text of the object `id`: from "id 0 obj" to "endobj".
pdf_object :: proc(pdf: []u8, id: int) -> string {
	text := string(pdf)
	marker := strings.concatenate({"\n", itoa(id), " 0 obj\n"}, context.temp_allocator)
	start := strings.index(text, marker)
	if start < 0 {
		return ""
	}
	start += len(marker)
	end := strings.index(text[start:], "\nendobj")
	return text[start:start + end] if end >= 0 else ""
}

// What a stream object holds once inflated.
pdf_stream :: proc(pdf: []u8, id: int) -> string {
	body := pdf_object(pdf, id)
	open := strings.index(body, "stream\n")
	if open < 0 {
		return ""
	}
	data := body[open + 7:]
	data = data[:strings.last_index(data, "\nendstream")]
	buf: bytes.Buffer
	if zlib.inflate_from_byte_array(transmute([]u8)data, &buf) != nil {
		return ""
	}
	return string(buf.buf[:])
}

pdf_page_content :: proc(pdf: []u8) -> string {
	return pdf_stream(pdf, 4)
}

@(test)
a_pdf_has_its_header_its_page_the_size_of_the_window_and_an_end :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	pdf, notes := pdf_of(&list, 200, 100)
	text := string(pdf)
	testing.expect(t, strings.has_prefix(text, "%PDF-1.4\n"))
	testing.expect(t, strings.has_suffix(text, "%%EOF\n"))
	testing.expect(t, strings.contains(pdf_object(pdf, 1), "/Type /Catalog"))
	testing.expect(t, strings.contains(pdf_object(pdf, 3), "/MediaBox [0 0 200 100]"))
	testing.expect_value(t, len(notes), 0)
}

@(test)
the_cross_reference_table_points_at_every_object :: proc(t: ^testing.T) {
	defer images_stop()
	id, _ := image_add_pixels(1, 1, []u8{1, 2, 3, 128})
	list := fresh()
	defer destroy(&list)
	g, _ := gradient_make({maths.rgb(255, 0, 0), maths.rgb(0, 0, 255)}, .Linear, 0)
	set_fill_gradient(&list, g)
	rect(&list, 0, 0, 50, 50)
	draw_image(&list, id, 0, 0, 10, 10)
	set_alpha(&list, 100)
	circle(&list, 5, 5, 5)
	pdf, _ := pdf_of(&list)
	text := string(pdf)
	xref := strings.index(text, "\nxref\n") + 1
	testing.expect(t, xref > 0)
	// "xref", "0 N", then N lines of 20 bytes
	lines := strings.split_lines(text[xref:], context.temp_allocator)
	count, _ := strconv.parse_int(strings.trim_prefix(lines[1], "0 "))
	testing.expect(t, count > 8)
	testing.expect_value(t, lines[2], "0000000000 65535 f ")
	for n in 1 ..< count {
		entry := lines[2 + n]
		testing.expect_value(t, len(entry) + 1, 20)
		offset, ok := strconv.parse_int(entry[:10])
		testing.expect(t, ok)
		want := strings.concatenate({itoa(n), " 0 obj\n"}, context.temp_allocator)
		testing.expectf(t, strings.has_prefix(text[offset:], want), "object %d is not at %d", n, offset)
	}
	// startxref names the table
	tail := text[strings.last_index(text, "startxref\n") + 10:]
	pointed, _ := strconv.parse_int(tail[:strings.index_byte(tail, '\n')])
	testing.expect_value(t, pointed, xref)
}

@(test)
the_page_is_turned_so_y_points_down_and_a_shape_is_a_path :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_fill(&list, maths.rgb(255, 0, 0))
	rect(&list, 10, 20, 30, 40)
	pdf, _ := pdf_of(&list)
	content := pdf_page_content(pdf)
	testing.expect(t, strings.has_prefix(content, "1 0 0 -1 0 100 cm\n"), content)
	testing.expect(t, strings.contains(content, "1 0 0 rg\n10 20 30 40 re\nf\n"), content)
	testing.expect(t, strings.contains(content, "q\n"))
}

@(test)
the_background_is_painted_first_and_one_with_no_alpha_is_not :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	background(&list, maths.rgb(0, 0, 255))
	circle(&list, 5, 5, 5)
	pdf, _ := pdf_of(&list)
	content := pdf_page_content(pdf)
	testing.expect(t, strings.index(content, "0 0 1 rg") < strings.index(content, " c\n"), content)
	testing.expect(t, strings.contains(content, "0 0 200 100 re\nf\n"), content)
	background(&list, maths.Colour{0, 0, 255, 0})
	pdf, _ = pdf_of(&list)
	testing.expect(t, !strings.contains(pdf_page_content(pdf), "0 0 200 100 re"))
}

@(test)
a_circle_is_four_curves_and_an_outline_has_width_caps_and_joins :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_stroke(&list, maths.rgb(0, 255, 0))
	set_thickness(&list, 3)
	set_caps(&list, .Square)
	set_joins(&list, .Bevel)
	circle(&list, 50, 40, 20)
	pdf, _ := pdf_of(&list)
	content := pdf_page_content(pdf)
	testing.expect_value(t, strings.count(content, " c\n"), 4)
	testing.expect(t, strings.contains(content, "0 1 0 RG\n3 w 2 J 2 j\n"), content)
	testing.expect(t, strings.contains(content, "70 40 m\n"), content)
	testing.expect(t, strings.contains(content, "h\nB\n"), content)
}

@(test)
fill_only_stroke_only_and_both_end_a_path_differently :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	rect(&list, 0, 0, 5, 5) // fill
	no_fill(&list)
	set_stroke(&list, maths.rgb(0, 0, 0))
	rect(&list, 0, 0, 6, 6) // stroke
	set_fill(&list, maths.rgb(1, 1, 1))
	rect(&list, 0, 0, 7, 7) // both
	pdf, _ := pdf_of(&list)
	content := pdf_page_content(pdf)
	testing.expect(t, strings.contains(content, "5 5 re\nf\n"), content)
	testing.expect(t, strings.contains(content, "6 6 re\nS\n"), content)
	testing.expect(t, strings.contains(content, "7 7 re\nB\n"), content)
}

@(test)
a_transform_is_a_cm_before_the_path_and_the_identity_is_not_written :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	rect(&list, 0, 0, 5, 5)
	move(&list, 10, 20)
	rect(&list, 0, 0, 5, 5)
	pdf, _ := pdf_of(&list)
	content := pdf_page_content(pdf)
	testing.expect_value(t, strings.count(content, " cm\n"), 2) // the page turn and the one move
	testing.expect(t, strings.contains(content, "1 0 0 1 10 20 cm\n0 0 5 5 re"), content)
}

@(test)
lines_points_and_polygons_are_drawn_by_their_own_path :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_stroke(&list, maths.rgb(0, 0, 0))
	set_thickness(&list, 4)
	line(&list, 1, 2, 3, 4)
	point(&list, 9, 9)
	triangle(&list, 0, 0, 10, 0, 5, 8)
	pdf, _ := pdf_of(&list)
	content := pdf_page_content(pdf)
	testing.expect(t, strings.contains(content, "1 2 m\n3 4 l\nS\n"), content)
	testing.expect(t, strings.contains(content, "0 0 m\n10 0 l\n5 8 l\nh\nB\n"), content)
	// the point is a dot filled in the stroke's color, 4 wide: a circle of radius 2
	testing.expect(t, strings.contains(content, "11 9 m\n"), content)
}

@(test)
a_pdf_arc_is_a_pie_for_the_fill_and_the_curve_for_the_outline :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_stroke(&list, maths.rgb(0, 0, 0))
	arc(&list, 50, 50, 40, 40, 0, 90)
	pdf, _ := pdf_of(&list)
	content := pdf_page_content(pdf)
	// the pie goes to the middle first and the curve alone for the outline starts at the right
	testing.expect(t, strings.contains(content, "50 50 m\n70 50 l\n"), content)
	testing.expect(t, strings.contains(content, "h f\n"), content)
	testing.expect_value(t, strings.count(content, "70 50 m\n"), 1)
	testing.expect_value(t, strings.count(content, " c\n"), 2) // one curve each
	testing.expect(t, strings.contains(content, "\nS\n"), content)
}

@(test)
a_whole_turn_of_an_arc_is_four_curves_closed_and_an_empty_one_is_nothing :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	arc(&list, 50, 50, 40, 40, 0, 360)
	arc(&list, 50, 50, 40, 40, 30, 30)
	pdf, _ := pdf_of(&list)
	content := pdf_page_content(pdf)
	testing.expect_value(t, strings.count(content, " c\n"), 4)
	testing.expect(t, !strings.contains(content, "50 50 m"), content)
}

@(test)
alpha_is_a_graphics_state_shared_by_shapes_that_have_it :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_alpha(&list, 127.5)
	circle(&list, 5, 5, 5)
	circle(&list, 15, 5, 5)
	set_alpha(&list, 255)
	circle(&list, 25, 5, 5)
	pdf, _ := pdf_of(&list)
	content := pdf_page_content(pdf)
	testing.expect_value(t, strings.count(content, "/G1 gs"), 2)
	testing.expect(t, !strings.contains(content, "/G2"), content)
	testing.expect(t, strings.contains(pdf_object(pdf, 3), "/ExtGState << /G1 "), pdf_object(pdf, 3))
	state := pdf_object(pdf, 5)
	testing.expect(t, strings.contains(state, "/ca 0.5 /CA 0.5"), state)
}

@(test)
a_blend_is_a_blend_mode_and_add_and_subtract_are_said :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_blend(&list, .Multiply)
	circle(&list, 5, 5, 5)
	pdf, notes := pdf_of(&list)
	testing.expect(t, strings.contains(pdf_object(pdf, 5), "/BM /Multiply"))
	testing.expect_value(t, len(notes), 0)
	set_blend(&list, .Add)
	circle(&list, 5, 5, 5)
	set_blend(&list, .Subtract)
	circle(&list, 5, 5, 5)
	_, notes = pdf_of(&list)
	testing.expect_value(t, len(notes), 2)
}

@(test)
a_clip_is_a_clip_path_inside_the_saved_state :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_clip(&list, 10, 20, 30, 40)
	circle(&list, 20, 30, 5)
	no_clip(&list)
	circle(&list, 20, 30, 5)
	pdf, _ := pdf_of(&list)
	content := pdf_page_content(pdf)
	testing.expect_value(t, strings.count(content, "W n"), 1)
	testing.expect(t, strings.contains(content, "q\n10 20 30 40 re\nW n\n"), content)
}

@(test)
a_linear_gradient_is_a_shading_pattern_in_the_pages_own_space :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	g, _ := gradient_make({maths.rgb(255, 0, 0), maths.rgb(0, 0, 255)}, .Linear, 0)
	set_fill_gradient(&list, g)
	rect(&list, 0, 0, 100, 50)
	pdf, notes := pdf_of(&list)
	content := pdf_page_content(pdf)
	testing.expect(t, strings.contains(content, "/Pattern cs /P1 scn\n"), content)
	testing.expect(t, strings.contains(pdf_object(pdf, 3), "/Pattern << /P1 "), pdf_object(pdf, 3))
	// object 5 is the function, 6 the pattern
	pattern := pdf_object(pdf, 6)
	testing.expect(t, strings.contains(pattern, "/PatternType 2 /Matrix [1 0 0 -1 0 100]"), pattern)
	testing.expect(t, strings.contains(pattern, "/ShadingType 2"), pattern)
	testing.expect(t, strings.contains(pattern, "/Coords [0 25 100 25]"), pattern)
	testing.expect(t, strings.contains(pattern, "/Extend [true true]"), pattern)
	function := pdf_object(pdf, 5)
	testing.expect(t, strings.contains(function, "/FunctionType 0"), function)
	testing.expect_value(t, len(notes), 0)
	// the colors: 33 samples from red to blue
	samples := pdf_stream(pdf, 5)
	testing.expect_value(t, len(samples), 99)
	testing.expect_value(t, [3]u8{samples[0], samples[1], samples[2]}, [3]u8{255, 0, 0})
	testing.expect_value(t, [3]u8{samples[96], samples[97], samples[98]}, [3]u8{0, 0, 255})
}

@(test)
a_radial_gradient_is_stretched_over_the_box_and_a_stroke_can_have_one_too :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	g, _ := gradient_make({maths.rgb(255, 255, 255), maths.rgb(0, 0, 0)}, .Radial, 0, centre = {50, 50})
	set_stroke_gradient(&list, g)
	set_thickness(&list, 2)
	no_fill(&list)
	circle(&list, 50, 40, 20)
	pdf, _ := pdf_of(&list)
	content := pdf_page_content(pdf)
	testing.expect(t, strings.contains(content, "/Pattern CS /P1 SCN\n"), content)
	pattern := pdf_object(pdf, 6)
	testing.expect(t, strings.contains(pattern, "/ShadingType 3"), pattern)
	testing.expect(t, strings.contains(pattern, "/Coords [0 0 0 0 0 1]"), pattern)
	// a circle of radius 1 made the size of the box (20 each way) and put at its middle (50, 40)
	testing.expect(t, strings.contains(pattern, "/Matrix [20 0 0 -20 50 60]"), pattern)
}

@(test)
a_conic_gradient_and_a_picture_fill_and_effects_are_said :: proc(t: ^testing.T) {
	defer images_stop()
	photo, _ := image_add_pixels(1, 1, []u8{1, 2, 3, 255})
	list := fresh()
	defer destroy(&list)
	g, _ := gradient_make({maths.rgb(0, 0, 0), maths.rgb(255, 255, 255)}, .Conic, 0)
	set_fill_gradient(&list, g)
	circle(&list, 5, 5, 5)
	set_fill_image(&list, Image_Fill{image = photo})
	circle(&list, 5, 5, 5)
	append(&list.effects, Effect{})
	_, notes := pdf_of(&list)
	joined := strings.join(notes, "|", context.temp_allocator)
	testing.expect(t, strings.contains(joined, "conic"), joined)
	testing.expect(t, strings.contains(joined, "picture fill"), joined)
	testing.expect(t, strings.contains(joined, "effects"), joined)
}

@(test)
text_is_the_outlines_of_its_letters_and_names_no_font :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_fill(&list, maths.rgb(0, 0, 255))
	typeset(&list, "Hi", 10, 20)
	pdf, notes := pdf_of(&list)
	content := pdf_page_content(pdf)
	testing.expect(t, strings.contains(content, "0 0 1 rg\n"), content)
	testing.expect(t, strings.count(content, " m\n") >= 3, content) // H has one contour, i two
	testing.expect(t, strings.has_suffix(content, "h\nf\nQ\n"), content)
	testing.expect(t, !strings.contains(string(pdf), "/Font"))
	testing.expect_value(t, len(notes), 0)
}

@(test)
text_lines_follow_each_other_and_the_alignment_moves_a_line_by_its_width :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	typeset(&list, "a\na", 0, 0)
	pdf, _ := pdf_of(&list)
	content := pdf_page_content(pdf)
	// two copies of one glyph, the second a line lower (a larger y on the page)
	first := strings.index(content, " m\n")
	second := strings.index(content[first + 3:], " m\n")
	testing.expect(t, first > 0 && second > 0)
	left := fresh()
	defer destroy(&left)
	background(&left, maths.Colour{0, 0, 0, 0})
	set_align(&left, .Right)
	typeset(&left, "ab", 100, 0)
	right_pdf, _ := pdf_of(&left)
	left_content := pdf_page_content(right_pdf)
	// right aligned in 100 wide: the first point is well to the right of the left edge
	number_end := strings.index_byte(left_content[strings.index(left_content, "rg\n") + 3:], ' ')
	start := left_content[strings.index(left_content, "rg\n") + 3:]
	x, _ := strconv.parse_f32(start[:number_end])
	testing.expect(t, x > 60 && x < 100, start[:30])
}

@(test)
characters_the_font_does_not_have_are_said_and_drawn_as_nothing :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	typeset(&list, "a中", 0, 0)
	_, notes := pdf_of(&list)
	if testing.expect_value(t, len(notes), 1) {
		testing.expect(t, strings.contains(notes[0], "characters"))
	}
}

@(test)
a_picture_is_an_image_object_with_its_alpha_as_a_soft_mask_and_is_there_once :: proc(t: ^testing.T) {
	defer images_stop()
	id, _ := image_add_pixels(2, 1, []u8{255, 0, 0, 255, 0, 255, 0, 128})
	opaque, _ := image_add_pixels(1, 1, []u8{9, 9, 9, 255})
	list := fresh()
	defer destroy(&list)
	draw_image(&list, id, 10, 20, 40, 60)
	draw_image(&list, id, 100, 20, 20, 20)
	draw_image(&list, opaque, 0, 0, 5, 5)
	pdf, notes := pdf_of(&list)
	page := pdf_object(pdf, 3)
	testing.expect(t, strings.contains(page, "/XObject << /I1 "), page)
	testing.expect(t, strings.contains(page, "/I2 "), page)
	testing.expect(t, !strings.contains(page, "/I3 "), page)
	content := pdf_page_content(pdf)
	testing.expect_value(t, strings.count(content, "/I1 Do"), 2)
	// 40 wide, 60 high, at 10, 20: a unit square turned over
	testing.expect(t, strings.contains(content, "40 0 0 -60 10 80 cm\n/I1 Do"), content)
	// objects 5 and 6: the alpha and then the colors
	testing.expect(t, strings.contains(pdf_object(pdf, 5), "/ColorSpace /DeviceGray"), pdf_object(pdf, 5))
	colours := pdf_object(pdf, 6)
	testing.expect(t, strings.contains(colours, "/ColorSpace /DeviceRGB /SMask 5 0 R"), colours)
	testing.expect_value(t, len(pdf_stream(pdf, 6)), 6)
	testing.expect_value(t, pdf_stream(pdf, 5), "\xff\x80")
	// the picture with no alpha has no mask
	testing.expect(t, !strings.contains(pdf_object(pdf, 8), "SMask"), pdf_object(pdf, 8))
	testing.expect_value(t, len(notes), 0)
}

@(test)
a_canvas_and_a_tint_are_said :: proc(t: ^testing.T) {
	defer images_stop()
	canvas, _ := image_add_canvas(10, 10, 1)
	photo, _ := image_add_pixels(1, 1, []u8{1, 2, 3, 255})
	list := fresh()
	defer destroy(&list)
	draw_image(&list, canvas, 0, 0, 10, 10)
	set_tint(&list, maths.Colour{255, 0, 0, 255})
	draw_image(&list, photo, 0, 0, 10, 10)
	_, notes := pdf_of(&list)
	joined := strings.join(notes, "|", context.temp_allocator)
	testing.expect(t, strings.contains(joined, "canvas"), joined)
	testing.expect(t, strings.contains(joined, "tint"), joined)
}

@(test)
the_same_frame_gives_the_same_bytes :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	g, _ := gradient_make({maths.rgb(255, 0, 0), maths.rgb(0, 0, 255)}, .Linear, 30)
	set_fill_gradient(&list, g)
	circle(&list, 50, 40, 20)
	typeset(&list, "same", 5, 5)
	a, _ := pdf_of(&list)
	b, _ := pdf_of(&list)
	testing.expect(t, bytes.equal(a, b))
}

@(test)
pdf_shapes_that_show_nothing_are_left_out :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	no_fill(&list)
	circle(&list, 5, 5, 5)
	pdf, _ := pdf_of(&list)
	// only the background (the window's grey) is drawn
	testing.expect_value(t, strings.count(pdf_page_content(pdf), "q\n"), 1)
}
