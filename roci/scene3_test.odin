// SPDX-License-Identifier: 0BSD
package roci

import "core:testing"

import "collide"
import "platform"

solids_sketch :: proc() {
	box(0, 0, 0, 50, Look{fill = Colour{255, 0, 0, 255}})
	sphere(10, 20, 30, 5, Look{fill = Colour{0, 255, 0, 255}})
	plane(0, 40, 0, 100, 100)
	box([3]f64{1, 2, 3}, 4)
	box([3]f64{1, 2, 3}, [3]f64{4, 5, 6})
	box(1, 2, 3, 4, 5, 6)
	sphere([3]f64{1, 2, 3}, 9)
	plane([3]f64{1, 2, 3}, [2]f64{4, 5})
}

@(test)
test_every_form_of_the_3d_shapes_adds_an_item :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(200, 200)
	draw(solids_sketch)
	step()
	items := win_for(w).list.scene.items
	if !testing.expect_value(t, len(items), 8) {
		return
	}
	testing.expect_value(t, items[0].colour, [4]f32{1, 0, 0, 1})
	testing.expect_value(t, items[0].model[0][0], 50) // a side makes a cube
	testing.expect_value(t, items[0].model[2][2], 50)
	testing.expect_value(t, items[1].model[0][3], 10)
	testing.expect_value(t, items[1].model[0][0], 10) // a radius of 5 is a diameter of 10
	testing.expect_value(t, items[2].model[1][1], 1)  // a plane is flat
	testing.expect_value(t, items[2].model[2][2], 100)
	testing.expect_value(t, items[3].model[1][1], 4)
	testing.expect_value(t, items[4].model[2][2], 6)
	testing.expect_value(t, items[5].model[1][1], 5)
	testing.expect_value(t, items[6].model[0][0], 18)
	testing.expect_value(t, items[7].model[2][2], 5)
	// the 2D list is untouched
	testing.expect_value(t, len(win_for(w).list.commands), 0)
}

@(test)
test_a_shape_with_no_fill_is_not_drawn :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(200, 200)
	draw(proc() {
		no_fill()
		box(0, 0, 0, 10)
		box(0, 0, 0, 10, Look{fill = Colour{9, 9, 9, 255}})
	})
	step()
	testing.expect_value(t, len(win_for(w).list.scene.items), 1)
}

@(test)
test_the_3d_transforms_apply_to_shapes_and_not_to_the_flat_ones :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(200, 200)
	draw(proc() {
		push()
		move_xyz(10, 0, 0)
		move_v3({0, 5, 0})
		grow_xyz(2, 2, 2)
		turn_about(90, .Z)
		box(0, 0, 0, 1)
		pop()
		box(0, 0, 0, 1)
		move(3, 4)
		circle(0, 0, 5)
	})
	step()
	list := &win_for(w).list
	items := list.scene.items
	if !testing.expect_value(t, len(items), 2) {
		return
	}
	testing.expect_value(t, items[0].model[0][3], 10)
	testing.expect_value(t, items[0].model[1][3], 5)
	testing.expect_value(t, items[0].model[1][0], 2) // a turn of 90 about z, scaled by 2: right becomes down
	testing.expect_value(t, items[1].model[0][3], 0) // the pop put it back
	// the flat transform is a separate one
	commands := commands_of(w)
	testing.expect_value(t, len(commands), 1)
	testing.expect_value(t, commands[0].transform.e, 3)
}

orbit_events :: proc(w: Window, buttons: bool, dx, dy, wheel: f32) -> []platform.Event {
	id := platform.Window_Id(w)
	events := make([dynamic]platform.Event, context.temp_allocator)
	append(&events, platform.Mouse_Moved{window = id, x = 100, y = 100})
	if buttons {
		append(&events, platform.Mouse_Button_Changed{window = id, button = .Left, down = true, x = 100, y = 100})
	}
	append(&events, platform.Mouse_Moved{window = id, x = 100 + dx, y = 100 + dy, dx = dx, dy = dy})
	if wheel != 0 {
		append(&events, platform.Wheel{window = id, dy = wheel})
	}
	return events[:]
}

flat_box :: proc() {
	box(0, 0, 0, 20)
}

@(test)
test_a_drag_orbits_a_window_that_drew_3d_and_the_wheel_zooms :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(200, 200)
	draw(flat_box)
	step() // the first frame draws, so the next one's events may orbit
	step(orbit_events(w, true, 50, 20, 2))
	scene := &win_for(w).list.scene
	testing.expect_value(t, scene.yaw, 20)   // 50 pixels at 0.4 degrees
	testing.expect_value(t, scene.pitch, 8)
	testing.expect_value(t, scene.zoom, 2)
}

@(test)
test_moving_the_mouse_without_a_button_does_not_orbit :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(200, 200)
	draw(flat_box)
	step()
	step(orbit_events(w, false, 50, 20, 0))
	testing.expect_value(t, win_for(w).list.scene.yaw, 0)
}

@(test)
test_a_window_that_drew_no_3d_is_not_orbited :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(200, 200)
	draw(proc() {circle(10, 10, 5)})
	step()
	step(orbit_events(w, true, 50, 20, 2))
	scene := &win_for(w).list.scene
	testing.expect_value(t, scene.yaw, 0)
	testing.expect_value(t, scene.zoom, 0)
}

