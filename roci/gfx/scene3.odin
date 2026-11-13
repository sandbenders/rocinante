// SPDX-License-Identifier: 0BSD
//
// The 3D scene of a window: the boxes, spheres and planes a frame drew, each with the
// transform it was drawn under and its color, and the camera that looks at them. It
// lives beside the 2D command list and knows nothing of the GPU; the renderer draws it
// first, with a depth buffer, and everything 2D goes over it.
//
// The world is the window's: the origin is the middle, x goes right, y goes down and z
// comes towards the viewer, and one unit is one pixel on the plane z = 0 as seen from
// the camera's starting place. A turn about an axis is clockwise as seen from the end of
// the axis, which for z is the way `turn` turns the 2D canvas.
package gfx

import "../maths"
import "core:math"

Shape3 :: enum u8 {
	Box,    // a cube of side 1 about its middle
	Sphere, // diameter 1 about its middle
	Plane,  // a square of side 1 in the plane of x and z, about its middle
}

Axis3 :: enum u8 {X, Y, Z}

Item3 :: struct {
	model:  [3][4]f32, // the first three rows of the transform from the shape's own space to the world
	colour: [4]f32,    // 0 to 1; the alpha is not used yet
	shape:  Shape3,
	_:      [15]u8, // so an item is 80 bytes and the vertex shader reads it as it is
}
#assert(size_of(Item3) == 80)

Scene3 :: struct {
	items: [dynamic]Item3,
	model: matrix[4, 4]f32, // the current transform; all zero until a verb sets it, which means identity
	// The camera orbits the origin. Yaw and pitch are in degrees and are changed by the
	// mouse; `zoom` is in steps of a wheel notch, each making the distance a tenth less.
	yaw, pitch, zoom: f32,
	shown: bool, // the last frame drew an item, so the mouse may orbit
}

// The vertical angle the camera sees, in degrees.
SCENE_FOV :: 50.0

// How far above the floor the camera starts, in degrees, so a plane in the plane of x and z shows.
CAMERA_PITCH :: 18.0

scene_destroy :: proc(s: ^Scene3) {
	delete(s.items)
	s^ = {}
}

// Starts a frame: forgets last frame's items and puts the transform back to the identity.
// The orbit stays, so a window keeps the way it was turned.
scene_begin :: proc(s: ^Scene3) {
	s.shown = len(s.items) > 0
	clear(&s.items)
	s.model = {}
}

current_model :: proc(s: ^Scene3) -> matrix[4, 4]f32 {
	if s.model[3, 3] == 0 {
		return identity4()
	}
	return s.model
}

identity4 :: proc() -> matrix[4, 4]f32 {
	return matrix[4, 4]f32{
		1, 0, 0, 0,
		0, 1, 0, 0,
		0, 0, 1, 0,
		0, 0, 0, 1,
	}
}

translate4 :: proc(x, y, z: f32) -> matrix[4, 4]f32 {
	m := identity4()
	m[0, 3], m[1, 3], m[2, 3] = x, y, z
	return m
}

scale4 :: proc(x, y, z: f32) -> matrix[4, 4]f32 {
	m := identity4()
	m[0, 0], m[1, 1], m[2, 2] = x, y, z
	return m
}

// A turn of `degrees` about an axis. Each is the 2D rotation of the other two axes in
// cyclic order, so a turn about z is the one `turn` makes on the canvas.
rotate4 :: proc(degrees: f64, axis: Axis3) -> matrix[4, 4]f32 {
	c, s := f32(maths.cos_deg(degrees)), f32(maths.sin_deg(degrees))
	m := identity4()
	switch axis {
	case .X:
		m[1, 1], m[1, 2], m[2, 1], m[2, 2] = c, -s, s, c
	case .Y:
		m[2, 2], m[2, 0], m[0, 2], m[0, 0] = c, -s, s, c
	case .Z:
		m[0, 0], m[0, 1], m[1, 0], m[1, 1] = c, -s, s, c
	}
	return m
}

// Moves, turns or scales everything the scene draws after it.
scene_move :: proc(s: ^Scene3, x, y, z: f64) {
	s.model = current_model(s) * translate4(f32(x), f32(y), f32(z))
}

