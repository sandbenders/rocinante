// SPDX-License-Identifier: 0BSD
//
// The 3D verbs: `box`, `sphere` and `plane`, and the transforms that move, turn and scale
// them (`move x y z`, `turn 30 around y`, `grow x y z`). They fill the window's 3D scene
// (gfx/scene3.odin), which is drawn first with a depth buffer; every 2D verb is drawn over
// it. A window that has drawn 3D lets the mouse turn the camera: a drag orbits the origin
// and the wheel zooms, unless the sketch reads the mouse itself or the drag begins on a widget.
package roci

import "core:math"
import "ui"
import "gfx"

Axis :: gfx.Axis3

@(private)
add_shape3 :: proc(shape: gfx.Shape3, at, size: [3]f64, look: Look) {
	list := current_list()
	opened := begin_look(list, look)
	if list.style.fill_on {
		gfx.scene_add(&list.scene, shape, at, size, list.style.fill)
	}
	end_look(list, opened)
}

box_xyz :: proc(x, y, z, width, height, depth: f64, look := Look{}) {
	add_shape3(.Box, {x, y, z}, {width, height, depth}, look)
}

box_xyz_side :: proc(x, y, z, side: f64, look := Look{}) {
	add_shape3(.Box, {x, y, z}, {side, side, side}, look)
}

box_v_side :: proc(position: [3]f64, side: f64, look := Look{}) {
	add_shape3(.Box, position, {side, side, side}, look)
}

box_v_size :: proc(position, size: [3]f64, look := Look{}) {
	add_shape3(.Box, position, size, look)
}

// A box about a point, drawn in the fill: a place and a side, or a place and a width, height and depth.
box :: proc{box_xyz, box_xyz_side, box_v_side, box_v_size}

sphere_xyzr :: proc(x, y, z, radius: f64, look := Look{}) {
	add_shape3(.Sphere, {x, y, z}, {radius * 2, radius * 2, radius * 2}, look)
}

sphere_vr :: proc(position: [3]f64, radius: f64, look := Look{}) {
	sphere_xyzr(position.x, position.y, position.z, radius, look)
}

// A sphere about a point.
sphere :: proc{sphere_xyzr, sphere_vr}

plane_xyz :: proc(x, y, z, width, depth: f64, look := Look{}) {
	add_shape3(.Plane, {x, y, z}, {width, 1, depth}, look)
}

plane_v :: proc(position: [3]f64, size: [2]f64, look := Look{}) {
	plane_xyz(position.x, position.y, position.z, size.x, size.y, look)
}

// A flat square in the plane of x and z, like a floor, about a point.
plane :: proc{plane_xyz, plane_v}

move_xyz :: proc(x, y, z: f64) {
	gfx.scene_move(&current_list().scene, x, y, z)
}

move_v3 :: proc(offset: [3]f64) {
	move_xyz(offset.x, offset.y, offset.z)
}

turn_about :: proc(degrees: f64, axis: Axis) {
	gfx.scene_turn(&current_list().scene, degrees, axis)
}

grow_xyz :: proc(x, y, z: f64) {
	gfx.scene_grow(&current_list().scene, x, y, z)
}

// Turns the camera of a window by a drag, in pixels, and by wheel notches.
orbit_window :: proc(w: ^Win, dx, dy: f32) {
	gfx.scene_orbit(&w.list.scene, dx, dy)
}

// Whether the mouse should turn the camera of this window: it has drawn 3D, the sketch has
// not read the mouse in its last frame, and the pointer is not on a widget.
@(private)
orbit_allowed :: proc(w: ^Win) -> bool {
	scene := &w.list.scene
	if !(scene.shown || len(scene.items) > 0) || w.mouse_read {
		return false
	}
	return !ui.over_widget(w.ui, f32(w.mouse.x), f32(w.mouse.y))
}

@(private)
orbit_drag :: proc(w: ^Win, dx, dy: f32) {
	if .Left in w.buttons && orbit_allowed(w) && !(math.is_nan(f64(dx)) || math.is_nan(f64(dy))) {
		gfx.scene_orbit(&w.list.scene, dx, dy)
	}
}

@(private)
orbit_wheel :: proc(w: ^Win, dy: f32) {
	if orbit_allowed(w) {
		gfx.scene_zoom(&w.list.scene, dy)
	}
}

// Says that the sketch reads the mouse (in one window, or in every window when `w` is 0), so
// the mouse no longer turns that window's 3D camera.
note_mouse_read :: proc(w: Window = 0) {
	if w == 0 {
		for each in the.windows {
			each.mouse_read = true
		}
	} else if found := win_for(w); found != nil {
		found.mouse_read = true
	}
}

@(private)
read_mouse :: proc() {
	if the.current != nil {
		the.current.mouse_read = true
	}
}

// The 2D commands a window recorded, for tests and tools.
commands_snapshot :: proc(w: Window) -> []gfx.Recorded {
	if win := win_for(w); win != nil {
		return win.list.commands[:]
	}
	return nil
}

// The 3D shapes a window drew in its last frame, for tests and tools.
scene_items :: proc(w: Window) -> []gfx.Item3 {
	if win := win_for(w); win != nil {
		return win.list.scene.items[:]
	}
	return nil
}

// How a window's camera is turned: yaw and pitch in degrees, and the zoom in wheel notches.
camera_of :: proc(w: Window) -> (yaw, pitch, zoom: f32) {
	if win := win_for(w); win != nil {
		return win.list.scene.yaw, win.list.scene.pitch, win.list.scene.zoom
	}
	return
}
