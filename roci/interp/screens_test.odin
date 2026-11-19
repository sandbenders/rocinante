// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "core:testing"

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
