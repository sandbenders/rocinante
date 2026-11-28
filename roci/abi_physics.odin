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

// The corners of an outline as the program gave them, or none when there are fewer than three or the array is missing.
@(private = "file")
abi_corners :: proc(corners: [^]Abi_Vec2, count: c.int) -> [][2]f64 {
	if corners == nil || count < 3 {
		return nil
	}
	points := make([][2]f64, int(count), context.temp_allocator)
	for i in 0 ..< int(count) {
		points[i] = {corners[i].x, corners[i].y}
	}
	return points
}

@(export, link_name = "roci_simulate_polygon")
abi_simulate_polygon :: proc "c" (corners: [^]Abi_Vec2, count: c.int) -> c.int {
	context = abi_context()
	points := abi_corners(corners, count)
	if points == nil {
		return 0
	}
	return c.int(physics_body(Physics_Desc{kind = .Polygon, points = points, density = -1, friction = -1, bounce = -1}))
}

@(export, link_name = "roci_fixed_polygon")
abi_fixed_polygon :: proc "c" (corners: [^]Abi_Vec2, count: c.int) -> c.int {
	context = abi_context()
	points := abi_corners(corners, count)
	if points == nil {
		return 0
	}
	return c.int(physics_body(Physics_Desc{kind = .Polygon, fixed = true, points = points, density = -1, friction = -1, bounce = -1}))
}

@(export, link_name = "roci_body_points")
abi_body_points :: proc "c" (body: c.int, corners: [^]Abi_Vec2, capacity: c.int) -> c.int {
	context = abi_context()
	points := physics_polygon(Physics_Body(body), context.temp_allocator)
	for i in 0 ..< min(len(points), int(capacity)) {
		if corners != nil {
			corners[i] = {points[i].x, points[i].y}
		}
	}
	return c.int(len(points))
}

// A zone: a body that never moves and nothing bumps into, which says (roci_on "zone enter" and "zone leave") what comes into it and goes out.
@(export, link_name = "roci_zone_circle")
abi_zone_circle :: proc "c" (x, y, radius: f64) -> c.int {
	context = abi_context()
	return c.int(physics_body(Physics_Desc{kind = .Circle, fixed = true, sensor = true, pos = {x, y}, radius = radius, density = -1, friction = -1, bounce = -1}))
}

@(export, link_name = "roci_zone_box")
abi_zone_box :: proc "c" (x, y, width, height, angle: f64) -> c.int {
	context = abi_context()
	return c.int(physics_body(Physics_Desc{kind = .Box, fixed = true, sensor = true, pos = {x, y}, size = {width, height}, angle = angle, density = -1, friction = -1, bounce = -1}))
}

