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

// Starts `n` builds of `m` in which only `corners` (nil: nothing) is drawn.
@(private = "file")
builds_drawing :: proc(m: ^Mesh, n: int, corners: [][2]f32) {
	for _ in 0 ..< n {
		clear(&m.vertices)
		clear(&m.indices)
		shapes_next_build(&m.shapes)
		if corners != nil {
			drawn_moved(m, 1, 0, 4, corners)
		}
	}
}

@(test)
test_a_shape_not_drawn_for_a_hundred_and_twenty_builds_is_forgotten_and_one_that_is_drawn_is_not :: proc(t: ^testing.T) {
	m: Mesh
	defer mesh_destroy(&m)
	shapes_next_build(&m.shapes)
	drawn_moved(&m, 1, 0)
	other := [][2]f32{{0, 0}, {10, 0}, {10, 10}}
	drawn_moved(&m, 1, 0, 4, other)
	testing.expect_value(t, shapes_count(&m.shapes), 4)
	builds_drawing(&m, SHAPES_KEPT_BUILDS + 1, other) // only this one is still drawn
	testing.expect_value(t, shapes_count(&m.shapes), 2)
	testing.expect(t, shapes_corners(&m.shapes) > 0)
	drawn_moved(&m, 1, 0, 4, other)
	testing.expect_value(t, m.shapes.cut, 0) // still kept, though it moved through two generations
	shapes_forget_all(&m.shapes)
	testing.expect_value(t, shapes_count(&m.shapes), 0)
	testing.expect_value(t, shapes_corners(&m.shapes), 0)
	drawn_moved(&m, 1, 0, 4, other)
	testing.expect_value(t, m.shapes.cut, 2) // cut again after everything was forgotten
}

@(test)
test_a_shape_left_out_for_less_than_half_the_builds_is_still_kept :: proc(t: ^testing.T) {
	m: Mesh
	defer mesh_destroy(&m)
	shapes_next_build(&m.shapes)
	drawn_moved(&m, 1, 0)
	builds_drawing(&m, SHAPES_KEPT_BUILDS / 2 - 1, nil)
	drawn_moved(&m, 1, 0)
	testing.expect_value(t, m.shapes.cut, 0)
	testing.expect_value(t, m.shapes.kept, 2)
}

@(test)
test_a_shape_found_in_the_older_generation_is_copied_into_the_newer_with_the_same_triangles :: proc(t: ^testing.T) {
	m: Mesh
	defer mesh_destroy(&m)
	shapes_next_build(&m.shapes)
	drawn_moved(&m, 1, 0)
	first := make([]Mesh_Vertex, len(m.vertices))
	defer delete(first)
	copy(first, m.vertices[:])
	builds_drawing(&m, SHAPES_KEPT_BUILDS / 2, nil) // the generation turns: the shape is in the older one now
	testing.expect_value(t, len(m.shapes.generations[0].shapes), 0)
	testing.expect_value(t, len(m.shapes.generations[1].shapes), 2)
	clear(&m.vertices)
	clear(&m.indices)
	drawn_moved(&m, 1, 0)
	testing.expect_value(t, m.shapes.cut, 0)
	testing.expect_value(t, m.shapes.kept, 2)
	testing.expect_value(t, len(m.shapes.generations[0].shapes), 2)
	testing.expect_value(t, shapes_count(&m.shapes), 2) // in both, counted once
	testing.expect_value(t, len(m.vertices), len(first))
	for v, i in m.vertices {
		testing.expect_value(t, v, first[i])
	}
	builds_drawing(&m, SHAPES_KEPT_BUILDS / 2, nil) // the older one is let go; the copy is kept
	drawn_moved(&m, 1, 0)
	testing.expect_value(t, m.shapes.cut, 0)
}

@(test)
test_a_generation_holding_half_the_corners_turns_at_the_next_build :: proc(t: ^testing.T) {
	m: Mesh
	defer mesh_destroy(&m)
	shapes_next_build(&m.shapes)
	drawn_moved(&m, 1, 0)
	m.shapes.generations[0].corners = SHAPES_KEPT_CORNERS / 2 + 1 // as if it held that many
	shapes_next_build(&m.shapes)
	testing.expect_value(t, m.shapes.started, m.shapes.builds)
	testing.expect_value(t, len(m.shapes.generations[0].shapes), 0)
	testing.expect_value(t, len(m.shapes.generations[1].shapes), 2)
	shapes_next_build(&m.shapes) // the newer one is empty: no turn
	testing.expect_value(t, m.shapes.started, m.shapes.builds - 1)
}

@(test)
test_many_shapes_drawn_once_are_let_go_and_the_memory_is_used_again :: proc(t: ^testing.T) {
	m: Mesh
	defer mesh_destroy(&m)
	corners := [][2]f32{{0, 0}, {10, 0}, {10, 10}, {0, 10}}
	blocks := 0
	for round in 0 ..< 3 {
		for build in 0 ..< SHAPES_KEPT_BUILDS / 2 {
			clear(&m.vertices)
			clear(&m.indices)
			shapes_next_build(&m.shapes)
			for i in 0 ..< 20 { // twenty shapes a build, each never drawn again, as a swaying plant makes
				corners[2] = {10 + f32(round * 10_000 + build * 20 + i), 10}
				drawn_moved(&m, 1, 0, 4, corners)
			}
		}
		testing.expect_value(t, m.shapes.kept, 0)
		held := len(m.shapes.generations[0].arena.used_blocks) + len(m.shapes.generations[1].arena.used_blocks) + len(m.shapes.generations[0].arena.unused_blocks) + len(m.shapes.generations[1].arena.unused_blocks)
		if round == 1 {
			blocks = held
		}
		if round == 2 {
			testing.expect_value(t, held, blocks) // the blocks of the generation let go were used again, none more made
		}
	}
	testing.expect(t, shapes_count(&m.shapes) <= SHAPES_KEPT_BUILDS * 40)
}

@(test)
test_an_empty_cache_turns_and_is_destroyed_without_harm :: proc(t: ^testing.T) {
	c: Shape_Cache
	for _ in 0 ..< 3 * SHAPES_KEPT_BUILDS {
		shapes_next_build(&c)
	}
	shapes_forget_all(&c)
	testing.expect_value(t, shapes_count(&c), 0)
	shapes_destroy(&c)
	shapes_destroy(&c)
}
