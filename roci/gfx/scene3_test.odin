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
		if shape == .Model {continue} // a loaded model has its own mesh
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

@(test)
test_every_shape_has_triangles_inside_its_unit_size :: proc(t: ^testing.T) {
	m := build_shape_meshes()
	defer shape_meshes_destroy(&m)
	total := 0
	for shape in Shape3 {
		if shape == .Model {continue}
		range := m.ranges[shape]
		testing.expectf(t, range.index_count > 0 && range.index_count % 3 == 0, "%v has whole triangles", shape)
		testing.expect_value(t, int(range.first_index), total)
		total += int(range.index_count)
	}
	testing.expect_value(t, total, len(m.mesh.indices))
	for i in m.mesh.indices {
		testing.expect(t, int(i) < len(m.mesh.vertices), "an index inside the vertices")
	}
	for v in m.mesh.vertices {
		n := math.sqrt(v.normal.x * v.normal.x + v.normal.y * v.normal.y + v.normal.z * v.normal.z)
		testing.expect(t, close(n, 1, 1e-3), "normals are unit length")
	}
	// the cone and the cylinder stand on y: height 1 and diameter 1
	for shape in ([?]Shape3{.Cone, .Cylinder}) {
		low, high := f32(10), f32(-10)
		widest := f32(0)
		range := m.ranges[shape]
		for i in range.first_index ..< range.first_index + range.index_count {
			p := m.mesh.vertices[m.mesh.indices[i]].position
			low, high = min(low, p.y), max(high, p.y)
			widest = max(widest, math.sqrt(p.x * p.x + p.z * p.z))
		}
		testing.expect(t, close(low, -0.5) && close(high, 0.5), "a height of 1")
		testing.expect(t, close(widest, 0.5), "a diameter of 1")
	}
	// the cone ends in a point at the top
	cone := m.ranges[.Cone]
	tip_seen := false
	for i in cone.first_index ..< cone.first_index + cone.index_count {
		p := m.mesh.vertices[m.mesh.indices[i]].position
		if p.y == -0.5 && p.x == 0 && p.z == 0 {
			tip_seen = true
		}
	}
	testing.expect(t, tip_seen, "the tip is at the top")
	// the capsule's two halves are told apart for the instance to move them apart
	tops, bottoms := 0, 0
	capsule := m.ranges[.Capsule]
	for i in capsule.first_index ..< capsule.first_index + capsule.index_count {
		switch m.mesh.vertices[m.mesh.indices[i]].stretch {
		case -1: tops += 1
		case 1:  bottoms += 1
		case:    testing.expect(t, false, "every corner of a capsule is in a half")
		}
	}
	testing.expect_value(t, tops > 0 && bottoms > 0, true)
	// the icosphere has 80 flat faces
	testing.expect_value(t, m.ranges[.Icosphere].index_count, 240)
	// a torus corner is on the ring of radius 0.5 before the tube is added
	torus := m.ranges[.Torus]
	for i in torus.first_index ..< torus.first_index + torus.index_count {
		p := m.mesh.vertices[m.mesh.indices[i]].position
		testing.expect(t, close(math.sqrt(p.x * p.x + p.z * p.z), 0.5) && p.y == 0, "on the ring")
	}
}

@(test)
test_a_basis_along_a_direction_takes_y_there :: proc(t: ^testing.T) {
	for dir in ([?][3]f64{{1, 0, 0}, {0, 1, 0}, {0, 0, -1}, {1, 2, 3}, {0, -1, 0}}) {
		m := basis_along(dir)
		want := normalize3(dir)
		testing.expect(t, close(m[0, 1], f32(want.x)) && close(m[1, 1], f32(want.y)) && close(m[2, 1], f32(want.z)), "y goes along the direction")
		// the other two axes are square to it and to each other, and have length 1
		x := [3]f64{f64(m[0, 0]), f64(m[1, 0]), f64(m[2, 0])}
		z := [3]f64{f64(m[0, 2]), f64(m[1, 2]), f64(m[2, 2])}
		testing.expect(t, close(f32(dot3(x, want)), 0) && close(f32(dot3(z, want)), 0) && close(f32(dot3(x, z)), 0), "square to each other")
		testing.expect(t, close(f32(dot3(x, x)), 1) && close(f32(dot3(z, z)), 1), "of length 1")
	}
	testing.expect_value(t, basis_along({}), identity4())
}

