// SPDX-License-Identifier: 0BSD
//
// A mesh a sketch makes itself: a list of corners, three for each triangle, drawn flat shaded as a model is, or as
// a wireframe. It becomes the data of a model (`Model_Data`, one part, a flat normal for each triangle) kept under a
// key of the call that makes it, so the same list drawn every frame is sent to the graphics card once and a list
// that changes is sent again.
//
// A wireframe is made of the mesh's feature edges, drawn as thin tubes (the turtle's in space are the same) with a
// ball at each corner so a bend is round. An edge is a feature when it is the side of one triangle only, of three or
// more, or of two that do not lie in one plane, so the diagonal that cuts a square into two triangles is not drawn
// and a box has its twelve edges, not eighteen.
package gfx

import "../maths"
import "core:hash"
import "core:math"

// The most edges a wireframe draws; a mesh with more is drawn up to this many.
MESH_MAX_EDGES :: 60_000

// How alike two triangles' normals must be (the cosine of the angle between them) for the edge they share to be
// left out: about a degree.
MESH_FLAT_COSINE :: 0.99985

@(private = "file")
Edge_Key :: [6]i32

@(private = "file")
Edge_Seen :: struct {
	count:   int,
	normal:  [3]f32, // of the first triangle
	crease:  bool,   // a triangle with another normal was met
}

@(private = "file")
quantised :: proc(p: [3]f32) -> [3]i32 {
	return {i32(math.round(p.x * 1024)), i32(math.round(p.y * 1024)), i32(math.round(p.z * 1024))}
}

// A hash of the corners, which says whether a mesh drawn again is the one drawn before.
mesh_hash :: proc(corners: [][3]f64) -> i64 {
	if len(corners) == 0 {
		return 0
	}
	bytes := ([^]u8)(raw_data(corners))[:len(corners) * size_of([3]f64)]
	return i64(hash.fnv64a(bytes))
}

// The data of a model made of the triangles of `corners` (three for each; a corner or two left over are ignored),
// in the sketch's world, with a flat normal for each triangle and the feature edges for a wireframe. A triangle with
// no area is left out. Nothing when there is no triangle.
mesh_data :: proc(corners: [][3]f64) -> (data: Model_Data, ok: bool) {
	triangles := len(corners) / 3
	if triangles == 0 {
		return {}, false
	}
	seen := make(map[Edge_Key]Edge_Seen, context.temp_allocator)
	low, high := [3]f32{max(f32), max(f32), max(f32)}, [3]f32{min(f32), min(f32), min(f32)}
	for i in 0 ..< triangles {
		a, b, c := to_f32(corners[i * 3]), to_f32(corners[i * 3 + 1]), to_f32(corners[i * 3 + 2])
		if !finite3(a) || !finite3(b) || !finite3(c) {
			continue
		}
		n := cross3f(b - a, c - a)
		length := math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z)
		if !(length > 0) {
			continue
		}
		n /= length
		first := u32(len(data.vertices))
		for p in ([3][3]f32{a, b, c}) {
			append(&data.vertices, Vertex3{position = p, normal = n, colour = {255, 255, 255, 255}})
			low = {min(low.x, p.x), min(low.y, p.y), min(low.z, p.z)}
			high = {max(high.x, p.x), max(high.y, p.y), max(high.z, p.z)}
		}
		append(&data.indices, first, first + 1, first + 2)
		points := [3][3]f32{a, b, c}
		for e in 0 ..< 3 {
			p, q := quantised(points[e]), quantised(points[(e + 1) % 3])
			if p == q {
				continue
			}
			if p.x > q.x || (p.x == q.x && (p.y > q.y || (p.y == q.y && p.z > q.z))) {
				p, q = q, p
			}
			key := Edge_Key{p.x, p.y, p.z, q.x, q.y, q.z}
			entry := seen[key]
			if entry.count == 0 {
				entry.normal = n
			} else if entry.normal.x * n.x + entry.normal.y * n.y + entry.normal.z * n.z < MESH_FLAT_COSINE {
				entry.crease = true
			}
			entry.count += 1
			seen[key] = entry
		}
	}
	if len(data.indices) == 0 {
		model_data_destroy(&data)
		return {}, false
	}
	part := model_part_default()
	part.index_count = u32(len(data.indices))
	part.metallic = 0
	part.roughness = 0.6
	append(&data.parts, part)
	data.low, data.high = low, high
	// the feature edges, in the order their triangles gave them, so the same mesh always draws the same lines
	listed := make(map[Edge_Key]bool, context.temp_allocator)
	for i in 0 ..< triangles {
		points := [3][3]f32{to_f32(corners[i * 3]), to_f32(corners[i * 3 + 1]), to_f32(corners[i * 3 + 2])}
		for e in 0 ..< 3 {
			from, to := points[e], points[(e + 1) % 3]
			p, q := quantised(from), quantised(to)
			if p == q {
				continue
			}
			if p.x > q.x || (p.x == q.x && (p.y > q.y || (p.y == q.y && p.z > q.z))) {
				p, q = q, p
			}
			key := Edge_Key{p.x, p.y, p.z, q.x, q.y, q.z}
			entry, found := seen[key]
			if !found || listed[key] {
				continue
			}
			if entry.count == 1 || entry.count > 2 || entry.crease {
				listed[key] = true
				append(&data.edges, [2][3]f32{from, to})
			}
		}
	}
	return data, true
}

