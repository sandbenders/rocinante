// SPDX-License-Identifier: 0BSD
package gfx

import "../maths"
import "core:testing"

// A filled, outlined path of a triangle and a notch, drawn `times` times, each moved by `step` more, into one mesh.
@(private = "file")
drawn_moved :: proc(m: ^Mesh, times: int, step: f32, thickness: f32 = 4, corners: [][2]f32 = nil) {
	list := fresh()
	defer destroy(&list)
	set_fill(&list, maths.rgb(255, 0, 0))
	set_stroke(&list, maths.rgb(0, 0, 0))
	set_thickness(&list, thickness)
	shape := [][2]f32{{0, 0}, {40, 0}, {40, 30}, {20, 10}, {0, 30}}
	if corners != nil {
		shape = corners
	}
	for i in 0 ..< times {
		push(&list, {})
		move(&list, f32(i) * step, 5)
		path(&list, {{shape, true}})
		pop(&list)
	}
	for i in 0 ..< len(list.commands) {
		c := command_at(&list, i)
		mesh_add_command(m, c, 0, 0, path_points(&list, c))
	}
}

@(test)
test_a_shape_drawn_again_moved_is_taken_from_the_cache_and_gives_the_same_triangles :: proc(t: ^testing.T) {
	cached: Mesh
	defer mesh_destroy(&cached)
	shapes_next_build(&cached.shapes)
	drawn_moved(&cached, 1, 0)
	testing.expect_value(t, cached.shapes.cut, 2) // its fill and its outline
	testing.expect_value(t, cached.shapes.kept, 0)
	first_vertices := len(cached.vertices)
	shapes_next_build(&cached.shapes)
	clear(&cached.vertices)
	clear(&cached.indices)
	drawn_moved(&cached, 3, 10)
	testing.expect_value(t, cached.shapes.cut, 0)
	testing.expect_value(t, cached.shapes.kept, 6)
	testing.expect_value(t, len(cached.vertices), 3 * first_vertices)
	// what a mesh with nothing kept makes for the same three is the same, vertex for vertex
	fresh_mesh: Mesh
	defer mesh_destroy(&fresh_mesh)
	drawn_moved(&fresh_mesh, 3, 10)
	testing.expect_value(t, len(fresh_mesh.indices), len(cached.indices))
	for v, i in cached.vertices {
		testing.expect_value(t, v, fresh_mesh.vertices[i])
	}
	for index, i in cached.indices {
		testing.expect_value(t, index, fresh_mesh.indices[i])
	}
}

@(test)
test_other_corners_or_another_outline_are_cut_again :: proc(t: ^testing.T) {
	m: Mesh
	defer mesh_destroy(&m)
	shapes_next_build(&m.shapes)
	drawn_moved(&m, 1, 0)
	testing.expect_value(t, m.shapes.cut, 2)
	shapes_next_build(&m.shapes)
	drawn_moved(&m, 1, 0, 4, [][2]f32{{0, 0}, {41, 0}, {40, 30}, {20, 10}, {0, 30}}) // one corner is not where it was
	testing.expect_value(t, m.shapes.cut, 2)
	drawn_moved(&m, 1, 0, 6) // a thicker outline: the fill is kept, the outline is not
	testing.expect_value(t, m.shapes.cut, 3)
	testing.expect_value(t, m.shapes.kept, 1)
}

@(test)
test_a_shape_not_drawn_for_a_hundred_and_twenty_builds_is_forgotten_and_one_that_is_drawn_is_not :: proc(t: ^testing.T) {
	m: Mesh
	defer mesh_destroy(&m)
	shapes_next_build(&m.shapes)
	drawn_moved(&m, 1, 0)
	other := [][2]f32{{0, 0}, {10, 0}, {10, 10}}
	drawn_moved(&m, 1, 0, 4, other)
	testing.expect_value(t, len(m.shapes.shapes), 4)
	for _ in 0 ..< 2 * SHAPES_KEPT_BUILDS + 1 { // the cache looks for the forgotten once in that many builds
		clear(&m.vertices)
		clear(&m.indices)
		shapes_next_build(&m.shapes)
		drawn_moved(&m, 1, 0, 4, other) // only this one is still drawn
	}
	testing.expect_value(t, len(m.shapes.shapes), 2)
	testing.expect(t, m.shapes.corners > 0)
	shapes_forget(&m.shapes, 0)
	testing.expect_value(t, len(m.shapes.shapes), 0)
	testing.expect_value(t, m.shapes.corners, 0)
}
