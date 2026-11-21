// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "core:testing"
import sdl "vendor:sdl3"

// A headless sketch has one stand-in screen, and `platform` is the system's name as text.
@(test)
test_a_sketch_reads_the_platform_and_the_stand_in_screen :: proc(t: ^testing.T) {
	p := run_text(t, `
system = platform
screen = item 1 of screens
name = screen.name
wide = screen.width
high = screen.height
density = screen.density
hertz = screen.refresh
main = screen.main
corner = screen.pos
`, 1)
	defer finish(p)
	testing.expect_value(t, as_text(global_named(p, "system")), roci.platform_name())
	testing.expect_value(t, as_text(global_named(p, "name")), "Screen")
	testing.expect_value(t, as_number(global_named(p, "wide")), 1920)
	testing.expect_value(t, as_number(global_named(p, "high")), 1080)
	testing.expect_value(t, as_number(global_named(p, "density")), 1)
	testing.expect_value(t, as_number(global_named(p, "hertz")), 60)
	testing.expect_value(t, as_bool(global_named(p, "main")), true)
	testing.expect_value(t, as_pair(global_named(p, "corner")), [2]f64{0, 0})
	testing.expect_value(t, len(p.errors), 0)
}

// Several screens come in the order the system gives, the main one first, with a negative place for
// one left of it, and a sketch can use them: here to find the widest and the real pixels of the main one.
@(test)
test_a_sketch_reads_every_screen :: proc(t: ^testing.T) {
	p := run_text(t, `
draw [
  n = count screens
  widest = 0
  for each s in screens [
    if s.width > widest [ widest = s.width ]
  ]
  first = item 1 of screens
  real = first.width * first.density
  other = item 2 of screens
  left = other.pos
  other_name = other.name
]
`)
	defer finish(p)
	roci.set_screens({{name = "Laptop", width = 1512, height = 982, density = 2, refresh = 120, main = true}, {name = "Left", x = -2560, y = -200, width = 2560, height = 1440, density = 1, refresh = 144}})
	roci.step()
	testing.expect_value(t, as_number(global_named(p, "n")), 2)
	testing.expect_value(t, as_number(global_named(p, "widest")), 2560)
	testing.expect_value(t, as_number(global_named(p, "real")), 3024)
	testing.expect_value(t, as_pair(global_named(p, "left")), [2]f64{-2560, -200})
	testing.expect_value(t, as_text(global_named(p, "other_name")), "Left")
	testing.expect_value(t, len(p.errors), 0)
}

// The platform example starts on the mark of the system it runs on, the arrow keys go through the
// seven marks and round again in both directions, and every mark draws something with no error.
@(test)
test_the_platform_example_shows_each_mark_and_the_arrow_keys_move_between_them :: proc(t: ^testing.T) {
	p := run_text(t, example_text("platform"), 1)
	defer finish(p)
	names := [?]string{"macos", "windows", "linux", "freebsd", "openbsd", "ios", "android"}
	start_at := 0
	for name, i in names {
		if name == roci.platform_name() {
			start_at = i + 1
		}
	}
	// a system the example has no mark for (none today) starts on the first
	start_at = max(start_at, 1)
	testing.expect_value(t, as_number(global_named(p, "shown")), f64(start_at))
	w := first_window()
	expected := start_at
	for _ in 0 ..< 8 {
		roci.step({key_event(w, sdl.Scancode.RIGHT)})
		roci.step({key_event(w, sdl.Scancode.RIGHT, false)})
		expected = expected % 7 + 1
		testing.expect_value(t, as_number(global_named(p, "shown")), f64(expected))
		testing.expect(t, len(roci.recorded(w)) > 3, "a mark draws shapes and a label")
	}
	for _ in 0 ..< 8 {
		roci.step({key_event(w, sdl.Scancode.LEFT)})
		roci.step({key_event(w, sdl.Scancode.LEFT, false)})
		expected = (expected + 5) % 7 + 1
		testing.expect_value(t, as_number(global_named(p, "shown")), f64(expected))
	}
	testing.expect_value(t, expected, start_at)
	testing.expect_value(t, len(p.errors), 0)
}

// A constant made by a verb reads the constants the verb names when the verb runs, so it is made where
// it is written, after the constants that wait on `screens`: it was moved before them, and found them empty.
@(test)
test_a_constant_made_by_a_verb_finds_the_constants_it_reads_made_from_screens :: proc(t: ^testing.T) {
	p := run_text(t, `
MAIN_SCREEN = item 1 of screens
SEEN = seen_height
learn seen_height [ give MAIN_SCREEN.height ]
LATER = 5
L2 = uses_later
learn uses_later [ give LATER + 1 ]
BOTH = both_of
learn both_of [ give MAIN_SCREEN.width + LATER ]
`, 1)
	defer finish(p)
	testing.expect_value(t, as_number(global_named(p, "SEEN")), 1080)
	testing.expect_value(t, as_number(global_named(p, "L2")), 6)
	testing.expect_value(t, as_number(global_named(p, "BOTH")), 1925)
	testing.expect_value(t, len(p.errors), 0)
}

// `safe` is how far in from each side of the window the screen is free: zeros on a computer, and what the phone says
// when it does, read again each frame.
@(test)
test_a_sketch_reads_the_safe_area_each_frame :: proc(t: ^testing.T) {
	p := run_text(t, `
draw [
  top = safe.top
  bottom = safe.bottom
  left = safe.left
  right = safe.right
  inner = height - safe.top - safe.bottom
]
`)
	defer finish(p)
	defer roci.set_safe_area({})
	roci.step()
	testing.expect_value(t, as_number(global_named(p, "top")), 0)
	testing.expect_value(t, as_number(global_named(p, "right")), 0)
	roci.set_safe_area({top = 54, bottom = 30, left = 12, right = 8})
	roci.step()
	testing.expect_value(t, as_number(global_named(p, "top")), 54)
	testing.expect_value(t, as_number(global_named(p, "bottom")), 30)
	testing.expect_value(t, as_number(global_named(p, "left")), 12)
	testing.expect_value(t, as_number(global_named(p, "right")), 8)
	testing.expect(t, as_number(global_named(p, "inner")) > 0)
	testing.expect_value(t, len(p.errors), 0)
}

// `vibrate` asks the phone for a buzz, a fifth of a second when no length is given; a computer does nothing.
@(test)
test_vibrate_asks_for_a_buzz_of_the_length_given :: proc(t: ^testing.T) {
	roci.vibrations_forget()
	defer roci.vibrations_forget()
	p := run_text(t, `
vibrate
vibrate 0.5
on touch down [ vibrate 0.1 ]
`, 1)
	defer finish(p)
	count, last := roci.vibrations()
	testing.expect_value(t, count, 2)
	testing.expect_value(t, last, 0.5)
	testing.expect_value(t, len(p.errors), 0)
}

// `language` is the player's language as a code: empty in a headless run, and what the system lists first when it does.
@(test)
test_a_sketch_reads_the_language :: proc(t: ^testing.T) {
	p := run_text(t, "said = language\nsame = language is \"\"\n", 1)
	testing.expect_value(t, as_text(global_named(p, "said")), "")
	testing.expect_value(t, as_bool(global_named(p, "same")), true)
	finish(p)
	roci.language_pretend_as("pt-BR")
	defer roci.language_pretend_as("", false)
	p2 := run_text(t, "said = language\nportuguese = language is \"pt-BR\"\n", 1)
	defer finish(p2)
	testing.expect_value(t, as_text(global_named(p2, "said")), "pt-BR")
	testing.expect_value(t, as_bool(global_named(p2, "portuguese")), true)
}
