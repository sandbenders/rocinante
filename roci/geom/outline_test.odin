// SPDX-License-Identifier: 0BSD
package geom

import "core:testing"

// A picture drawn as text: '#' is a solid pixel, anything else is not.
@(private = "file")
mask_of :: proc(rows: []string) -> (solid: []bool, width, height: int) {
	height = len(rows)
	width = len(rows[0])
	solid = make([]bool, width * height, context.temp_allocator)
	for row, y in rows {
		for c, x in row {
			solid[y * width + x] = c == '#'
		}
	}
	return
}

@(private = "file")
area_of :: proc(points: [][2]f64) -> f64 {
	sum := 0.0
	for p, i in points {
		q := points[(i + 1) % len(points)]
		sum += p.x * q.y - q.x * p.y
	}
	return sum / 2
}

@(test)
test_a_solid_block_is_its_four_corners :: proc(t: ^testing.T) {
	solid, w, h := mask_of({"....", ".##.", ".##.", "...."})
	out := trace_outline(solid, w, h, 1)
	defer delete(out)
	testing.expect_value(t, len(out), 4)
	testing.expect_value(t, area_of(out), 4.0) // clockwise on a y-down screen is positive here
	for p in out {
		testing.expect(t, p.x == 1 || p.x == 3)
		testing.expect(t, p.y == 1 || p.y == 3)
	}
}

@(test)
test_one_solid_pixel_is_a_square :: proc(t: ^testing.T) {
	solid, w, h := mask_of({"#"})
	out := trace_outline(solid, w, h, 1)
	defer delete(out)
	testing.expect_value(t, len(out), 4)
	testing.expect_value(t, area_of(out), 1.0)
}

@(test)
test_nothing_solid_is_no_outline :: proc(t: ^testing.T) {
	solid, w, h := mask_of({"...", "..."})
	testing.expect(t, trace_outline(solid, w, h, 1) == nil)
	testing.expect(t, trace_outline(nil, 0, 0, 1) == nil)
	testing.expect(t, trace_outline(solid, 5, 5, 1) == nil) // the sizes do not match
}

@(test)
test_an_l_shape_keeps_its_inner_corner :: proc(t: ^testing.T) {
	solid, w, h := mask_of({"#..", "#..", "###"})
	out := trace_outline(solid, w, h, 0.5)
	defer delete(out)
	testing.expect_value(t, len(out), 6)
	testing.expect_value(t, area_of(out), 5.0)
	found := false
	for p in out {
		if p == {1, 2} {
			found = true
		}
	}
	testing.expect(t, found)
}

@(test)
test_only_the_biggest_group_is_traced :: proc(t: ^testing.T) {
	solid, w, h := mask_of({"#.....", "......", "..###.", "..###."})
	out := trace_outline(solid, w, h, 1)
	defer delete(out)
	testing.expect_value(t, area_of(out), 6.0)
}

@(test)
test_pixels_that_only_touch_at_a_corner_are_not_joined :: proc(t: ^testing.T) {
	// The two upper pixels are one group with the lower right one only through the
	// diagonal, so the outline is the bigger group's alone.
	solid, w, h := mask_of({"##.", "...", "..#"})
	out := trace_outline(solid, w, h, 1)
	defer delete(out)
	testing.expect_value(t, area_of(out), 2.0)
}

@(test)
test_a_hole_is_left_out :: proc(t: ^testing.T) {
	solid, w, h := mask_of({"###", "#.#", "###"})
	out := trace_outline(solid, w, h, 1)
	defer delete(out)
	testing.expect_value(t, area_of(out), 9.0)
}

@(test)
test_a_staircase_becomes_a_straight_line :: proc(t: ^testing.T) {
	// A triangle drawn in pixels: its slanted side is a staircase of one-pixel steps.
	rows: [dynamic]string
	defer delete(rows)
	for y in 0 ..< 20 {
		row := make([]u8, 20, context.temp_allocator)
		for x in 0 ..< 20 {
			row[x] = '#' if x <= y else '.'
		}
		append(&rows, string(row))
	}
	solid, w, h := mask_of(rows[:])
	exact := trace_outline(solid, w, h, 0)
	defer delete(exact)
	simple := trace_outline(solid, w, h, 1)
	defer delete(simple)
	testing.expect(t, len(exact) > 30)
	testing.expect(t, len(simple) <= 6)
	// The simple outline stays within about a pixel of the exact one in area.
	testing.expect(t, abs(area_of(simple) - area_of(exact)) < 20)
}

@(test)
test_a_picture_edge_touching_group_closes_up :: proc(t: ^testing.T) {
	solid, w, h := mask_of({"##", "##"})
	out := trace_outline(solid, w, h, 1)
	defer delete(out)
	testing.expect_value(t, len(out), 4)
	testing.expect_value(t, area_of(out), 4.0)
}

@(test)
test_simplify_keeps_short_polygons_and_zero_tolerance :: proc(t: ^testing.T) {
	triangle := [][2]f64{{0, 0}, {4, 0}, {0, 4}}
	out := simplify_closed(triangle, 1)
	defer delete(out)
	testing.expect_value(t, len(out), 3)
	square := [][2]f64{{0, 0}, {4, 0}, {4, 1}, {4, 4}, {0, 4}}
	none := simplify_closed(square, 0)
	defer delete(none)
	testing.expect_value(t, len(none), 5)
	straight := simplify_closed(square, 0.5)
	defer delete(straight)
	testing.expect_value(t, len(straight), 4) // the point on the straight side goes
}