@(test)
test_an_arrow_is_a_shaft_and_a_head_that_meet :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	scene_arrow(&s, {0, 0, 0}, {100, 0, 0}, {255, 255, 255, 255})
	if !testing.expect_value(t, len(s.items), 2) {
		return
	}
	testing.expect_value(t, s.items[0].shape, Shape3.Cylinder)
	testing.expect_value(t, s.items[1].shape, Shape3.Cone)
	// the shaft's middle is at 42 along (the shaft is 84 long), the head's at 92
	testing.expect(t, close(s.items[0].model[0][3], 42, 1e-3), "the shaft's middle")
	testing.expect(t, close(s.items[1].model[0][3], 92, 1e-3), "the head's middle")
	// no length, no arrow
	scene_arrow(&s, {1, 1, 1}, {1, 1, 1}, {255, 255, 255, 255})
	testing.expect_value(t, len(s.items), 2)
	scene_arrow(&s, {0, 0, 0}, {math.nan_f64(), 0, 0}, {255, 255, 255, 255})
	testing.expect_value(t, len(s.items), 2)
}

@(test)
test_axes_and_a_grid_are_made_of_shapes :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	scene_axes(&s, 100)
	testing.expect_value(t, len(s.items), 6) // a shaft and a head for each
	testing.expect(t, s.items[0].colour.r > 0.8 && s.items[0].colour.g < 0.5, "x is red")
	testing.expect(t, s.items[2].colour.g > 0.6 && s.items[2].colour.r < 0.5, "y is green")
	testing.expect(t, s.items[4].colour.b > 0.8 && s.items[4].colour.r < 0.5, "z is blue")
	clear(&s.items)
	scene_grid(&s, 100, 4, {255, 255, 255, 255})
	testing.expect_value(t, len(s.items), 10) // five lines each way
	clear(&s.items)
	scene_grid(&s, 100, 100000, {255, 255, 255, 255})
	testing.expect_value(t, len(s.items), 402) // never more than 200 squares
	clear(&s.items)
	scene_grid(&s, -5, 4, {255, 255, 255, 255})
	scene_grid(&s, math.nan_f64(), 4, {255, 255, 255, 255})
	testing.expect_value(t, len(s.items), 0)
}

@(test)
test_params_reach_the_instance_and_the_hash :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	scene_add(&s, .Capsule, {}, {1, 1, 1}, {0, 0, 0, 255}, {0.5, 0})
	testing.expect_value(t, s.items[0].params, [4]f32{0.5, 0, 0, 0})
	before := scene_hash(&s)
	s.items[0].params.x = 1
	testing.expect(t, scene_hash(&s) != before, "a longer capsule is a different picture")
	scene_add(&s, .Torus, {}, {1, 1, 1}, {0, 0, 0, 255}, {math.nan_f64(), 0})
	testing.expect_value(t, len(s.items), 1)
}

@(test)
test_the_orbit_camera_starts_in_front_and_above :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	cam := scene_camera(&s, {640, 420})
	testing.expect(t, cam.eye.z > 0 && cam.eye.y > 0, "in front and above (the internal world is y up)")
	testing.expect(t, close(f32(dot3(cam.forward, cam.forward)), 1), "a unit direction")
	testing.expect(t, close(f32(dot3(cam.side, cam.up)), 0) && close(f32(dot3(cam.side, cam.forward)), 0), "square axes")
	testing.expect(t, cam.up.y > 0, "the top of the picture is up")
	testing.expect(t, !cam.ortho, "with perspective")
}

