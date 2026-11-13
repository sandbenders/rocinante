// SPDX-License-Identifier: 0BSD
//
// Makes the model that `examples/model` draws, `ship.glb`: a small ship put together from two
// shapes (a box and a cone) placed by the nodes of a glTF file, each with a material of its own,
// so the example has a model to show without one being downloaded from anywhere, and a file that
// checks the loader's nodes, transforms and materials. It writes the glb by hand, the way the
// loader reads it:
//
//     odin run tools/model -- examples/model/assets/3d-models/ship.glb
package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"

Mesh :: struct {
	positions: [dynamic][3]f32,
	normals:   [dynamic][3]f32,
	indices:   [dynamic]u16,
}

// A box of side 1 about its middle.
box_mesh :: proc() -> Mesh {
	m: Mesh
	faces := [6][3]f32{{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}}
	for n in faces {
		a := [3]f32{n.y, n.z, n.x}
		b := [3]f32{n.z, n.x, n.y}
		base := u16(len(m.positions))
		for corner in ([4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}) {
			append(&m.positions, n * 0.5 + a * (corner.x * 0.5) + b * (corner.y * 0.5))
			append(&m.normals, n)
		}
		// wound so the face looks outward
		append(&m.indices, base, base + 1, base + 2, base, base + 2, base + 3)
		if (n.x + n.y + n.z) < 0 {
			m.indices[len(m.indices) - 5], m.indices[len(m.indices) - 4] = m.indices[len(m.indices) - 4], m.indices[len(m.indices) - 5]
			m.indices[len(m.indices) - 2], m.indices[len(m.indices) - 1] = m.indices[len(m.indices) - 1], m.indices[len(m.indices) - 2]
		}
	}
	return m
}

// A cone along x: its base at x = -0.5, radius 0.5, its tip at x = 0.5.
cone_mesh :: proc() -> Mesh {
	m: Mesh
	segments := 20
	for i in 0 ..< segments {
		a0 := f64(i) / f64(segments) * math.TAU
		a1 := f64(i + 1) / f64(segments) * math.TAU
		p0 := [3]f32{-0.5, f32(math.cos(a0)) * 0.5, f32(math.sin(a0)) * 0.5}
		p1 := [3]f32{-0.5, f32(math.cos(a1)) * 0.5, f32(math.sin(a1)) * 0.5}
		tip := [3]f32{0.5, 0, 0}
		base := u16(len(m.positions))
		// the side leans out and forward
		for p in ([3]([3]f32){p0, p1, tip}) {
			ring := [3]f32{0, p.y, p.z}
			if p == tip {
				ring = {0, f32(math.cos((a0 + a1) / 2)), f32(math.sin((a0 + a1) / 2))}
			}
			length := math.sqrt(f64(ring.y * ring.y + ring.z * ring.z))
			n := [3]f32{0.5, f32(f64(ring.y) / max(length, 1e-6)), f32(f64(ring.z) / max(length, 1e-6))}
			l := math.sqrt(f64(n.x * n.x + n.y * n.y + n.z * n.z))
			append(&m.positions, p)
			append(&m.normals, n / f32(l))
		}
		append(&m.indices, base, base + 2, base + 1)
		// the base, a fan of triangles facing back
		centre := u16(len(m.positions))
		append(&m.positions, [3]f32{-0.5, 0, 0}, p0, p1)
		append(&m.normals, [3]f32{-1, 0, 0}, [3]f32{-1, 0, 0}, [3]f32{-1, 0, 0})
		append(&m.indices, centre, centre + 1, centre + 2)
	}
	return m
}

// A shape of the model: a mesh by number, the material it wears, and where it sits.
Piece :: struct {
	mesh:        int,
	material:    int,
	translation: [3]f32,
	scale:       [3]f32,
	rotation:    [4]f32, // a quaternion
}

