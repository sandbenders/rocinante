// SPDX-License-Identifier: 0BSD
//
// The turtle in space. `turtle space` switches a window's turtle to this one for the frame: it
// walks the 3D scene, drawing a thin tube behind it while its pen is down, and the words that
// walk the flat turtle walk it (`forward`, `back`, `left`, `right`, `pen up`, `pen down`, `home`,
// `show turtle`) with three more for the third turn: `up` and `down` tip its nose towards its top
// and away, and `roll` turns it about the way it faces.
//
// It keeps three directions at right angles: the way it faces, the way its top points and the way
// its right side does. It starts at the origin facing up the screen with its top towards the
// viewer, so a flat sketch's `right 90` turns it to face right on the screen as it does there, and
// a `right` is a turn about its top, clockwise seen from where its top points. Like the flat
// turtle it lives beside the transform: `begin_frame` sends it home and `push` saves it. Its
// places are in the coordinates of the 3D transform that was current when it walked.
package gfx

import "../maths"

Turtle3 :: struct {
	on:      bool,      // the frame's turtle is this one (`turtle space`)
	at:      [3]f64,
	heading: [3]f64,    // the way it faces; all three directions are zero until it first moves, which means the start
	top:     [3]f64,
	side:    [3]f64,    // its right
	pen_up:  bool,
}

TURTLE3_START_HEADING :: [3]f64{0, -1, 0} // up the screen
TURTLE3_START_TOP :: [3]f64{0, 0, 1}      // towards the viewer
TURTLE3_START_SIDE :: [3]f64{1, 0, 0}     // right on the screen

// The turtle's three directions, with the start for one that has none yet.
turtle3_axes :: proc(t: ^Turtle3) -> (heading, top, side: [3]f64) {
	if t.heading == {} {
		return TURTLE3_START_HEADING, TURTLE3_START_TOP, TURTLE3_START_SIDE
	}
	return t.heading, t.top, t.side
}

turtle3_set_axes :: proc(t: ^Turtle3, heading, top, side: [3]f64) {
	// made square again, so a long walk of turns never leaves them leaning
	h := normalize3(heading)
	s := normalize3(side - h * dot3(side, h))
	u := cross3(s, h)
	// the top has to stay the side the sketch had it on: a mirrored basis would turn it over
	if dot3(u, top) < 0 {
		u = -u
	}
	t.heading, t.top, t.side = h, u, s
}

// Turns about its top: the nose goes to the right of the way it faced.
turtle3_right :: proc(s: ^Scene3, degrees: f64) {
	if degrees * 0 != 0 {
		return
	}
	t := &s.turtle
	h, u, side := turtle3_axes(t)
	c, sn := maths.cos_deg(degrees), maths.sin_deg(degrees)
	turtle3_set_axes(t, h * c + side * sn, u, side * c - h * sn)
}

// Tips the nose towards the turtle's top.
turtle3_up :: proc(s: ^Scene3, degrees: f64) {
	if degrees * 0 != 0 {
		return
	}
	t := &s.turtle
	h, u, side := turtle3_axes(t)
	c, sn := maths.cos_deg(degrees), maths.sin_deg(degrees)
	turtle3_set_axes(t, h * c + u * sn, u * c - h * sn, side)
}

// Rolls about the way it faces: its top goes to the right.
turtle3_roll :: proc(s: ^Scene3, degrees: f64) {
	if degrees * 0 != 0 {
		return
	}
	t := &s.turtle
	h, u, side := turtle3_axes(t)
	c, sn := maths.cos_deg(degrees), maths.sin_deg(degrees)
	turtle3_set_axes(t, h, u * c + side * sn, side * c - u * sn)
}

turtle3_pen :: proc(s: ^Scene3, down: bool) {
	s.turtle.pen_up = !down
}

// Back to the origin, facing up the screen, without drawing; the pen and the mode stay.
turtle3_home :: proc(s: ^Scene3) {
	s.turtle = Turtle3{on = s.turtle.on, pen_up = s.turtle.pen_up}
}

// Walks `distance` along the way it faces (backwards when negative), and while the pen is down
// leaves a tube of `thickness` across in `colour`, with a ball at the end so a bend is round.
// Gives false when the walk could not be recorded (a number that is not finite).
turtle3_forward :: proc(s: ^Scene3, distance, thickness: f64, colour: maths.Colour) -> bool {
	if distance * 0 != 0 || thickness * 0 != 0 {
		return false
	}
	t := &s.turtle
	h, _, _ := turtle3_axes(t)
	from := t.at
	to := from + h * distance
	t.at = to
	if t.heading == {} {
		hh, uu, ss := turtle3_axes(t)
		t.heading, t.top, t.side = hh, uu, ss
	}
	if t.pen_up || distance == 0 {
		return true
	}
	width := max(thickness, 0.5)
	middle := (from + to) / 2
	along := to - from
	m := translate4(f32(middle.x), f32(middle.y), f32(middle.z)) * basis_along(along) * scale4(f32(width), f32(abs(distance)), f32(width))
	scene_add_model(s, .Cylinder, m, colour)
	scene_add(s, .Sphere, to, {width, width, width}, colour)
	return true
}

// Draws the turtle itself: a small cone pointing the way it faces, solid while its pen is down.
turtle3_show :: proc(s: ^Scene3, colour: maths.Colour) {
	t := &s.turtle
	h, _, _ := turtle3_axes(t)
	size := f64(20)
	// a cone's tip is towards negative y in its own space, so the cone is turned to have y along the way back
	middle := t.at + h * (size / 2)
	m := translate4(f32(middle.x), f32(middle.y), f32(middle.z)) * basis_along(-h) * scale4(f32(size * 0.5), f32(size), f32(size * 0.5))
	scene_add_model(s, .Cone, m, colour)
}