@(test)
test_a_fixed_camera_stays_where_it_was_put_and_looks_at_the_middle :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	scene_camera_at(&s, {640, 420}, {0, -100, 500})
	testing.expect(t, s.fixed, "the camera no longer follows the orbit")
	cam := scene_camera(&s, {640, 420})
	// the sketch's y is down, so the eye 100 above the floor is y = -100 there and +100 in the camera's y-up world
	testing.expect(t, close(f32(cam.eye.y), 100) && close(f32(cam.eye.z), 500), "the eye where it was put")
	at, visible := scene_screen_point(&s, {640, 420}, {0, 0, 0})
	testing.expect(t, visible && close(f32(at.x), 320, 0.01) && close(f32(at.y), 210, 0.01), "the middle is in the middle of the window")
	// the orbit does not move it
	scene_orbit(&s, 100, 100)
	again := scene_camera(&s, {640, 420})
	testing.expect_value(t, again.eye, cam.eye)
}

@(test)
test_look_at_aims_the_camera_and_starts_from_the_orbit_eye :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	before := scene_camera(&s, {640, 420})
	scene_look_at(&s, {640, 420}, {100, 0, 0})
	after := scene_camera(&s, {640, 420})
	testing.expect_value(t, after.eye, before.eye) // it stayed where the orbit had it
	at, visible := scene_screen_point(&s, {640, 420}, {100, 0, 0})
	testing.expect(t, visible && close(f32(at.x), 320, 0.01) && close(f32(at.y), 210, 0.01), "the target is in the middle")
	// to the right of the target is to the right of the window
	right, _ := scene_screen_point(&s, {640, 420}, {200, 0, 0})
	testing.expect(t, right.x > 320, "x still goes right")
}

@(test)
test_a_new_frame_gives_the_camera_back_to_the_mouse :: proc(t: ^testing.T) {
	list: Command_List
	defer destroy(&list)
	begin_frame(&list)
	scene_camera_at(&list.scene, {640, 420}, {10, 20, 30})
	list.scene.fov = 70
	list.scene.ortho = true
	begin_frame(&list)
	testing.expect(t, !list.scene.fixed && !list.scene.ortho && list.scene.fov == 0, "the next frame starts with the orbit camera")
}

@(test)
test_the_field_of_view_changes_how_much_is_seen :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	narrow, _ := scene_screen_point(&s, {640, 420}, {100, 0, 0})
	s.fov = 100
	wide, _ := scene_screen_point(&s, {640, 420}, {100, 0, 0})
	testing.expect(t, abs(wide.x - 320) < abs(narrow.x - 320), "a wider view makes things smaller")
	s.fov = 100000
	cam := scene_camera(&s, {640, 420})
	testing.expect(t, !math.is_inf(cam.tan_half) && cam.tan_half < 1e6, "the field of view is kept sane")
}

@(test)
test_an_orthographic_camera_keeps_every_distance_the_same_size :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	s.pitch = -CAMERA_PITCH // straight on
	s.ortho = true
	near, _ := scene_screen_point(&s, {640, 420}, {100, 0, 200})
	far, _ := scene_screen_point(&s, {640, 420}, {100, 0, -200})
	testing.expect(t, close(f32(near.x), f32(far.x), 0.01) && close(f32(near.y), f32(far.y), 0.01), "the same size near and far")
	testing.expect(t, close(f32(near.x - 320), 100, 0.01), "one unit a pixel")
	// the shader's matrix agrees: depth is not divided by
	u := scene_uniforms(&s, {640, 420})
	testing.expect_value(t, u.clip[3], [4]f32{0, 0, 0, 1})
	// and what is behind the middle of the orbit is still seen (nothing is behind the camera)
	_, visible := scene_screen_point(&s, {640, 420}, {0, 0, 100000})
	testing.expect(t, visible, "no perspective, so nothing is behind it")
}

@(test)
test_a_place_behind_the_camera_is_not_visible :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	_, visible := scene_screen_point(&s, {640, 420}, {0, 0, 100000})
	testing.expect(t, !visible, "behind the eye")
}