@(test)
test_a_sketch_that_reads_the_mouse_keeps_the_camera_still :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(200, 200)
	draw(proc() {
		box(0, 0, 0, 20)
		_ = mouse()
	})
	step()
	step(orbit_events(w, true, 50, 20, 2))
	testing.expect_value(t, win_for(w).list.scene.yaw, 0)
	testing.expect(t, win_for(w).mouse_read, "reading the mouse is remembered")
}

@(test)
test_saying_the_mouse_is_read_reaches_one_window_or_all :: proc(t: ^testing.T) {
	begin()
	defer finish()
	a := window(100, 100)
	b := window(100, 100)
	note_mouse_read(a)
	testing.expect(t, win_for(a).mouse_read && !win_for(b).mouse_read, "one window")
	note_mouse_read()
	testing.expect(t, win_for(b).mouse_read, "every window")
}

@(test)
test_a_drag_that_starts_on_a_widget_is_the_widgets :: proc(t: ^testing.T) {
	begin()
	defer finish()
	ui_reset()
	w := window(400, 300)
	draw(proc() {
		box(0, 0, 0, 20)
		ui_label("controls")
		_ = ui_slider("size", &ui_amount, 0, 100)
	})
	step_frames(4)
	slider, found := record_for(w, "size")
	if !testing.expect(t, found, "the slider is made") {
		return
	}
	x, y := (slider[0] + slider[2]) / 2, (slider[1] + slider[3]) / 2
	id := platform.Window_Id(w)
	step_frames(2, {platform.Mouse_Moved{window = id, x = x, y = y}})
	step_frames(2, {
		platform.Mouse_Button_Changed{window = id, button = .Left, down = true, x = x, y = y},
		platform.Mouse_Moved{window = id, x = x + 30, y = y, dx = 30},
	})
	testing.expect_value(t, win_for(w).list.scene.yaw, 0)
}

@(test)
test_the_frame_hash_sees_3d_shapes :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(100, 100)
	draw(proc() {box(0, 0, 0, f64(frame_count() % 2 * 10 + 10))})
	step()
	first := frame_hash(w)
	step()
	testing.expect(t, frame_hash(w) != first, "a box that changed size changes the hash")
	step()
	testing.expect_value(t, frame_hash(w), first)
}

@(test)
test_the_camera_verbs_set_the_scene_camera :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(200, 200)
	draw(proc() {
		box(0, 0, 0, 20)
		camera(0, -100, 400, 70)
		look_at(10, 0, 0)
		ortho()
	})
	step()
	scene := &win_for(w).list.scene
	testing.expect(t, scene.fixed && scene.ortho, "fixed and orthographic")
	testing.expect_value(t, scene.eye, [3]f64{0, -100, 400})
	testing.expect_value(t, scene.target, [3]f64{10, 0, 0})
	testing.expect_value(t, scene.fov, 70)
}

@(test)
test_perspective_undoes_ortho_and_sets_the_field_of_view :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(200, 200)
	draw(proc() {
		ortho()
		perspective(80)
	})
	step()
	testing.expect(t, !win_for(w).list.scene.ortho, "perspective again")
	testing.expect_value(t, win_for(w).list.scene.fov, 80)
}

@(test)
test_the_mouse_does_not_orbit_a_camera_the_sketch_places :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(200, 200)
	draw(proc() {
		box(0, 0, 0, 20)
		camera([3]f64{0, -100, 400})
	})
	step()
	step(orbit_events(w, true, 50, 20, 2))
	scene := &win_for(w).list.scene
	testing.expect_value(t, scene.yaw, 0)
	testing.expect_value(t, scene.zoom, 0)
}

screen_result: [2]f64
floor_result: [3]f64
found_result: bool

@(test)
test_screen_point_and_world_point_are_inverses_on_the_floor :: proc(t: ^testing.T) {
	begin()
	defer finish()
	window(400, 300)
	draw(proc() {
		camera(100, -250, 400)
		look_at(0, 0, 0)
		floor, found := world_point(300, 250)
		found_result, floor_result = found, floor
		screen_result, _ = screen_point(floor.x, floor.y, floor.z)
		plain, _ := screen_point(10, 0, 0)
		move_xyz(10, 0, 0)
		moved, _ := screen_point(0, 0, 0)
		testing.expect_value(nil, moved, plain) // `screen point` is in the coordinates of the moment
	})
	step()
	testing.expect(t, found_result, "the floor is under that pixel")
testing.expect(t, abs(screen_result.x - 300) < 1e-3 && abs(screen_result.y - 250) < 1e-3, "back to the same pixel")
	testing.expect_value(t, floor_result.y, 0)
}

turned_box_sketch :: proc() {
	push()
	turn_about(20, .X)
	turn_about(35, .Y)
	turn_about(50, .Z)
	box(0, 0, 0, 1, Look{})
	pop()
}

@(test)
test_the_angle_of_a_box_in_collision_is_the_turn_that_turn_writes :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(200, 200)
	draw(turned_box_sketch)
	step()
	items := win_for(w).list.scene.items
	if !testing.expect_value(t, len(items), 1) {
		return
	}
	// the box drawn after turns about x, y and z has, as the columns of its matrix, the axes collide gives
	// the angle { 20, 35, 50 }
	axes := collide.box_axes({20, 35, 50})
	for column in 0 ..< 3 {
		for row in 0 ..< 3 {
			testing.expectf(t, abs(f64(items[0].model[row][column]) - axes[column][row]) < 1e-5, "column %d row %d: drawn %v, collision %v", column, row, items[0].model[row][column], axes[column][row])
		}
	}
}
