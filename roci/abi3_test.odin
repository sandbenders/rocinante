// SPDX-License-Identifier: 0BSD
//
// The C functions for the 3D verbs do what the Odin verbs they stand for do.
package roci

import "core:testing"

import "gfx"

abi_solids_sketch :: proc "c" () {
	abi_box(1, 2, 3, 4)
	abi_box_sized(0, 0, 0, 4, 5, 6)
	abi_box_v({1, 2, 3}, 7)
	abi_box_sized_v({0, 0, 0}, {8, 9, 10})
	abi_sphere(0, 0, 0, 5)
	abi_sphere_v({1, 1, 1}, 5)
	abi_plane(0, 0, 0, 20, 30)
	abi_plane_v({0, 0, 0}, {20, 30})
	abi_cone(0, 0, 0, 5, 10)
	abi_cone_v({0, 0, 0}, 5, 10)
	abi_cylinder(0, 0, 0, 5, 10)
	abi_cylinder_v({0, 0, 0}, 5, 10)
	abi_capsule(0, 0, 0, 5, 20)
	abi_capsule_v({0, 0, 0}, 5, 20)
	abi_torus(0, 0, 0, 5, 1)
	abi_torus_v({0, 0, 0}, 5, 1)
	abi_icosphere(0, 0, 0, 5)
	abi_icosphere_v({0, 0, 0}, 5)
	abi_grid(100, 4)
	abi_axes(50)
	abi_arrow(0, 0, 0, 10, 0, 0)
	abi_arrow_v({0, 0, 0}, {0, 10, 0})
}

@(test)
test_the_c_solids_draw_what_the_odin_ones_draw :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(200, 200)
	draw(proc() {abi_solids_sketch()})
	step()
	items := scene_items(w)
	testing.expect(t, len(items) >= 22, "every solid drew at least one item")
	testing.expect_value(t, items[0].model[0][0], 4) // a side makes a cube
	testing.expect_value(t, items[0].model[0][3], 1)
	testing.expect_value(t, items[1].model[2][2], 6)
	testing.expect_value(t, items[2].model[0][0], 7)
	testing.expect_value(t, items[3].model[1][1], 9)
}

@(test)
test_the_c_camera_lights_material_and_shadows_set_the_scene :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(200, 200)
	draw(proc() {
		abi_light_ambient({40, 40, 40, 255})
		abi_light_sun(1, -1, 0, {255, 255, 255, 255})
		abi_light_point(10, -20, 30, {255, 0, 0, 255}, 100)
		abi_light_spot(0, -100, 0, 0, 0, 0, 20, {0, 255, 0, 255}, 200)
		abi_material(1, 0.2, 0.5)
		abi_shadows()
		abi_sphere(0, 0, 0, 5)
		abi_camera(0, -100, 300)
		abi_look_at(0, 0, 0)
	})
	step()
	lights, lit, _, material := scene_state(w)
	testing.expect(t, lit, "a light was written")
	testing.expect_value(t, len(lights), 4)
	testing.expect_value(t, lights[2].falloff, 100)
	testing.expect_value(t, lights[3].angle, 20)
	testing.expect_value(t, material.metallic, 1)
	testing.expect_value(t, material.roughness, 0.2)
	testing.expect(t, shadows_of(w), "shadows are on")
}

@(test)
test_the_c_no_lights_flattens_and_ortho_and_perspective_switch_the_camera :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(200, 200)
	draw(proc() {
		abi_no_lights()
		abi_ortho()
		abi_box(0, 0, 0, 10)
		abi_perspective_fov(70)
		abi_camera_fov(0, -100, 300, 60)
		abi_camera_v({0, -50, 200})
		abi_look_at_v({0, 0, 0})
	})
	step()
	_, _, unlit, _ := scene_state(w)
	testing.expect(t, unlit, "flat")
	testing.expect_value(t, len(scene_items(w)), 1)
	testing.expect(t, win_for(w).list.scene.ortho == false, "perspective again")
}

