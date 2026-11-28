// SPDX-License-Identifier: 0BSD
//
// 2D physics in a compiled sketch: `simulate ball`, `fixed wall`, `no simulate ball`, `kick ball { 0, -300 }` (`gravity` goes straight to
// `roci`). A record of the sketch is a struct, so the physics finds its `pos`, `vel`, `angle` and the rest by their names once, when the
// shape is given, and keeps pointers to them, which stay good because the collector does not move what it keeps. What is read, and what
// is written back around each step, is decided by `roci.physics_take_in` and `physics_give_back`, the same as in the interpreter, so a
// sketch moves the same either way. The collector is told to keep the records of bodies.
package rt

import "../"
import "core:reflect"

@(private)
Bound :: struct {
	owner:                         ^Header,
	link:                          roci.Physics_Link,
	pos, vel:                      ^[2]f64,
	angle, spin:                   ^f64,
	density, friction, bounce:     ^f64,
	hit:                           ^f64,
	points:                        ^^List([2]f64), // an outline's corners, rewritten as the body moves
}

@(thread_local) @(private) bound: [dynamic]Bound

// The procedures that take a record are generic, so they are checked where a program uses them: this keeps the import used.
_ :: reflect.struct_field_by_name

// A pointer to a field of a record, by its name, when the record has it and it is of this type; a field of another type (one that is a
// number in one record and something else in another is boxed) is not used.
@(private)
field_pointer :: proc(record: ^$T, name: string, $F: typeid) -> ^F {
	field := reflect.struct_field_by_name(T, name)
	if field.type == nil || field.type.id != F {
		return nil
	}
	return (^F)(rawptr(uintptr(record) + field.offset))
}

@(private)
read_fields :: proc(b: ^Bound) -> (fields: roci.Physics_Fields, has: roci.Physics_Has) {
	if b.pos != nil     {fields.pos, has = b.pos^, has + {.Pos}}
	if b.angle != nil   {fields.angle, has = b.angle^, has + {.Angle}}
	if b.vel != nil     {fields.vel, has = b.vel^, has + {.Vel}}
	if b.spin != nil    {fields.spin, has = b.spin^, has + {.Spin}}
	if b.density != nil {fields.density, has = b.density^, has + {.Density}}
	if b.friction != nil {fields.friction, has = b.friction^, has + {.Friction}}
	if b.bounce != nil  {fields.bounce, has = b.bounce^, has + {.Bounce}}
	if b.hit != nil     {fields.hit, has = b.hit^, has + {.Hit}}
	if b.points != nil  {has += {.Points}}
	return
}

@(private)
bound_of :: proc(owner: ^Header) -> int {
	for b, i in bound {
		if b.owner == owner {
			return i
		}
	}
	return -1
}

// `simulate ball` and `fixed wall`: the shape is a circle, a rectangle or a wall as the fields of its type say.
simulate :: proc(record: ^$T, shape: roci.Physics_Shape, fixed := false) {
	if record == nil {
		return
	}
	owner := &record.gc__
	if i := bound_of(owner); i >= 0 {
		roci.physics_destroy(bound[i].link.body)
		unordered_remove(&bound, i)
	}
	b := Bound {
		owner    = owner,
		pos      = field_pointer(record, "pos", [2]f64),
		vel      = field_pointer(record, "vel", [2]f64),
		angle    = field_pointer(record, "angle", f64),
		spin     = field_pointer(record, "spin", f64),
		density  = field_pointer(record, "density", f64),
		friction = field_pointer(record, "friction", f64),
		bounce   = field_pointer(record, "bounce", f64),
		hit      = field_pointer(record, "hit", f64),
		points   = field_pointer(record, "points", ^List([2]f64)),
	}
	flag :: proc(record: ^$T, name: string) -> bool {
		if p := field_pointer(record, name, bool); p != nil {
			return p^
		}
		return false
	}
	desc := roci.Physics_Desc{kind = shape, fixed = fixed, density = -1, friction = -1, bounce = -1, sensor = flag(record, "sensor"), bullet = flag(record, "bullet")}
	if b.vel != nil      {desc.vel = b.vel^}
	if b.spin != nil     {desc.spin = b.spin^}
	if b.density != nil  {desc.density = b.density^}
	if b.friction != nil {desc.friction = b.friction^}
	if b.bounce != nil   {desc.bounce = b.bounce^}
	usable := true
	switch shape {
	case .Circle:
		radius := field_pointer(record, "radius", f64)
		usable = b.pos != nil && radius != nil
		if usable {
			desc.pos, desc.radius = b.pos^, radius^
		}
	case .Box:
		size := field_pointer(record, "size", [2]f64)
		usable = b.pos != nil && size != nil
		if usable {
			desc.pos, desc.size = b.pos^, size^
			if b.angle != nil {
				desc.angle = b.angle^
			}
		}
	case .Polygon:
		usable = b.points != nil && b.points^ != nil
		if usable {
			desc.points = b.points^.items[:]
		}
	case .Segment:
		from, to := field_pointer(record, "from", [2]f64), field_pointer(record, "to", [2]f64)
		usable = from != nil && to != nil
		if usable {
			desc.from, desc.to = from^, to^
		}
	}
	body := roci.physics_body(desc) if usable else 0
	if body == 0 {
		say_once("physics body", "The physics cannot use a shape it is given as it is: a circle needs a `radius` above 0, a rectangle a `size` above 0 both ways and a wall a `from` that is not its `to`, every number has to be a number, and the physics holds at most 20,000 shapes.")
		return
	}
	fields, _ := read_fields(&b)
	fields.pos, fields.vel, fields.angle, fields.spin = desc.pos, desc.vel, desc.angle, desc.spin
	fields.density, fields.friction, fields.bounce = desc.density, desc.friction, desc.bounce
	b.link = roci.physics_link(body, fixed, shape, fields)
	append(&bound, b)
	roci.physics_sync(sync_in, sync_out)
}