Material :: struct {
	colour:    [4]f32,
	metallic:  f32,
	roughness: f32,
	emissive:  [3]f32,
}

main :: proc() {
	if len(os.args) < 2 {
		fmt.eprintln("usage: odin run tools/model -- ship.glb")
		os.exit(2)
	}
	meshes := [2]Mesh{box_mesh(), cone_mesh()}
	materials := [4]Material{
		{{0.62, 0.68, 0.78, 1}, 0.7, 0.35, {0, 0, 0}},   // the hull
		{{0.95, 0.5, 0.15, 1}, 0.2, 0.55, {0, 0, 0}},    // the wings and the fins
		{{0.3, 0.85, 1, 1}, 0.0, 0.1, {0.1, 0.5, 0.7}},  // the glass, glowing a little
		{{0.15, 0.15, 0.18, 1}, 0.9, 0.3, {1, 0.45, 0.1}}, // the engines, hot
	}
	q := f32(0.38268343) // sin of 22.5 degrees: the quaternion of a turn of 45 degrees has it and 0.9239 (the cos)
	pieces := []Piece{
		{0, 0, {0, 0, 0}, {1.6, 0.28, 0.34}, {0, 0, 0, 1}},          // the body
		{1, 0, {1.15, 0, 0}, {0.7, 0.34, 0.34}, {0, 0, 0, 1}},       // the nose
		{0, 1, {-0.1, 0, 0.55}, {0.5, 0.05, 0.7}, {0, q, 0, 0.9239}}, // the right wing (turned 45 degrees about y)
		{0, 1, {-0.1, 0, -0.55}, {0.5, 0.05, 0.7}, {0, -q, 0, 0.9239}}, // the left wing
		{0, 1, {-0.62, 0.24, 0}, {0.35, 0.4, 0.04}, {0, 0, 0, 1}},   // the fin on top
		{1, 2, {0.45, 0.2, 0}, {0.5, 0.2, 0.26}, {0, 0, 0, 1}},      // the glass
		{1, 3, {-0.95, 0.07, 0.17}, {0.3, 0.14, 0.14}, {0, 0, 1, 0}}, // an engine, turned to face back
		{1, 3, {-0.95, 0.07, -0.17}, {0.3, 0.14, 0.14}, {0, 0, 1, 0}}, // the other
	}

	// the binary chunk: for each mesh its positions, normals and indices
	binary: [dynamic]u8
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)
	write :: proc(b: ^strings.Builder, args: ..any) {
		fmt.sbprint(b, ..args, sep = "")
	}
	views, accessors: [dynamic]string
	for mesh, i in meshes {
		low, high := mesh.positions[0], mesh.positions[0]
		for p in mesh.positions {
			for axis in 0 ..< 3 {
				low[axis], high[axis] = min(low[axis], p[axis]), max(high[axis], p[axis])
			}
		}
		for stream in 0 ..< 3 {
			start := len(binary)
			switch stream {
			case 0: for p in mesh.positions {for c in p {append_f32(&binary, c)}}
			case 1: for n in mesh.normals {for c in n {append_f32(&binary, c)}}
			case 2: for index in mesh.indices {append(&binary, u8(index), u8(index >> 8))}
			}
			for len(binary) % 4 != 0 {append(&binary, 0)}
			append(&views, fmt.aprintf(`{{"buffer": 0, "byteOffset": %d, "byteLength": %d}}`, start, len(binary) - start))
			switch stream {
			case 0: append(&accessors, fmt.aprintf(`{{"bufferView": %d, "componentType": 5126, "count": %d, "type": "VEC3", "min": [%v, %v, %v], "max": [%v, %v, %v]}}`, i * 3, len(mesh.positions), low.x, low.y, low.z, high.x, high.y, high.z))
			case 1: append(&accessors, fmt.aprintf(`{{"bufferView": %d, "componentType": 5126, "count": %d, "type": "VEC3"}}`, i * 3 + 1, len(mesh.normals)))
			case 2: append(&accessors, fmt.aprintf(`{{"bufferView": %d, "componentType": 5123, "count": %d, "type": "SCALAR"}}`, i * 3 + 2, len(mesh.indices)))
			}
		}
	}
	// one mesh for each (shape, material) pair the pieces use, one node for each piece
	mesh_json, node_json, material_json: [dynamic]string
	for m in materials {
		append(&material_json, fmt.aprintf(`{{"pbrMetallicRoughness": {{"baseColorFactor": [%v, %v, %v, %v], "metallicFactor": %v, "roughnessFactor": %v}}, "emissiveFactor": [%v, %v, %v]}}`, m.colour.r, m.colour.g, m.colour.b, m.colour.a, m.metallic, m.roughness, m.emissive.r, m.emissive.g, m.emissive.b))
	}
	children: [dynamic]string
	for piece, i in pieces {
		append(&mesh_json, fmt.aprintf(`{{"primitives": [{{"attributes": {{"POSITION": %d, "NORMAL": %d}}, "indices": %d, "material": %d}}]}}`, piece.mesh * 3, piece.mesh * 3 + 1, piece.mesh * 3 + 2, piece.material))
		append(&node_json, fmt.aprintf(`{{"mesh": %d, "translation": [%v, %v, %v], "rotation": [%v, %v, %v, %v], "scale": [%v, %v, %v]}}`, i, piece.translation.x, piece.translation.y, piece.translation.z, piece.rotation.x, piece.rotation.y, piece.rotation.z, piece.rotation.w, piece.scale.x, piece.scale.y, piece.scale.z))
		append(&children, fmt.aprint(i))
	}
	// a root node that holds them all and tips the whole ship a little, to be sure the nodes nest
	root := fmt.aprintf(`{{"children": [%s], "rotation": [0, 0, 0, 1]}}`, strings.join(children[:], ", "))
	append(&node_json, root)
	text := fmt.aprintf(`{{"asset": {{"version": "2.0", "generator": "rocinante tools/model"}}, "scene": 0, "scenes": [{{"nodes": [%d]}}], "nodes": [%s], "meshes": [%s], "materials": [%s], "accessors": [%s], "bufferViews": [%s], "buffers": [{{"byteLength": %d}}]}}`,
		len(pieces), strings.join(node_json[:], ", "), strings.join(mesh_json[:], ", "), strings.join(material_json[:], ", "), strings.join(accessors[:], ", "), strings.join(views[:], ", "), len(binary))

	pad4 :: proc(n: int) -> int {return (n + 3) &~ 3}
	json_length, bin_length := pad4(len(text)), pad4(len(binary))
	total := 12 + 8 + json_length + 8 + bin_length
	out := make([dynamic]u8)
	append_u32 :: proc(out: ^[dynamic]u8, v: u32) {
		append(out, u8(v), u8(v >> 8), u8(v >> 16), u8(v >> 24))
	}
	append(&out, "glTF")
	append_u32(&out, 2)
	append_u32(&out, u32(total))
	append_u32(&out, u32(json_length))
	append_u32(&out, 0x4E4F534A)
	append(&out, text)
	for len(out) < 20 + json_length {append(&out, ' ')}
	append_u32(&out, u32(bin_length))
	append_u32(&out, 0x004E4942)
	append(&out, ..binary[:])
	for len(out) < total {append(&out, 0)}
	if err := os.write_entire_file(os.args[1], out[:]); err != nil {
		fmt.eprintfln("cannot write %s", os.args[1])
		os.exit(1)
	}
	fmt.printfln("wrote %s: %d bytes, %d pieces", os.args[1], total, len(pieces))
}

append_f32 :: proc(out: ^[dynamic]u8, v: f32) {
	bits := transmute(u32)v
	append(out, u8(bits), u8(bits >> 8), u8(bits >> 16), u8(bits >> 24))
}
