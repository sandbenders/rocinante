// SPDX-License-Identifier: 0BSD
//
// What the interpreter and a compiled sketch share when a shape of the sketch is a body: the numbers a record has, and what to do
// with them around each step. A program keeps a `Physics_Link` for each record, reads the fields it has into a `Physics_Fields`
// (the ones it does not have are left out of `has`), and asks `physics_take_in` before the step what the sketch changed, and
// `physics_give_back` after it which fields to write and with what. Doing this here, once, is what makes a sketch behave the same
// interpreted and compiled.
package roci

import "core:math"

// The fields of a shape's record the physics reads and writes, in the units of the language.
Physics_Fields :: struct {
	pos, vel:                  [2]f64,
	angle, spin:               f64,
	density, friction, bounce: f64,
	hit:                       f64, // written by the physics only: the hardest impact of the last step
}

Physics_Field :: enum u8 {
	Pos,
	Angle,
	Vel,
	Spin,
	Density,
	Friction,
	Bounce,
	Hit,
	Points, // an outline's corners: written back whenever the body moved, never taken in
}

Physics_Has :: bit_set[Physics_Field]

// A record that is a body: which body, how it was made, and the numbers last given to the record or taken from it, which tell whether
// the sketch has changed them since.
Physics_Link :: struct {
	body:  Physics_Body,
	fixed: bool,
	shape: Physics_Shape,
	last:  Physics_Fields,
}

// The numbers a body gives back differ in the seventh place from the ones it was given (it works in 32-bit floats), so a number is
// said to have changed only when it moved by more than this: a floor that never moved is not written to.
PHYSICS_NOISE :: 1e-4

@(private)
moved_by :: proc(a, b: f64) -> bool {
	return abs(a - b) > PHYSICS_NOISE
}

@(private)
moved_pair :: proc(a, b: [2]f64) -> bool {
	return moved_by(a.x, b.x) || moved_by(a.y, b.y)
}

// How far one angle is from another by the shorter way round, in degrees: from -180 up to 180.
@(private)
angle_between :: proc(from, to: f64) -> f64 {
	d := math.mod(to - from, 360)
	if d > 180 {
		d -= 360
	} else if d < -180 {
		d += 360
	}
	return d
}

// Makes the link of a body that was just made from these fields.
physics_link :: proc(body: Physics_Body, fixed: bool, shape: Physics_Shape, fields: Physics_Fields) -> Physics_Link {
	l := Physics_Link{body = body, fixed = fixed, shape = shape, last = fields}
	if shape == .Polygon {
		// an outline has no `pos` and `angle` of its own: they are the body's, to tell when it has moved
		s := physics_state(body)
		l.last.pos, l.last.angle = s.pos, s.angle
	}
	return l
}

// Before the step: takes in what the sketch changed in the record. `now` holds the record's fields as they are, those in `has` only.
// A fixed shape moves only when the sketch moves it, at the speed that gets it there in this step, and pushes what is in the way.
physics_take_in :: proc(l: ^Physics_Link, now: Physics_Fields, has: Physics_Has) {
	if l.shape == .Segment || !physics_exists(l.body) {
		return
	}
	current := physics_state(l.body)
	if l.shape == .Polygon {
		// an outline is moved by the physics only: what the sketch writes to its corners is not taken in, but its speed and feel are
		if !l.fixed {
			if moved_pair(now.vel, l.last.vel) && .Vel in has || moved_by(now.spin, l.last.spin) && .Spin in has {
				physics_motion(l.body, now.vel if .Vel in has else l.last.vel, now.spin if .Spin in has else l.last.spin)
				l.last.vel, l.last.spin = now.vel if .Vel in has else l.last.vel, now.spin if .Spin in has else l.last.spin
			}
		}
		density := now.density if .Density in has else l.last.density
		friction := now.friction if .Friction in has else l.last.friction
		bounce := now.bounce if .Bounce in has else l.last.bounce
		if density != l.last.density || friction != l.last.friction || bounce != l.last.bounce {
			physics_feel(l.body, density, friction, bounce)
			l.last.density, l.last.friction, l.last.bounce = density, friction, bounce
		}
		return
	}
	pos := now.pos if .Pos in has else l.last.pos
	angle := now.angle if .Angle in has else l.last.angle
	vel := now.vel if .Vel in has else l.last.vel
	spin := now.spin if .Spin in has else l.last.spin
	seconds := physics_frame_seconds()
	moved := moved_pair(pos, l.last.pos) || moved_by(angle, l.last.angle)
	if l.fixed {
		if moved && seconds > 0 {
			physics_motion(l.body, (pos - current.pos) / seconds, angle_between(current.angle, angle) / seconds)
		} else {
			physics_motion(l.body, {}, 0)
		}
	} else {
		if moved {
			physics_pose(l.body, pos, angle)
		}
		if moved_pair(vel, l.last.vel) || moved_by(spin, l.last.spin) {
			physics_motion(l.body, vel, spin)
		}
	}
	density := now.density if .Density in has else l.last.density
	friction := now.friction if .Friction in has else l.last.friction
	bounce := now.bounce if .Bounce in has else l.last.bounce
	if density != l.last.density || friction != l.last.friction || bounce != l.last.bounce {
		physics_feel(l.body, density, friction, bounce)
	}
	l.last.pos, l.last.angle, l.last.vel, l.last.spin = pos, angle, vel, spin
	l.last.density, l.last.friction, l.last.bounce = density, friction, bounce
}

// After the step: which of the fields the record has (`has`) the body's new numbers differ from the last the record was given, with the
// new numbers, which the program writes into the record. Only the ones that moved, so a body that sleeps does not make its record look
// written to.
physics_give_back :: proc(l: ^Physics_Link, has: Physics_Has) -> (out: Physics_Fields, changed: Physics_Has) {
	if l.shape == .Segment || !physics_exists(l.body) {
		return
	}
	s := physics_state(l.body)
	out = l.last
	if l.shape == .Polygon {
		if .Points in has && (moved_pair(s.pos, l.last.pos) || moved_by(s.angle, l.last.angle)) {
			changed += {.Points}
		}
		out.pos = s.pos // where the body is, to tell the next move
		if .Angle not_in has {
			out.angle = s.angle
		}
	} else if .Pos in has && moved_pair(s.pos, l.last.pos) {
		out.pos, changed = s.pos, changed + {.Pos}
	}
	if .Angle in has && moved_by(s.angle, l.last.angle) {
		out.angle, changed = s.angle, changed + {.Angle}
	}
	if .Vel in has && moved_pair(s.vel, l.last.vel) {
		out.vel, changed = s.vel, changed + {.Vel}
	}
	if .Spin in has && moved_by(s.spin, l.last.spin) {
		out.spin, changed = s.spin, changed + {.Spin}
	}
	if .Hit in has && moved_by(s.hit, l.last.hit) {
		out.hit, changed = s.hit, changed + {.Hit}
	}
	l.last = out
	return
}