@(test)
test_the_c_screen_and_world_points_round_trip :: proc(t: ^testing.T) {
	begin()
	defer finish()
	window(400, 300)
	draw(proc() {
		abi_camera(0, -300, 300)
		abi_look_at(0, 0, 0)
		pixel := abi_screen_point(0, 0, 0)
		pixel_again := abi_screen_point_v({0, 0, 0})
		on_floor := abi_world_point_v(pixel)
		on_floor_again := abi_world_point(pixel.x, pixel.y)
		abi_test_results = {pixel, pixel_again, {on_floor.x, on_floor.z}, {on_floor_again.x, on_floor_again.z}}
	})
	step()
	testing.expect(t, abi_test_results[0] == abi_test_results[1], "both forms agree")
	testing.expect(t, abs(abi_test_results[0].x - 200) < 1 && abs(abi_test_results[0].y - 150) < 1, "the origin is where the camera looks, the middle")
	testing.expect(t, abs(abi_test_results[2].x) < 1e-6 && abs(abi_test_results[2].y) < 1e-6, "back to the origin")
	testing.expect(t, abi_test_results[2] == abi_test_results[3], "both forms agree")
}

@(thread_local)
abi_test_results: [4]Abi_Vec2

@(test)
test_the_c_transforms_and_the_turtle_in_space_draw :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(200, 200)
	draw(proc() {
		abi_push()
		abi_move_xyz(10, 0, 0)
		abi_move_v3({0, 20, 0})
		abi_grow_xyz(2, 2, 2)
		abi_turn_about(90, "y")
		abi_turn_about(90, "sideways") // no axis: nothing turns
		abi_box(0, 0, 0, 5)
		abi_pop()
		abi_turtle_space()
		abi_forward(30)
		abi_up(90)
		abi_forward(30)
		abi_down(45)
		abi_roll(10)
		abi_back(5)
	})
	step()
	items := scene_items(w)
	testing.expect(t, len(items) >= 3, "the box and the turtle's tubes")
	testing.expect_value(t, items[0].model[0][3], 10)
	testing.expect_value(t, items[0].model[1][3], 20)
}

@(test)
test_the_c_mesh_is_kept_and_drawn_solid_or_as_a_wireframe :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(200, 200)
	draw(proc() {
		corners := [6]Abi_Vec3{{0, 0, 0}, {10, 0, 0}, {0, 10, 0}, {0, 0, 5}, {10, 0, 5}, {0, 10, 5}}
		abi_mesh("a", raw_data(corners[:]), 6, 0)
		abi_mesh("b", raw_data(corners[:]), 3, 1)
		abi_mesh("c", raw_data(corners[:]), 2, 0) // not a triangle
		abi_mesh("d", nil, 9, 0)
	})
	step()
	testing.expect(t, len(scene_items(w)) >= 2, "a solid mesh and a wireframe's edges")
}

@(test)
test_the_c_model_is_read_from_a_file_and_drawn :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(200, 200)
	testing.expect_value(t, abi_load_model(nil), 0)
	testing.expect_value(t, abi_load_model(""), 0)
	testing.expect_value(t, abi_load_model("tests/models/no-such-model.glb"), 0)
	model := abi_load_model("tests/models/ship.glb")
	testing.expect(t, model != 0, "the fixture is a model")
	testing.expect_value(t, abi_load_model("tests/models/ship.glb"), model) // unchanged: the same number
	abi_model_for_test = model
	draw(proc() {
		abi_model(abi_model_for_test, 0, 0, 0, 100)
		abi_model_v(abi_model_for_test, {50, 0, 0}, 100)
	})
	step()
	testing.expect(t, len(scene_items(w)) >= 2, "each draw added the model's parts")
}

@(thread_local)
abi_model_for_test: i32

@(thread_local)
abi_ray_result: Abi_Line3

@(test)
test_the_c_ray_starts_at_the_eye_and_looks_through_the_pixel :: proc(t: ^testing.T) {
	begin()
	defer finish()
	window(400, 300)
	draw(proc() {
		abi_camera(0, 0, 500)
		abi_look_at(0, 0, 0)
		abi_ray_result = abi_ray(200, 150)
		abi_ray_again = abi_ray_v({200, 150})
	})
	step()
	ray := abi_ray_result
	testing.expect(t, abs(ray.from.z - 500) < 1e-6 && abs(ray.from.x) < 1e-6, "from the eye")
	testing.expect(t, abs(ray.to.x) < 1e-3 && abs(ray.to.y) < 1e-3 && ray.to.z < 0, "through the middle of the window, away from the eye")
	testing.expect(t, abi_ray_again == ray, "both forms agree")
}

@(thread_local)
abi_ray_again: Abi_Line3

