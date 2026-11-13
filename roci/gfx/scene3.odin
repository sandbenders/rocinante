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
	Box,       // a cube of side 1 about its middle
	Sphere,    // diameter 1 about its middle
	Plane,     // a square of side 1 in the plane of x and z, about its middle
	Cone,      // base diameter 1 and height 1, the tip up (towards negative y)
	Cylinder,  // diameter 1 and height 1, along y
	Capsule,   // a sphere of diameter 1 stretched along y by `params.x` on each side
	Torus,     // a ring of diameter 1 whose tube is `params.y` (in the same units) thick
	Icosphere, // diameter 1, cut into 80 flat triangles
	Model,     // a part of a loaded model (models.odin): the item says which
}

Axis3 :: enum u8 {X, Y, Z}

// What the vertex shader reads of each shape: three rows of its transform, its color and two
// numbers that stretch it (`params.x` the length a capsule's middle adds on each side, `params.y`
// how far a torus's tube reaches from its ring), both in the shape's own units, and its material. 96 bytes.
Instance3 :: struct {
	model:  [3][4]f32, // the first three rows of the transform from the shape's own space to the world
	colour: [4]f32,    // 0 to 1; the alpha is not used yet
	params: [4]f32,
	// How the surface answers light: how metal it is, how rough, 1 when it is drawn flat in its color
	// (no lights), and how much it glows by itself.
	material: [4]f32,
}
#assert(size_of(Instance3) == 96)

Item3 :: struct {
	using instance: Instance3,
	shape:          Shape3,
	model_id:       Model_Id, // for a `Model`: which model
	part:           u32,      // and which of its parts
	texture:        Image_Id, // for a solid: the picture that paints it (0: its color)
}

Scene3 :: struct {
	items: [dynamic]Item3,
	model: matrix[4, 4]f32, // the current transform; all zero until a verb sets it, which means identity
	// The camera orbits the origin. Yaw and pitch are in degrees and are changed by the
	// mouse; `zoom` is in steps of a wheel notch, each making the distance a tenth less.
	yaw, pitch, zoom: f32,
	shown: bool, // the last frame drew an item, so the mouse may orbit
	// A camera put somewhere by a verb, until the frame ends (the orbit comes back with the next one): where it is and what it looks at, in the sketch's world, how wide it sees (0 for the usual) and whether it sees without perspective.
	// The lights of the frame, and the material and lighting that shapes drawn from now on get.
	lights:   [dynamic]Light3,
	lit:      bool,       // a `light` was written this frame, so the usual lights are not there
	unlit:    bool,       // shapes are drawn flat in their color (`no lights`)
	shadows:  bool,       // what the first sun or spot light does not reach is dark (`shadows`)
	turtle:   Turtle3,   // the turtle in space (turtle3.odin); `begin_frame` sends it home and `push` saves it
	material: Material3,
	fixed:       bool,
	eye, target: [3]f64,
	fov:         f32,
	ortho:       bool,
}

// The vertical angle the camera sees, in degrees.
SCENE_FOV :: 50.0

// How far above the floor the camera starts, in degrees, so a plane in the plane of x and z shows.
CAMERA_PITCH :: 18.0

scene_destroy :: proc(s: ^Scene3) {
	delete(s.items)
	delete(s.lights)
	s^ = {}
}

