// SPDX-License-Identifier: 0BSD
//
// 2D physics for the language: `simulate ball`, `fixed wall`, `no simulate ball`, `gravity { 0, 400 }` and `kick ball { 0, -300 }`.
// A shape given to the physics stays a record of the sketch: its numbers are handed to a body (`roci.physics_body`), and each frame,
// around the physics' step, the interpreter takes in what the sketch changed in the record (a new `pos` puts the shape there, a new
// `vel` sets its speed) and writes back where the body went into the record's own `pos`, `angle`, `vel` and `spin`, whichever it
// has. A record is found again by its place in memory, which the collector moves it from, so the links are moved with it.
package interp

import "../"
import "../lang"

// A record that is a body: the record, and what the physics keeps about it (`roci.Physics_Link`).
Body_Link :: struct {
	record: ^Record,
	link:   roci.Physics_Link,
	class:  lang.Shape_Class,
}

// The value of a field of a record, when it has one.
@(private = "file")
field_of :: proc(it: ^Interp, r: ^Record, name: string) -> (Value, bool) {
	place := field_index(it, r.shape, name)
	if place < 0 || place >= len(r.fields) {
		return nil, false
	}
	return r.fields[place], true
}

@(private = "file")
number_field :: proc(it: ^Interp, r: ^Record, name: string, otherwise: f64) -> f64 {
	if v, has := field_of(it, r, name); has {
		return as_number(v)
	}
	return otherwise
}

@(private = "file")
pair_field :: proc(it: ^Interp, r: ^Record, name: string, otherwise: [2]f64) -> [2]f64 {
	if v, has := field_of(it, r, name); has {
		return as_pair(v)
	}
	return otherwise
}

@(private = "file")
flag_field :: proc(it: ^Interp, r: ^Record, name: string) -> bool {
	if v, has := field_of(it, r, name); has {
		return as_bool(v)
	}
	return false
}

// Writes a field of a record, if it has it, and says the record changed.
@(private = "file")
put_field :: proc(it: ^Interp, r: ^Record, name: string, v: Value) {
	if place := field_index(it, r.shape, name); place >= 0 && place < len(r.fields) {
		r.fields[place] = v
	}
}

// What a record says a body is: its shape, place and motion, and what it is like. False for a shape the physics cannot use.
@(private = "file")
body_desc :: proc(it: ^Interp, r: ^Record, fixed: bool) -> (desc: roci.Physics_Desc, ok: bool) {
	desc.fixed = fixed
	desc.vel = pair_field(it, r, "vel", {})
	desc.spin = number_field(it, r, "spin", 0)
	desc.density = number_field(it, r, "density", -1)
	desc.friction = number_field(it, r, "friction", -1)
	desc.bounce = number_field(it, r, "bounce", -1)
	desc.sensor = flag_field(it, r, "sensor")
	desc.bullet = flag_field(it, r, "bullet")
	#partial switch r.class {
	case .Circle:
		desc.kind = .Circle
		desc.pos = pair_field(it, r, "pos", {})
		desc.radius = number_field(it, r, "radius", 0)
		return desc, true
	case .Box:
		desc.kind = .Box
		desc.pos = pair_field(it, r, "pos", {})
		desc.size = pair_field(it, r, "size", {})
		desc.angle = number_field(it, r, "angle", 0)
		return desc, true
	case .Segment:
		desc.kind = .Segment
		desc.from = pair_field(it, r, "from", {})
		desc.to = pair_field(it, r, "to", {})
		return desc, true
	}
	return {}, false
}

// The link a record has, if it is a body.
@(private = "file")
link_of :: proc(it: ^Interp, r: ^Record) -> int {
	for l, i in it.bodies {
		if l.record == r {
			return i
		}
	}
	return -1
}

@(private = "file")
drop_link :: proc(it: ^Interp, i: int) {
	roci.physics_destroy(it.bodies[i].link.body)
	ordered_remove(&it.bodies, i)
}

