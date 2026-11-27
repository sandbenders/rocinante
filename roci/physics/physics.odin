// SPDX-License-Identifier: 0BSD
//
// 2D physics on Box2D: a world of bodies that a sketch's shapes are given to. The package works in what the language does, pixels,
// degrees turning clockwise (y goes down, so a positive angle turns the way the clock does) and seconds, and keeps Box2D in the metres
// it is tuned for (`PIXELS_PER_METRE` of them to a metre), so no global setting of the library is touched and worlds on several
// threads do not meet. A circle's place is its middle and a box's its top left corner, as in the collision verbs, which is also what
// the shapes of a sketch say. Nothing here knows about records or windows: `roci` hands it numbers and reads numbers back.
package physics

import box2d "../../vendor/box2d"
import "core:math"
import "core:sync"

// How many pixels a metre is: Box2D's tolerances (about a centimetre) and its idea of a body (a metre or so across) fit a sketch
// whose shapes are some tens of pixels wide when a metre is fifty of them.
PIXELS_PER_METRE :: 50

// The gravity a world starts with, in pixels a second each second, downwards (a little above eight metres a second each second).
DEFAULT_GRAVITY :: [2]f64{0, 400}

// How many times Box2D divides a step to solve the contacts and joints, which its documentation recommends to be four.
SUB_STEPS :: 4

// The most bodies one world holds: a sketch that makes a new one every frame would otherwise fill the computer.
MOST_BODIES :: 20_000

// The longest step a world takes: a frame that took longer (a window dragged, a computer that slept) is a step of this and no more, so
// nothing flies apart.
LONGEST_STEP :: 1.0 / 30

Shape_Kind :: enum u8 {
	Circle, // `pos` is the middle, `radius` its radius
	Box,    // `pos` is the top left corner, `size` its width and height, `angle` turns it about its middle
	Segment, // `from` to `to` in the world: a wall, which never moves
}

// What a body is made of, as a sketch says it. A negative `density`, `friction` or `bounce` is the usual one (1, 0.6 and 0).
Body_Desc :: struct {
	kind:     Shape_Kind,
	fixed:    bool,   // never moves by itself and is not pushed: a wall, or a paddle the sketch moves
	pos:      [2]f64,
	radius:   f64,
	size:     [2]f64,
	angle:    f64,    // degrees clockwise
	from, to: [2]f64, // a segment's ends
	vel:      [2]f64, // pixels a second
	spin:     f64,    // degrees a second, clockwise
	density:  f64,
	friction: f64,
	bounce:   f64,
	sensor:   bool,   // reports what is inside it and is no obstacle
	bullet:   bool,   // checked more carefully against fast movement through thin things
}

// Where a body is and how it moves: the same words as the description.
Body_State :: struct {
	pos:   [2]f64,
	angle: f64, // degrees clockwise, from 0 up to 360
	vel:   [2]f64,
	spin:  f64,
	awake: bool,
}

Body :: distinct int // 1 and up; 0 is no body

Slot :: struct {
	id:   box2d.Body_Id,
	kind: Shape_Kind,
	size: [2]f64, // a box's, for the corner and the middle
	live: bool,
}

World :: struct {
	id:      box2d.World_Id,
	gravity: [2]f64,
	slots:   [dynamic]Slot,
	made:    bool,
}

// Box2D keeps its worlds in one static array and looks for a free place in it without a lock, so two threads that make worlds at the
// same time (tests do, and so can a program with a window on each thread) could be given the same place and break each other. Making
// and ending a world take turns, here; what a world does afterwards is its own and needs no lock.
@(private)
world_lock: sync.Mutex

// A world with the usual gravity, or none when Box2D could not make one (the number of worlds it makes is limited).
make_world :: proc() -> (w: World, ok: bool) {
	def := box2d.DefaultWorldDef()
	def.gravity = metres(DEFAULT_GRAVITY)
	sync.mutex_lock(&world_lock)
	id := box2d.CreateWorld(&def)
	sync.mutex_unlock(&world_lock)
	if box2d.world_is_null(id) {
		return {}, false
	}
	return World{id = id, gravity = DEFAULT_GRAVITY, made = true}, true
}

destroy_world :: proc(w: ^World) {
	if w.made {
		sync.mutex_lock(&world_lock)
		box2d.DestroyWorld(w.id)
		sync.mutex_unlock(&world_lock)
	}
	delete(w.slots)
	w^ = {}
}

@(private)
metres :: proc(v: [2]f64) -> box2d.Vec2 {
	return {f32(v.x / PIXELS_PER_METRE), f32(v.y / PIXELS_PER_METRE)}
}

@(private)
pixels :: proc(v: box2d.Vec2) -> [2]f64 {
	return {f64(v.x) * PIXELS_PER_METRE, f64(v.y) * PIXELS_PER_METRE}
}

