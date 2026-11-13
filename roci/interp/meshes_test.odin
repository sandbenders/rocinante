// SPDX-License-Identifier: 0BSD
package interp

import "core:testing"

import "../"
import "../gfx"

TRIANGLE_SKETCH :: "tris = [ { 0, 0, 0 } { 10, 0, 0 } { 0, 10, 0 } ]\n"

@(test)
test_a_mesh_is_drawn_flat_shaded_in_the_fill_under_the_transform :: proc(t: ^testing.T) {
	p := run_text(t, TRIANGLE_SKETCH + "draw [\n  fill red\n  move 5 6 7\n  mesh tris\n]\n", 2)
	defer finish(p)
	items := roci.scene_items(first_window())
	if !testing.expect_value(t, len(items), 1) {return}
	testing.expect_value(t, items[0].shape, gfx.Shape3.Model)
	testing.expect_value(t, items[0].colour, [4]f32{1, 0, 0, 1})
	testing.expect_value(t, items[0].model[0][3], 5)
	testing.expect_value(t, items[0].model[2][3], 7)
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_a_wireframe_is_tubes_and_balls_as_wide_as_the_thickness :: proc(t: ^testing.T) {
	p := run_text(t, TRIANGLE_SKETCH + "draw [\n  fill lime\n  thickness 2\n  mesh tris as wireframe\n]\n", 2)
	defer finish(p)
	cylinders, spheres := 0, 0
	for item in roci.scene_items(first_window()) {
		#partial switch item.shape {
		case .Cylinder:
			cylinders += 1
			testing.expect_value(t, item.colour, [4]f32{0, 1, 0, 1})
			width := item.model[0][0] * item.model[0][0] + item.model[1][0] * item.model[1][0] + item.model[2][0] * item.model[2][0]
			testing.expect(t, abs(width - 4) < 1e-3, "two across")
		case .Sphere:
			spheres += 1
		}
	}
	testing.expect_value(t, cylinders, 3)
	testing.expect_value(t, spheres, 3)
}

@(test)
test_a_mesh_drawn_every_frame_from_the_same_list_is_made_once :: proc(t: ^testing.T) {
	p := run_text(t, TRIANGLE_SKETCH + "draw [\n  fill red\n  mesh tris\n]\n", 3)
	defer finish(p)
	id := roci.scene_items(first_window())[0].model_id
	for _ in 0 ..< 3 {
		roci.step()
	}
	testing.expect_value(t, gfx.model_version(id), 1)
}

@(test)
test_a_mesh_that_changes_takes_the_place_of_the_one_before_it :: proc(t: ^testing.T) {
	p := run_text(t, "draw [\n  fill red\n  wide = 10 + frame\n  mesh [ { 0, 0, 0 } { wide, 0, 0 } { 0, 10, 0 } ]\n]\n", 2)
	defer finish(p)
	id := roci.scene_items(first_window())[0].model_id
	before := gfx.model_version(id)
	roci.step()
	roci.step()
	items := roci.scene_items(first_window())
	testing.expect_value(t, len(items), 1)
	testing.expect_value(t, items[0].model_id, id) // the same call, the same place
	testing.expect_value(t, gfx.model_version(id), before + 2)
}

@(test)
test_one_call_that_draws_several_meshes_in_a_loop_makes_each_its_own :: proc(t: ^testing.T) {
	p := run_text(t, "draw [\n  fill red\n  for i from 1 to 3 [\n    mesh [ { 0, 0, 0 } { i * 10, 0, 0 } { 0, 10, 0 } ]\n  ]\n]\n", 2)
	defer finish(p)
	items := roci.scene_items(first_window())
	if !testing.expect_value(t, len(items), 3) {return}
	testing.expect(t, items[0].model_id != items[1].model_id && items[1].model_id != items[2].model_id, "three meshes")
	versions := gfx.model_version(items[0].model_id)
	roci.step()
	roci.step()
	testing.expect_value(t, gfx.model_version(items[0].model_id), versions) // they are not sent again while they stay the same
}

@(test)
test_a_list_that_is_no_triangle_or_a_mesh_with_no_fill_draws_nothing :: proc(t: ^testing.T) {
	p := run_text(t, "draw [\n  fill red\n  mesh [ { 0, 0, 0 } { 1, 0, 0 } ]\n  mesh []\n  no fill\n  mesh [ { 0, 0, 0 } { 1, 0, 0 } { 0, 1, 0 } ]\n]\n", 2)
	defer finish(p)
	testing.expect_value(t, len(roci.scene_items(first_window())), 0)
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_corners_of_two_numbers_are_read_with_a_z_of_0 :: proc(t: ^testing.T) {
	// a vector of two numbers has no z, which reads as 0
	p := run_text(t, "draw [\n  fill red\n  mesh [ { 0, 0 } { 1, 0 } { 0, 1 } ]\n]\n", 2)
	defer finish(p)
	testing.expect_value(t, len(roci.scene_items(first_window())), 1)
}
