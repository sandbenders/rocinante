// SPDX-License-Identifier: 0BSD
//
// 2D physics for a sketch: one world of bodies (`roci/physics`, on Box2D), made by the first body or the first `gravity` and
// stepped once at the end of every frame, after every window has drawn, by the time the frame took (a headless frame takes a
// sixtieth, or one frame at the rate the window asked for). A sketch that never makes a body has no world. Where shapes are
// records, as in the language, the program that runs them hands bodies the numbers of their records and reads them back through
// two procedures it registers (`physics_sync`): one called before the step, to take in what the sketch changed, and one after
// it, to give back where everything went. C programs have bodies as numbers and read them with `physics_state`.
package roci

import "physics"

Physics_Body :: physics.Body
Physics_Desc :: physics.Body_Desc
Physics_State :: physics.Body_State
Physics_Shape :: physics.Shape_Kind

// The usual gravity of a world, in pixels a second each second.
PHYSICS_GRAVITY :: physics.DEFAULT_GRAVITY

// Makes the world when there is none. False when Box2D could not make one.
@(private)
physics_world :: proc() -> bool {
	if !the.physics.made {
		world, ok := physics.make_world()
		if !ok {
			return false
		}
		the.physics = world
	}
	return true
}

// Whether the sketch has a world of bodies.
has_physics :: proc() -> bool {
	return the.physics.made
}

// Makes a body, and the world if it is the first. Gives 0 for a body that cannot be made.
physics_body :: proc(desc: Physics_Desc) -> Physics_Body {
	if !physics_world() {
		return 0
	}
	return physics.create(&the.physics, desc)
}

Physics_Joint :: physics.Joint_Desc
Physics_Joint_Kind :: physics.Joint_Kind
Physics_Joint_Field :: physics.Joint_Field

// Holds two bodies to each other, or changes the joint they have: the fields named in `joint.set` are put over its own. False when it
// cannot be made (the same body twice, a body that is gone, a rod of no length, a number that is not one).
physics_join :: proc(joint: Physics_Joint) -> bool {
	return the.physics.made && physics.join(&the.physics, joint)
}

// Lets go of the joint between two bodies.
physics_unjoin :: proc(a, b: Physics_Body) {
	if the.physics.made {
		physics.unjoin(&the.physics, a, b)
	}
}

// Whether a joint holds two bodies.
physics_joined :: proc(a, b: Physics_Body) -> bool {
	return the.physics.made && physics.joined(&the.physics, a, b)
}

// How many joints the world holds.
physics_joint_count :: proc() -> int {
	return physics.joint_count(&the.physics) if the.physics.made else 0
}

// The corners of a polygon body now, in the world, in the order it was given (nothing for another kind of body). Made with the allocator given.
physics_polygon :: proc(body: Physics_Body, allocator := context.allocator) -> [dynamic][2]f64 {
	if !the.physics.made {
		return nil
	}
	return physics.polygon_points(&the.physics, body, allocator)
}

// Takes a body out of the world.
physics_destroy :: proc(body: Physics_Body) {
	physics.destroy(&the.physics, body)
}

// Whether a body is still in the world.
physics_exists :: proc(body: Physics_Body) -> bool {
	return the.physics.made && physics.exists(&the.physics, body)
}

// How many bodies the world holds.
physics_count :: proc() -> int {
	return physics.count(&the.physics) if the.physics.made else 0
}

// Where a body is now, in the places a sketch's shapes use.
physics_state :: proc(body: Physics_Body) -> Physics_State {
	return physics.state(&the.physics, body) if the.physics.made else {}
}

// Puts a body somewhere (a box by its top left corner, a circle by its middle; the angle in degrees clockwise).
physics_pose :: proc(body: Physics_Body, pos: [2]f64, angle: f64) {
	if the.physics.made {
		physics.set_pose(&the.physics, body, pos, angle)
	}
}

// Gives a body a velocity (pixels a second) and a spin (degrees a second, clockwise).
physics_motion :: proc(body: Physics_Body, vel: [2]f64, spin: f64) {
	if the.physics.made {
		physics.set_motion(&the.physics, body, vel, spin)
	}
}

// Adds to a body's velocity, whatever its mass.
physics_kick :: proc(body: Physics_Body, dv: [2]f64) {
	if the.physics.made {
		physics.kick(&the.physics, body, dv)
	}
}

// Changes how heavy, how rough and how bouncy a body is; a negative number leaves what it has.
physics_feel :: proc(body: Physics_Body, density, friction, bounce: f64) {
	if the.physics.made {
		physics.set_feel(&the.physics, body, density, friction, bounce)
	}
}

// Sets the gravity of the world, and makes it if it has none (so `gravity` can come before the first body).
physics_gravity :: proc(gravity: [2]f64) {
	if physics_world() {
		physics.set_gravity(&the.physics, gravity)
	}
}

// The gravity of the world, which is the usual one while there is none.
physics_gravity_now :: proc() -> [2]f64 {
	return the.physics.gravity if the.physics.made else PHYSICS_GRAVITY
}

// Registers what a program that keeps its shapes as records does around each step: `before` takes in what the sketch changed since
// the last one, `after` gives back where the bodies went. Either may be nil.
physics_sync :: proc(before, after: proc()) {
	the.physics_before, the.physics_after = before, after
}

// Steps the world, once, by the time this frame took. Called as a frame ends.
@(private)
physics_advance :: proc() {
	if !the.physics.made {
		return
	}
	if the.physics_before != nil {
		the.physics_before()
	}
	physics.step(&the.physics, the.delta)
	if the.physics_after != nil {
		the.physics_after()
	}
}

// Puts what the last step found of zones into the frame's happenings: a body came into a zone, or went out of it. They are for the window
// the other events that belong to no window go to, and heard in the frame after the step, since the step ends a frame.
@(private)
sensor_step :: proc() {
	if !the.physics.made {
		return
	}
	events := physics.take_sensor_events(&the.physics)
	if len(events) == 0 {
		return
	}
	window := Window(0) // no window yet: nothing runs for the event, but the log still has it
	if target := midi_target(); target != nil {
		window = target.id
	}
	for e in events {
		append(&the.log, Happened{kind = .Sensor_Enter if e.entered else .Sensor_Leave, window = window, bodies = {e.sensor, e.visitor}})
	}
}

// Lets go of the world (when a sketch ends).
@(private)
physics_stop :: proc() {
	if the.physics.made {
		physics.destroy_world(&the.physics)
	}
	the.physics_before, the.physics_after = nil, nil
}

// The seconds the next step will take: the frame's time, no more than a world takes at once.
physics_frame_seconds :: proc() -> f64 {
	return min(max(the.delta, 0), physics.LONGEST_STEP)
}
