// SPDX-License-Identifier: 0BSD
package gfx

import "../maths"
import "core:math"
import "core:testing"

square_contour :: proc(x, y, side: f32) -> [4][2]f32 {
	return {{x, y}, {x + side, y}, {x + side, y + side}, {x, y + side}}
}

@(test)
test_a_path_keeps_its_points_and_the_box_round_them :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	outer := square_contour(10, 20, 100)
	inner := square_contour(40, 50, 20)
	testing.expect(t, path(&list, {{outer[:], true}, {inner[:], true}}))
	c := command_at(&list, 0)
	testing.expect_value(t, c.kind, Kind.Path)
	x, y, w, h := local_bounds(c)
	testing.expect_value(t, [4]f32{x, y, w, h}, [4]f32{10, 20, 100, 100})
	points := path_points(&list, c)
	testing.expect_value(t, len(points), 10) // eight corners and two breaks
	first, closed, after, ok := next_contour(points, 0)
	testing.expect(t, ok && closed && len(first) == 4)
	second, _, last, ok2 := next_contour(points, after)
	testing.expect(t, ok2 && len(second) == 4)
	_, _, _, more := next_contour(points, last)
	testing.expect(t, !more, "no third contour")
	testing.expect_value(t, kind_name(c.kind), "path")
}

@(test)
test_a_path_of_nothing_or_of_a_number_that_is_not_one_is_not_recorded :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	testing.expect(t, !path(&list, nil))
	testing.expect(t, !path(&list, {{nil, true}}), "an empty contour is no path")
	before := len(list.commands)
	bad := [][2]f32{{0, 0}, {math.inf_f32(1), 1}}
	testing.expect(t, !path(&list, {{bad, false}}))
	testing.expect_value(t, len(list.commands), before)
	testing.expect_value(t, len(list.points), 0) // nothing half written
}

@(test)
test_a_filled_path_is_a_mesh_and_a_contour_inside_another_is_a_hole :: proc(t: ^testing.T) {
	setup :: proc(list: ^Command_List) {
		outer := square_contour(0, 0, 100)
		inner := square_contour(25, 25, 50)
		no_stroke(list)
		path(list, {{outer[:], true}, {inner[:], true}})
	}
	list := fresh()
	defer destroy(&list)
	setup(&list)
	m: Mesh
	defer mesh_destroy(&m)
	c := command_at(&list, 0)
	testing.expect(t, needs_mesh(c))
	mesh_add_command(&m, c, 0, 0, path_points(&list, c))
	testing.expect(t, abs(mesh_area(m)) - 7500 < 1e-3 && abs(mesh_area(m)) - 7500 > -1e-3, "the square less its hole")
}

@(test)
test_a_stroked_open_contour_is_not_closed_and_a_closed_one_is :: proc(t: ^testing.T) {
	open_area, closed_area: f64
	for closed in ([?]bool{false, true}) {
		list := fresh()
		defer destroy(&list)
		no_fill(&list)
		set_stroke(&list, maths.rgb(0, 0, 0))
		corner := [][2]f32{{0, 0}, {100, 0}, {100, 100}, {0, 100}}
		path(&list, {{corner, closed}})
		m: Mesh
		c := command_at(&list, 0)
		mesh_add_command(&m, c, 0, 0, path_points(&list, c))
		area := abs(mesh_area(m))
		mesh_destroy(&m)
		if closed {closed_area = area} else {open_area = area}
	}
	testing.expect(t, closed_area > open_area, "the closing side adds ink")
}

@(test)
test_a_path_is_written_to_svg_and_pdf :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	outer := square_contour(0, 0, 100)
	inner := square_contour(25, 25, 50)
	open := [][2]f32{{5, 5}, {50, 90}}
	path(&list, {{outer[:], true}, {inner[:], true}, {open, false}})
	svg, _ := svg_write(&list, 200, 100, context.temp_allocator)
	testing.expect(t, has(svg, `<path fill-rule="evenodd" d="M0,0 L100,0 L100,100 L0,100 Z M25,25`), svg)
	testing.expect(t, has(svg, "M5,5 L50,90"), svg)
	pdf, _ := pdf_write(&list, 200, 100, context.temp_allocator)
	testing.expect(t, len(pdf) > 0)
}

@(test)
test_rewinding_the_list_forgets_the_points_of_a_path :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	m := mark(&list)
	corner := square_contour(0, 0, 10)
	path(&list, {{corner[:], true}})
	testing.expect(t, len(list.points) > 0)
	rewind(&list, m)
	testing.expect_value(t, len(list.points), 0)
	begin_frame(&list)
	path(&list, {{corner[:], true}})
	begin_frame(&list)
	testing.expect_value(t, len(list.points), 0)
}

@(test)
test_two_paths_with_other_points_have_other_hashes :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	a := square_contour(0, 0, 10)
	b := square_contour(0, 0, 11)
	path(&list, {{a[:], true}})
	path(&list, {{b[:], true}})
	testing.expect(t, command_hash(command_at(&list, 0)) != command_hash(command_at(&list, 1)))
}