@(test)
test_the_floor_under_a_pixel_and_the_pixel_of_a_floor_point_are_the_same_place :: proc(t: ^testing.T) {
	for ortho in ([?]bool{false, true}) {
		s: Scene3
		defer scene_destroy(&s)
		s.ortho = ortho
		s.yaw = 25
		for spot in ([?][2]f64{{320, 300}, {100, 380}, {500, 250}}) {
			floor, found := scene_world_point(&s, {640, 420}, spot)
			if !testing.expect(t, found, "the floor is under a pixel below the horizon") {
				continue
			}
			testing.expect(t, abs(floor.y) < 1e-9, "on the floor")
			back, visible := scene_screen_point(&s, {640, 420}, floor)
			testing.expect(t, visible && close(f32(back.x), f32(spot.x), 0.01) && close(f32(back.y), f32(spot.y), 0.01), "and it shows where it was found")
		}
	}
	// a pixel above the horizon looks past the floor
	s: Scene3
	defer scene_destroy(&s)
	_, found := scene_world_point(&s, {640, 420}, {320, 0})
	testing.expect(t, !found, "the sky has no floor")
	// a camera on the floor looks along it
	scene_camera_at(&s, {640, 420}, {0, 0, 300})
	scene_look_at(&s, {640, 420}, {0, 0, 0})
	_, found = scene_world_point(&s, {640, 420}, {320, 210})
	testing.expect(t, !found, "parallel to the floor")
}

@(test)
test_a_screen_point_follows_the_current_transform :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	scene_move(&s, 50, 0, 0)
	moved := scene_to_world(&s, {0, 0, 0})
	testing.expect_value(t, moved, [3]f64{50, 0, 0})
	scene_grow(&s, 2, 2, 2)
	testing.expect_value(t, scene_to_world(&s, {1, 1, 1}), [3]f64{52, 2, 2})
}

@(test)
test_the_hash_follows_the_camera_verbs :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	plain := scene_hash(&s)
	s.ortho = true
	testing.expect(t, scene_hash(&s) != plain, "ortho")
	s.ortho = false
	s.fov = 70
	testing.expect(t, scene_hash(&s) != plain, "fov")
	s.fov = 0
	scene_camera_at(&s, {640, 420}, {1, 2, 3})
	testing.expect(t, scene_hash(&s) != plain, "the eye")
}

@(test)
test_a_shape_carries_the_material_it_was_drawn_with :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	scene_add(&s, .Box, {}, {1, 1, 1}, {0, 0, 0, 255})
	testing.expect_value(t, s.items[0].material, [4]f32{0, DEFAULT_ROUGHNESS, 0, 0}) // the usual material, lit
	scene_material(&s, 1.0, 0.2, nil)
	scene_add(&s, .Box, {}, {1, 1, 1}, {0, 0, 0, 255})
	testing.expect_value(t, s.items[1].material, [4]f32{1, 0.2, 0, 0})
	// a word left out keeps its value; the others are clamped to 0 and 1
	scene_material(&s, nil, 5.0, 0.5)
	scene_material(&s, -3.0, nil, nil)
	scene_add(&s, .Box, {}, {1, 1, 1}, {0, 0, 0, 255})
	testing.expect_value(t, s.items[2].material, [4]f32{0, 1, 0, 0.5})
	scene_no_lights(&s)
	scene_add(&s, .Box, {}, {1, 1, 1}, {0, 0, 0, 255})
	testing.expect_value(t, s.items[3].material[2], 1)
	testing.expect_value(t, size_of(Instance3), 96)
}

@(test)
test_push_and_pop_put_the_material_and_the_lighting_back :: proc(t: ^testing.T) {
	list: Command_List
	defer destroy(&list)
	begin_frame(&list)
	scene_material(&list.scene, 0.3, nil, nil)
	push(&list, .Style_And_Transform)
	scene_material(&list.scene, 1.0, 0.1, nil)
	scene_no_lights(&list.scene)
	testing.expect(t, list.scene.unlit && list.scene.material.metallic == 1, "changed inside")
	pop(&list)
	testing.expect(t, !list.scene.unlit, "lit again")
	testing.expect_value(t, list.scene.material.metallic, 0.3)
	// a new frame starts with the usual material, and lit
	scene_no_lights(&list.scene)
	begin_frame(&list)
	testing.expect(t, !list.scene.unlit && !list.scene.material.set, "a new frame starts afresh")
}

