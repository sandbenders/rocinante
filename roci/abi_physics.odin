// SPDX-License-Identifier: 0BSD
//
// The C side of the 2D physics: bodies are numbers (`roci_body_id`, 0 for none), made by the shape's numbers, moved by gravity and what
// they meet each frame (the physics steps as every frame ends), and read with `roci_body_pos` and the rest. Pixels, degrees turning
// clockwise, and seconds, as in the language; a circle's place is its middle and a box's its top left corner.
package roci

import "core:c"

@(export, link_name = "roci_simulate_circle")
abi_simulate_circle :: proc "c" (x, y, radius: f64) -> c.int {
	context = abi_context()
	return c.int(physics_body(Physics_Desc{kind = .Circle, pos = {x, y}, radius = radius, density = -1, friction = -1, bounce = -1}))
}

@(export, link_name = "roci_simulate_box")
abi_simulate_box :: proc "c" (x, y, width, height, angle: f64) -> c.int {
	context = abi_context()
	return c.int(physics_body(Physics_Desc{kind = .Box, pos = {x, y}, size = {width, height}, angle = angle, density = -1, friction = -1, bounce = -1}))
}

@(export, link_name = "roci_fixed_circle")
abi_fixed_circle :: proc "c" (x, y, radius: f64) -> c.int {
	context = abi_context()
	return c.int(physics_body(Physics_Desc{kind = .Circle, fixed = true, pos = {x, y}, radius = radius, density = -1, friction = -1, bounce = -1}))
}

@(export, link_name = "roci_fixed_box")
abi_fixed_box :: proc "c" (x, y, width, height, angle: f64) -> c.int {
	context = abi_context()
	return c.int(physics_body(Physics_Desc{kind = .Box, fixed = true, pos = {x, y}, size = {width, height}, angle = angle, density = -1, friction = -1, bounce = -1}))
}

@(export, link_name = "roci_fixed_wall")
abi_fixed_wall :: proc "c" (from_x, from_y, to_x, to_y: f64) -> c.int {
	context = abi_context()
	return c.int(physics_body(Physics_Desc{kind = .Segment, fixed = true, from = {from_x, from_y}, to = {to_x, to_y}, density = -1, friction = -1, bounce = -1}))
}

@(export, link_name = "roci_no_simulate")
abi_no_simulate :: proc "c" (body: c.int) {
	context = abi_context()
	physics_destroy(Physics_Body(body))
}

@(export, link_name = "roci_gravity")
abi_gravity :: proc "c" (x, y: f64) {
	context = abi_context()
	physics_gravity({x, y})
}

@(export, link_name = "roci_kick")
abi_kick :: proc "c" (body: c.int, dx, dy: f64) {
	context = abi_context()
	physics_kick(Physics_Body(body), {dx, dy})
}

@(export, link_name = "roci_body_pos")
abi_body_pos :: proc "c" (body: c.int) -> Abi_Vec2 {
	context = abi_context()
	p := physics_state(Physics_Body(body)).pos
	return {p.x, p.y}
}

@(export, link_name = "roci_body_angle")
abi_body_angle :: proc "c" (body: c.int) -> f64 {
	context = abi_context()
	return physics_state(Physics_Body(body)).angle
}

@(export, link_name = "roci_body_vel")
abi_body_vel :: proc "c" (body: c.int) -> Abi_Vec2 {
	context = abi_context()
	v := physics_state(Physics_Body(body)).vel
	return {v.x, v.y}
}

@(export, link_name = "roci_body_spin")
abi_body_spin :: proc "c" (body: c.int) -> f64 {
	context = abi_context()
	return physics_state(Physics_Body(body)).spin
}

@(export, link_name = "roci_body_exists")
abi_body_exists :: proc "c" (body: c.int) -> c.int {
	context = abi_context()
	return 1 if physics_exists(Physics_Body(body)) else 0
}

@(export, link_name = "roci_body_pose")
abi_body_pose :: proc "c" (body: c.int, x, y, angle: f64) {
	context = abi_context()
	physics_pose(Physics_Body(body), {x, y}, angle)
}

@(export, link_name = "roci_body_motion")
abi_body_motion :: proc "c" (body: c.int, vx, vy, spin: f64) {
	context = abi_context()
	physics_motion(Physics_Body(body), {vx, vy}, spin)
}

@(export, link_name = "roci_body_feel")
abi_body_feel :: proc "c" (body: c.int, density, friction, bounce: f64) {
	context = abi_context()
	physics_feel(Physics_Body(body), density, friction, bounce)
}

