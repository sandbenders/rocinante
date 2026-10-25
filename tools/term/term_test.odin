// SPDX-License-Identifier: 0BSD
package term

import "core:strings"
import "core:testing"

@(test)
test_paint_off_returns_the_text_untouched :: proc(t: ^testing.T) {
	testing.expect_value(t, paint("hello", .Red, false), "hello")
}

@(test)
test_paint_on_wraps_in_codes_and_resets :: proc(t: ^testing.T) {
	testing.expect_value(t, paint("hello", .Red, true), "\x1b[31mhello\x1b[0m")
}

@(test)
test_paint_empty_text_prints_no_codes :: proc(t: ^testing.T) {
	testing.expect_value(t, paint("", .Green, true), "")
}

@(test)
test_every_style_has_its_own_code :: proc(t: ^testing.T) {
	seen: [Style]string
	for style in Style {
		c := code(style)
		testing.expect(t, c != "" && c != "0", "every style needs a real code")
		for other in Style {
			if other < style {
				testing.expect(t, seen[other] != c, "two styles share a code")
			}
		}
		seen[style] = c
	}
}

@(test)
test_bold_colours_combine_bold_and_the_colour :: proc(t: ^testing.T) {
	testing.expect_value(t, code(.Bold_Red), "1;31")
	testing.expect_value(t, code(.Bold_Green), "1;32")
	testing.expect_value(t, code(.Bold_Cyan), "1;36")
}

@(test)
test_out_and_err_follow_their_own_switch :: proc(t: ^testing.T) {
	// the globals are only written by setup() at start-up; tests never write them
	testing.expect_value(t, paint("x", .Dim, out_colour), out("x", .Dim))
	testing.expect_value(t, paint("x", .Dim, err_colour), err("x", .Dim))
}

@(test)
test_pad :: proc(t: ^testing.T) {
	testing.expect_value(t, pad("ab", 5), "ab   ")
	testing.expect_value(t, pad("abcde", 5), "abcde")
	testing.expect_value(t, pad("abcdef", 5), "abcdef")
	testing.expect_value(t, pad("", 3), "   ")
	testing.expect_value(t, pad("ab", 0), "ab")
	testing.expect(t, strings.has_prefix(pad("a", 4), "a"))
}
