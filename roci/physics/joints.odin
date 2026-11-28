// SPDX-License-Identifier: 0BSD
//
// Joints: two bodies held to each other in one of six ways, in the units of the package (pixels, degrees clockwise, seconds). There is
// one joint between a pair of bodies: describing it again changes it (the options given are put over the ones it has), which is done by
// making it again with the merged description, since Box2D 3.2 fixes a joint's settings when it is made. A joint goes with either of
// its bodies. Its anchors are given in the world, and the frames Box2D wants in each body's own coordinates are worked out here from
// where the bodies are at that moment, so the joint holds them as they are then.
package physics

import box2d "../../vendor/box2d"
import "core:math"

Joint_Kind :: enum u8 {
	Hinge,  // the bodies turn about a point (`at`), between the angles of `limit`, driven by `motor`
	Rod,    // the ends (`at` on the first, `to` on the second) stay `length` apart; with `limit` a rope: any length between the two
	Spring, // the ends are pulled to `length` apart like a spring (`stiffness`, `damping`)
	Weld,   // the bodies are glued at a point, stiff or, with `stiffness`, a little springy
	Wheel,  // the second body turns about a point and slides along `axis` on a spring (a car's wheel)
	Slider, // the second body slides along `axis` only, between the places of `limit`, driven by `motor`
}

// Which of the options of a description were given: the others are what the joint has already or the usual.
Joint_Field :: enum u8 {
	Kind,
	At,
	To,
	Axis,
	Length,
	Stiffness,
	Damping,
	Limit,
	Motor,
	Torque,
	Collide,
}

Joint_Fields :: bit_set[Joint_Field]

Joint_Desc :: struct {
	a, b:       Body,
	set:        Joint_Fields,
	kind:       Joint_Kind,
	at, to:     [2]f64, // anchors in the world; by default the middle of each body
	axis:       [2]f64, // for a wheel and a slider, in the world; by default straight down
	length:     f64,    // pixels; by default as far apart as the anchors are when it is made
	stiffness:  f64,    // times a second a spring bounces; 0 is none (a rigid rod, a rigid weld)
	damping:    f64,    // 0 to 1: how fast a spring settles
	low, high:  f64,    // `limit`: degrees for a hinge, pixels otherwise (a rod's lengths)
	speed:      f64,    // `motor`: degrees a second for a hinge and a wheel, pixels a second for a slider
	torque:     f64,    // how hard the motor pushes; 0 turns it off
	collide:    bool,   // whether the two bodies still bump into each other
	limited:    bool,   // set by `join`: a `limit` was given at some time
	driven:     bool,   // set by `join`: a `motor` was given at some time
}

@(private)
Joint_Slot :: struct {
	id:   box2d.Joint_Id,
	desc: Joint_Desc, // with every field settled, `set` holding all of them
	a, b: box2d.Transform, // where the joint is in each body's own coordinates, kept so that making it again does not move its zero
	live: bool,
}

// What a motor pushes with when the description does not say.
USUAL_TORQUE :: 1000.0

@(private)
inverse_turn :: proc(q: box2d.Rot, v: box2d.Vec2) -> box2d.Vec2 {
	return {q.c * v.x + q.s * v.y, -q.s * v.x + q.c * v.y}
}

// A point of the world in the coordinates of a body, with the frame's rotation turned the way `world_angle` points.
@(private)
frame_of :: proc(s: ^Slot, world_point: [2]f64, world_angle: f64) -> box2d.Transform {
	t := box2d.Body_GetTransform(s.id)
	there := metres(world_point)
	point := inverse_turn(t.q, box2d.Vec2{there.x - t.p.x, there.y - t.p.y})
	turn := degrees_of(t.q)
	return box2d.Transform{p = point, q = rotation(world_angle - turn)}
}

// Whether a joint is held between two bodies.
joined :: proc(w: ^World, a, b: Body) -> bool {
	return find_joint(w, a, b) >= 0
}

@(private)
find_joint :: proc(w: ^World, a, b: Body) -> int {
	for j, i in w.joints {
		if j.live && ((j.desc.a == a && j.desc.b == b) || (j.desc.a == b && j.desc.b == a)) {
			return i
		}
	}
	return -1
}

// How many joints the world holds.
joint_count :: proc(w: ^World) -> int {
	n := 0
	for j in w.joints {
		n += int(j.live)
	}
	return n
}