scene_turn :: proc(s: ^Scene3, degrees: f64, axis: Axis3) {
	s.model = current_model(s) * rotate4(degrees, axis)
}

scene_grow :: proc(s: ^Scene3, x, y, z: f64) {
	s.model = current_model(s) * scale4(f32(x), f32(y), f32(z))
}

// Adds a shape at a place, of a size (the diameter of a sphere is the size's x) and
// a color. Anything not a finite number leaves it out.
scene_add :: proc(s: ^Scene3, shape: Shape3, at, size: [3]f64, colour: maths.Colour) {
	for v in ([?]f64{at.x, at.y, at.z, size.x, size.y, size.z}) {
		if math.is_nan(v) || math.is_inf(v) {
			return
		}
	}
	m := current_model(s) * translate4(f32(at.x), f32(at.y), f32(at.z)) * scale4(f32(size.x), f32(size.y), f32(size.z))
	item := Item3{shape = shape, colour = {colour.r / 255, colour.g / 255, colour.b / 255, colour.a / 255}}
	for r in 0 ..< 3 {
		for c in 0 ..< 4 {
			item.model[r][c] = m[r, c]
		}
	}
	append(&s.items, item)
}

// Turns the orbit by a drag of the mouse, in pixels, and keeps the camera from going over the poles.
scene_orbit :: proc(s: ^Scene3, dx, dy: f32) {
	s.yaw += dx * 0.4
	s.pitch = clamp(s.pitch + dy * 0.4, -89, 89)
	for s.yaw > 180 {s.yaw -= 360}
	for s.yaw < -180 {s.yaw += 360}
}

scene_zoom :: proc(s: ^Scene3, notches: f32) {
	s.zoom = clamp(s.zoom + notches, -20, 40)
}

// What the vertex shader reads: the rows of the matrix that takes a world place to the
// screen (view and perspective, with the flip that makes y go down), where the eye is and
// the direction to the light, both in the world.
Scene_Uniforms :: struct {
	clip:  [4][4]f32, // rows
	eye:   [4]f32,
	light: [4]f32,
}

// The camera of a scene for a window of this size (logical pixels).
scene_uniforms :: proc(s: ^Scene3, canvas: [2]f32) -> Scene_Uniforms {
	width, height := max(canvas.x, 1), max(canvas.y, 1)
	fov := f64(SCENE_FOV)
	tan_half := math.tan(fov * math.PI / 360)
	distance := f64(height) / 2 / tan_half * math.exp(-0.1 * f64(s.zoom))
	yaw, pitch := f64(s.yaw), clamp(f64(s.pitch) + CAMERA_PITCH, -89, 89)
	// the eye in the y-up world the projection works in; the world of the sketch is it flipped in y
	eye := [3]f64{
		distance * maths.cos_deg(pitch) * maths.sin_deg(yaw),
		distance * maths.sin_deg(pitch),
		distance * maths.cos_deg(pitch) * maths.cos_deg(yaw),
	}
	forward := normalize3(-eye)
	side := normalize3(cross3(forward, {0, 1, 0}))
	up := cross3(side, forward)
	view := identity4()
	rows := [3][3]f64{side, up, -forward}
	for r in 0 ..< 3 {
		for c in 0 ..< 3 {
			view[r, c] = f32(rows[r][c])
		}
	}
	view[0, 3] = f32(-dot3(side, eye))
	view[1, 3] = f32(-dot3(up, eye))
	view[2, 3] = f32(dot3(forward, eye))
	near, far := f64(1), max(distance * 100, 10000)
	aspect := f64(width) / f64(height)
	proj: matrix[4, 4]f32
	proj[0, 0] = f32(1 / (aspect * tan_half))
	proj[1, 1] = f32(1 / tan_half)
	proj[2, 2] = f32(far / (near - far))
	proj[2, 3] = f32(near * far / (near - far))
	proj[3, 2] = -1
	flip := scale4(1, -1, 1)
	all := proj * view * flip
	u := Scene_Uniforms{}
	for r in 0 ..< 4 {
		for c in 0 ..< 4 {
			u.clip[r][c] = all[r, c]
		}
	}
	u.eye = {f32(eye.x), f32(-eye.y), f32(eye.z), 1}
	l := normalize3({-0.4, -0.7, 0.6})
	u.light = {f32(l.x), f32(l.y), f32(l.z), 0}
	return u
}