abi_physics_group :: proc(all: ^[dynamic]Abi_Entry) {
	append(all, abi_entry("roci_simulate_circle", typeid_of(type_of(abi_simulate_circle)), "roci_body_id roci_simulate_circle(double x, double y, double radius)", "Gives a circle to the physics, which moves it every frame by gravity and by what it meets: its middle at x, y, in pixels. Gives its number, or 0 when it cannot be made (a radius of nothing, a number that is not one). The first body makes the world."))
	append(all, abi_entry("roci_simulate_box", typeid_of(type_of(abi_simulate_box)), "roci_body_id roci_simulate_box(double x, double y, double width, double height, double angle)", "Gives a rectangle to the physics: its top left corner at x, y, turned `angle` degrees clockwise about its middle. Gives its number, or 0 when it cannot be made."))
	append(all, abi_entry("roci_fixed_circle", typeid_of(type_of(abi_fixed_circle)), "roci_body_id roci_fixed_circle(double x, double y, double radius)", "Gives a circle to the physics that is not pushed and never moves by itself; roci_body_pose moves it, and it pushes what it meets."))
	append(all, abi_entry("roci_fixed_box", typeid_of(type_of(abi_fixed_box)), "roci_body_id roci_fixed_box(double x, double y, double width, double height, double angle)", "Gives a rectangle to the physics that is not pushed and never moves by itself; roci_body_pose moves it, and it pushes what it meets."))
	append(all, abi_entry("roci_fixed_wall", typeid_of(type_of(abi_fixed_wall)), "roci_body_id roci_fixed_wall(double from_x, double from_y, double to_x, double to_y)", "Gives a wall to the physics, a line from one place to another, which never moves."))
	append(all, abi_entry("roci_no_simulate", typeid_of(type_of(abi_no_simulate)), "void roci_no_simulate(roci_body_id body)", "Takes a body out of the physics."))
	append(all, abi_entry("roci_gravity", typeid_of(type_of(abi_gravity)), "void roci_gravity(double x, double y)", "Sets the gravity of the physics in pixels a second each second: 0, 400 pulls things down (y goes down) and is what a world has to start with."))
	append(all, abi_entry("roci_kick", typeid_of(type_of(abi_kick)), "void roci_kick(roci_body_id body, double dx, double dy)", "Adds a speed to a body, however heavy it is: 0, -300 sends it up at 300 pixels a second more than it had."))
	append(all, abi_entry("roci_body_pos", typeid_of(type_of(abi_body_pos)), "roci_vec2 roci_body_pos(roci_body_id body)", "Where a body is: a circle's middle, a rectangle's top left corner. 0, 0 for a body that is not there."))
	append(all, abi_entry("roci_body_angle", typeid_of(type_of(abi_body_angle)), "double roci_body_angle(roci_body_id body)", "How far a body is turned, in degrees clockwise, from 0 up to 360."))
	append(all, abi_entry("roci_body_vel", typeid_of(type_of(abi_body_vel)), "roci_vec2 roci_body_vel(roci_body_id body)", "A body's speed in pixels a second."))
	append(all, abi_entry("roci_body_spin", typeid_of(type_of(abi_body_spin)), "double roci_body_spin(roci_body_id body)", "How fast a body turns, in degrees a second, clockwise."))
	append(all, abi_entry("roci_body_exists", typeid_of(type_of(abi_body_exists)), "int roci_body_exists(roci_body_id body)", "1 while a body is in the physics, 0 for one taken out or never made."))
	append(all, abi_entry("roci_body_pose", typeid_of(type_of(abi_body_pose)), "void roci_body_pose(roci_body_id body, double x, double y, double angle)", "Puts a body somewhere, in the same places roci_body_pos gives. A fixed body put somewhere moves there in the next step and pushes what it meets on the way; a wall is not moved."))
	append(all, abi_entry("roci_body_motion", typeid_of(type_of(abi_body_motion)), "void roci_body_motion(roci_body_id body, double vx, double vy, double spin)", "Gives a body a speed in pixels a second and a spin in degrees a second."))
	append(all, abi_entry("roci_body_feel", typeid_of(type_of(abi_body_feel)), "void roci_body_feel(roci_body_id body, double density, double friction, double bounce)", "Sets how heavy, how rough and how bouncy a body is (1, 0.6 and 0 are usual); a negative number leaves what it has."))
}