// Holds two bodies to each other, or changes the joint they already have: the fields in `d.set` are put over its own. Gives false for
// bodies that are not there or are the same one, a number that is not one, a rod or spring of no length, and a world that has no room.
join :: proc(w: ^World, d: Joint_Desc) -> bool {
	if !w.made || d.a == d.b || !exists(w, d.a) || !exists(w, d.b) {
		return false
	}
	merged := d
	existing := find_joint(w, d.a, d.b)
	if existing >= 0 {
		old := w.joints[existing].desc
		merged = old
		merged.a, merged.b = d.a, d.b
		for field in Joint_Field {
			if field not_in d.set {
				continue
			}
			switch field {
			case .Kind:      merged.kind = d.kind
			case .At:        merged.at = d.at
			case .To:        merged.to = d.to
			case .Axis:      merged.axis = d.axis
			case .Length:    merged.length = d.length
			case .Stiffness: merged.stiffness = d.stiffness
			case .Damping:   merged.damping = d.damping
			case .Limit:     merged.low, merged.high = d.low, d.high
			case .Motor:     merged.speed = d.speed
			case .Torque:    merged.torque = d.torque
			case .Collide:   merged.collide = d.collide
			}
		}
		merged.limited, merged.driven = old.limited, old.driven
		if .Kind in d.set && d.kind != old.kind {
			merged = d // another kind starts from the usual settings of that kind, with what was just given
		}
	}
	if !all_finite(merged.at.x, merged.at.y, merged.to.x, merged.to.y, merged.axis.x, merged.axis.y, merged.length, merged.stiffness, merged.damping, merged.low, merged.high, merged.speed, merged.torque) {
		return false
	}
	merged.limited ||= .Limit in d.set
	merged.driven ||= .Motor in d.set
	sa, sb := slot_of(w, merged.a), slot_of(w, merged.b)
	// settle every field that was not given
	if .At not_in merged.set {
		merged.at = middle(w, merged.a)
	}
	if .To not_in merged.set {
		merged.to = middle(w, merged.b)
	}
	if .Axis not_in merged.set || merged.axis == {} {
		merged.axis = {0, 1}
	}
	if .Length not_in merged.set {
		delta := merged.to - merged.at
		merged.length = math.sqrt(delta.x * delta.x + delta.y * delta.y)
	}
	if (merged.kind == .Rod || merged.kind == .Spring) && !(merged.length > 0) {
		return false
	}
	if .Damping not_in merged.set {
		merged.damping = 0.3
	}
	if merged.kind == .Spring && .Stiffness not_in merged.set {
		merged.stiffness = 3
	}
	if merged.driven && merged.torque == 0 && .Torque not_in d.set {
		merged.torque = USUAL_TORQUE
	}
	merged.set = {.Kind, .At, .To, .Axis, .Length, .Stiffness, .Damping, .Limit, .Motor, .Torque, .Collide} // every field is settled now
	frame_a, frame_b: box2d.Transform
	if existing >= 0 && d.set & {.At, .To, .Axis} == {} && merged.kind == w.joints[existing].desc.kind {
		frame_a, frame_b = w.joints[existing].a, w.joints[existing].b // the joint stays where it is held: an angle or a place of 0 is still where it was
	} else {
		frame_a, frame_b = frames_of(sa, sb, merged)
	}
	if existing >= 0 {
		box2d.DestroyJoint(w.joints[existing].id)
		w.joints[existing].live = false
	}
	id, made := make_joint(w, sa, sb, merged, frame_a, frame_b)
	if !made {
		return false
	}
	slot := Joint_Slot{id = id, desc = merged, a = frame_a, b = frame_b, live = true}
	if existing >= 0 {
		w.joints[existing] = slot
		return true
	}
	for &j in w.joints {
		if !j.live {
			j = slot
			return true
		}
	}
	append(&w.joints, slot)
	return true
}

// Where a joint is in the coordinates of each of its bodies, from where the bodies are now.
@(private)
frames_of :: proc(sa, sb: ^Slot, d: Joint_Desc) -> (a, b: box2d.Transform) {
	axis_angle := math.atan2(d.axis.y, d.axis.x) * 180 / math.PI
	switch d.kind {
	case .Hinge, .Weld:
		return frame_of(sa, d.at, 0), frame_of(sb, d.at, 0)
	case .Rod, .Spring:
		return frame_of(sa, d.at, 0), frame_of(sb, d.to, 0)
	case .Wheel, .Slider:
		return frame_of(sa, d.at, axis_angle), frame_of(sb, d.at, axis_angle)
	}
	return
}