@(test)
test_the_usual_lights_are_there_until_a_sketch_writes_its_own :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	lights := scene_lights(&s, {640, 420})
	testing.expect_value(t, lights.ambient.w, 1) // one sun
	testing.expect_value(t, lights.lights[0][0][3], f32(Light_Kind.Sun))
	testing.expect(t, lights.ambient.r > 0, "and an ambient light")
	// the first light of the sketch takes them away
	scene_light(&s, Light3{kind = .Point, at = {1, 2, 3}, colour = {1, 0.5, 0}, falloff = 100})
	lights = scene_lights(&s, {640, 420})
	testing.expect_value(t, lights.ambient.w, 1)
	testing.expect_value(t, lights.lights[0][0][3], f32(Light_Kind.Point))
	testing.expect_value(t, lights.lights[0][0][0], 1)
	testing.expect_value(t, lights.lights[0][1], [4]f32{1, 0.5, 0, 100})
	testing.expect_value(t, lights.ambient.r, 0) // no ambient light was written
	// ambient lights add up, to at most 1
	scene_light(&s, Light3{kind = .Ambient, colour = {0.4, 0.2, 0.9}})
	scene_light(&s, Light3{kind = .Ambient, colour = {0.4, 0.2, 0.9}})
	lights = scene_lights(&s, {640, 420})
	testing.expect(t, close(lights.ambient.r, 0.8) && close(lights.ambient.g, 0.4) && lights.ambient.b == 1, "added and kept to 1")
	testing.expect_value(t, lights.ambient.w, 1) // ambient lights are not counted among the others
	// a new frame gives the usual lights back
	scene_begin(&s)
	lights = scene_lights(&s, {640, 420})
	testing.expect_value(t, lights.lights[0][0][3], f32(Light_Kind.Sun))
}

@(test)
test_a_sun_is_a_direction_and_a_spot_light_has_an_axis_and_a_cone :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	scene_light(&s, Light3{kind = .Sun, at = {0, -3, 4}, colour = {1, 1, 1}})
	scene_light(&s, Light3{kind = .Spot, at = {0, -100, 0}, aim = {0, 0, 0}, colour = {1, 1, 1}, angle = 60, falloff = 50})
	lights := scene_lights(&s, {640, 420})
	testing.expect(t, close(lights.lights[0][0][1], -0.6) && close(lights.lights[0][0][2], 0.8), "the sun's direction is made unit length")
	testing.expect(t, close(lights.lights[1][2][1], 1) && close(lights.lights[1][2][3], 0.5, 1e-3), "the spot light points down (y is down) and its cone's cosine is that of 60 degrees")
	// a cone of no width or a flat one is kept sane
	scene_light(&s, Light3{kind = .Spot, aim = {1, 0, 0}, colour = {1, 1, 1}, angle = 0})
	scene_light(&s, Light3{kind = .Spot, aim = {1, 0, 0}, colour = {1, 1, 1}, angle = 500})
	lights = scene_lights(&s, {640, 420})
	testing.expect(t, lights.lights[2][2][3] < 1 && lights.lights[3][2][3] > 0, "a cone is never a line or a plane")
}

@(test)
test_there_are_at_most_sixty_four_lights_and_a_bad_number_leaves_one_out :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	for i in 0 ..< MAX_LIGHTS + 20 {
		result := scene_light(&s, Light3{kind = .Point, colour = {1, 1, 1}, falloff = 10})
		testing.expect_value(t, result, Light_Result.Added if i < MAX_LIGHTS else Light_Result.Too_Many)
	}
	testing.expect_value(t, MAX_LIGHTS, 64)
	testing.expect_value(t, len(s.lights), MAX_LIGHTS)
	testing.expect_value(t, scene_lights(&s, {10, 10}).ambient.w, MAX_LIGHTS)
	testing.expect(t, size_of(Scene_Lights) <= 4096, "the block of lights fits what Metal passes")
	scene_begin(&s)
	testing.expect_value(t, scene_light(&s, Light3{kind = .Point, at = {math.nan_f64(), 0, 0}, colour = {1, 1, 1}}), Light_Result.Left_Out)
	testing.expect_value(t, len(s.lights), 0)
	testing.expect(t, !s.lit, "a light that was left out is not a light written")
}

