// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "../folder"
import "../lang"
import "../platform"
import "core:os"
import "core:testing"

@(test)
test_a_picture_is_made_from_colours_and_pixel_reads_them_back :: proc(t: ^testing.T) {
	p := run_text(t, `p = picture from [ red green blue white ] size 2 2
print p.width
print p.height
c = pixel p at 1 0
print c.g
d = pixel p at { 0, 1 }
print d.b
e = pixel p at 5 5
print e.a
f = pixel p at 1.9 1.9
print f.r`)
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, printed(p), "2\n2\n128\n255\n0\n255")
}

@(test)
test_pixels_lists_every_colour_in_order :: proc(t: ^testing.T) {
	p := run_text(t, `p = picture from [ 10 20 30 40 50 60 ] size 3 2
colors = pixels p
print (count colors)
for each c in colors [ print c.r ]`)
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, printed(p), "6\n10\n20\n30\n40\n50\n60")
}

@(test)
test_crop_resize_filter_and_mask_make_new_pictures_of_the_right_size :: proc(t: ^testing.T) {
	p := run_text(t, `p = picture from [ red green blue white ] size 2 2
a = crop p at 1 0 size 1 2
print a.width
print a.height
b = resize p size 6 4
print b.width
print b.height
c = resize p size 8 0
print c.height
d = resize p size 0 6
print d.width
e = resize p size 4 4 as nearest
ge = pixel e at 3 0
print ge.g
stencil = picture from [ white black white black ] size 2 2
m = mask p by stencil
shown = pixel m at 0 0
gone_pixel = pixel m at 1 0
print gone_pixel.a
print shown.a
nothing = crop p at 10 10 size 3 3
print nothing.width
g = filter p as gray
print g.width`)
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, printed(p), "1\n2\n6\n4\n8\n6\n128\n0\n100\n0\n2")
}

@(test)
test_every_filter_word_works_and_by_changes_the_amount :: proc(t: ^testing.T) {
	p := run_text(t, `p = picture from [ #202020 #e0e0e0 ] size 2 1
learn red_of q x [
  c = pixel q at x 0
  give c.r
]
print (red_of (filter p as invert) 0)
print (red_of (filter p as gray) 0)
print (red_of (filter p as threshold) 0)
print (red_of (filter p as threshold by 10) 0)
print (red_of (filter p as posterize by 2) 1)
b = filter p as blur
print b.width
b5 = filter p as blur by 5
print b5.width
e = filter p as edges
print e.width
px = filter p as pixelate by 2
print px.width
print (red_of px 0)`)
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, printed(p), "223\n32\n0\n255\n255\n2\n2\n2\n2\n128")
}

@(test)
test_the_same_call_gives_the_same_picture_each_frame :: proc(t: ^testing.T) {
	p := run_text(t, `p = picture from [ red green ] size 2 1
draw [
  small = resize p size 20 10
  inverted = filter small as invert
  image inverted at 0 0
]`, 5)
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	found := drawn_commands()
	if testing.expect_value(t, len(found), 1) {
		testing.expect_value(t, [2]f32{found[0].args[2], found[0].args[3]}, [2]f32{20, 10})
	}
	// Five frames of the same two calls made two pictures, not ten.
	made := 0
	for _, _ in roci.derived_pictures() {
		made += 1
	}
	testing.expect_value(t, made, 3) // the colours, the resized one and the inverted one
}

@(test)
test_a_picture_of_a_size_it_cannot_be_is_empty_and_said :: proc(t: ^testing.T) {
	p := run_text(t, "a = picture from [ red ] size 0 5\nb = picture from [ red ] size 3 0\nc = picture from [ red ] size 20000 1\nd = resize a size 0 0\nprint a.width")
	defer finish(p)
	testing.expect_value(t, printed(p), "0")
	count := 0
	for e in p.errors {
		if e.id == .Picture_Size {
			count += 1
		}
	}
	testing.expect_value(t, count, 3) // a call said once for each place; `resize` of nothing is quiet
}