// `no simulate ball`.
no_simulate :: proc(record: ^$T) {
	if record == nil {
		return
	}
	if i := bound_of(&record.gc__); i >= 0 {
		roci.physics_destroy(bound[i].link.body)
		unordered_remove(&bound, i)
	}
}

// `kick ball { 0, -300 }`.
kick :: proc(record: ^$T, speed: [2]f64) {
	if record == nil {
		return
	}
	if i := bound_of(&record.gc__); i >= 0 {
		roci.physics_kick(bound[i].link.body, speed)
	}
}

// `link a b as rod ...`: holds two bodies to each other, or changes the link they have. The joint says which options were written.
link :: proc(a: ^$A, b: ^$B, joint: roci.Physics_Joint) {
	if a == nil || b == nil {
		return
	}
	ia, ib := bound_of(&a.gc__), bound_of(&b.gc__)
	if ia < 0 || ib < 0 {
		say_once("physics link", "A link holds two shapes that the physics already has: give both to it with `simulate` or `fixed` first.")
		return
	}
	joint := joint
	joint.a, joint.b = bound[ia].link.body, bound[ib].link.body
	if !roci.physics_join(joint) {
		say_once("physics link", "A shape cannot be linked to itself, a `rod` or a `spring` needs ends that are apart (or a `length` above 0), and every number has to be a number.")
	}
}

// `no link a b`.
no_link :: proc(a: ^$A, b: ^$B) {
	if a == nil || b == nil {
		return
	}
	if ia, ib := bound_of(&a.gc__), bound_of(&b.gc__); ia >= 0 && ib >= 0 {
		roci.physics_unjoin(bound[ia].link.body, bound[ib].link.body)
	}
}

@(private)
sync_in :: proc() {
	for i := len(bound) - 1; i >= 0; i -= 1 {
		b := &bound[i]
		if !roci.physics_exists(b.link.body) {
			unordered_remove(&bound, i)
			continue
		}
		now, has := read_fields(b)
		roci.physics_take_in(&b.link, now, has)
	}
}

@(private)
sync_out :: proc() {
	for &b in bound {
		_, has := read_fields(&b)
		out, changed := roci.physics_give_back(&b.link, has)
		if .Pos in changed   {b.pos^ = out.pos}
		if .Angle in changed {b.angle^ = out.angle}
		if .Vel in changed   {b.vel^ = out.vel}
		if .Spin in changed  {b.spin^ = out.spin}
		if .Hit in changed   {b.hit^ = out.hit}
		if .Points in changed && b.points^ != nil {
			corners := roci.physics_polygon(b.link.body, context.temp_allocator)
			clear(&b.points^.items)
			append(&b.points^.items, ..corners[:])
		}
	}
}

// `on enter goal balls`: the shape that came in or went out, as a record of the kind the sketch holds, when the zone is the shape the
// event says and the shape is the one `things` is or one of the items of `things`.
zone_visitor_of :: proc(zone: ^$Z, things: ^$V, happening: roci.Happened) -> (^V, bool) {
	visitor := visitor_body(zone, happening)
	if visitor == nil || things == nil || &things.gc__ != visitor {
		return nil, false
	}
	return things, true
}

zone_visitor_in :: proc(zone: ^$Z, things: ^List(^$V), happening: roci.Happened) -> (^V, bool) {
	visitor := visitor_body(zone, happening)
	if visitor == nil || things == nil {
		return nil, false
	}
	for item in things.items {
		if item != nil && &item.gc__ == visitor {
			return item, true
		}
	}
	return nil, false
}

// The header of the record that is the second body of the happening, when the first is the zone given.
@(private)
visitor_body :: proc(zone: ^$Z, happening: roci.Happened) -> ^Header {
	if zone == nil {
		return nil
	}
	if i := bound_of(&zone.gc__); i < 0 || bound[i].link.body != happening.bodies[0] {
		return nil
	}
	for b in bound {
		if b.link.body == happening.bodies[1] {
			return b.owner
		}
	}
	return nil
}

// What the collector must keep: the records of bodies.
@(private)
mark_bodies :: proc() {
	for b in bound {
		mark(b.owner)
	}
}

// Lets go of the list of bodies (when a program that checks its memory ends).
@(private)
forget_bodies :: proc() {
	delete(bound)
	bound = nil
}