@(test)
test_the_hash_follows_the_lights_and_the_material :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	scene_add(&s, .Box, {}, {1, 1, 1}, {255, 0, 0, 255})
	plain := scene_hash(&s)
	scene_light(&s, Light3{kind = .Sun, at = {1, 1, 1}, colour = {1, 1, 1}})
	lit := scene_hash(&s)
	testing.expect(t, lit != plain, "a light")
	s.lights[0].colour = {0.5, 1, 1}
	testing.expect(t, scene_hash(&s) != lit, "its color")
	scene_begin(&s)
	scene_material(&s, 1.0, nil, nil)
	scene_add(&s, .Box, {}, {1, 1, 1}, {255, 0, 0, 255})
	testing.expect(t, scene_hash(&s) != plain, "the material")
}

// Where a place of the world lands in a light's view, as the matrix rows say: x and y from -1 to 1
// across the map and z from 0 to 1 in depth.
light_project :: proc(rows: [4][4]f32, p: [3]f64) -> (x, y, z: f32, ahead: bool) {
	q := [4]f32{f32(p.x), f32(p.y), f32(p.z), 1}
	row :: proc(r: [4]f32, q: [4]f32) -> f32 {return r[0] * q[0] + r[1] * q[1] + r[2] * q[2] + r[3] * q[3]}
	w := row(rows[3], q)
	return row(rows[0], q) / w, row(rows[1], q) / w, row(rows[2], q) / w, w > 0
}

@(test)
test_the_bounds_of_a_scene_hold_every_shape :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	centre, radius := scene_bounds(&s)
	testing.expect(t, centre == {} && radius == 1, "an empty scene is a unit sphere")
	scene_add(&s, .Box, {100, 0, 0}, {20, 20, 20}, {0, 0, 0, 255})
	scene_add(&s, .Sphere, {-100, 50, 0}, {40, 40, 40}, {0, 0, 0, 255})
	scene_add(&s, .Capsule, {0, 0, 300}, {10, 10, 10}, {0, 0, 0, 255}, {3, 0})
	centre, radius = scene_bounds(&s)
	for item in s.items {
		at := [3]f64{f64(item.model[0][3]), f64(item.model[1][3]), f64(item.model[2][3])}
		d := at - centre
		testing.expect(t, math.sqrt(dot3(d, d)) <= radius, "every shape's middle is inside")
	}
	// the capsule stretches by 3 each side of a 10 wide shape: 40 from its middle at least
	far := [3]f64{0, 0, 340} - centre
	testing.expect(t, math.sqrt(dot3(far, far)) <= radius + 1e-6, "and so is the end of the capsule")
}

@(test)
test_a_suns_view_holds_the_whole_scene :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	scene_add(&s, .Box, {100, 0, 0}, {40, 40, 40}, {0, 0, 0, 255})
	scene_add(&s, .Sphere, {-120, 60, 50}, {60, 60, 60}, {0, 0, 0, 255})
	scene_add(&s, .Plane, {0, 100, 0}, {400, 1, 400}, {0, 0, 0, 255})
	for toward in ([?][3]f64{{-0.4, -0.7, 0.6}, {0, -1, 0}, {1, 0, 0}, {0, 0, 1}} ) {
		rows, texel := shadow_view(&s, Light3{kind = .Sun, at = toward})
		testing.expect(t, texel > 0, "a texel has a size")
		for item in s.items {
			at := [3]f64{f64(item.model[0][3]), f64(item.model[1][3]), f64(item.model[2][3])}
			x, y, z, ahead := light_project(rows, at)
			testing.expectf(t, ahead && abs(x) <= 1 && abs(y) <= 1 && z >= 0 && z <= 1, "the middle of a shape is inside the view from %v: %v %v %v", toward, x, y, z)
		}
	}
	// a light with no direction still has a view
	rows, _ := shadow_view(&s, Light3{kind = .Sun})
	_, _, z, _ := light_project(rows, {0, 0, 0})
	testing.expect(t, z >= 0 && z <= 1, "straight above when it has no direction")
}