normalize3 :: proc(v: [3]f64) -> [3]f64 {
	n := math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
	if n == 0 {
		return {}
	}
	return v / n
}

cross3 :: proc(a, b: [3]f64) -> [3]f64 {
	return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}
}

dot3 :: proc(a, b: [3]f64) -> f64 {
	return a.x * b.x + a.y * b.y + a.z * b.z
}

// A hash of what the scene shows: its items and the way the camera is turned.
scene_hash :: proc(s: ^Scene3) -> u64 {
	h := FNV_OFFSET
	for item in s.items {
		h = hash_u64(h, u64(item.shape))
		for row in item.model {
			for v in row {
				h = hash_f32(h, v)
			}
		}
		for v in item.colour {
			h = hash_f32(h, v)
		}
	}
	h = hash_f32_pair(h, s.yaw, s.pitch)
	return hash_f32(h, s.zoom)
}

// ---- the shapes ----

// One corner of a shape's mesh: where it is and which way the surface faces.
Vertex3 :: struct {
	position: [3]f32,
	normal:   [3]f32,
}

Mesh3 :: struct {
	vertices: [dynamic]Vertex3,
	indices:  [dynamic]u32,
}

// Where each shape's triangles are in the one mesh the renderer keeps.
Shape_Range :: struct {
	first_index, index_count: u32,
}

Shape_Meshes :: struct {
	mesh:   Mesh3,
	ranges: [Shape3]Shape_Range,
}

shape_meshes_destroy :: proc(m: ^Shape_Meshes) {
	delete(m.mesh.vertices)
	delete(m.mesh.indices)
	m^ = {}
}

// Builds the three shapes into one mesh: a cube of side 1, a sphere of diameter 1 and a
// square of side 1, all about their middles.
build_shape_meshes :: proc() -> Shape_Meshes {
	out: Shape_Meshes
	m := &out.mesh

	// the box: four corners for each face, so each face has its own normal
	start := u32(len(m.indices))
	faces := [6][3]f32{{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}}
	for n in faces {
		// two axes along the face
		a: [3]f32 = {n.y, n.z, n.x}
		b: [3]f32 = {n.z, n.x, n.y}
		base := u32(len(m.vertices))
		for corner in ([4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}) {
			p := n * 0.5 + a * (corner.x * 0.5) + b * (corner.y * 0.5)
			append(&m.vertices, Vertex3{p, n})
		}
		append(&m.indices, base, base + 1, base + 2, base, base + 2, base + 3)
	}
	out.ranges[.Box] = {start, u32(len(m.indices)) - start}

	// the sphere: rings of latitude (a diameter of 1, like the box's side)
	start = u32(len(m.indices))
	rings, segments := 24, 48
	base := u32(len(m.vertices))
	for ring in 0 ..= rings {
		phi := f64(ring) / f64(rings) * 180
		for seg in 0 ..= segments {
			theta := f64(seg) / f64(segments) * 360
			n := [3]f32{
				f32(maths.sin_deg(phi) * maths.cos_deg(theta)),
				f32(-maths.cos_deg(phi)),
				f32(maths.sin_deg(phi) * maths.sin_deg(theta)),
			}
			append(&m.vertices, Vertex3{n * 0.5, n})
		}
	}
	for ring in 0 ..< rings {
		for seg in 0 ..< segments {
			a := base + u32(ring * (segments + 1) + seg)
			b := a + u32(segments + 1)
			append(&m.indices, a, b, a + 1, a + 1, b, b + 1)
		}
	}
	out.ranges[.Sphere] = {start, u32(len(m.indices)) - start}

	// the plane
	start = u32(len(m.indices))
	base = u32(len(m.vertices))
	for corner in ([4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}) {
		append(&m.vertices, Vertex3{{corner.x * 0.5, 0, corner.y * 0.5}, {0, -1, 0}})
	}
	append(&m.indices, base, base + 1, base + 2, base, base + 2, base + 3)
	out.ranges[.Plane] = {start, u32(len(m.indices)) - start}
	return out
}
