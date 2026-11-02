// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "../gfx"
import "../lang"
import "core:os"
import "core:testing"

typeset_commands :: proc() -> [dynamic]gfx.Command {
	found: [dynamic]gfx.Command
	for c in roci.recorded(first_window()) {
		if c.kind == .Typeset {
			append(&found, c)
		}
	}
	return found
}

@(test)
test_text_draws_real_text_at_its_point :: proc(t: ^testing.T) {
	p := run_text(t, "text \"hello\" at 20 30")
	defer finish(p)
	found := typeset_commands()
	defer delete(found)
	if testing.expect_value(t, len(found), 1) {
		testing.expect_value(t, [2]f32{found[0].args[0], found[0].args[1]}, [2]f32{20, 30})
		testing.expect(t, found[0].args[3] > 0, "it has a width")
	}
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_text_words_style_one_text_and_font_and_align_stick :: proc(t: ^testing.T) {
	p := run_text(t, "text \"a\" at 1 1 size 50 font \"Inter Bold\" align right fill red\nfont \"Inter Bold\" size 33\nalign center\ntext \"b\" at 2 2")
	defer finish(p)
	found := typeset_commands()
	defer delete(found)
	if testing.expect_value(t, len(found), 2) {
		testing.expect_value(t, found[0].style.font_size, f32(50))
		testing.expect_value(t, found[0].style.align, gfx.Align.Right)
		testing.expect_value(t, found[0].style.font, gfx.FACE_BOLD)
		testing.expect_value(t, found[1].style.font_size, f32(33))
		testing.expect_value(t, found[1].style.align, gfx.Align.Center)
	}
}

@(test)
test_a_width_wraps_the_text :: proc(t: ^testing.T) {
	p := run_text(t, "text \"a long line that has to wrap\" at 0 0 width 70")
	defer finish(p)
	found := typeset_commands()
	defer delete(found)
	if testing.expect_value(t, len(found), 1) {
		testing.expect_value(t, found[0].args[2], f32(70))
	}
}

@(test)
test_text_at_a_vector_and_text_made_from_a_calculation :: proc(t: ^testing.T) {
	p := run_text(t, "p = { 5, 6 }\nn = 3\ntext (\"n is \" + n) at p")
	defer finish(p)
	found := typeset_commands()
	defer delete(found)
	if testing.expect_value(t, len(found), 1) {
		testing.expect_value(t, [2]f32{found[0].args[0], found[0].args[1]}, [2]f32{5, 6})
	}
}

@(test)
test_measure_gives_a_vector_that_follows_the_font_size :: proc(t: ^testing.T) {
	expect_printed(t, "a = measure \"hello\"\nfont \"Inter\" size 80\nb = measure \"hello\"\nprint (a.x > 0)\nprint (b.x > a.x * 2)\nprint (b.y > a.y)", "true\ntrue\ntrue")
}

@(test)
test_an_unknown_font_is_said_once_and_the_text_still_draws :: proc(t: ^testing.T) {
	p := run_text(t, "font \"No Such Font\"\ntext \"x\" at 1 1 font \"Nor This\"\ntext \"y\" at 2 2 font \"Nor This\"")
	defer finish(p)
	testing.expect_value(t, len(p.errors), 3)
	for e in p.errors {
		testing.expect_value(t, e.id, lang.Message_Id.Font_Missing)
	}
	found := typeset_commands()
	defer delete(found)
	testing.expect_value(t, len(found), 2)
}

@(test)
test_a_font_file_in_the_sketchs_assets_is_found_by_name :: proc(t: ^testing.T) {
	root := "output/tests/font_sketch"
	_ = os.make_directory_all("output/tests/font_sketch/assets/fonts")
	testing.expect(t, os.write_entire_file("output/tests/font_sketch/assets/fonts/Mine.ttf", gfx.INTER_REGULAR) == nil)
	testing.expect(t, os.write_entire_file("output/tests/font_sketch/assets/fonts/Other.otf", gfx.INTER_BOLD) == nil)
	testing.expect(t, os.write_entire_file("output/tests/font_sketch/assets/fonts/Broken.ttf", transmute([]byte)string("not a font")) == nil)
	path := "output/tests/font_sketch/sketch.roci"
	text := "font \"Mine\"\ntext \"a\" at 1 1\nfont \"Other.otf\" size 22\ntext \"b\" at 2 2\nfont \"Broken\"\n"
	testing.expect(t, os.write_entire_file(path, transmute([]byte)text) == nil)
	_ = root
	p, ok := load(path, text)
	testing.expect(t, ok)
	roci.start_headless(1)
	watch(p, path)
	start(p)
	defer finish_all()
	testing.expect(t, roci.has_font("Mine"))
	testing.expect(t, roci.has_font("Other.otf"))
	testing.expect(t, !roci.has_font("Broken"), "bytes that are not a font are not a font")
	testing.expect_value(t, len(p.errors), 1)
	testing.expect_value(t, p.errors[0].id, lang.Message_Id.Font_Missing)
}
