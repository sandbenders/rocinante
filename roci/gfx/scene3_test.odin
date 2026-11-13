// SPDX-License-Identifier: 0BSD
package gfx

import "core:math"
import "core:testing"

// Where a world place lands on the screen: the camera's rows applied to it, divided by w.
project :: proc(u: Scene_Uniforms, p: [3]f32) -> (x, y, w: f32) {
	q := [4]f32{p.x, p.y, p.z, 1}
	row :: proc(r: [4]f32, q: [4]f32) -> f32 {return r[0] * q[0] + r[1] * q[1] + r[2] * q[2] + r[3] * q[3]}
	w = row(u.clip[3], q)
	return row(u.clip[0], q) / w, row(u.clip[1], q) / w, w
}

@(test)
test_a_scene_with_no_transform_uses_the_identity :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	testing.expect_value(t, current_model(&s), identity4())
	scene_add(&s, .Box, {10, 20, 30}, {2, 3, 4}, {255, 0, 0, 255})
	testing.expect_value(t, len(s.items), 1)
	item := s.items[0]
	// the size scales the shape about its own middle, then the place moves it
	testing.expect_value(t, item.model[0], [4]f32{2, 0, 0, 10})
	testing.expect_value(t, item.model[1], [4]f32{0, 3, 0, 20})
	testing.expect_value(t, item.model[2], [4]f32{0, 0, 4, 30})
	testing.expect_value(t, item.colour, [4]f32{1, 0, 0, 1})
	testing.expect_value(t, item.shape, Shape3.Box)
}

@(test)
test_move_turn_and_grow_change_what_comes_after :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	scene_move(&s, 5, 6, 7)
	scene_add(&s, .Sphere, {0, 0, 0}, {1, 1, 1}, {0, 0, 0, 255})
	testing.expect_value(t, s.items[0].model[0][3], 5)
	testing.expect_value(t, s.items[0].model[1][3], 6)
	testing.expect_value(t, s.items[0].model[2][3], 7)
	scene_grow(&s, 2, 2, 2)
	scene_add(&s, .Box, {1, 0, 0}, {1, 1, 1}, {0, 0, 0, 255})
	// moved by 5, then scaled by 2: the place 1 is 2 further along
	testing.expect_value(t, s.items[1].model[0][3], 7)
	testing.expect_value(t, s.items[1].model[0][0], 2)
}

@(test)
test_a_turn_about_each_axis_goes_the_way_the_2d_turn_goes :: proc(t: ^testing.T) {
	// about z, a quarter turn takes the way right to the way down, which is clockwise on the screen
	m := rotate4(90, .Z)
	testing.expect(t, near(m[0, 0], 0) && near(m[1, 0], 1), "z: right becomes down")
	// about x it takes down to towards the viewer, and about y it takes towards the viewer to right
	m = rotate4(90, .X)
	testing.expect(t, near(m[1, 1], 0) && near(m[2, 1], 1), "x: down becomes towards you")
	m = rotate4(90, .Y)
	testing.expect(t, near(m[2, 2], 0) && near(m[0, 2], 1), "y: towards you becomes right")
	// a right angle is exact, never a hair off
	testing.expect_value(t, rotate4(90, .Z)[0, 0], 0)
	testing.expect_value(t, rotate4(0, .X), identity4())
}

@(test)
test_a_non_finite_number_leaves_a_shape_out :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	scene_add(&s, .Box, {math.nan_f64(), 0, 0}, {1, 1, 1}, {0, 0, 0, 255})
	scene_add(&s, .Box, {0, 0, 0}, {math.inf_f64(1), 1, 1}, {0, 0, 0, 255})
	testing.expect_value(t, len(s.items), 0)
}

@(test)
test_push_and_pop_put_the_3d_transform_back :: proc(t: ^testing.T) {
	list: Command_List
	defer destroy(&list)
	begin_frame(&list)
	scene_move(&list.scene, 10, 0, 0)
	push(&list, .Style_And_Transform)
	scene_move(&list.scene, 5, 0, 0)
	testing.expect_value(t, list.scene.model[0, 3], 15)
	testing.expect(t, pop(&list), "the push is popped")
	testing.expect_value(t, list.scene.model[0, 3], 10)
	// a style scope leaves the transform alone
	push(&list, .Style)
	scene_move(&list.scene, 1, 0, 0)
	pop(&list)
	testing.expect_value(t, list.scene.model[0, 3], 11)
}

@(test)
test_a_new_frame_forgets_the_shapes_but_keeps_the_camera :: proc(t: ^testing.T) {
	list: Command_List
	defer destroy(&list)
	begin_frame(&list)
	testing.expect(t, !list.scene.shown, "nothing drawn yet")
	scene_add(&list.scene, .Plane, {0, 0, 0}, {1, 1, 1}, {0, 0, 0, 255})
	scene_orbit(&list.scene, 10, 5)
	scene_move(&list.scene, 1, 1, 1)
	begin_frame(&list)
	testing.expect_value(t, len(list.scene.items), 0)
	testing.expect(t, list.scene.shown, "the last frame drew a shape, so the mouse may orbit")
	testing.expect_value(t, list.scene.model[3, 3], 0) // the identity again
	testing.expect_value(t, list.scene.yaw, 4)
	begin_frame(&list)
	testing.expect(t, !list.scene.shown, "a frame with none says so")
}

