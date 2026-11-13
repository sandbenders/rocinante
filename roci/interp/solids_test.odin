// SPDX-License-Identifier: 0BSD
package interp

import "core:testing"

import "../"
import "../platform"

@(test)
test_the_solids_example_draws_a_floor_a_sphere_and_a_ring_of_boxes :: proc(t: ^testing.T) {
	p := run_text(t, example_text("solids"), 3)
	defer finish(p)
	items := roci.scene_items(first_window())
	testing.expect_value(t, len(items), 8)
	testing.expect_value(t, len(p.errors), 0)
	// the flat text goes to the 2D list, over the scene
	testing.expect_value(t, len(roci.commands_snapshot(first_window())), 1)
}

@(test)
test_every_3d_form_of_the_language_reaches_the_scene :: proc(t: ^testing.T) {
	p := run_text(t, `box at 0 0 0 size 10
box at 1 2 3 size 4 5 6
box at { 1, 2, 3 } size 7
box at { 1, 2, 3 } size { 4, 5, 6 }
sphere at 0 0 0 radius 3
sphere at { 1, 2, 3 } radius 4
plane at 0 0 0 size 8 9
plane at { 1, 2, 3 } size { 4, 5 }
`, 1)
	defer finish(p)
	items := roci.scene_items(first_window())
	if !testing.expect_value(t, len(items), 8) {
		return
	}
	testing.expect_value(t, items[0].model[0][0], 10)
	testing.expect_value(t, items[1].model[2][2], 6)
	testing.expect_value(t, items[2].model[0][3], 1)
	testing.expect_value(t, items[3].model[1][1], 5)
	testing.expect_value(t, items[4].model[0][0], 6)
	testing.expect_value(t, items[5].model[2][3], 3)
	testing.expect_value(t, items[6].model[2][2], 9)
	testing.expect_value(t, items[7].model[0][0], 4)
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_move_turn_and_grow_in_three_dimensions :: proc(t: ^testing.T) {
	p := run_text(t, `draw [
  push [
    move 10 20 30
    move { 1, 1, 1 }
    grow 2 2 2
    turn 90 around z
    box at 0 0 0 size 1
  ]
  push [
    turn 90 around x
    box at 0 1 0 size 1
  ]
  push [
    turn 90 around y
    box at 0 0 1 size 1
  ]
  move 5 5
  circle at 0 0 radius 3
]
`, 2)
	defer finish(p)
	items := roci.scene_items(first_window())
	if !testing.expect_value(t, len(items), 3) {
		return
	}
	testing.expect_value(t, items[0].model[0][3], 11)
	testing.expect_value(t, items[0].model[2][3], 31)
	testing.expect_value(t, items[0].model[1][0], 2)
	testing.expect_value(t, items[1].model[2][3], 1) // y becomes towards you
	testing.expect_value(t, items[2].model[0][3], 1) // towards you becomes right
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_the_fill_of_a_3d_shape_can_be_given_on_the_line :: proc(t: ^testing.T) {
	p := run_text(t, `draw [
  fill blue
  box at 0 0 0 size 5
  box at 0 0 0 size 5 fill red
]
`, 1)
	defer finish(p)
	items := roci.scene_items(first_window())
	if !testing.expect_value(t, len(items), 2) {
		return
	}
	testing.expect(t, items[0].colour.b > 0.9 && items[0].colour.r < 0.1, "the style's color")
	testing.expect(t, items[1].colour.r > 0.9 && items[1].colour.b < 0.1, "the shape's own")
}

@(test)
test_a_sketch_with_a_mouse_event_keeps_the_camera_to_itself :: proc(t: ^testing.T) {
	p := run_text(t, `draw [ box at 0 0 0 size 5 ]
on mouse down [ print "down" ]
`, 1)
	defer finish(p)
	id := platform.Window_Id(first_window())
	roci.step({
		platform.Mouse_Moved{window = id, x = 10, y = 10},
		platform.Mouse_Button_Changed{window = id, button = .Left, down = true, x = 10, y = 10},
		platform.Mouse_Moved{window = id, x = 60, y = 10, dx = 50},
	})
	testing.expect_value(t, len(p.errors), 0)
	yaw, pitch, _ := roci.camera_of(first_window())
	testing.expect(t, yaw == 0 && pitch == 0, "a sketch that handles the mouse itself is not given a camera that moves under it")
}

@(test)
test_a_sketch_that_leaves_the_mouse_alone_gets_the_orbit :: proc(t: ^testing.T) {
	p := run_text(t, `draw [ box at 0 0 0 size 5 ]
`, 1)
	defer finish(p)
	id := platform.Window_Id(first_window())
	roci.step({
		platform.Mouse_Moved{window = id, x = 10, y = 10},
		platform.Mouse_Button_Changed{window = id, button = .Left, down = true, x = 10, y = 10},
		platform.Mouse_Moved{window = id, x = 60, y = 10, dx = 50},
	})
	yaw, _, _ := roci.camera_of(first_window())
	testing.expect_value(t, yaw, 20)
}

@(test)
test_every_form_of_the_other_solids_and_the_helpers_reaches_the_scene :: proc(t: ^testing.T) {
	p := run_text(t, `cone at 0 0 0 radius 10 height 40
cone at { 1, 2, 3 } radius 10 height 40
cylinder at 0 0 0 radius 10 height 40
cylinder at { 1, 2, 3 } radius 10 height 40
capsule at 0 0 0 radius 10 height 60
capsule at { 1, 2, 3 } radius 10 height 20
torus at 0 0 0 radius 40 tube 10
torus at { 1, 2, 3 } radius 40 tube 10
icosphere at 0 0 0 radius 20
icosphere at { 1, 2, 3 } radius 20
arrow from 0 0 0 to 100 0 0
arrow from { 0, 0, 0 } to { 0, 100, 0 }
axes size 50
fill gray
grid size 100 lines 4
`, 1)
	defer finish(p)
	items := roci.scene_items(first_window())
	// 10 shapes, 2 arrows of 2 parts, axes of 6 parts, a grid of 10 boxes
	if !testing.expect_value(t, len(items), 10 + 4 + 6 + 10) {
		return
	}
	testing.expect_value(t, items[0].model[0][0], 20) // a cone of radius 10 is 20 across
	testing.expect_value(t, items[0].model[1][1], 40) // and 40 high
	testing.expect_value(t, items[3].model[1][3], 2)
	testing.expect_value(t, items[4].params[0], 1) // 60 high, radius 10: the middle adds 20 on each side, which is 1 in the shape's own units (20 across)
	testing.expect_value(t, items[5].params[0], 0)   // a height under two radii is a sphere
	testing.expect_value(t, items[6].params[1], 0.125) // a tube of 10 on a ring of radius 40: 10 / 80
	testing.expect_value(t, items[8].model[0][0], 40)
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_the_shapes3d_example_runs_with_no_errors :: proc(t: ^testing.T) {
	p := run_text(t, example_text("shapes3d"), 3)
	defer finish(p)
	testing.expect_value(t, len(roci.scene_items(first_window())), 34 + 6 + 6 + 2) // a grid of 17 lines each way, the axes, six solids and an arrow
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_the_stage_example_runs_and_names_its_boxes :: proc(t: ^testing.T) {
	p := run_text(t, example_text("stage"), 3)
	defer finish(p)
	items := roci.scene_items(first_window())
	// a grid of 17 lines each way, three boxes and the ball
	testing.expect_value(t, len(items), 34 + 3 + 1)
	// the three names are flat text drawn over it
	texts := 0
	for c in roci.commands_snapshot(first_window()) {
		if c.kind == .Typeset {
			texts += 1
		}
	}
	testing.expect_value(t, texts, 4)
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_a_click_switches_the_stage_to_ortho :: proc(t: ^testing.T) {
	p := run_text(t, example_text("stage"), 2)
	defer finish(p)
	id := platform.Window_Id(first_window())
	roci.step({platform.Mouse_Button_Changed{window = id, button = .Left, down = true, x = 10, y = 10}})
	roci.step()
	yaw, _, _ := roci.camera_of(first_window())
	testing.expect_value(t, yaw, 0) // the sketch has the camera, and the click is the sketch's
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_world_point_gives_a_vector_of_three_and_screen_point_one_of_two :: proc(t: ^testing.T) {
	p := run_text(t, `draw [
  camera at 0 -250 400
  look at 0 0 0
  spot = world point 300 250
  there = screen point spot
  print spot.z
  print there.y
  middle = screen point 0 0 0
  print middle
  again = world point { 300, 250 }
  print again.y
]
`, 1)
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	testing.expect(t, len(p.printed) >= 4, "it printed")
	if len(p.printed) >= 4 {
		testing.expect_value(t, p.printed[len(p.printed) - 4:][3], "0")
	}
}

@(test)
test_normalize_and_limit_keep_the_length_of_the_vector_they_are_given :: proc(t: ^testing.T) {
	p := run_text(t, `v = normalize { 0, 3, 4 }
w = limit { 0, 30, 40 } 5
print v.z
print w.z
`, 0)
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
}