@(private)
make_joint :: proc(w: ^World, sa, sb: ^Slot, d: Joint_Desc, frame_a, frame_b: box2d.Transform) -> (id: box2d.Joint_Id, ok: bool) {
	limits := d.limited
	motor := d.driven && d.torque > 0
	spring := d.stiffness > 0
	radians := math.PI / 180
	switch d.kind {
	case .Hinge:
		def := box2d.DefaultRevoluteJointDef()
		def.base.body_id_a, def.base.body_id_b = sa.id, sb.id
		def.base.local_frame_a, def.base.local_frame_b = frame_a, frame_b
		def.base.collide_connected = d.collide
		def.enable_limit = limits
		def.lower_angle, def.upper_angle = f32(min(d.low, d.high) * radians), f32(max(d.low, d.high) * radians)
		def.enable_spring = spring
		def.hertz, def.damping_ratio = f32(d.stiffness), f32(d.damping)
		def.enable_motor = motor
		def.max_motor_torque, def.motor_speed = f32(d.torque), f32(d.speed * radians)
		id = box2d.CreateRevoluteJoint(w.id, &def)
	case .Rod, .Spring:
		def := box2d.DefaultDistanceJointDef()
		def.base.body_id_a, def.base.body_id_b = sa.id, sb.id
		def.base.local_frame_a, def.base.local_frame_b = frame_a, frame_b
		def.base.collide_connected = d.collide
		def.length = f32(d.length / PIXELS_PER_METRE)
		if d.kind == .Spring {
			def.enable_spring = true
			def.hertz, def.damping_ratio = f32(d.stiffness), f32(d.damping)
			if limits {
				def.enable_limit = true
				def.min_length, def.max_length = f32(min(d.low, d.high) / PIXELS_PER_METRE), f32(max(d.low, d.high) / PIXELS_PER_METRE)
			}
		} else if limits {
			def.enable_spring = true // no spring force: a rope, any length between the two
			def.hertz = 0
			def.enable_limit = true
			def.min_length, def.max_length = f32(min(d.low, d.high) / PIXELS_PER_METRE), f32(max(d.low, d.high) / PIXELS_PER_METRE)
		}
		def.enable_motor = motor
		def.max_motor_force, def.motor_speed = f32(d.torque), f32(d.speed / PIXELS_PER_METRE)
		id = box2d.CreateDistanceJoint(w.id, &def)
	case .Weld:
		def := box2d.DefaultWeldJointDef()
		def.base.body_id_a, def.base.body_id_b = sa.id, sb.id
		def.base.local_frame_a, def.base.local_frame_b = frame_a, frame_b
		def.base.collide_connected = d.collide
		def.linear_hertz, def.angular_hertz = f32(d.stiffness), f32(d.stiffness)
		def.linear_damping_ratio, def.angular_damping_ratio = f32(d.damping), f32(d.damping)
		id = box2d.CreateWeldJoint(w.id, &def)
	case .Wheel:
		def := box2d.DefaultWheelJointDef()
		def.base.body_id_a, def.base.body_id_b = sa.id, sb.id
		def.base.local_frame_a, def.base.local_frame_b = frame_a, frame_b
		def.base.collide_connected = d.collide
		def.enable_spring = spring
		def.hertz, def.damping_ratio = f32(d.stiffness), f32(d.damping)
		def.enable_limit = limits
		def.lower_translation, def.upper_translation = f32(min(d.low, d.high) / PIXELS_PER_METRE), f32(max(d.low, d.high) / PIXELS_PER_METRE)
		def.enable_motor = motor
		def.max_motor_torque, def.motor_speed = f32(d.torque), f32(d.speed * radians)
		id = box2d.CreateWheelJoint(w.id, &def)
	case .Slider:
		def := box2d.DefaultPrismaticJointDef()
		def.base.body_id_a, def.base.body_id_b = sa.id, sb.id
		def.base.local_frame_a, def.base.local_frame_b = frame_a, frame_b
		def.base.collide_connected = d.collide
		def.enable_spring = spring
		def.hertz, def.damping_ratio = f32(d.stiffness), f32(d.damping)
		def.enable_limit = limits
		def.lower_translation, def.upper_translation = f32(min(d.low, d.high) / PIXELS_PER_METRE), f32(max(d.low, d.high) / PIXELS_PER_METRE)
		def.enable_motor = motor
		def.max_motor_force, def.motor_speed = f32(d.torque), f32(d.speed / PIXELS_PER_METRE)
		id = box2d.CreatePrismaticJoint(w.id, &def)
	}
	return id, !box2d.joint_is_null(id)
}

// Lets go of the joint between two bodies. Nothing happens when there is none.
unjoin :: proc(w: ^World, a, b: Body) {
	if i := find_joint(w, a, b); i >= 0 {
		box2d.DestroyJoint(w.joints[i].id)
		w.joints[i].live = false
	}
}