@(private)
rotation :: proc(degrees: f64) -> box2d.Rot {
	radians := degrees * math.PI / 180
	return {c = f32(math.cos(radians)), s = f32(math.sin(radians))}
}

@(private)
degrees_of :: proc(q: box2d.Rot) -> f64 {
	d := math.atan2(f64(q.s), f64(q.c)) * 180 / math.PI
	if d < 0 {
		d += 360
	}
	return d
}

// `v` turned by an angle in degrees, clockwise.
@(private)
turned :: proc(v: [2]f64, degrees: f64) -> [2]f64 {
	radians := degrees * math.PI / 180
	c, s := math.cos(radians), math.sin(radians)
	return {v.x * c - v.y * s, v.x * s + v.y * c}
}

finite :: proc(v: f64) -> bool {
	return !(math.is_nan(v) || math.is_inf(v))
}

@(private)
all_finite :: proc(values: ..f64) -> bool {
	for v in values {
		if !finite(v) {
			return false
		}
	}
	return true
}

// The middle of a box whose top left corner is at `pos`, turned by `angle` about its middle.
@(private)
box_middle :: proc(pos, size: [2]f64, angle: f64) -> [2]f64 {
	return pos + turned(size / 2, angle) // the corner and the middle are `size / 2` apart, turned with the box
}

// Makes a body of a shape. Gives 0 for one that cannot be made: a size or a radius of nothing, a number that is not one, a
// segment of no length, or a world that is full.
create :: proc(w: ^World, desc: Body_Desc) -> Body {
	if !w.made || count(w) >= MOST_BODIES {
		return 0
	}
	if !all_finite(desc.pos.x, desc.pos.y, desc.radius, desc.size.x, desc.size.y, desc.angle, desc.from.x, desc.from.y, desc.to.x, desc.to.y, desc.vel.x, desc.vel.y, desc.spin) {
		return 0
	}
	def := box2d.DefaultBodyDef()
	def.type = .Kinematic if desc.fixed else .Dynamic // a fixed body can be moved by the sketch, and pushes what it meets
	def.is_bullet = desc.bullet
	def.linear_velocity = metres(desc.vel)
	def.angular_velocity = f32(desc.spin * math.PI / 180)
	switch desc.kind {
	case .Circle:
		if !(desc.radius > 0) {
			return 0
		}
		def.position = metres(desc.pos)
	case .Box:
		if !(desc.size.x > 0 && desc.size.y > 0) {
			return 0
		}
		def.position = metres(box_middle(desc.pos, desc.size, desc.angle))
		def.rotation = rotation(desc.angle)
	case .Segment:
		if desc.from == desc.to {
			return 0
		}
		def.type = .Static // a wall: nothing moves it
	}
	body := box2d.CreateBody(w.id, &def)
	if box2d.body_is_null(body) {
		return 0
	}
	shape_def := box2d.DefaultShapeDef()
	shape_def.density = f32(desc.density) if desc.density >= 0 else shape_def.density
	shape_def.material.friction = f32(desc.friction) if desc.friction >= 0 else shape_def.material.friction
	shape_def.material.restitution = f32(desc.bounce) if desc.bounce >= 0 else shape_def.material.restitution
	shape_def.is_sensor = desc.sensor
	shape_def.enable_sensor_events = true
	shape_def.enable_contact_events = true
	made: box2d.Shape_Id
	switch desc.kind {
	case .Circle:
		circle := box2d.Circle{{0, 0}, f32(desc.radius / PIXELS_PER_METRE)}
		made = box2d.CreateCircleShape(body, &shape_def, &circle)
	case .Box:
		box := box2d.MakeBox(f32(desc.size.x / 2 / PIXELS_PER_METRE), f32(desc.size.y / 2 / PIXELS_PER_METRE))
		made = box2d.CreatePolygonShape(body, &shape_def, &box)
	case .Segment:
		segment := box2d.Segment{metres(desc.from), metres(desc.to)}
		made = box2d.CreateSegmentShape(body, &shape_def, &segment)
	}
	if box2d.shape_is_null(made) {
		box2d.DestroyBody(body)
		return 0
	}
	// the first free place, so a long sketch that makes and drops bodies does not grow the list for ever
	slot := Slot{id = body, kind = desc.kind, size = desc.size, live = true}
	for &s, i in w.slots {
		if !s.live {
			s = slot
			return Body(i + 1)
		}
	}
	append(&w.slots, slot)
	return Body(len(w.slots))
}

@(private)
slot_of :: proc(w: ^World, b: Body) -> ^Slot {
	if b < 1 || int(b) > len(w.slots) || !w.slots[int(b) - 1].live {
		return nil
	}
	return &w.slots[int(b) - 1]
}

