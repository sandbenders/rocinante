// SPDX-License-Identifier: 0BSD
package roci

import "core:testing"
import "gfx"

@(test)
test_text_records_real_text_in_the_current_font_size_and_alignment :: proc(t: ^testing.T) {
	begin()
	defer finish()
	testing.expect(t, font("Inter Bold", 30))
	align(.Center)
	text("hello", 100, 50)
	list := &the.windows[0].list
	testing.expect_value(t, len(list.commands), 1)
	c := gfx.command_at(list, 0)
	testing.expect_value(t, c.kind, gfx.Kind.Typeset)
	testing.expect_value(t, [2]f32{c.args[0], c.args[1]}, [2]f32{100, 50})
	testing.expect_value(t, c.style.font, gfx.FACE_BOLD)
	testing.expect_value(t, c.style.font_size, f32(30))
	testing.expect_value(t, c.style.align, gfx.Align.Center)
}

@(test)
test_a_look_styles_one_text_and_leaves_the_current_style_alone :: proc(t: ^testing.T) {
	begin()
	defer finish()
	text("one", 0, 0, Look{size = 40.0, font = "Inter Bold", align = Align.Right})
	text("two", 0, 20)
	list := &the.windows[0].list
	first, second := gfx.command_at(list, 0), gfx.command_at(list, 1)
	testing.expect_value(t, first.style.font_size, f32(40))
	testing.expect_value(t, first.style.font, gfx.FACE_BOLD)
	testing.expect_value(t, first.style.align, gfx.Align.Right)
	testing.expect_value(t, second.style.font_size, gfx.DEFAULT_FONT_SIZE)
	testing.expect_value(t, second.style.font, gfx.FACE_DEFAULT)
	testing.expect_value(t, second.style.align, gfx.Align.Left)
}

@(test)
test_text_at_a_vector_and_with_a_wrap_width :: proc(t: ^testing.T) {
	begin()
	defer finish()
	text("a long line to wrap", [2]f64{10, 20}, wrap = 60)
	c := gfx.command_at(&the.windows[0].list, 0)
	testing.expect_value(t, [3]f32{c.args[0], c.args[1], c.args[2]}, [3]f32{10, 20, 60})
	one_line := measure("a long line to wrap")
	testing.expect(t, f64(c.args[4]) > one_line.y * 1.5, "wrapped onto lines")
}

@(test)
test_a_font_that_is_not_there_changes_nothing :: proc(t: ^testing.T) {
	begin()
	defer finish()
	_ = current_list()
	testing.expect(t, !font("No Such Font", 99))
	testing.expect(t, !has_font("No Such Font"))
	testing.expect_value(t, the.windows[0].list.style.font_size, gfx.DEFAULT_FONT_SIZE)
	testing.expect(t, has_font("Inter"))
}

@(test)
test_measure_gives_the_size_of_a_text_in_the_current_font :: proc(t: ^testing.T) {
	begin()
	defer finish()
	small := measure("hello")
	font_size(60)
	big := measure("hello")
	testing.expect(t, small.x > 0 && small.y > 0)
	testing.expect(t, big.x > small.x * 2 && big.y > small.y * 2)
	testing.expect_value(t, measure(""), [2]f64{})
}

@(test)
test_a_font_added_from_bytes_is_found_by_its_name :: proc(t: ^testing.T) {
	begin()
	defer finish()
	testing.expect(t, !add_font("Broken", {1, 2, 3}))
	testing.expect(t, add_font("Inter Copy", gfx.INTER_REGULAR))
	testing.expect(t, font("Inter Copy"))
}

@(test)
test_the_c_functions_for_text_draw_and_measure :: proc(t: ^testing.T) {
	begin()
	defer finish()
	abi_font("Inter")
	abi_font_size(25)
	abi_align("right")
	abi_text("from c", 5, 6)
	abi_text_v("again", {7, 8})
	abi_align("sideways") // not a side: nothing changes
	list := &the.windows[0].list
	testing.expect_value(t, len(list.commands), 2)
	testing.expect_value(t, gfx.command_at(list, 0).style.align, gfx.Align.Right)
	testing.expect_value(t, gfx.command_at(list, 1).style.font_size, f32(25))
	testing.expect_value(t, gfx.command_at(list, 1).args[0], f32(7))
	size := abi_measure("from c")
	testing.expect(t, size.x > 0 && size.y > 0)
}