@(test)
test_a_spot_lights_view_holds_the_scene_it_lights :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	scene_add(&s, .Box, {0, 0, 0}, {40, 40, 40}, {0, 0, 0, 255})
	scene_add(&s, .Sphere, {60, 40, 20}, {30, 30, 30}, {0, 0, 0, 255})
	light := Light3{kind = .Spot, at = {0, -300, 100}, aim = {0, 0, 0}, angle = 30}
	rows, texel := shadow_view(&s, light)
	testing.expect(t, texel > 0, "a texel has a size")
	for item in s.items {
		at := [3]f64{f64(item.model[0][3]), f64(item.model[1][3]), f64(item.model[2][3])}
		x, y, z, ahead := light_project(rows, at)
		testing.expectf(t, ahead && abs(x) <= 1 && abs(y) <= 1 && z > 0 && z < 1, "inside the cone: %v %v %v", x, y, z)
	}
	// a spot light that looks at itself still has a view
	_, _ = shadow_view(&s, Light3{kind = .Spot, at = {1, 2, 3}, aim = {1, 2, 3}, angle = 30})
}

@(test)
test_shadows_are_off_until_asked_for_and_the_first_sun_or_spot_light_casts_them :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	scene_add(&s, .Box, {}, {10, 10, 10}, {0, 0, 0, 255})
	testing.expect_value(t, scene_lights(&s, {640, 420}).shadow.x, 0)
	scene_shadows(&s)
	lights := scene_lights(&s, {640, 420})
	testing.expect_value(t, lights.shadow.x, 1) // the usual sun casts them
	testing.expect_value(t, lights.shadow.y, 0)
	testing.expect(t, lights.shadow.z > 0 && lights.shadow.w == 1.0 / SHADOW_SIZE, "a push out along the normal and a texel")
	// a point light is the first light and casts into a map of its own: the sun after it casts the other, and the shader finds each by its number
	scene_light(&s, Light3{kind = .Point, colour = {1, 1, 1}, falloff = 10})
	scene_light(&s, Light3{kind = .Ambient, colour = {0.2, 0.2, 0.2}})
	scene_light(&s, Light3{kind = .Sun, at = {0, -1, 0}, colour = {1, 1, 1}})
	scene_light(&s, Light3{kind = .Spot, at = {0, -100, 0}, colour = {1, 1, 1}, angle = 30})
	lights = scene_lights(&s, {640, 420})
	testing.expect_value(t, lights.shadow.x, 1)
	testing.expect_value(t, lights.shadow.y, 1) // the sun is the second light that is not ambient
	testing.expect_value(t, lights.point_at.w, 1) // the point light is the first
	// a second point light casts nothing, and nothing but point lights leaves the sun's map unused
	scene_begin(&s)
	scene_add(&s, .Box, {}, {10, 10, 10}, {0, 0, 0, 255})
	scene_shadows(&s)
	scene_light(&s, Light3{kind = .Point, colour = {1, 1, 1}, falloff = 10})
	scene_light(&s, Light3{kind = .Point, at = {5, 5, 5}, colour = {1, 1, 1}, falloff = 10})
	lights = scene_lights(&s, {640, 420})
	testing.expect_value(t, lights.shadow.x, 0)
	testing.expect_value(t, lights.point_at.w, 1)
	testing.expect_value(t, lights.point_at.x, 0) // the first one's place
	// no shadows asked for: nothing casts
	scene_begin(&s)
	scene_light(&s, Light3{kind = .Point, colour = {1, 1, 1}, falloff = 10})
	testing.expect_value(t, scene_lights(&s, {640, 420}).point_at.w, 0)
	// a new frame starts without shadows
	scene_begin(&s)
	testing.expect(t, !s.shadows, "off again")
	testing.expect(t, size_of(Scene_Lights) <= 4096, "the block still fits what Metal passes")
}