// Starts a frame: forgets last frame's items and puts the transform back to the identity.
// The orbit stays, so a window keeps the way it was turned.
scene_begin :: proc(s: ^Scene3) {
	s.shown = len(s.items) > 0
	s.fixed, s.eye, s.target, s.fov, s.ortho = false, {}, {}, 0, false
	clear(&s.lights)
	s.lit, s.unlit, s.material = false, false, {}
	s.shadows = false
	s.turtle = {}
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
scene_add :: proc(s: ^Scene3, shape: Shape3, at, size: [3]f64, colour: maths.Colour, params := [2]f64{}, texture := Image_Id(0)) {
	for v in ([?]f64{at.x, at.y, at.z, size.x, size.y, size.z, params.x, params.y}) {
		if math.is_nan(v) || math.is_inf(v) {
			return
		}
	}
	m := current_model(s) * translate4(f32(at.x), f32(at.y), f32(at.z)) * scale4(f32(size.x), f32(size.y), f32(size.z))
	add_item(s, shape, m, colour, params, texture)
}

// Adds a shape whose whole transform from its own space is given (the model of `scene_add`
// is only a place and a size), still under the current transform.
scene_add_model :: proc(s: ^Scene3, shape: Shape3, model: matrix[4, 4]f32, colour: maths.Colour, params := [2]f64{}) {
	for r in 0 ..< 4 {
		for c in 0 ..< 4 {
			if math.is_nan(f64(model[r, c])) || math.is_inf(f64(model[r, c])) {
				return
			}
		}
	}
	add_item(s, shape, current_model(s) * model, colour, params)
}

@(private)
add_item :: proc(s: ^Scene3, shape: Shape3, m: matrix[4, 4]f32, colour: maths.Colour, params: [2]f64, texture := Image_Id(0)) {
	item := Item3{shape = shape, texture = texture}
	item.colour = {colour.r / 255, colour.g / 255, colour.b / 255, colour.a / 255}
	if texture != 0 {
		item.colour = {1, 1, 1, 1} // the picture is the color
	}
	item.params = {f32(params.x), f32(params.y), 0, 0}
	material := current_material(s)
	item.material = {material.metallic, material.roughness, 1 if s.unlit else 0, material.emissive}
	for r in 0 ..< 3 {
		for c in 0 ..< 4 {
			item.model[r][c] = m[r, c]
		}
	}
	append(&s.items, item)
}

// A shape of a size, standing on its middle with its y axis along `direction`, the tip (for
// a cone) the way the direction points. The turn that does it is the one that takes y to
// `direction`; the other two axes are any two that are square to it.
basis_along :: proc(direction: [3]f64) -> matrix[4, 4]f32 {
	y := normalize3(direction)
	if y == {} {
		return identity4()
	}
	helper := [3]f64{1, 0, 0}
	if abs(y.x) > 0.9 {
		helper = {0, 0, 1}
	}
	x := normalize3(cross3(helper, y))
	z := cross3(x, y)
	m := identity4()
	for r in 0 ..< 3 {
		m[r, 0], m[r, 1], m[r, 2] = f32(x[r]), f32(y[r]), f32(z[r])
	}
	return m
}

// An arrow from one place to another: a thin shaft and a head, in one color. The cone's tip
// is the way it is drawn towards negative y, so the head's basis points y back along the arrow.
scene_arrow :: proc(s: ^Scene3, from, to: [3]f64, colour: maths.Colour, thickness := 0.012) {
	along := to - from
	length := math.sqrt(dot3(along, along))
	if length == 0 || math.is_nan(length) || math.is_inf(length) {
		return
	}
	dir := along / length
	radius := length * thickness
	head := length * 0.16
	shaft := length - head
	shaft_middle := from + dir * (shaft / 2)
	scene_add_model(s, .Cylinder, translate4(f32(shaft_middle.x), f32(shaft_middle.y), f32(shaft_middle.z)) * basis_along(dir) * scale4(f32(radius * 2), f32(shaft), f32(radius * 2)), colour)
	head_middle := from + dir * (shaft + head / 2)
	scene_add_model(s, .Cone, translate4(f32(head_middle.x), f32(head_middle.y), f32(head_middle.z)) * basis_along(-dir) * scale4(f32(radius * 8), f32(head), f32(radius * 8)), colour)
}

// The three axes as arrows from the origin: x red, y green, z blue.
scene_axes :: proc(s: ^Scene3, length: f64) {
	scene_arrow(s, {}, {length, 0, 0}, {226, 72, 56, 255}, 0.03)
	scene_arrow(s, {}, {0, length, 0}, {70, 190, 90, 255}, 0.03)
	scene_arrow(s, {}, {0, 0, length}, {64, 120, 230, 255}, 0.03)
}

// A grid on the floor (the plane of x and z): `lines` squares each way across `size`,
// made of thin boxes in a color. At most 200 squares, so a mistake cannot make a million boxes.
scene_grid :: proc(s: ^Scene3, size: f64, lines: int, colour: maths.Colour) {
	n := clamp(lines, 1, 200)
	if size <= 0 || math.is_nan(size) || math.is_inf(size) {
		return
	}
	thick := max(size / 400, 0.5)
	for i in 0 ..= n {
		offset := (f64(i) / f64(n) - 0.5) * size
		scene_add(s, .Box, {offset, 0, 0}, {thick, thick, size + thick}, colour)
		scene_add(s, .Box, {0, 0, offset}, {size + thick, thick, thick}, colour)
	}
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
// screen (view and projection, with the flip that makes y go down) and where the eye is in the world.
Scene_Uniforms :: struct {
	clip:  [4][4]f32, // rows
	eye:   [4]f32,
}

// Where the camera is and how it looks, in the y-up world the projection works in (the
// sketch's world flipped in y): the eye, the three axes of the camera and how the picture
// is cut. Every camera verb and the shader's matrix are made from it, so they agree.
Camera :: struct {
	eye:         [3]f64,
	forward:     [3]f64,
	side:        [3]f64,
	up:          [3]f64,
	tan_half:    f64, // of half the vertical field of view; a perspective camera's
	half_height: f64, // how much the picture shows above the middle, in world units; an orthographic camera's
	ortho:       bool,
	aspect:      f64,
	near, far:   f64,
}

// The camera of a scene for a window of this size (logical pixels): the orbit camera unless
// a verb has put the eye somewhere.
scene_camera :: proc(s: ^Scene3, canvas: [2]f32) -> Camera {
	width, height := max(canvas.x, 1), max(canvas.y, 1)
	fov := f64(SCENE_FOV)
	if s.fov > 0 {
		fov = clamp(f64(s.fov), 1, 170)
	}
	cam := Camera{aspect = f64(width) / f64(height), ortho = s.ortho}
	cam.tan_half = math.tan(fov * math.PI / 360)
	// how far away the middle plane is seen at one unit a pixel, with the starting field of view
	distance := f64(height) / 2 / math.tan(f64(SCENE_FOV) * math.PI / 360) * math.exp(-0.1 * f64(s.zoom))
	target := [3]f64{}
	if s.fixed {
		cam.eye = {s.eye.x, -s.eye.y, s.eye.z}
		target = {s.target.x, -s.target.y, s.target.z}
	} else {
		yaw, pitch := f64(s.yaw), clamp(f64(s.pitch) + CAMERA_PITCH, -89, 89)
		cam.eye = {
			distance * maths.cos_deg(pitch) * maths.sin_deg(yaw),
			distance * maths.sin_deg(pitch),
			distance * maths.cos_deg(pitch) * maths.cos_deg(yaw),
		}
	}
	away := target - cam.eye
	length := math.sqrt(dot3(away, away))
	if length == 0 {
		// an eye at the target looks along the way it would have looked from the middle of the orbit
		cam.forward = {0, 0, -1}
		length = distance
	} else {
		cam.forward = away / length
	}
	helper := [3]f64{0, 1, 0}
	if abs(cam.forward.y) > 0.9999 {
		helper = {0, 0, -1} // looking straight up or down: keep the top of the picture to the back
	}
	cam.side = normalize3(cross3(cam.forward, helper))
	cam.up = cross3(cam.side, cam.forward)
	cam.half_height = f64(height) / 2 * math.exp(-0.1 * f64(s.zoom))
	if s.fixed {
		cam.half_height = f64(height) / 2
	}
	cam.near, cam.far = 1, max(length * 100, 10000)
	return cam
}

// The camera of a scene for a window of this size (logical pixels).
scene_uniforms :: proc(s: ^Scene3, canvas: [2]f32) -> Scene_Uniforms {
	cam := scene_camera(s, canvas)
	view := identity4()
	rows := [3][3]f64{cam.side, cam.up, -cam.forward}
	for r in 0 ..< 3 {
		for c in 0 ..< 3 {
			view[r, c] = f32(rows[r][c])
		}
	}
	view[0, 3] = f32(-dot3(cam.side, cam.eye))
	view[1, 3] = f32(-dot3(cam.up, cam.eye))
	view[2, 3] = f32(dot3(cam.forward, cam.eye))
	proj: matrix[4, 4]f32
	near, far := cam.near, cam.far
	if cam.ortho {
		proj[0, 0] = f32(1 / (cam.aspect * cam.half_height))
		proj[1, 1] = f32(1 / cam.half_height)
		proj[2, 2] = f32(1 / (near - far))
		proj[2, 3] = f32(near / (near - far))
		proj[3, 3] = 1
	} else {
		proj[0, 0] = f32(1 / (cam.aspect * cam.tan_half))
		proj[1, 1] = f32(1 / cam.tan_half)
		proj[2, 2] = f32(far / (near - far))
		proj[2, 3] = f32(near * far / (near - far))
		proj[3, 2] = -1
	}
	flip := scale4(1, -1, 1)
	all := proj * view * flip
	u := Scene_Uniforms{}
	for r in 0 ..< 4 {
		for c in 0 ..< 4 {
			u.clip[r][c] = all[r, c]
		}
	}
	// shading looks along the way the camera does; an orthographic camera has no place it looks from, so it is put far back
	eye := cam.eye
	if cam.ortho {
		eye = cam.forward * -100000
		eye += {cam.eye.x, cam.eye.y, cam.eye.z}
	}
	u.eye = {f32(eye.x), f32(-eye.y), f32(eye.z), 1}
	return u
}

// Where a place of the world shows in the window, in logical pixels from its top left.
// `visible` is false for a place behind the camera, where the answer means nothing.
scene_screen_point :: proc(s: ^Scene3, canvas: [2]f32, world: [3]f64) -> (at: [2]f64, visible: bool) {
	cam := scene_camera(s, canvas)
	p := [3]f64{world.x, -world.y, world.z} - cam.eye
	x, y, depth := dot3(p, cam.side), dot3(p, cam.up), dot3(p, cam.forward)
	ndc: [2]f64
	if cam.ortho {
		ndc = {x / (cam.aspect * cam.half_height), y / cam.half_height}
	} else {
		if depth <= 0 {
			return {}, false
		}
		ndc = {x / (depth * cam.aspect * cam.tan_half), y / (depth * cam.tan_half)}
	}
	return {(ndc.x * 0.5 + 0.5) * f64(canvas.x), (0.5 - ndc.y * 0.5) * f64(canvas.y)}, true
}

// The place on the floor (the plane y = 0 of the world) that shows at a spot of the window,
// where a line from the eye through the spot meets it. `found` is false when the line
// runs parallel to the floor or meets it behind the eye.
scene_world_point :: proc(s: ^Scene3, canvas: [2]f32, spot: [2]f64) -> (at: [3]f64, found: bool) {
	cam := scene_camera(s, canvas)
	ndc := [2]f64{spot.x / f64(max(canvas.x, 1)) * 2 - 1, 1 - spot.y / f64(max(canvas.y, 1)) * 2}
	origin, dir := cam.eye, cam.forward
	if cam.ortho {
		origin += cam.side * (ndc.x * cam.aspect * cam.half_height) + cam.up * (ndc.y * cam.half_height)
	} else {
		dir = normalize3(cam.forward + cam.side * (ndc.x * cam.aspect * cam.tan_half) + cam.up * (ndc.y * cam.tan_half))
	}
	if abs(dir.y) < 1e-12 {
		return {}, false
	}
	t := -origin.y / dir.y
	if t < 0 && !cam.ortho { // an orthographic view has no eye, so its lines go both ways
		return {}, false
	}
	hit := origin + dir * t
	return {hit.x + 0, 0 - hit.y, hit.z + 0}, true // back into the sketch's world, where y is down (and never a minus zero)
}

// Puts the eye of the camera somewhere, which takes the camera off the mouse: until the frame
// ends, it looks at the target (the middle at first) from there.
scene_camera_at :: proc(s: ^Scene3, canvas: [2]f32, eye: [3]f64) {
	scene_fix_camera(s, canvas)
	s.eye = eye
}

// Aims the camera at a place, which takes it off the mouse like `scene_camera_at`.
scene_look_at :: proc(s: ^Scene3, canvas: [2]f32, target: [3]f64) {
	scene_fix_camera(s, canvas)
	s.target = target
}

// Turns the orbit camera into a camera that stays where it is, starting where the orbit has it.
@(private)
scene_fix_camera :: proc(s: ^Scene3, canvas: [2]f32) {
	if s.fixed {
		return
	}
	cam := scene_camera(s, canvas)
	s.eye = {cam.eye.x, -cam.eye.y, cam.eye.z}
	s.target = {}
	s.fixed = true
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
		h = hash_u64(h, u64(item.model_id) << 32 | u64(item.part))
		for row in item.model {
			for v in row {
				h = hash_f32(h, v)
			}
		}
		for v in item.colour {
			h = hash_f32(h, v)
		}
		h = hash_f32_pair(h, item.params.x, item.params.y)
		h = hash_f32_pair(h, item.material[0], item.material[1])
		h = hash_f32_pair(h, item.material[2], item.material[3])
	}
	h = hash_f32_pair(h, s.yaw, s.pitch)
	h = hash_u64(h, u64(s.fixed) | u64(s.ortho) << 1)
	for light in s.lights {
		h = hash_u64(h, u64(light.kind))
		for v in ([?]f64{light.at.x, light.at.y, light.at.z, light.aim.x, light.aim.y, light.aim.z, f64(light.falloff), f64(light.angle), f64(light.colour.r), f64(light.colour.g), f64(light.colour.b)}) {
			h = hash_f32(h, f32(v))
		}
	}
	h = hash_u64(h, u64(s.lit) | u64(s.shadows) << 1)
	for v in ([?]f64{s.eye.x, s.eye.y, s.eye.z, s.target.x, s.target.y, s.target.z, f64(s.fov)}) {
		h = hash_f32(h, f32(v))
	}
	return hash_f32(h, s.zoom)
}

// ---- the shapes ----

// One corner of a shape's mesh: where it is and which way the surface faces. `stretch` is
// -1 or 1 for the corners of a capsule's two ends, which move apart by the instance's
// `params.x`, and 0 for everything else.
Vertex3 :: struct {
	position: [3]f32,
	normal:   [3]f32,
	stretch:  f32,
	uv:       [2]f32, // where in a model's textures this corner is (0 for the shapes, which have none)
	uv1:      [2]f32, // and in the pictures that use a second set of coordinates
	colour:   [4]u8,  // the corner's own color, which multiplies the material's (white for the shapes)
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

SEGMENTS :: 48 // round the axis of a cone, cylinder, capsule or sphere

// Joins two rings of `SEGMENTS + 1` corners that follow each other in the mesh.
@(private)
stitch_rings :: proc(m: ^Mesh3, first, second: u32) {
	for seg in 0 ..< u32(SEGMENTS) {
		a, b := first + seg, second + seg
		append(&m.indices, a, b, a + 1, a + 1, b, b + 1)
	}
}

// A ring of corners at height `y` and radius `radius`, each with its normal and stretch.
@(private)
add_ring :: proc(m: ^Mesh3, y, radius: f32, normal_y: f32, normal_scale: f32, stretch: f32, v := f32(0)) -> u32 {
	first := u32(len(m.vertices))
	for seg in 0 ..= SEGMENTS {
		theta := f64(seg) / f64(SEGMENTS) * 360
		c, s := f32(maths.cos_deg(theta)), f32(maths.sin_deg(theta))
		n := normalize3f({c * normal_scale, normal_y, s * normal_scale})
		append(&m.vertices, Vertex3{{c * radius, y, s * radius}, n, stretch, {f32(seg) / f32(SEGMENTS), v}, {}, {255, 255, 255, 255}})
	}
	return first
}

@(private)
normalize3f :: proc(v: [3]f32) -> [3]f32 {
	n := math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
	if n == 0 {
		return {}
	}
	return v / n
}

// A flat disc facing along y (a cone's or cylinder's end) at height y.
@(private)
add_cap :: proc(m: ^Mesh3, y: f32, facing: f32) {
	centre := u32(len(m.vertices))
	append(&m.vertices, Vertex3{{0, y, 0}, {0, facing, 0}, 0, {}, {}, {255, 255, 255, 255}})
	ring := add_ring(m, y, 0.5, facing, 0, 0)
	m.vertices[centre].uv = {0.5, 0.5}
	for seg in 0 ..= SEGMENTS {
		theta := f64(seg) / f64(SEGMENTS) * 360
		m.vertices[ring + u32(seg)].uv = {0.5 + 0.5 * f32(maths.cos_deg(theta)), 0.5 + 0.5 * f32(maths.sin_deg(theta))} // the disc seen from its end
	}
	for seg in 0 ..< u32(SEGMENTS) {
		append(&m.indices, centre, ring + seg, ring + seg + 1)
	}
}

// Builds every shape into one mesh, all about their middles: a cube of side 1, a sphere of
// diameter 1, a square of side 1, a cone and a cylinder of diameter 1 and height 1, a capsule
// that is a sphere until it is stretched, a ring of diameter 1 (whose tube the instance
// thickens) and a sphere of 80 flat faces.
build_shape_meshes :: proc() -> Shape_Meshes {
	out: Shape_Meshes
	m := &out.mesh
	range :: proc(out: ^Shape_Meshes, shape: Shape3, start: u32) {
		out.ranges[shape] = {start, u32(len(out.mesh.indices)) - start}
	}

	// the box: four corners for each face, so each face has its own normal
	start := u32(len(m.indices))
	faces := [6][3]f32{{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}}
	for n in faces {
		a: [3]f32 = {n.y, n.z, n.x}
		b: [3]f32 = {n.z, n.x, n.y}
		base := u32(len(m.vertices))
		for corner in ([4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}) {
			p := n * 0.5 + a * (corner.x * 0.5) + b * (corner.y * 0.5)
			append(&m.vertices, Vertex3{p, n, 0, {corner.x * 0.5 + 0.5, 0.5 - corner.y * 0.5}, {}, {255, 255, 255, 255}}) // each face holds the whole picture
		}
		append(&m.indices, base, base + 1, base + 2, base, base + 2, base + 3)
	}
	range(&out, .Box, start)

	// the sphere: rings of latitude (a diameter of 1, like the box's side)
	start = u32(len(m.indices))
	rings := 24
	ring_starts := make([dynamic]u32, context.temp_allocator)
	for ring in 0 ..= rings {
		phi := f64(ring) / f64(rings) * 180
		first := u32(len(m.vertices))
		append(&ring_starts, first)
		for seg in 0 ..= SEGMENTS {
			theta := f64(seg) / f64(SEGMENTS) * 360
			n := [3]f32{
				f32(maths.sin_deg(phi) * maths.cos_deg(theta)),
				f32(-maths.cos_deg(phi)),
				f32(maths.sin_deg(phi) * maths.sin_deg(theta)),
			}
			append(&m.vertices, Vertex3{n * 0.5, n, 0, {f32(seg) / f32(SEGMENTS), f32(ring) / f32(rings)}, {}, {255, 255, 255, 255}})
		}
	}
	for ring in 0 ..< rings {
		stitch_rings(m, ring_starts[ring], ring_starts[ring + 1])
	}
	range(&out, .Sphere, start)

	// the plane
	start = u32(len(m.indices))
	base := u32(len(m.vertices))
	for corner in ([4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}) {
		append(&m.vertices, Vertex3{{corner.x * 0.5, 0, corner.y * 0.5}, {0, -1, 0}, 0, {corner.x * 0.5 + 0.5, corner.y * 0.5 + 0.5}, {}, {255, 255, 255, 255}})
	}
	append(&m.indices, base, base + 1, base + 2, base, base + 2, base + 3)
	range(&out, .Plane, start)

	// the cone: its tip at the top (negative y), its base at the bottom
	start = u32(len(m.indices))
	tip := add_ring(m, -0.5, 0, -1, 2, 0, 0) // every corner at the tip, each with its side's normal
	base_ring := add_ring(m, 0.5, 0.5, -1, 2, 0, 1)
	stitch_rings(m, tip, base_ring)
	add_cap(m, 0.5, 1)
	range(&out, .Cone, start)

	// the cylinder
	start = u32(len(m.indices))
	top := add_ring(m, -0.5, 0.5, 0, 1, 0, 0)
	bottom := add_ring(m, 0.5, 0.5, 0, 1, 0, 1)
	stitch_rings(m, top, bottom)
	add_cap(m, -0.5, -1)
	add_cap(m, 0.5, 1)
	range(&out, .Cylinder, start)

	// the capsule: a sphere cut at its equator into two halves that the instance moves apart
	start = u32(len(m.indices))
	half := 12
	capsule_rings := make([dynamic]u32, context.temp_allocator)
	for ring in 0 ..= half {
		phi := f64(ring) / f64(half) * 90
		first := u32(len(m.vertices))
		append(&capsule_rings, first)
		for seg in 0 ..= SEGMENTS {
			theta := f64(seg) / f64(SEGMENTS) * 360
			n := [3]f32{
				f32(maths.sin_deg(phi) * maths.cos_deg(theta)),
				f32(-maths.cos_deg(phi)),
				f32(maths.sin_deg(phi) * maths.sin_deg(theta)),
			}
			append(&m.vertices, Vertex3{n * 0.5, n, -1, {f32(seg) / f32(SEGMENTS), 0.25 * f32(ring) / f32(half)}, {}, {255, 255, 255, 255}})
		}
	}
	for ring in half ..= half * 2 {
		phi := f64(ring) / f64(half) * 90
		first := u32(len(m.vertices))
		append(&capsule_rings, first)
		for seg in 0 ..= SEGMENTS {
			theta := f64(seg) / f64(SEGMENTS) * 360
			n := [3]f32{
				f32(maths.sin_deg(phi) * maths.cos_deg(theta)),
				f32(-maths.cos_deg(phi)),
				f32(maths.sin_deg(phi) * maths.sin_deg(theta)),
			}
			append(&m.vertices, Vertex3{n * 0.5, n, 1, {f32(seg) / f32(SEGMENTS), 0.75 + 0.25 * f32(ring - half) / f32(half)}, {}, {255, 255, 255, 255}})
		}
	}
	for i in 0 ..< len(capsule_rings) - 1 {
		stitch_rings(m, capsule_rings[i], capsule_rings[i + 1])
	}
	range(&out, .Capsule, start)

	// the torus: each corner is on the ring, and the instance pushes it out along its normal by the tube's radius
	start = u32(len(m.indices))
	tube_segments := 24
	torus_rings := make([dynamic]u32, context.temp_allocator)
	for v in 0 ..= tube_segments {
		angle := f64(v) / f64(tube_segments) * 360
		first := u32(len(m.vertices))
		append(&torus_rings, first)
		for seg in 0 ..= SEGMENTS {
			theta := f64(seg) / f64(SEGMENTS) * 360
			dir := [3]f32{f32(maths.cos_deg(theta)), 0, f32(maths.sin_deg(theta))}
			n := dir * f32(maths.cos_deg(angle)) + [3]f32{0, f32(-maths.sin_deg(angle)), 0}
			append(&m.vertices, Vertex3{dir * 0.5, n, 0, {f32(seg) / f32(SEGMENTS), f32(v) / f32(tube_segments)}, {}, {255, 255, 255, 255}})
		}
	}
	for i in 0 ..< len(torus_rings) - 1 {
		stitch_rings(m, torus_rings[i], torus_rings[i + 1])
	}
	range(&out, .Torus, start)

	// the icosphere: an icosahedron cut once into 80 triangles, each flat
	start = u32(len(m.indices))
	t := f32((1 + math.sqrt(f64(5))) / 2)
	corners := [12][3]f32{
		{-1, t, 0}, {1, t, 0}, {-1, -t, 0}, {1, -t, 0},
		{0, -1, t}, {0, 1, t}, {0, -1, -t}, {0, 1, -t},
		{t, 0, -1}, {t, 0, 1}, {-t, 0, -1}, {-t, 0, 1},
	}
	triangles := [20][3]int{
		{0, 11, 5}, {0, 5, 1}, {0, 1, 7}, {0, 7, 10}, {0, 10, 11},
		{1, 5, 9}, {5, 11, 4}, {11, 10, 2}, {10, 7, 6}, {7, 1, 8},
		{3, 9, 4}, {3, 4, 2}, {3, 2, 6}, {3, 6, 8}, {3, 8, 9},
		{4, 9, 5}, {2, 4, 11}, {6, 2, 10}, {8, 6, 7}, {9, 8, 1},
	}
	add_face :: proc(m: ^Mesh3, p, q, r: [3]f32) {
		a, b, c := normalize3f(p) * 0.5, normalize3f(q) * 0.5, normalize3f(r) * 0.5
		edge1, edge2 := b - a, c - a
		n := normalize3f({edge1.y * edge2.z - edge1.z * edge2.y, edge1.z * edge2.x - edge1.x * edge2.z, edge1.x * edge2.y - edge1.y * edge2.x})
		// make it face away from the middle, which is the way every face of a convex shape faces
		if n.x * (a.x + b.x + c.x) + n.y * (a.y + b.y + c.y) + n.z * (a.z + b.z + c.z) < 0 {
			n = -n
		}
		// longitude and latitude, with a face that crosses the seam taking the far side past 1 (the picture repeats)
		spot :: proc(p: [3]f32) -> [2]f32 {
			return {0.5 + f32(math.atan2(f64(p.z), f64(p.x)) / (2 * math.PI)), 0.5 + f32(math.asin(clamp(f64(p.y) * 2, -1, 1)) / math.PI)}
		}
		ua, ub, uc := spot(a), spot(b), spot(c)
		if max(ua.x, ub.x, uc.x) - min(ua.x, ub.x, uc.x) > 0.5 {
			for uv in ([3]^[2]f32{&ua, &ub, &uc}) {
				if uv.x < 0.5 {uv.x += 1}
			}
		}
		base := u32(len(m.vertices))
		append(&m.vertices, Vertex3{a, n, 0, ua, {}, {255, 255, 255, 255}}, Vertex3{b, n, 0, ub, {}, {255, 255, 255, 255}}, Vertex3{c, n, 0, uc, {}, {255, 255, 255, 255}})
		append(&m.indices, base, base + 1, base + 2)
	}
	for tri in triangles {
		a, b, c := corners[tri[0]], corners[tri[1]], corners[tri[2]]
		ab, bc, ca := normalize3f(a + b), normalize3f(b + c), normalize3f(c + a)
		add_face(m, a, ab, ca)
		add_face(m, b, bc, ab)
		add_face(m, c, ca, bc)
		add_face(m, ab, bc, ca)
	}
	range(&out, .Icosphere, start)
	return out
}

// A place given in the coordinates of the current transform, in the world.
scene_to_world :: proc(s: ^Scene3, p: [3]f64) -> [3]f64 {
	m := current_model(s)
	v := [4]f32{f32(p.x), f32(p.y), f32(p.z), 1}
	out: [3]f64
	for r in 0 ..< 3 {
		out[r] = f64(m[r, 0] * v[0] + m[r, 1] * v[1] + m[r, 2] * v[2] + m[r, 3] * v[3])
	}
	return out
}

// ---- materials and lights ----

// How a surface answers light, as `material` says it: `metallic` 0 for paint and plastic up to 1
// for metal (which tints what it reflects with its own color), `roughness` 0 for a mirror up to 1
// for chalk, and `emissive` how much of its color it gives off itself.
Material3 :: struct {
	metallic, roughness, emissive: f32,
	set:                       bool, // a `material` was written; otherwise the usual one is meant
}

DEFAULT_ROUGHNESS :: 0.5

current_material :: proc(s: ^Scene3) -> Material3 {
	if s.material.set {
		return s.material
	}
	return {roughness = DEFAULT_ROUGHNESS, set = true}
}

scene_material :: proc(s: ^Scene3, metallic, roughness, emissive: Maybe(f64)) {
	m := current_material(s)
	if v, ok := metallic.?; ok {m.metallic = f32(clamp(v, 0, 1))}
	if v, ok := roughness.?; ok {m.roughness = f32(clamp(v, 0, 1))}
	if v, ok := emissive.?; ok {m.emissive = f32(clamp(v, 0, 1))}
	s.material = m
}

// Shapes drawn from now on are flat in their color, with no light or shade.
scene_no_lights :: proc(s: ^Scene3) {
	s.unlit = true
}

Light_Kind :: enum u8 {
	Ambient, // from everywhere, the same on every surface
	Sun,     // from far away in one direction
	Point,   // from a place, weaker the further away
	Spot,    // from a place, towards a place, inside a cone
}

Light3 :: struct {
	kind:     Light_Kind,
	at:       [3]f64,  // a point or spot light's place; a sun's direction towards the light
	aim:      [3]f64,  // where a spot light looks
	colour:   [3]f32,  // 0 to 1
	falloff:  f32,     // the distance at which a point or spot light has dropped to half
	angle:    f32,     // a spot light's half angle in degrees
}

MAX_LIGHTS :: 64

// A uniform block has to fit in 4,096 bytes, which is what Metal passes a shader that way.
#assert(size_of(Scene_Lights) <= 4096)

// What happened to a light a verb gave.
Light_Result :: enum {
	Added,
	Left_Out, // a number that is not a number
	Too_Many, // the scene has MAX_LIGHTS already
}

// Adds a light, in world coordinates. The first one of a frame takes the usual lights away; one
// past the sixty-fourth is left out, which is said. Anything not a finite number leaves the light out.
scene_light :: proc(s: ^Scene3, light: Light3) -> Light_Result {
	for v in ([?]f64{light.at.x, light.at.y, light.at.z, light.aim.x, light.aim.y, light.aim.z, f64(light.falloff), f64(light.angle)}) {
		if math.is_nan(v) || math.is_inf(v) {
			return .Left_Out
		}
	}
	s.lit = true
	if len(s.lights) >= MAX_LIGHTS {
		return .Too_Many
	}
	append(&s.lights, light)
	return .Added
}

// What the fragment shader reads: where the eye is, the ambient light and the other lights, each
// three float4: (place or direction, kind), (color, falloff), (the way a spot light points, the
// cosine of its half angle). The color of the lights the frame did not give is the usual pair.
Scene_Lights :: struct {
	eye:     [4]f32,
	ambient: [4]f32, // the color, and in w how many lights there are
	lights:  [MAX_LIGHTS][3][4]f32,
	shadow_rows: [4][4]f32, // the matrix from the world to the shadow-casting light's view, as rows
	shadow:      [4]f32,    // 1 when there is a shadow map, which light casts it, how far to push a surface out, the size of a texel
}

USUAL_AMBIENT :: [3]f32{0.4, 0.4, 0.4}
USUAL_SUN :: Light3{kind = .Sun, at = {-0.4, -0.7, 0.6}, colour = {0.96, 0.96, 0.96}}

scene_lights :: proc(s: ^Scene3, canvas: [2]f32) -> Scene_Lights {
	out: Scene_Lights
	u := scene_uniforms(s, canvas)
	out.eye = u.eye
	lights := s.lights[:]
	usual := [1]Light3{USUAL_SUN}
	ambient := [3]f32{}
	if !s.lit {
		lights = usual[:]
		ambient = USUAL_AMBIENT
	}
	count := 0
	for light in lights {
		switch light.kind {
		case .Ambient:
			ambient += light.colour
		case .Sun, .Point, .Spot:
			if s.shadows && out.shadow.x == 0 && light.kind != .Point {
				// the first sun or spot light casts the shadows; the number it has among the lights is the shader's way to find it
				rows, texel := shadow_view(s, light)
				out.shadow_rows = rows
				out.shadow = {1, f32(count), f32(texel * 1.5), 1.0 / SHADOW_SIZE}
			}
			g := &out.lights[count]
			count += 1
			place := light.at
			if light.kind == .Sun {
				place = normalize3(place)
			}
			g[0] = {f32(place.x), f32(place.y), f32(place.z), f32(light.kind)}
			g[1] = {light.colour.r, light.colour.g, light.colour.b, max(light.falloff, 1e-3)}
			if light.kind == .Spot {
				axis := normalize3(light.aim - light.at)
				half := clamp(f64(light.angle), 1, 89)
				g[2] = {f32(axis.x), f32(axis.y), f32(axis.z), f32(maths.cos_deg(half))}
			}
		}
	}
	out.ambient = {min(ambient.r, 1), min(ambient.g, 1), min(ambient.b, 1), f32(count)}
	return out
}

// ---- shadows ----

// The shadow map is a square of this many texels, drawn from the first sun or spot light.
SHADOW_SIZE :: 2048

// Turns shadows on for the rest of the frame: what the first sun or spot light does not reach is dark.
scene_shadows :: proc(s: ^Scene3) {
	s.shadows = true
}

// A sphere that holds every shape of the scene: its middle and radius. Each shape is held by a
// sphere of its own, as far across as its corner is from its middle, stretched by what makes a
// capsule longer and a torus's tube thicker.
scene_bounds :: proc(s: ^Scene3) -> (centre: [3]f64, radius: f64) {
	if len(s.items) == 0 {
		return {}, 1
	}
	low, high := [3]f64{math.INF_F64, math.INF_F64, math.INF_F64}, [3]f64{-math.INF_F64, -math.INF_F64, -math.INF_F64}
	spheres := make([dynamic][4]f64, 0, len(s.items), context.temp_allocator)
	for item in s.items {
		if item.shape == .Model {
			// a loaded model is held by the box it was fitted from, whose corners are put where the item puts them
			if data := model_data(item.model_id); data != nil {
				for corner in 0 ..< 8 {
					p := [3]f32{data.low.x if corner & 1 == 0 else data.high.x, data.low.y if corner & 2 == 0 else data.high.y, data.low.z if corner & 4 == 0 else data.high.z}
					w: [3]f64
					for row in 0 ..< 3 {
						w[row] = f64(item.model[row][0] * p.x + item.model[row][1] * p.y + item.model[row][2] * p.z + item.model[row][3])
					}
					append(&spheres, [4]f64{w.x, w.y, w.z, 0})
					for axis in 0 ..< 3 {
						low[axis] = min(low[axis], w[axis])
						high[axis] = max(high[axis], w[axis])
					}
				}
			}
			continue
		}
		widest := f64(0)
		for column in 0 ..< 3 {
			x, y, z := f64(item.model[0][column]), f64(item.model[1][column]), f64(item.model[2][column])
			widest = max(widest, math.sqrt(x * x + y * y + z * z))
		}
		at := [3]f64{f64(item.model[0][3]), f64(item.model[1][3]), f64(item.model[2][3])}
		r := widest * (0.87 + f64(abs(item.params.x)) + f64(abs(item.params.y)))
		append(&spheres, [4]f64{at.x, at.y, at.z, r})
		for axis in 0 ..< 3 {
			low[axis] = min(low[axis], at[axis] - r)
			high[axis] = max(high[axis], at[axis] + r)
		}
	}
	centre = (low + high) / 2
	for sphere in spheres {
		d := [3]f64{sphere[0], sphere[1], sphere[2]} - centre
		radius = max(radius, math.sqrt(dot3(d, d)) + sphere[3])
	}
	return centre, max(radius, 1e-3)
}

// The rows of the matrix that takes a place of the world to the view of a light that sits at
// `eye` and looks along `forward` (both in the world of the sketch, whose y is down), with a
// projection that is square on the screen: orthographic when `half_size` is given (the light
// is a sun), a perspective of `fov` degrees otherwise (a spot light).
light_matrix_rows :: proc(eye, forward: [3]f64, half_size, fov, near, far: f64) -> [4][4]f32 {
	// the projection works in the y-up world, which is the sketch's flipped in y
	e := [3]f64{eye.x, -eye.y, eye.z}
	f := normalize3({forward.x, -forward.y, forward.z})
	helper := [3]f64{0, 1, 0}
	if abs(f.y) > 0.999 {
		helper = {0, 0, -1}
	}
	side := normalize3(cross3(f, helper))
	up := cross3(side, f)
	view := identity4()
	rows := [3][3]f64{side, up, -f}
	for r in 0 ..< 3 {
		for c in 0 ..< 3 {
			view[r, c] = f32(rows[r][c])
		}
	}
	view[0, 3] = f32(-dot3(side, e))
	view[1, 3] = f32(-dot3(up, e))
	view[2, 3] = f32(dot3(f, e))
	proj: matrix[4, 4]f32
	if half_size > 0 {
		proj[0, 0] = f32(1 / half_size)
		proj[1, 1] = f32(1 / half_size)
		proj[2, 2] = f32(1 / (near - far))
		proj[2, 3] = f32(near / (near - far))
		proj[3, 3] = 1
	} else {
		t := math.tan(clamp(fov, 1, 170) * math.PI / 360)
		proj[0, 0] = f32(1 / t)
		proj[1, 1] = f32(1 / t)
		proj[2, 2] = f32(far / (near - far))
		proj[2, 3] = f32(near * far / (near - far))
		proj[3, 2] = -1
	}
	all := proj * view * scale4(1, -1, 1)
	out: [4][4]f32
	for r in 0 ..< 4 {
		for c in 0 ..< 4 {
			out[r][c] = all[r, c]
		}
	}
	return out
}

// The view of a sun or spot light that holds the whole scene: for a sun, a box as wide as the
// scene looking along the way the light shines; for a spot light, a cone as wide as the light's
// own with a little to spare. `texel` is how far across one texel of the map is at the scene's middle.
shadow_view :: proc(s: ^Scene3, light: Light3) -> (rows: [4][4]f32, texel: f64) {
	centre, radius := scene_bounds(s)
	if light.kind == .Sun {
		toward := normalize3(light.at)
		if toward == {} {
			toward = {0, -1, 0}
		}
		eye := centre + toward * (radius * 2)
		return light_matrix_rows(eye, -toward, radius, 0, 0, radius * 4), radius * 2 / SHADOW_SIZE
	}
	away := centre - light.at
	distance := math.sqrt(dot3(away, away))
	fov := clamp(f64(light.angle) * 2 + 10, 10, 170)
	near := max(1.0, (distance - radius) * 0.5)
	far := max(distance + radius * 1.5, near + 1)
	aim := normalize3(light.aim - light.at)
	if aim == {} {
		aim = normalize3(away)
	}
	width := 2 * math.tan(fov * math.PI / 360) * distance
	return light_matrix_rows(light.at, aim, 0, fov, near, far), width / SHADOW_SIZE
}

// ---- loaded models ----

// Adds a loaded model, fitted to a size: its box is moved so its middle is at `at` and scaled so
// its longest side is `size` long, under the current transform. Each part of the model is one
// item, with the color, metal, roughness and glow its material gave; `no lights` still makes it flat.
// Gives how many items it added: none for a number that names no model.
scene_add_loaded_model :: proc(s: ^Scene3, id: Model_Id, at: [3]f64, size: f64) -> int {
	data := model_data(id)
	if data == nil || len(data.parts) == 0 {
		return 0
	}
	for v in ([?]f64{at.x, at.y, at.z, size}) {
		if math.is_nan(v) || math.is_inf(v) {
			return 0
		}
	}
	centre, longest := model_extent(data)
	k := size / f64(longest) if longest > 0 else 1
	m := current_model(s) * translate4(f32(at.x), f32(at.y), f32(at.z)) * scale4(f32(k), f32(k), f32(k)) * translate4(-centre.x, -centre.y, -centre.z)
	return add_loaded_parts(s, data, id, m)
}

// One item for each part of a model, placed by `m`; the parts' own colors unless `colour` is given.
@(private)
add_loaded_parts :: proc(s: ^Scene3, data: ^Model_Data, id: Model_Id, m: matrix[4, 4]f32, colour: Maybe(maths.Colour) = nil) -> int {
	for part, i in data.parts {
		item := Item3{shape = .Model, model_id = id, part = u32(i)}
		item.colour = {part.colour.r, part.colour.g, part.colour.b, 1}
		material := current_material(s)
		item.material = {part.metallic, part.roughness, 1 if (s.unlit || part.unlit) else 0, part.emissive}
		if own, given := colour.?; given {
			item.colour = {own.r / 255, own.g / 255, own.b / 255, own.a / 255}
			item.material = {material.metallic, material.roughness, 1 if s.unlit else 0, material.emissive}
		}
		for r in 0 ..< 3 {
			for c in 0 ..< 4 {
				item.model[r][c] = m[r, c]
			}
		}
		append(&s.items, item)
	}
	return len(data.parts)
}

// The line from the eye through a spot of the window, as two places of the world (y down): where it
// starts (the eye, or for an orthographic view the spot's own place on the lens) and a far place along
// it, `PICK_RANGE` from the start. `cast` along it finds what shows at the spot.
PICK_RANGE :: 100_000.0

scene_pixel_ray :: proc(s: ^Scene3, canvas: [2]f32, spot: [2]f64) -> (from, to: [3]f64) {
	cam := scene_camera(s, canvas)
	ndc := [2]f64{spot.x / f64(max(canvas.x, 1)) * 2 - 1, 1 - spot.y / f64(max(canvas.y, 1)) * 2}
	origin, dir := cam.eye, cam.forward
	if cam.ortho {
		origin += cam.side * (ndc.x * cam.aspect * cam.half_height) + cam.up * (ndc.y * cam.half_height)
	} else {
		dir = normalize3(cam.forward + cam.side * (ndc.x * cam.aspect * cam.tan_half) + cam.up * (ndc.y * cam.tan_half))
	}
	far := origin + dir * PICK_RANGE
	// back into the sketch's world, where y is down (and never a minus zero)
	return {origin.x + 0, 0 - origin.y, origin.z + 0}, {far.x + 0, 0 - far.y, far.z + 0}
}

// The corners of a loaded model's triangles, three for each, as `scene_add_loaded_model` would draw it:
// fitted to a size, with its middle at `at`, under the current transform. Nothing for a number that
// names no model.
scene_model_triangles :: proc(s: ^Scene3, id: Model_Id, at: [3]f64, size: f64, allocator := context.allocator) -> [][3]f64 {
	data := model_data(id)
	if data == nil || len(data.parts) == 0 {
		return nil
	}
	for v in ([?]f64{at.x, at.y, at.z, size}) {
		if math.is_nan(v) || math.is_inf(v) {
			return nil
		}
	}
	centre, longest := model_extent(data)
	k := size / f64(longest) if longest > 0 else 1
	m := current_model(s) * translate4(f32(at.x), f32(at.y), f32(at.z)) * scale4(f32(k), f32(k), f32(k)) * translate4(-centre.x, -centre.y, -centre.z)
	out := make([dynamic][3]f64, allocator)
	for part in data.parts {
		for i in part.first_index ..< part.first_index + part.index_count {
			p := data.vertices[data.indices[i]].position
			append(&out, [3]f64{
				f64(m[0, 0] * p.x + m[0, 1] * p.y + m[0, 2] * p.z + m[0, 3]),
				f64(m[1, 0] * p.x + m[1, 1] * p.y + m[1, 2] * p.z + m[1, 3]),
				f64(m[2, 0] * p.x + m[2, 1] * p.y + m[2, 2] * p.z + m[2, 3]),
			})
		}
	}
	return out[:]
}
