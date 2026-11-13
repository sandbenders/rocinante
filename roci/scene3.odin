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
Light_Kind :: gfx.Light_Kind

@(private)
add_shape3 :: proc(shape: gfx.Shape3, at, size: [3]f64, look: Look, params := [2]f64{}) {
	list := current_list()
	opened := begin_look(list, look)
	if list.style.fill_on {
		// a picture as the fill paints the solid with it, over the shape's own coordinates (the mode words of the flat fills do not apply)
		gfx.scene_add(&list.scene, shape, at, size, list.style.fill, params, list.style.fill_image.image)
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
	if !(scene.shown || len(scene.items) > 0) || w.mouse_read || scene.fixed {
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

// The commands a window drew in its last frame, each with its style and transform, for tests and tools.
commands_whole :: proc(w: Window, allocator := context.temp_allocator) -> []gfx.Command {
	win := win_for(w)
	if win == nil {
		return nil
	}
	out := make([]gfx.Command, len(win.list.commands), allocator)
	for i in 0 ..< len(out) {
		out[i] = gfx.command_at(&win.list, i)
	}
	return out
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

// ---- the other solids ----

@(private)
add_round3 :: proc(shape: gfx.Shape3, at: [3]f64, radius, height: f64, look: Look) {
	add_shape3(shape, at, {radius * 2, height, radius * 2}, look)
}

cone_xyz :: proc(x, y, z, radius, height: f64, look := Look{}) {
	add_round3(.Cone, {x, y, z}, radius, height, look)
}

cone_v :: proc(position: [3]f64, radius, height: f64, look := Look{}) {
	add_round3(.Cone, position, radius, height, look)
}

// A cone about its middle, its tip up, from a radius and a height.
cone :: proc{cone_xyz, cone_v}

cylinder_xyz :: proc(x, y, z, radius, height: f64, look := Look{}) {
	add_round3(.Cylinder, {x, y, z}, radius, height, look)
}

cylinder_v :: proc(position: [3]f64, radius, height: f64, look := Look{}) {
	add_round3(.Cylinder, position, radius, height, look)
}

// A cylinder about its middle, standing on its end, from a radius and a height.
cylinder :: proc{cylinder_xyz, cylinder_v}

@(private)
add_capsule :: proc(at: [3]f64, given_radius, height: f64, look: Look) {
	// the height counts the rounded ends, so it is never less than the two radii
	radius := abs(given_radius)
	stretch := 0.0
	if radius > 0 {
		stretch = max(height - radius * 2, 0) / (radius * 4)
	}
	add_shape3(.Capsule, at, {radius * 2, radius * 2, radius * 2}, look, {stretch, 0})
}

capsule_xyz :: proc(x, y, z, radius, height: f64, look := Look{}) {
	add_capsule({x, y, z}, radius, height, look)
}

capsule_v :: proc(position: [3]f64, radius, height: f64, look := Look{}) {
	add_capsule(position, radius, height, look)
}

// A capsule about its middle: a cylinder with a half sphere on each end, the height counting both.
capsule :: proc{capsule_xyz, capsule_v}

@(private)
add_torus :: proc(at: [3]f64, given_radius, tube: f64, look: Look) {
	radius := abs(given_radius)
	ratio := 0.0
	if radius > 0 {
		ratio = abs(tube) / (radius * 2)
	}
	add_shape3(.Torus, at, {radius * 2, radius * 2, radius * 2}, look, {0, ratio})
}

torus_xyz :: proc(x, y, z, radius, tube: f64, look := Look{}) {
	add_torus({x, y, z}, radius, tube, look)
}

torus_v :: proc(position: [3]f64, radius, tube: f64, look := Look{}) {
	add_torus(position, radius, tube, look)
}

// A ring lying in the plane of x and z about a point: its radius is to the middle of the tube, whose own radius is `tube`.
torus :: proc{torus_xyz, torus_v}

icosphere_xyzr :: proc(x, y, z, radius: f64, look := Look{}) {
	add_shape3(.Icosphere, {x, y, z}, {radius * 2, radius * 2, radius * 2}, look)
}

icosphere_vr :: proc(position: [3]f64, radius: f64, look := Look{}) {
	icosphere_xyzr(position.x, position.y, position.z, radius, look)
}

// A sphere of 80 flat faces, which shows how the light falls on each.
icosphere :: proc{icosphere_xyzr, icosphere_vr}

// ---- helpers ----

grid_size_lines :: proc(size: f64, lines: int, look := Look{}) {
	list := current_list()
	opened := begin_look(list, look)
	if list.style.fill_on {
		gfx.scene_grid(&list.scene, size, lines, list.style.fill)
	}
	end_look(list, opened)
}

// A grid on the floor, `lines` squares across, in the fill.
grid :: proc{grid_size_lines}

axes_size :: proc(size: f64) {
	gfx.scene_axes(&current_list().scene, size)
}

// The three axes as arrows: x red, y green, z blue.
axes :: proc{axes_size}

arrow_xyz :: proc(x1, y1, z1, x2, y2, z2: f64, look := Look{}) {
	arrow_v({x1, y1, z1}, {x2, y2, z2}, look)
}

arrow_v :: proc(from, to: [3]f64, look := Look{}) {
	list := current_list()
	opened := begin_look(list, look)
	if list.style.fill_on {
		gfx.scene_arrow(&list.scene, from, to, list.style.fill)
	}
	end_look(list, opened)
}

// An arrow from one place to another, in the fill.
arrow :: proc{arrow_xyz, arrow_v}

// ---- the camera ----

@(private)
canvas_of_current :: proc() -> [2]f32 {
	return {f32(width()), f32(height())}
}

// Puts the eye somewhere. The camera then stays there, looking at the middle or at what
// `look_at` says, until the frame ends, and the mouse no longer turns it.
camera_xyz :: proc(x, y, z: f64, fov := 0.0) {
	scene := &current_list().scene
	gfx.scene_camera_at(scene, canvas_of_current(), {x, y, z})
	if fov > 0 {
		scene.fov = f32(fov)
	}
}

camera_v :: proc(eye: [3]f64, fov := 0.0) {
	camera_xyz(eye.x, eye.y, eye.z, fov)
}

camera :: proc{camera_xyz, camera_v}

look_at_xyz :: proc(x, y, z: f64) {
	gfx.scene_look_at(&current_list().scene, canvas_of_current(), {x, y, z})
}

look_at_v :: proc(target: [3]f64) {
	look_at_xyz(target.x, target.y, target.z)
}

// Aims the camera at a place.
look_at :: proc{look_at_xyz, look_at_v}

// Draws the scene without perspective: the same size at every distance, one unit a pixel.
ortho :: proc() {
	current_list().scene.ortho = true
}

// Draws the scene with perspective again, with a field of view in degrees when given (50 otherwise).
perspective :: proc(fov := 0.0) {
	scene := &current_list().scene
	scene.ortho = false
	if fov > 0 {
		scene.fov = f32(fov)
	}
}

// Where a place of the scene shows in the window: its pixel from the top left, in the
// coordinates of the current transform. Gives false for a place behind the camera.
screen_point :: proc(x, y, z: f64) -> (at: [2]f64, visible: bool) {
	scene := &current_list().scene
	return gfx.scene_screen_point(scene, canvas_of_current(), gfx.scene_to_world(scene, {x, y, z}))
}

// The place on the floor (y = 0 of the world) that shows at a pixel of the window, as the
// world has it. Gives false when the pixel looks past the floor.
world_point :: proc(x, y: f64) -> (at: [3]f64, found: bool) {
	return gfx.scene_world_point(&current_list().scene, canvas_of_current(), {x, y})
}

// ---- lights and materials ----

// Adds a light to the scene: the first one of a frame takes the usual lights away, so a sketch
// that writes its own writes all of them (an ambient light too). A point or spot light's place and
// where a spot light looks are in the coordinates of the current transform; a sun's `at` is the
// direction towards it in the world. Gives false when the scene already has the most lights it can (`MAX_LIGHTS`),
// and the light is left out. Any of them left out is the usual: a white light 500 units
// from half-brightness, a spot light's half angle of 30 degrees, looking at the middle.
light :: proc(kind: gfx.Light_Kind, at: Maybe([3]f64) = nil, aim: Maybe([3]f64) = nil, colour: Maybe(Colour) = nil, falloff: Maybe(f64) = nil, angle: Maybe(f64) = nil) -> (room: bool) {
	scene := &current_list().scene
	l := gfx.Light3{kind = kind, colour = {1, 1, 1}, falloff = 500, angle = 30}
	if c, ok := colour.?; ok {
		l.colour = {c.r / 255, c.g / 255, c.b / 255}
	}
	if f, ok := falloff.?; ok {l.falloff = f32(f)}
	if a, ok := angle.?; ok {l.angle = f32(a)}
	switch kind {
	case .Ambient:
	case .Sun:
		l.at = at.? or_else gfx.USUAL_SUN.at
	case .Point:
		l.at = gfx.scene_to_world(scene, at.? or_else {})
	case .Spot:
		l.at = gfx.scene_to_world(scene, at.? or_else {0, -200, 0})
		l.aim = gfx.scene_to_world(scene, aim.? or_else {})
	}
	return gfx.scene_light(scene, l) != .Too_Many
}

// Shapes drawn from now on are flat in their color.
no_lights :: proc() {
	gfx.scene_no_lights(&current_list().scene)
}

// What 3D shapes drawn from now on are made of: how metal (0 to 1), how rough (0 to 1) and how much
// they emissive by themselves (0 to 1); a word left out keeps what it was.
material :: proc(metallic: Maybe(f64) = nil, roughness: Maybe(f64) = nil, emissive: Maybe(f64) = nil) {
	gfx.scene_material(&current_list().scene, metallic, roughness, emissive)
}

// The lights a window wrote in its last frame and the material and lighting state, for tests and tools.
scene_state :: proc(w: Window) -> (lights: []gfx.Light3, lit, unlit: bool, material: gfx.Material3) {
	if win := win_for(w); win != nil {
		s := &win.list.scene
		return s.lights[:], s.lit, s.unlit, s.material
	}
	return
}

// Turns shadows on for the rest of the frame: the first `sun` or `spot` light (the usual sun, when no
// light is written) casts them, and everything in the scene is dark where it does not reach. Point lights cast none.
shadows :: proc() {
	gfx.scene_shadows(&current_list().scene)
}

// Whether a window turned shadows on in its last frame, for tests and tools.
shadows_of :: proc(w: Window) -> bool {
	if win := win_for(w); win != nil {
		return win.list.scene.shadows
	}
	return false
}

// ---- models ----

Model :: gfx.Model_Id

// Reads a model (the bytes of a `.glb`, a `.gltf` or an `.obj`) and keeps it. `path` and `stamp` (when the file
// was last changed) are how it is told from the others and found again: the same path with a new stamp
// replaces what was kept, under the same number. `reader` gives the files a model names beside itself: a
// `.gltf`'s data, an `.obj`'s `.mtl`, and the pictures.
// Gives the model, or why it could not be read.
add_model :: proc(path: string, stamp: i64, bytes: []u8, reader: gfx.Gltf_Reader = nil) -> (model: Model, error: gfx.Gltf_Error) {
	data, read_error := gfx.model_read(path, bytes, reader)
	if read_error != .None {
		return 0, read_error
	}
	return gfx.model_add(path, stamp, data), .None
}

// The number of the model read from `path` when it was last changed at `stamp`, if there is one.
find_model :: proc(path: string, stamp: i64) -> (Model, bool) {
	return gfx.model_find(path, stamp)
}

// Which models exist now: it changes when every model is let go (`shutdown`).
model_epoch :: proc() -> int {
	return gfx.model_epoch()
}

// Draws a loaded model with its middle at a place, as big as `size` along its longest side.
// Its colors come from the model's own materials.
model_xyz :: proc(model: Model, x, y, z, size: f64) {
	gfx.scene_add_loaded_model(&current_list().scene, model, {x, y, z}, size)
}

model_v :: proc(model: Model, position: [3]f64, size: f64) {
	model_xyz(model, position.x, position.y, position.z, size)
}

// Draws a loaded model: `model_xyz` or `model_v`.
draw_model :: proc{model_xyz, model_v}

// How many pictures a loaded model names that could not be read (a file that is not beside it, or not a
// picture), which leave their material in its plain color.
model_lost_textures :: proc(model: Model) -> int {
	if data := gfx.model_data(model); data != nil {
		return data.lost_textures
	}
	return 0
}

// The line from the eye through a pixel of the window, as two places of the world (y down): the eye,
// and a place far along the way the pixel looks. `cast` along it finds what shows at the pixel.
pixel_ray :: proc(x, y: f64) -> (from, to: [3]f64) {
	return gfx.scene_pixel_ray(&current_list().scene, canvas_of_current(), {x, y})
}

// The corners of a loaded model's triangles, three for each, as `model` would draw it at a place with a
// longest side of `size`, under the transform of the moment; the shape of a model for collision.
model_triangles :: proc(model: Model, x, y, z, size: f64, allocator := context.allocator) -> [][3]f64 {
	return gfx.scene_model_triangles(&current_list().scene, model, {x, y, z}, size, allocator)
}