@(test)
test_the_six_faces_of_a_point_light_see_every_direction :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	scene_add(&s, .Box, {0, 0, 0}, {40, 40, 40}, {0, 0, 0, 255})
	scene_add(&s, .Sphere, {200, 40, 20}, {30, 30, 30}, {0, 0, 0, 255})
	light := [3]f64{20, -50, 30}
	rows, near, far := point_faces(&s, light)
	testing.expect(t, near > 0 && far > near, "the faces cut the scene between two distances")
	// a place one step from the light along each axis is straight ahead of exactly the face that looks that way
	steps := [6][3]f64{{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}}
	for step, face in steps {
		for other in 0 ..< 6 {
			x, y, z, ahead := light_project(rows[other], light + step * 10)
			if other == face {
				testing.expectf(t, ahead && abs(x) < 1e-5 && abs(y) < 1e-5 && z > 0 && z < 1, "face %v looks along step %v: %v %v %v", face, step, x, y, z)
			}
		}
	}
	// every shape of the scene is inside the face its middle is nearest the axis of
	for item in s.items {
		at := [3]f64{f64(item.model[0][3]), f64(item.model[1][3]), f64(item.model[2][3])}
		d := at - light
		best, best_len := 0, f64(0)
		for step, face in steps {
			if along := dot3(d, step); along > best_len {
				best, best_len = face, along
			}
		}
		x, y, z, ahead := light_project(rows[best], at)
		testing.expectf(t, ahead && abs(x) <= 1 && abs(y) <= 1 && z > 0 && z < 1, "inside its face: %v %v %v", x, y, z)
	}
}

@(test)
test_the_hash_follows_shadows :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	scene_add(&s, .Box, {}, {1, 1, 1}, {255, 0, 0, 255})
	plain := scene_hash(&s)
	scene_shadows(&s)
	testing.expect(t, scene_hash(&s) != plain, "shadows change the picture")
}

@(test)
test_every_solid_has_texture_coordinates_that_cover_its_picture :: proc(t: ^testing.T) {
	meshes := build_shape_meshes()
	defer shape_meshes_destroy(&meshes)
	for shape in Shape3 {
		if shape == .Model {
			continue
		}
		range := meshes.ranges[shape]
		low, high := [2]f32{1e9, 1e9}, [2]f32{-1e9, -1e9}
		for i in range.first_index ..< range.first_index + range.index_count {
			uv := meshes.mesh.vertices[meshes.mesh.indices[i]].uv
			low = {min(low.x, uv.x), min(low.y, uv.y)}
			high = {max(high.x, uv.x), max(high.y, uv.y)}
		}
		// the whole picture is used (a face that crosses the seam of a sphere goes a little past 1, where the picture repeats)
		testing.expectf(t, low.x >= 0 && low.y >= 0 && high.x <= 2 && high.y <= 1.0001, "%v has coordinates from %v to %v", shape, low, high)
		testing.expectf(t, high.x - low.x > 0.9 && high.y - low.y > 0.9, "%v covers only %v of its picture", shape, high - low)
	}
}

@(test)
test_a_solid_that_wears_a_picture_has_it_for_its_color_and_keeps_the_other_solids_plain :: proc(t: ^testing.T) {
	s: Scene3
	defer delete(s.items)
	scene_add(&s, .Box, {0, 0, 0}, {1, 1, 1}, {255, 0, 0, 255}, {}, Image_Id(7))
	scene_add(&s, .Sphere, {0, 0, 0}, {1, 1, 1}, {0, 255, 0, 255})
	testing.expect_value(t, s.items[0].texture, Image_Id(7))
	testing.expect_value(t, s.items[0].colour, [4]f32{1, 1, 1, 1}) // the picture is the color
	testing.expect_value(t, s.items[1].texture, Image_Id(0))
	testing.expect_value(t, s.items[1].colour, [4]f32{0, 1, 0, 1})
}