@(private = "file")
to_f32 :: proc(p: [3]f64) -> [3]f32 {
	return {f32(p.x), f32(p.y), f32(p.z)}
}

@(private = "file")
finite3 :: proc(p: [3]f32) -> bool {
	return !(math.is_nan(p.x) || math.is_inf(p.x) || math.is_nan(p.y) || math.is_inf(p.y) || math.is_nan(p.z) || math.is_inf(p.z))
}

// Keeps the mesh of `corners` under `key` and gives its number, or 0 when there is no triangle in it. A key that is
// there with the same corners gives the same number without making anything.
mesh_keep :: proc(key: string, corners: [][3]f64) -> Model_Id {
	stamp := mesh_hash(corners)
	if id, found := model_find(key, stamp); found {
		return id
	}
	data, ok := mesh_data(corners)
	if !ok {
		return 0
	}
	return model_add(key, stamp, data)
}

// Adds the mesh kept as `id` to the scene, filled, in `colour`, under the current transform.
scene_add_mesh :: proc(s: ^Scene3, id: Model_Id, colour: maths.Colour) -> int {
	data := model_data(id)
	if data == nil {
		return 0
	}
	return add_loaded_parts(s, data, id, current_model(s), colour)
}

// Adds the feature edges of the mesh kept as `id` to the scene as tubes `width` across, in `colour`.
// Gives how many tubes it added.
scene_add_wireframe :: proc(s: ^Scene3, id: Model_Id, width: f64, colour: maths.Colour) -> int {
	data := model_data(id)
	if data == nil || !(width > 0) || math.is_inf(width) {
		return 0
	}
	added := 0
	corner_done := make(map[[3]i32]bool, context.temp_allocator)
	for edge in data.edges {
		if added >= MESH_MAX_EDGES {
			break
		}
		from := [3]f64{f64(edge[0].x), f64(edge[0].y), f64(edge[0].z)}
		to := [3]f64{f64(edge[1].x), f64(edge[1].y), f64(edge[1].z)}
		along := to - from
		length := math.sqrt(along.x * along.x + along.y * along.y + along.z * along.z)
		if !(length > 0) {
			continue
		}
		middle := (from + to) / 2
		m := translate4(f32(middle.x), f32(middle.y), f32(middle.z)) * basis_along(along) * scale4(f32(width), f32(length), f32(width))
		scene_add_model(s, .Cylinder, m, colour)
		for point in ([2][3]f64{from, to}) {
			key := quantised({f32(point.x), f32(point.y), f32(point.z)})
			if !corner_done[key] {
				corner_done[key] = true
				scene_add(s, .Sphere, point, {width, width, width}, colour)
			}
		}
		added += 1
	}
	return added
}