@(export, link_name = "roci_zone_polygon")
abi_zone_polygon :: proc "c" (corners: [^]Abi_Vec2, count: c.int) -> c.int {
	context = abi_context()
	points := abi_corners(corners, count)
	if points == nil {
		return 0
	}
	return c.int(physics_body(Physics_Desc{kind = .Polygon, fixed = true, sensor = true, points = points, density = -1, friction = -1, bounce = -1}))
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

@(export, link_name = "roci_body_hit")
abi_body_hit :: proc "c" (body: c.int) -> f64 {
	context = abi_context()
	return physics_state(Physics_Body(body)).hit
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

Abi_Link_Options :: struct {
	kind:                                                                                                          cstring,
	has_at, has_to, has_axis, has_length, has_stiffness, has_damping, has_limit, has_motor, has_torque, has_collide: c.int,
	at, to, axis:                                                                                                  Abi_Vec2,
	length, stiffness, damping, low, high, speed, torque:                                                          f64,
	collide:                                                                                                       c.int,
}

@(export, link_name = "roci_link")
abi_link :: proc "c" (a, b: c.int, options: ^Abi_Link_Options) -> c.int {
	context = abi_context()
	if options == nil {
		return 0
	}
	joint := Physics_Joint{a = Physics_Body(a), b = Physics_Body(b)}
	if options.kind != nil {
		switch string(options.kind) {
		case "hinge":  joint.kind = .Hinge
		case "rod":    joint.kind = .Rod
		case "spring": joint.kind = .Spring
		case "weld":   joint.kind = .Weld
		case "wheel":  joint.kind = .Wheel
		case "slider": joint.kind = .Slider
		case:          return 0
		}
		joint.set += {.Kind}
	}
	if options.has_at != 0 {
		joint.at, joint.set = {options.at.x, options.at.y}, joint.set + {.At}
	}
	if options.has_to != 0 {
		joint.to, joint.set = {options.to.x, options.to.y}, joint.set + {.To}
	}
	if options.has_axis != 0 {
		joint.axis, joint.set = {options.axis.x, options.axis.y}, joint.set + {.Axis}
	}
	if options.has_length != 0 {
		joint.length, joint.set = options.length, joint.set + {.Length}
	}
	if options.has_stiffness != 0 {
		joint.stiffness, joint.set = options.stiffness, joint.set + {.Stiffness}
	}
	if options.has_damping != 0 {
		joint.damping, joint.set = options.damping, joint.set + {.Damping}
	}
	if options.has_limit != 0 {
		joint.low, joint.high, joint.set = options.low, options.high, joint.set + {.Limit}
	}
	if options.has_motor != 0 {
		joint.speed, joint.set = options.speed, joint.set + {.Motor}
	}
	if options.has_torque != 0 {
		joint.torque, joint.set = options.torque, joint.set + {.Torque}
	}
	if options.has_collide != 0 {
		joint.collide, joint.set = options.collide != 0, joint.set + {.Collide}
	}
	return 1 if physics_join(joint) else 0
}

@(export, link_name = "roci_no_link")
abi_no_link :: proc "c" (a, b: c.int) {
	context = abi_context()
	physics_unjoin(Physics_Body(a), Physics_Body(b))
}

@(export, link_name = "roci_linked")
abi_linked :: proc "c" (a, b: c.int) -> c.int {
	context = abi_context()
	return 1 if physics_joined(Physics_Body(a), Physics_Body(b)) else 0
}

abi_physics_group :: proc(all: ^[dynamic]Abi_Entry) {
	append(all, abi_entry("roci_simulate_circle", typeid_of(type_of(abi_simulate_circle)), "roci_body_id roci_simulate_circle(double x, double y, double radius)", "Gives a circle to the physics, which moves it every frame by gravity and by what it meets: its middle at x, y, in pixels. Gives its number, or 0 when it cannot be made (a radius of nothing, a number that is not one). The first body makes the world."))
	append(all, abi_entry("roci_simulate_box", typeid_of(type_of(abi_simulate_box)), "roci_body_id roci_simulate_box(double x, double y, double width, double height, double angle)", "Gives a rectangle to the physics: its top left corner at x, y, turned `angle` degrees clockwise about its middle. Gives its number, or 0 when it cannot be made."))
	append(all, abi_entry("roci_fixed_circle", typeid_of(type_of(abi_fixed_circle)), "roci_body_id roci_fixed_circle(double x, double y, double radius)", "Gives a circle to the physics that is not pushed and never moves by itself; roci_body_pose moves it, and it pushes what it meets."))
	append(all, abi_entry("roci_fixed_box", typeid_of(type_of(abi_fixed_box)), "roci_body_id roci_fixed_box(double x, double y, double width, double height, double angle)", "Gives a rectangle to the physics that is not pushed and never moves by itself; roci_body_pose moves it, and it pushes what it meets."))
	append(all, abi_entry("roci_fixed_wall", typeid_of(type_of(abi_fixed_wall)), "roci_body_id roci_fixed_wall(double from_x, double from_y, double to_x, double to_y)", "Gives a wall to the physics, a line from one place to another, which never moves."))
	append(all, abi_entry("roci_simulate_polygon", typeid_of(type_of(abi_simulate_polygon)), "roci_body_id roci_simulate_polygon(const roci_vec2 *corners, int count)", "Gives an outline to the physics, any number of corners at least three, in the window's pixels, concave or not. It keeps its shape and moves by gravity and what it meets. Gives its number, or 0 when it cannot be made (fewer than three corners, no area, a number that is not one)."))
	append(all, abi_entry("roci_fixed_polygon", typeid_of(type_of(abi_fixed_polygon)), "roci_body_id roci_fixed_polygon(const roci_vec2 *corners, int count)", "Gives an outline to the physics as ground: it never moves, and things land on it."))
	append(all, abi_entry("roci_body_points", typeid_of(type_of(abi_body_points)), "int roci_body_points(roci_body_id body, roci_vec2 *corners, int capacity)", "The corners of an outline body now, in the window's pixels and in the order they were given. Copies up to `capacity` of them into `corners` (which may be NULL) and gives how many there are, 0 for a body that is not an outline, so a first call with capacity 0 says how big an array to make."))
	append(all, abi_entry("roci_zone_circle", typeid_of(type_of(abi_zone_circle)), "roci_body_id roci_zone_circle(double x, double y, double radius)", "Makes a zone, a circle that never moves and that nothing bumps into: roci_on with \"zone enter\" and \"zone leave\" says which bodies come into it and go out. Gives its number, or 0 when it cannot be made."))
	append(all, abi_entry("roci_zone_box", typeid_of(type_of(abi_zone_box)), "roci_body_id roci_zone_box(double x, double y, double width, double height, double angle)", "A zone that is a rectangle: its top left corner at x, y, turned `angle` degrees clockwise about its middle."))
	append(all, abi_entry("roci_zone_polygon", typeid_of(type_of(abi_zone_polygon)), "roci_body_id roci_zone_polygon(const roci_vec2 *corners, int count)", "A zone that is an outline, any number of corners at least three."))
	append(all, abi_entry("roci_no_simulate", typeid_of(type_of(abi_no_simulate)), "void roci_no_simulate(roci_body_id body)", "Takes a body out of the physics."))
	append(all, abi_entry("roci_gravity", typeid_of(type_of(abi_gravity)), "void roci_gravity(double x, double y)", "Sets the gravity of the physics in pixels a second each second: 0, 400 pulls things down (y goes down) and is what a world has to start with."))
	append(all, abi_entry("roci_kick", typeid_of(type_of(abi_kick)), "void roci_kick(roci_body_id body, double dx, double dy)", "Adds a speed to a body, however heavy it is: 0, -300 sends it up at 300 pixels a second more than it had."))
	append(all, abi_entry("roci_body_pos", typeid_of(type_of(abi_body_pos)), "roci_vec2 roci_body_pos(roci_body_id body)", "Where a body is: a circle's middle, a rectangle's top left corner. 0, 0 for a body that is not there."))
	append(all, abi_entry("roci_body_angle", typeid_of(type_of(abi_body_angle)), "double roci_body_angle(roci_body_id body)", "How far a body is turned, in degrees clockwise, from 0 up to 360."))
	append(all, abi_entry("roci_body_vel", typeid_of(type_of(abi_body_vel)), "roci_vec2 roci_body_vel(roci_body_id body)", "A body's speed in pixels a second."))
	append(all, abi_entry("roci_body_spin", typeid_of(type_of(abi_body_spin)), "double roci_body_spin(roci_body_id body)", "How fast a body turns, in degrees a second, clockwise."))
	append(all, abi_entry("roci_body_hit", typeid_of(type_of(abi_body_hit)), "double roci_body_hit(roci_body_id body)", "How hard the hardest thing a body hit in the last step was, in pixels a second that the two came together at, 0 when it hit nothing: what to play a sound or draw a spark by."))
	append(all, abi_entry("roci_body_exists", typeid_of(type_of(abi_body_exists)), "int roci_body_exists(roci_body_id body)", "1 while a body is in the physics, 0 for one taken out or never made."))
	append(all, abi_entry("roci_body_pose", typeid_of(type_of(abi_body_pose)), "void roci_body_pose(roci_body_id body, double x, double y, double angle)", "Puts a body somewhere, in the same places roci_body_pos gives. A fixed body put somewhere moves there in the next step and pushes what it meets on the way; a wall is not moved."))
	append(all, abi_entry("roci_body_motion", typeid_of(type_of(abi_body_motion)), "void roci_body_motion(roci_body_id body, double vx, double vy, double spin)", "Gives a body a speed in pixels a second and a spin in degrees a second."))
	append(all, abi_entry("roci_body_feel", typeid_of(type_of(abi_body_feel)), "void roci_body_feel(roci_body_id body, double density, double friction, double bounce)", "Sets how heavy, how rough and how bouncy a body is (1, 0.6 and 0 are usual); a negative number leaves what it has."))
	append(all, abi_entry("roci_link", typeid_of(type_of(abi_link)), "int roci_link(roci_body_id a, roci_body_id b, const roci_link_options *options)", "Holds two bodies to each other, or changes the link they have: the options with a `has_` field that is not 0 are put over the link's own and the others stay. Gives 1, or 0 when it cannot be made (a body that is not there, the same body twice, a rod or spring of no length, a kind that is not one of the six, a number that is not one). A link goes when either body does."))
	append(all, abi_entry("roci_no_link", typeid_of(type_of(abi_no_link)), "void roci_no_link(roci_body_id a, roci_body_id b)", "Lets go of the link between two bodies."))
	append(all, abi_entry("roci_linked", typeid_of(type_of(abi_linked)), "int roci_linked(roci_body_id a, roci_body_id b)", "1 while a link holds two bodies, in either order."))
}