@(test)
test_the_orbit_stays_off_the_poles_and_the_zoom_in_its_range :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	scene_orbit(&s, 0, 100000)
	testing.expect_value(t, s.pitch, 89)
	scene_orbit(&s, 0, -1000000)
	testing.expect_value(t, s.pitch, -89)
	scene_orbit(&s, 100000, 0)
	testing.expect(t, s.yaw >= -180 && s.yaw <= 180, "the yaw wraps")
	scene_orbit(&s, -100000, 0)
	testing.expect(t, s.yaw >= -180 && s.yaw <= 180, "and wraps the other way")
	scene_zoom(&s, 1000)
	testing.expect_value(t, s.zoom, 40)
	scene_zoom(&s, -1000)
	testing.expect_value(t, s.zoom, -20)
}

@(test)
test_the_camera_looks_at_the_middle_with_y_down :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	u := scene_uniforms(&s, {640, 420})
	x, y, w := project(u, {0, 0, 0})
	testing.expect(t, near(x, 0, 1e-3) && w > 0, "the origin is in front of the camera")
	// the camera starts a little above the floor, so the origin is a little below the middle
	testing.expect(t, near(y, 0, 1e-3), "the origin is in the middle of the screen")
	rx, _, _ := project(u, {100, 0, 0})
	testing.expect(t, rx > 0.05, "x goes right")
	_, dy, _ := project(u, {0, 100, 0})
	testing.expect(t, dy < -0.05, "y goes down (clip space has up as positive)")
	// something nearer the viewer is bigger: the same step sideways is further across
	nx, _, _ := project(u, {100, 0, 200})
	testing.expect(t, nx > rx, "z comes towards the viewer")
	// the eye is above the floor (y is down in the world, so smaller) and in front of the scene
	testing.expect(t, u.eye.y < 0 && u.eye.z > 0, "the eye starts above and in front")
}

@(test)
test_the_pixel_scale_of_the_middle_plane_is_one_to_one :: proc(t: ^testing.T) {
	// seen from straight ahead (the camera's pitch removed), a step of 100 on the plane z = 0 is 100 pixels
	s: Scene3
	defer scene_destroy(&s)
	s.pitch = -CAMERA_PITCH
	u := scene_uniforms(&s, {640, 420})
	x, _, _ := project(u, {100, 0, 0})
	testing.expect(t, near(x * 320, 100, 0.5), "100 units are 100 pixels at the middle")
	// a wider window shows more, and the same height keeps the scale
	u = scene_uniforms(&s, {1280, 420})
	x, _, _ = project(u, {100, 0, 0})
	testing.expect(t, near(x * 640, 100, 0.5), "the scale follows the height")
}

@(test)
test_a_window_of_no_size_still_has_a_camera :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	u := scene_uniforms(&s, {0, 0})
	for row in u.clip {
		for v in row {
			testing.expect(t, !math.is_nan(v) && !math.is_inf(v), "no NaN in the camera")
		}
	}
}

@(test)
test_the_hash_follows_what_is_shown :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	empty := scene_hash(&s)
	scene_add(&s, .Box, {0, 0, 0}, {1, 1, 1}, {255, 0, 0, 255})
	one := scene_hash(&s)
	testing.expect(t, one != empty, "an item changes it")
	scene_orbit(&s, 1, 0)
	testing.expect(t, scene_hash(&s) != one, "so does the camera")
	again: Scene3
	defer scene_destroy(&again)
	scene_add(&again, .Box, {0, 0, 0}, {1, 1, 1}, {255, 0, 0, 255})
	testing.expect_value(t, scene_hash(&again), one)
	again.items[0].colour = {0, 1, 0, 1}
	testing.expect(t, scene_hash(&again) != one, "and a color")
}

@(test)
test_the_shape_meshes_are_whole :: proc(t: ^testing.T) {
	m := build_shape_meshes()
	defer shape_meshes_destroy(&m)
	testing.expect_value(t, m.ranges[.Box].index_count, 36)
	testing.expect_value(t, m.ranges[.Plane].index_count, 6)
	testing.expect_value(t, m.ranges[.Sphere].index_count, 24 * 48 * 6)
	total := 0
	for shape in Shape3 {
		range := m.ranges[shape]
		testing.expect_value(t, int(range.first_index), total)
		total += int(range.index_count)
	}
	testing.expect_value(t, total, len(m.mesh.indices))
	for i in m.mesh.indices {
		testing.expect(t, int(i) < len(m.mesh.vertices), "an index inside the vertices")
	}
	for v in m.mesh.vertices {
		n := math.sqrt(v.normal.x * v.normal.x + v.normal.y * v.normal.y + v.normal.z * v.normal.z)
		testing.expect(t, near(n, 1, 1e-3), "normals are unit length")
	}
	// the box has side 1 and the sphere diameter 1, so nothing reaches past half
	for v in m.mesh.vertices {
		for c in v.position {
			testing.expect(t, abs(c) <= 0.5 + 1e-4, "within half a unit of the middle")
		}
	}
	// the plane lies flat: its normal is up (y is down in the world, so -1)
	for i in m.ranges[.Plane].first_index ..< m.ranges[.Plane].first_index + 6 {
		v := m.mesh.vertices[m.mesh.indices[i]]
		testing.expect_value(t, v.position.y, 0)
		testing.expect_value(t, v.normal, [3]f32{0, -1, 0})
	}
}

@(test)
test_normalising_and_crossing_vectors :: proc(t: ^testing.T) {
	testing.expect_value(t, normalize3({0, 0, 0}), [3]f64{})
	testing.expect_value(t, normalize3({0, 3, 4}), [3]f64{0, 0.6, 0.8})
	testing.expect_value(t, cross3({1, 0, 0}, {0, 1, 0}), [3]f64{0, 0, 1})
	testing.expect_value(t, dot3({1, 2, 3}, {4, 5, 6}), 32)
}

close :: proc(a, b: f32, tolerance: f32 = 1e-4) -> bool {
	return abs(a - b) <= tolerance
}
