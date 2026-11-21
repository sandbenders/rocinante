// SPDX-License-Identifier: 0BSD
package lang

import "core:strings"
import "core:testing"


@(test)
test_a_use_of_a_file_is_told_from_a_library_and_its_path_is_worked_out :: proc(t: ^testing.T) {
	text := "use \"flocking\"\nuse \"github.com/someone/noise.git\"\nuse \"../../look.roci\"\nuse \"./sibling.roci\"\nuse \"/shared/abs.roci\"\n"
	testing.expect_value(t, strings.join(uses_in("tools/a/sketch.roci", text, context.temp_allocator), " ", context.temp_allocator), "flocking noise")
	testing.expect_value(t, strings.join(file_uses_in("tools/a/sketch.roci", text, context.temp_allocator), " ", context.temp_allocator), "look.roci tools/a/sibling.roci /shared/abs.roci")
	testing.expect(t, is_file_use("look.roci") && is_file_use("../x/y.roci") && !is_file_use("flocking") && !is_file_use("github.com/a/b.git"))
	for want in ([?][3]string{
		{"sketch.roci", "look.roci", "look.roci"},
		{"./sketch.roci", "../look.roci", "../look.roci"},
		{"a/b/sketch.roci", "../../look.roci", "look.roci"},
		{"a/b/sketch.roci", "../../../look.roci", "../look.roci"},
		{"/p/a/sketch.roci", "../x/./y.roci", "/p/x/y.roci"},
		{"/sketch.roci", "../x.roci", "/x.roci"},
		{"a/sketch.roci", "/abs/z.roci", "/abs/z.roci"},
		{"", "w.roci", "w.roci"},
	}) {
		testing.expect_value(t, use_file_path(want[0], want[1], context.temp_allocator), want[2])
	}
}