// Whether a body is still in the world.
exists :: proc(w: ^World, b: Body) -> bool {
	return slot_of(w, b) != nil
}

// Takes a body out of the world. Nothing happens for a body that is not there.
destroy :: proc(w: ^World, b: Body) {
	if s := slot_of(w, b); s != nil {
		box2d.DestroyBody(s.id)
		s.live = false
	}
}

// How many bodies the world holds.
count :: proc(w: ^World) -> int {
	n := 0
	for s in w.slots {
		n += int(s.live)
	}
	return n
}

// A number as far as the 32-bit floats of Box2D can be told from the next: a body that never moved gives back the place it was given and
// not that place and a few millionths, which a sketch would see as the shape being moved.
@(private)
tidy :: proc(v: f64) -> f64 {
	return math.round(v * 1e4) / 1e4
}

// Where a body is now, in the places a sketch's shapes use (a box's top left corner, a circle's middle).
state :: proc(w: ^World, b: Body) -> Body_State {
	s := slot_of(w, b)
	if s == nil {
		return {}
	}
	transform := box2d.Body_GetTransform(s.id)
	angle := degrees_of(transform.q)
	pos := pixels(transform.p)
	if s.kind == .Box {
		pos -= turned(s.size / 2, angle) // from the middle back to the corner
	}
	if s.kind == .Segment {
		pos = {}
		angle = 0
	}
	velocity := box2d.Body_GetLinearVelocity(s.id)
	moving := pixels(velocity)
	return {
		pos = {tidy(pos.x), tidy(pos.y)},
		angle = tidy(angle),
		vel = {tidy(moving.x), tidy(moving.y)},
		spin = tidy(f64(box2d.Body_GetAngularVelocity(s.id)) * 180 / math.PI),
		awake = box2d.Body_IsAwake(s.id),
	}
}

// Puts a body somewhere, as the sketch changed it: its place and angle, in the same words as `state`. A segment cannot be put.
set_pose :: proc(w: ^World, b: Body, pos: [2]f64, angle: f64) {
	s := slot_of(w, b)
	if s == nil || s.kind == .Segment || !all_finite(pos.x, pos.y, angle) {
		return
	}
	middle := box_middle(pos, s.size, angle) if s.kind == .Box else pos
	box2d.Body_SetTransform(s.id, metres(middle), rotation(angle))
}

// Gives a body a velocity and a spin.
set_motion :: proc(w: ^World, b: Body, vel: [2]f64, spin: f64) {
	s := slot_of(w, b)
	if s == nil || s.kind == .Segment || !all_finite(vel.x, vel.y, spin) {
		return
	}
	box2d.Body_SetLinearVelocity(s.id, metres(vel))
	box2d.Body_SetAngularVelocity(s.id, f32(spin * math.PI / 180))
}

// Adds to a body's velocity, whatever its mass: a kick of `{ 0, -300 }` sends anything up at 300 pixels a second more.
kick :: proc(w: ^World, b: Body, dv: [2]f64) {
	s := slot_of(w, b)
	if s == nil || s.kind == .Segment || !all_finite(dv.x, dv.y) {
		return
	}
	box2d.Body_SetAwake(s.id, true)
	now := box2d.Body_GetLinearVelocity(s.id)
	added := metres(dv)
	box2d.Body_SetLinearVelocity(s.id, {now.x + added.x, now.y + added.y})
}

// Changes the feel of a body's shape: a negative number leaves the one it has.
set_feel :: proc(w: ^World, b: Body, density, friction, bounce: f64) {
	s := slot_of(w, b)
	if s == nil {
		return
	}
	shapes: [1]box2d.Shape_Id
	if box2d.Body_GetShapes(s.id, raw_data(shapes[:]), 1) < 1 {
		return
	}
	if density >= 0 && finite(density) {
		box2d.Shape_SetDensity(shapes[0], f32(density), true)
	}
	if friction >= 0 && finite(friction) {
		box2d.Shape_SetFriction(shapes[0], f32(friction))
	}
	if bounce >= 0 && finite(bounce) {
		box2d.Shape_SetRestitution(shapes[0], f32(bounce))
	}
}

// The gravity of the world, in pixels a second each second.
set_gravity :: proc(w: ^World, gravity: [2]f64) {
	if !w.made || !all_finite(gravity.x, gravity.y) {
		return
	}
	w.gravity = gravity
	box2d.World_SetGravity(w.id, metres(gravity))
}

// Moves the world on by `seconds` (no more than LONGEST_STEP, and nothing for none or a number that is not one).
step :: proc(w: ^World, seconds: f64) {
	if !w.made || !(seconds > 0) || !finite(seconds) {
		return
	}
	box2d.World_Step(w.id, f32(min(seconds, LONGEST_STEP)), SUB_STEPS)
}