// `simulate ball` and `fixed wall`: makes a body of a record, in place of the one it had.
@(private)
body_verb :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call, fixed: bool) {
	r := as_record(eval(it, call.args[0]))
	if r == nil {
		return
	}
	name := lang.span_text(it.src, call.args[0].span)
	if !r.long {
		fail(it, .Body_Not_Lasting, e.span, name, "", "", "ball = { pos: { 200, 100 }, radius: 10 }\nsimulate ball")
		return
	}
	if i := link_of(it, r); i >= 0 {
		drop_link(it, i)
	}
	desc, usable := body_desc(it, r, fixed)
	body := roci.physics_body(desc) if usable else 0
	if body == 0 {
		fail(it, .Body_Refused, e.span, name, "", "", "ball = { pos: { 200, 100 }, radius: 10 }\nsimulate ball")
		return
	}
	append(&it.bodies, Body_Link{
		record = r, class = r.class,
		link = roci.physics_link(body, fixed, desc.kind, {
			pos = desc.pos, vel = desc.vel, angle = desc.angle, spin = desc.spin,
			density = desc.density, friction = desc.friction, bounce = desc.bounce,
		}),
	})
	roci.physics_sync(sync_bodies_in, sync_bodies_out)
}

// `no simulate ball`.
@(private)
body_release :: proc(it: ^Interp, call: lang.IR_Call) {
	if r := as_record(eval(it, call.args[0])); r != nil {
		if i := link_of(it, r); i >= 0 {
			drop_link(it, i)
		}
	}
}

// `kick ball { 0, -300 }`: adds to a body's speed.
@(private)
body_kick :: proc(it: ^Interp, call: lang.IR_Call) {
	r := as_record(eval(it, call.args[0]))
	dv := as_pair(eval(it, call.args[1]))
	if r == nil {
		return
	}
	if i := link_of(it, r); i >= 0 {
		// the record's own `vel` is brought up to date after the step; `vel` here is what the record last said, so the kick is not undone
		roci.physics_kick(it.bodies[i].link.body, dv)
	}
}

// Which of the physics fields a record has.
@(private = "file")
fields_of :: proc(it: ^Interp, r: ^Record) -> (fields: roci.Physics_Fields, has: roci.Physics_Has) {
	for entry in ([?]struct{name: string, field: roci.Physics_Field}{{"pos", .Pos}, {"angle", .Angle}, {"vel", .Vel}, {"spin", .Spin}, {"density", .Density}, {"friction", .Friction}, {"bounce", .Bounce}}) {
		field := entry.field
		v, found := field_of(it, r, entry.name)
		if !found {
			continue
		}
		has += {field}
		switch field {
		case .Pos:      fields.pos = as_pair(v)
		case .Vel:      fields.vel = as_pair(v)
		case .Angle:    fields.angle = as_number(v)
		case .Spin:     fields.spin = as_number(v)
		case .Density:  fields.density = as_number(v)
		case .Friction: fields.friction = as_number(v)
		case .Bounce:   fields.bounce = as_number(v)
		}
	}
	return
}

// Before the step: takes in what the sketch changed in the records of bodies.
@(private)
sync_bodies_in :: proc() {
	it := current
	if it == nil {
		return
	}
	for i := len(it.bodies) - 1; i >= 0; i -= 1 {
		l := &it.bodies[i]
		if !roci.physics_exists(l.link.body) {
			ordered_remove(&it.bodies, i)
			continue
		}
		now, has := fields_of(it, l.record)
		roci.physics_take_in(&l.link, now, has)
	}
}

// After the step: gives back where the bodies are, into the records' own `pos`, `angle`, `vel` and `spin`, those the record has.
@(private)
sync_bodies_out :: proc() {
	it := current
	if it == nil {
		return
	}
	for &l in it.bodies {
		_, has := fields_of(it, l.record)
		out, changed := roci.physics_give_back(&l.link, has)
		if changed == {} {
			continue
		}
		if .Pos in changed {
			put_field(it, l.record, "pos", vec2(out.pos))
		}
		if .Angle in changed {
			put_field(it, l.record, "angle", out.angle)
		}
		if .Vel in changed {
			put_field(it, l.record, "vel", vec2(out.vel))
		}
		if .Spin in changed {
			put_field(it, l.record, "spin", out.spin)
		}
		l.record.stamp = next_write(it)
	}
}

// Lets go of every body the sketch made (when it ends or is run again), and puts the gravity back to the usual one.
@(private)
drop_bodies :: proc(it: ^Interp) {
	for l in it.bodies {
		roci.physics_destroy(l.link.body)
	}
	delete(it.bodies)
	it.bodies = nil
	if roci.has_physics() {
		roci.physics_gravity(roci.PHYSICS_GRAVITY)
		roci.physics_sync(nil, nil)
	}
}