@(test)
test_a_picture_of_too_many_pixels_has_no_list :: proc(t: ^testing.T) {
	p := run_text(t, "big = picture from [ red ] size 1100 1000\ncolors = pixels big\nprint (count colors)")
	defer finish(p)
	testing.expect_value(t, printed(p), "0")
	if testing.expect_value(t, len(p.errors), 1) {
		testing.expect_value(t, p.errors[0].id, lang.Message_Id.Picture_Too_Big)
	}
}

@(test)
test_a_picture_that_is_not_there_gives_empty_answers_quietly :: proc(t: ^testing.T) {
	p := run_picture_sketch(t, "pixels_missing", `gone = load "nothing.png"
c = pixel gone at 0 0
print c.a
colors = pixels gone
print (count colors)
a = crop gone at 0 0 size 5 5
print a.width
b = resize gone size 5 5
print b.width
d = filter gone as gray
print d.width
e = mask gone by gone
print e.width`)
	defer finish(p)
	testing.expect_value(t, printed(p), "0\n0\n0\n0\n0\n0")
	for e in p.errors {
		testing.expect_value(t, e.id, lang.Message_Id.Image_Missing) // said once by load, nothing more
	}
}

@(test)
test_a_canvas_cannot_be_read_without_graphics_and_the_sketch_carries_on :: proc(t: ^testing.T) {
	roci.set_graphics_refused(true)
	defer roci.set_graphics_refused(false)
	p := run_text(t, "c = canvas 20 20\ncolor = pixel c at 1 1\nprint color.a\nsmall = crop c at 0 0 size 5 5\nprint small.width")
	defer finish(p)
	testing.expect_value(t, printed(p), "0\n0")
	found := 0
	for e in p.errors {
		if e.id == .Pixels_Unavailable {
			found += 1
		}
	}
	testing.expect_value(t, found, 2)
}

@(test)
test_the_pixels_example_looks_where_the_mouse_is_pressed :: proc(t: ^testing.T) {
	text, read := os.read_entire_file("examples/pixels/sketch.roci", context.temp_allocator)
	testing.expect(t, read == nil)
	p := run_example_with_assets(t, "pixels_example", string(text), "examples/pixels/assets/images/landscape.png")
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, as_pair(global_named(p, "spot")), [2]f64{192, 100})
	w := first_window()
	roci.step({platform.Mouse_Moved{window = platform.Window_Id(w), x = 100, y = 80}, click_event(w, 100, 80)})
	roci.step()
	testing.expect_value(t, as_pair(global_named(p, "spot")), [2]f64{80, 60})
	// Each frame crops the picture again around the spot, and the made pictures are not piling up
	// beyond the few of each frame.
	made := 0
	for _, _ in roci.derived_pictures() {
		made += 1
	}
	testing.expect(t, made <= 14, "a few pictures for each place looked at, plus the six filters")
}

// Runs a sketch in a folder whose assets hold a copy of the picture at `source`.
run_example_with_assets :: proc(t: ^testing.T, folder_name, text, source: string) -> ^Interp {
	root := concat("output/tests/", folder_name)
	_ = os.remove_all(root)
	testing.expect(t, folder.ensure_directory(concat(root, "/assets/images")))
	data, err := os.read_entire_file(source, context.temp_allocator)
	testing.expect(t, err == nil)
	testing.expect(t, os.write_entire_file(concat(root, "/assets/images/landscape.png"), data) == nil)
	path := concat(root, "/sketch.roci")
	testing.expect(t, os.write_entire_file(path, transmute([]byte)text) == nil)
	roci.start_headless(1)
	p, ok := load(path, text)
	if !testing.expectf(t, ok, "the sketch has errors:\n%s", lang.render_all(p.src, p.checked.diagnostics, context.temp_allocator)) {
		return p
	}
	watch(p, path)
	start(p)
	roci.step()
	roci.step()
	return p
}