@(thread_local)
abi_triangle_model: i32

@(test)
test_the_c_triangles_are_counted_and_copied_as_far_as_they_fit :: proc(t: ^testing.T) {
	begin()
	defer finish()
	window(200, 200)
	model := abi_load_model("tests/models/ship.glb")
	if !testing.expect(t, model != 0, "the fixture is a model") {
		return
	}
	total := abi_triangles(model, 0, 0, 0, 100, nil, 0)
	testing.expect(t, total > 0 && total % 3 == 0, "three corners for each triangle")
	testing.expect_value(t, abi_triangles_v(model, {0, 0, 0}, 100, nil, 0), total)
	corners: [3]Abi_Vec3
	corners[2] = {-7, -7, -7}
	testing.expect_value(t, abi_triangles(model, 0, 0, 0, 100, raw_data(corners[:]), 2), total) // two fit
	testing.expect(t, corners[0] != corners[1], "the first two corners were written")
	testing.expect_value(t, corners[2], Abi_Vec3{-7, -7, -7}) // and no more
	testing.expect_value(t, abi_triangles(0, 0, 0, 0, 100, nil, 0), 0) // no model, no triangles
	// a model placed elsewhere has the same count and moved corners
	moved: [3]Abi_Vec3
	abi_triangles_v(model, {1000, 0, 0}, 100, raw_data(moved[:]), 3)
	testing.expect(t, moved[0].x > corners[0].x + 500, "moved along x")
}

@(test)
test_the_c_svg_is_read_kept_and_drawn :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(300, 300)
	testing.expect_value(t, abi_load_svg(nil), 0)
	testing.expect_value(t, abi_load_svg(""), 0)
	testing.expect_value(t, abi_load_svg("examples/vector/assets/images/no-such.svg"), 0)
	testing.expect_value(t, abi_svg_width(0), 0)
	testing.expect_value(t, abi_svg_lost(0), 0)
	svg := abi_load_svg("examples/vector/assets/images/badge.svg")
	if !testing.expect(t, svg != 0, "the badge is a drawing") {
		return
	}
	testing.expect_value(t, abi_load_svg("examples/vector/assets/images/badge.svg"), svg) // unchanged: the same number
	testing.expect(t, abi_svg_width(svg) > 0 && abi_svg_height(svg) > 0, "it has a size")
	abi_svg_for_test = svg
	draw(proc() {
		abi_svg(abi_svg_for_test, 0, 0)
		abi_svg_v(abi_svg_for_test, {10, 10})
		abi_svg_sized(abi_svg_for_test, 0, 0, 100, 50)
		abi_svg_sized_v(abi_svg_for_test, {0, 0}, {100, 50})
		abi_svg(99, 0, 0) // no such drawing: nothing
	})
	step()
	testing.expect(t, len(win_for(w).list.commands) >= 4, "each draw added the drawing's shapes")
}

@(thread_local)
abi_svg_for_test: i32

@(test)
test_a_kept_svg_is_replaced_under_its_number_when_its_file_changes :: proc(t: ^testing.T) {
	defer svgs_stop()
	first := `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="10" height="10"/></svg>`
	second := `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 40"><rect width="20" height="40"/><text x="1" y="1">hi</text></svg>`
	a, error := add_svg("some/where.svg", 1, transmute([]u8)first)
	testing.expect_value(t, error, gfx.Svg_Error.None)
	testing.expect_value(t, svg_size(a), [2]f64{10, 10})
	_, found := find_svg("some/where.svg", 1)
	testing.expect(t, found, "found by path and time")
	b, _ := add_svg("some/where.svg", 2, transmute([]u8)second)
	testing.expect_value(t, b, a)
	testing.expect_value(t, svg_size(a), [2]f64{20, 40})
	testing.expect(t, .Text in svg_lost(a), "the text cannot be drawn")
	_, found = find_svg("some/where.svg", 1)
	testing.expect(t, !found, "the old time is gone")
	_, bad := add_svg("not.svg", 1, transmute([]u8)string("plain words"))
	testing.expect_value(t, bad, gfx.Svg_Error.Not_Svg)
	other, _ := add_svg("other.svg", 1, transmute([]u8)first)
	testing.expect(t, other != a, "another path is another drawing")
	testing.expect_value(t, svg_size(Svg(100)), [2]f64{})
}
