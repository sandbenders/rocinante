// SPDX-License-Identifier: 0BSD
//
// glTF 2.0 models, read in plain Odin with no library: a `.glb` file (a header, a JSON chunk and
// a binary chunk) or a `.gltf` file with its buffers beside it or inside it as data. What is read
// is what a still picture of a model needs: the meshes of the default scene, placed by the
// transforms of their nodes (a matrix, or a translation, rotation and scale), as triangles with
// their normals, and the plain color, metal, roughness and glow of each one's material. Textures,
// animations, skins, cameras and lights are left out, and so are compressed meshes (Draco,
// meshopt), which are said, not guessed at.
//
// The model's own world is glTF's: y up, in metres, the front facing +z. Every corner and normal is
// put into the sketch's world on the way in (y down), so a model is upright on the screen, and the
// parts keep one mesh between them, which the renderer uploads once. The size of the model is not
// kept, only its box, because a sketch says how big it should be drawn.
package gfx

import "core:encoding/base64"
import "core:encoding/json"
import "core:math"
import "core:strings"

// One material's worth of a model: a run of its indices and how it answers light.
Model_Part :: struct {
	first_index: u32,
	index_count: u32,
	colour:      [4]f32,
	metallic:    f32,
	roughness:   f32,
	emissive:    f32, // 0 to 1, from the brightest channel of the material's emissive color
	textures:    [Texture_Slot]Image_Id, // pictures the material is painted with (0: none); they multiply what the numbers above give
	normal_scale: f32, // how strongly the normal picture bends the surface
	alpha_cutoff: f32, // above 0, a pixel whose alpha is less than this is not drawn (a leaf, a fence)
	uv_set:       [Texture_Slot]u8, // which set of coordinates each picture is read with: 0 or 1
	uv_transform: [Texture_Slot][6]f32, // how each picture's coordinates are moved: a, b, tx, c, d, ty, so u' = a u + b v + tx and v' = c u + d v + ty
	dielectric:   f32, // how much a straight look at a surface that is not metal reflects: 0.04 unless the model says otherwise
	unlit:        bool, // drawn in its color alone, with no light or shade
}

// A part with nothing said about it: white, metal and rough as glTF has them when a material says nothing, pictures
// none, left where they are.
model_part_default :: proc() -> Model_Part {
	p := Model_Part{colour = {1, 1, 1, 1}, metallic = 1, roughness = 1, normal_scale = 1, dielectric = 0.04}
	for slot in Texture_Slot {
		p.uv_transform[slot] = {1, 0, 0, 0, 1, 0}
	}
	return p
}

// The pictures a material can have: the color, the way the surface faces (a normal map), metal and roughness
// (roughness in green, metal in blue, as glTF packs them) and the light the surface gives.
Texture_Slot :: enum {
	Colour,
	Normal,
	Metal_Rough,
	Emissive,
}

Model_Data :: struct {
	vertices: [dynamic]Vertex3,
	indices:  [dynamic]u32,
	parts:    [dynamic]Model_Part,
	low:      [3]f32, // the box that holds it, in the sketch's world
	high:     [3]f32,
	lost_textures: int, // how many pictures the file names that could not be read
	edges:    [dynamic][2][3]f32, // the lines of a wireframe, for a mesh a sketch made (mesh3.odin)
}

model_data_destroy :: proc(m: ^Model_Data) {
	for part in m.parts {
		for id in part.textures {
			if id != 0 {image_release(id)} // a picture two parts share is let go once; the second try names nothing
		}
	}
	delete(m.vertices)
	delete(m.indices)
	delete(m.parts)
	delete(m.edges)
	m^ = {}
}

// What went wrong reading a model, in words that go into a message.
Gltf_Error :: enum {
	None,
	Not_Gltf,        // not JSON, not a glb, or not glTF 2
	Version,         // a glTF of another major version
	Compressed,      // meshes packed with Draco or meshopt
	Missing_Buffer,  // a buffer that is not in the file and not beside it
	Bad_Data,        // a number that points outside its buffer, or a shape that does not fit
	No_Triangles,    // nothing in it to draw
	Not_Obj,         // not an OBJ model: no faces and no corners
}

gltf_error_words :: proc(e: Gltf_Error) -> string {
	switch e {
	case .None:           return ""
	case .Not_Gltf:       return "what is in it is not glTF 2"
	case .Version:        return "it is a glTF of a version I do not read, and I read version 2"
	case .Compressed:     return "its meshes are compressed with Draco or meshopt, which I do not read yet"
	case .Missing_Buffer: return "it needs a file of data that is not beside it"
	case .Bad_Data:       return "its data does not fit together, so the file is damaged"
	case .No_Triangles:   return "there are no triangles in it to draw"
	case .Not_Obj:        return "what is in it is not an OBJ model"
	}
	return ""
}

// Gives the bytes of a file the model names beside itself (`scene.bin`); false when there is none.
Gltf_Reader :: #type proc(uri: string) -> ([]byte, bool)

@(private = "file")
Reading :: struct {
	root:     json.Object,
	buffers:  [dynamic][]byte,
	model:    ^Model_Data,
	failed:   Gltf_Error,
	reader:   Gltf_Reader,
	have_box: bool,
	pictures: map[int]Image_Id, // the glTF images read so far, by their number (0: one that could not be read)
}

// Reads a model from the bytes of a `.glb` or a `.gltf` file. Everything it makes temporarily is
// in the temporary allocator; the model's own arrays are in `allocator`.
gltf_read :: proc(bytes: []byte, reader: Gltf_Reader = nil, allocator := context.allocator) -> (model: Model_Data, error: Gltf_Error) {
	json_bytes := bytes
	binary: []byte
	if len(bytes) >= 12 && string(bytes[0:4]) == "glTF" {
		// a glb: 12 bytes of header, then chunks of (length, type, data)
		if read_u32(bytes, 4) != 2 {
			return {}, .Version
		}
		at := 12
		json_bytes = nil
		for at + 8 <= len(bytes) {
			length := int(read_u32(bytes, at))
			kind := read_u32(bytes, at + 4)
			start := at + 8
			if length < 0 || start + length > len(bytes) {
				return {}, .Bad_Data
			}
			switch kind {
			case 0x4E4F534A: json_bytes = bytes[start:start + length]
			case 0x004E4942: if binary == nil {binary = bytes[start:start + length]}
			}
			at = start + ((length + 3) &~ 3)
		}
		if json_bytes == nil {
			return {}, .Not_Gltf
		}
	}
	value, parse_error := json.parse(json_bytes, .JSON, false, context.temp_allocator)
	if parse_error != .None {
		return {}, .Not_Gltf
	}
	root, is_object := value.(json.Object)
	if !is_object {
		return {}, .Not_Gltf
	}
	asset, has_asset := root["asset"].(json.Object)
	if !has_asset {
		return {}, .Not_Gltf
	}
	if version, ok := asset["version"].(json.String); ok {
		if !strings.has_prefix(string(version), "2") {
			return {}, .Version
		}
	} else {
		return {}, .Not_Gltf
	}
	for name in array_of(root, "extensionsRequired") {
		if text, ok := name.(json.String); ok && (text == "KHR_draco_mesh_compression" || text == "EXT_meshopt_compression" || text == "KHR_meshopt_compression") {
			return {}, .Compressed
		}
	}

	model.vertices = make([dynamic]Vertex3, allocator)
	model.indices = make([dynamic]u32, allocator)
	model.parts = make([dynamic]Model_Part, allocator)
	r := Reading{root = root, model = &model, reader = reader}
	r.pictures = make(map[int]Image_Id, context.temp_allocator)
	r.buffers = make([dynamic][]byte, context.temp_allocator)
	for entry, i in array_of(root, "buffers") {
		buffer, is_buffer := entry.(json.Object)
		if !is_buffer {
			return {}, .Bad_Data
		}
		uri, has_uri := buffer["uri"].(json.String)
		switch {
		case !has_uri:
			if i != 0 || binary == nil {
				model_data_destroy(&model)
				return {}, .Missing_Buffer
			}
			append(&r.buffers, binary)
		case strings.has_prefix(string(uri), "data:"):
			comma := strings.index_byte(string(uri), ',')
			if comma < 0 {
				model_data_destroy(&model)
				return {}, .Bad_Data
			}
			decoded, decode_error := base64.decode(string(uri)[comma + 1:], allocator = context.temp_allocator)
			if decode_error != nil {
				model_data_destroy(&model)
				return {}, .Bad_Data
			}
			append(&r.buffers, decoded)
		case:
			data: []byte
			found := false
			if reader != nil {
				data, found = reader(string(uri))
			}
			if !found {
				model_data_destroy(&model)
				return {}, .Missing_Buffer
			}
			append(&r.buffers, data)
		}
	}

	// the nodes of the default scene, or of the first scene, or every node nothing else holds
	nodes := array_of(root, "nodes")
	scene_nodes := make([dynamic]int, context.temp_allocator)
	scenes := array_of(root, "scenes")
	scene_index := int(number_of(root, "scene", 0))
	if scene_index >= 0 && scene_index < len(scenes) {
		if scene, ok := scenes[scene_index].(json.Object); ok {
			for n in array_of(scene, "nodes") {
				append(&scene_nodes, int(number_value(n)))
			}
		}
	} else if len(scenes) == 0 {
		held := make([]bool, len(nodes), context.temp_allocator)
		for node in nodes {
			if object, ok := node.(json.Object); ok {
				for child in array_of(object, "children") {
					if c := int(number_value(child)); c >= 0 && c < len(held) {
						held[c] = true
					}
				}
			}
		}
		for i in 0 ..< len(nodes) {
			if !held[i] {
				append(&scene_nodes, i)
			}
		}
	}
	for n in scene_nodes {
		visit_node(&r, n, identity4(), 0)
		if r.failed != .None {
			model_data_destroy(&model)
			return {}, r.failed
		}
	}
	if len(model.indices) == 0 {
		model_data_destroy(&model)
		return {}, .No_Triangles
	}
	return model, .None
}

@(private = "file")
read_u32 :: proc(bytes: []byte, at: int) -> u32 {
	if at < 0 || at + 4 > len(bytes) {
		return 0
	}
	return u32(bytes[at]) | u32(bytes[at + 1]) << 8 | u32(bytes[at + 2]) << 16 | u32(bytes[at + 3]) << 24
}

@(private = "file")
array_of :: proc(object: json.Object, key: string) -> json.Array {
	if array, ok := object[key].(json.Array); ok {
		return array
	}
	return nil
}

@(private = "file")
number_value :: proc(v: json.Value) -> f64 {
	#partial switch n in v {
	case json.Float:   return f64(n)
	case json.Integer: return f64(n)
	}
	return 0
}

@(private = "file")
number_of :: proc(object: json.Object, key: string, otherwise: f64) -> f64 {
	if v, ok := object[key]; ok {
		#partial switch n in v {
		case json.Float:   return f64(n)
		case json.Integer: return f64(n)
		}
	}
	return otherwise
}

@(private = "file")
numbers_of :: proc(object: json.Object, key: string, out: []f64) -> bool {
	array := array_of(object, key)
	if len(array) != len(out) {
		return false
	}
	for v, i in array {
		out[i] = number_value(v)
	}
	return true
}

// The transform a node gives its own things: its matrix, or translation, rotation and scale.
@(private = "file")
node_matrix :: proc(node: json.Object) -> matrix[4, 4]f32 {
	m: [16]f64
	if numbers_of(node, "matrix", m[:]) {
		out: matrix[4, 4]f32
		for column in 0 ..< 4 {
			for row in 0 ..< 4 {
				out[row, column] = f32(m[column * 4 + row])
			}
		}
		return out
	}
	t := [3]f64{0, 0, 0}
	s := [3]f64{1, 1, 1}
	q := [4]f64{0, 0, 0, 1}
	_ = numbers_of(node, "translation", t[:])
	_ = numbers_of(node, "scale", s[:])
	_ = numbers_of(node, "rotation", q[:])
	// a quaternion that is not unit length is made so; one of no length is no turn
	length := math.sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3])
	if length == 0 {
		q = {0, 0, 0, 1}
	} else {
		q /= length
	}
	x, y, z, w := q[0], q[1], q[2], q[3]
	rotation := matrix[4, 4]f32{
		f32(1 - 2 * (y * y + z * z)), f32(2 * (x * y - z * w)), f32(2 * (x * z + y * w)), 0,
		f32(2 * (x * y + z * w)), f32(1 - 2 * (x * x + z * z)), f32(2 * (y * z - x * w)), 0,
		f32(2 * (x * z - y * w)), f32(2 * (y * z + x * w)), f32(1 - 2 * (x * x + y * y)), 0,
		0, 0, 0, 1,
	}
	return translate4(f32(t.x), f32(t.y), f32(t.z)) * rotation * scale4(f32(s.x), f32(s.y), f32(s.z))
}

// Places the meshes of a node and of the nodes under it. A loop of nodes holding each other is
// cut at 64 deep, which no real model comes near.
@(private = "file")
visit_node :: proc(r: ^Reading, index: int, parent: matrix[4, 4]f32, depth: int) {
	nodes := array_of(r.root, "nodes")
	if index < 0 || index >= len(nodes) || depth > 64 {
		r.failed = .Bad_Data if index < 0 || index >= len(nodes) else r.failed
		return
	}
	node, ok := nodes[index].(json.Object)
	if !ok {
		r.failed = .Bad_Data
		return
	}
	world := parent * node_matrix(node)
	if mesh_index, has_mesh := node["mesh"]; has_mesh {
		add_mesh(r, int(number_value(mesh_index)), world)
		if r.failed != .None {
			return
		}
	}
	for child in array_of(node, "children") {
		visit_node(r, int(number_value(child)), world, depth + 1)
		if r.failed != .None {
			return
		}
	}
}

// What an accessor holds, as numbers: `components` to each of `count` elements.
@(private = "file")
Accessor :: struct {
	count:      int,
	components: int,
	kind:       int, // the glTF component type: 5120 to 5126
	normalized: bool,
	data:       []byte,
	stride:     int,
}

@(private = "file")
open_accessor :: proc(r: ^Reading, index: int) -> (a: Accessor, ok: bool) {
	accessors := array_of(r.root, "accessors")
	if index < 0 || index >= len(accessors) {
		return {}, false
	}
	object, is_object := accessors[index].(json.Object)
	if !is_object {
		return {}, false
	}
	a.count = int(number_of(object, "count", 0))
	a.kind = int(number_of(object, "componentType", 0))
	if normalized, has := object["normalized"].(json.Boolean); has {
		a.normalized = bool(normalized)
	}
	kind, _ := object["type"].(json.String)
	switch string(kind) {
	case "SCALAR": a.components = 1
	case "VEC2":   a.components = 2
	case "VEC3":   a.components = 3
	case "VEC4":   a.components = 4
	case:          return {}, false
	}
	size := 0
	switch a.kind {
	case 5120, 5121: size = 1
	case 5122, 5123: size = 2
	case 5125, 5126: size = 4
	case:            return {}, false
	}
	if a.count < 0 || a.count > 50_000_000 {
		return {}, false
	}
	view_index, has_view := object["bufferView"]
	if !has_view {
		// no data: all zeros, which a model with a sparse accessor alone would want, and which is not supported
		return {}, false
	}
	views := array_of(r.root, "bufferViews")
	vi := int(number_value(view_index))
	if vi < 0 || vi >= len(views) {
		return {}, false
	}
	view, is_view := views[vi].(json.Object)
	if !is_view {
		return {}, false
	}
	bi := int(number_of(view, "buffer", 0))
	if bi < 0 || bi >= len(r.buffers) {
		return {}, false
	}
	buffer := r.buffers[bi]
	start := int(number_of(view, "byteOffset", 0)) + int(number_of(object, "byteOffset", 0))
	length := int(number_of(view, "byteLength", f64(len(buffer))))
	a.stride = int(number_of(view, "byteStride", 0))
	if a.stride == 0 {
		a.stride = size * a.components
	}
	view_start := int(number_of(view, "byteOffset", 0))
	if start < 0 || a.stride < size * a.components || view_start + length > len(buffer) {
		return {}, false
	}
	if a.count > 0 {
		last := start + (a.count - 1) * a.stride + size * a.components
		if last > view_start + length || last > len(buffer) {
			return {}, false
		}
	}
	a.data = buffer[start:]
	return a, true
}

// One number of an accessor: the element, the component of it.
@(private = "file")
accessor_number :: proc(a: Accessor, element, component: int) -> f64 {
	size := 4
	switch a.kind {
	case 5120, 5121: size = 1
	case 5122, 5123: size = 2
	}
	at := element * a.stride + component * size
	switch a.kind {
	case 5120:
		v := f64(i8(a.data[at]))
		return max(v / 127, -1) if a.normalized else v
	case 5121:
		v := f64(a.data[at])
		return v / 255 if a.normalized else v
	case 5122:
		v := f64(i16(u16(a.data[at]) | u16(a.data[at + 1]) << 8))
		return max(v / 32767, -1) if a.normalized else v
	case 5123:
		v := f64(u16(a.data[at]) | u16(a.data[at + 1]) << 8)
		return v / 65535 if a.normalized else v
	case 5125:
		return f64(u32(a.data[at]) | u32(a.data[at + 1]) << 8 | u32(a.data[at + 2]) << 16 | u32(a.data[at + 3]) << 24)
	case 5126:
		bits := u32(a.data[at]) | u32(a.data[at + 1]) << 8 | u32(a.data[at + 2]) << 16 | u32(a.data[at + 3]) << 24
		return f64(transmute(f32)bits)
	}
	return 0
}

// A cofactor matrix of the upper three by three, which turns a normal as the surface turns even when it is stretched.
@(private = "file")
transform_normal :: proc(m: matrix[4, 4]f32, n: [3]f64) -> [3]f64 {
	a0 := [3]f64{f64(m[0, 0]), f64(m[0, 1]), f64(m[0, 2])}
	a1 := [3]f64{f64(m[1, 0]), f64(m[1, 1]), f64(m[1, 2])}
	a2 := [3]f64{f64(m[2, 0]), f64(m[2, 1]), f64(m[2, 2])}
	c0, c1, c2 := cross3(a1, a2), cross3(a2, a0), cross3(a0, a1)
	return normalize3({dot3(c0, n), dot3(c1, n), dot3(c2, n)})
}

@(private = "file")
add_mesh :: proc(r: ^Reading, index: int, world: matrix[4, 4]f32) {
	meshes := array_of(r.root, "meshes")
	if index < 0 || index >= len(meshes) {
		r.failed = .Bad_Data
		return
	}
	mesh, is_mesh := meshes[index].(json.Object)
	if !is_mesh {
		r.failed = .Bad_Data
		return
	}
	for entry in array_of(mesh, "primitives") {
		primitive, is_primitive := entry.(json.Object)
		if !is_primitive {
			r.failed = .Bad_Data
			return
		}
		if extensions, has := primitive["extensions"].(json.Object); has {
			if _, draco := extensions["KHR_draco_mesh_compression"]; draco {
				r.failed = .Compressed
				return
			}
		}
		mode := int(number_of(primitive, "mode", 4))
		if mode < 4 || mode > 6 {
			continue // points and lines are not triangles
		}
		attributes, has_attributes := primitive["attributes"].(json.Object)
		if !has_attributes {
			r.failed = .Bad_Data
			return
		}
		position_index, has_position := attributes["POSITION"]
		if !has_position {
			continue
		}
		positions, positions_ok := open_accessor(r, int(number_value(position_index)))
		if !positions_ok || positions.components != 3 {
			r.failed = .Bad_Data
			return
		}
		normals: Accessor
		has_normals := false
		if normal_index, has := attributes["NORMAL"]; has {
			normals, has_normals = open_accessor(r, int(number_value(normal_index)))
			if has_normals && (normals.components != 3 || normals.count != positions.count) {
				r.failed = .Bad_Data
				return
			}
		}
		uvs: Accessor
		has_uvs := false
		if uv_index, has := attributes["TEXCOORD_0"]; has {
			uvs, has_uvs = open_accessor(r, int(number_value(uv_index)))
			if has_uvs && (uvs.components != 2 || uvs.count != positions.count) {
				r.failed = .Bad_Data
				return
			}
		}
		uvs1: Accessor
		has_uvs1 := false
		if uv_index, has := attributes["TEXCOORD_1"]; has {
			uvs1, has_uvs1 = open_accessor(r, int(number_value(uv_index)))
			if has_uvs1 && (uvs1.components != 2 || uvs1.count != positions.count) {
				r.failed = .Bad_Data
				return
			}
		}
		colours: Accessor
		has_colours := false
		if colour_index, has := attributes["COLOR_0"]; has {
			colours, has_colours = open_accessor(r, int(number_value(colour_index)))
			if has_colours && ((colours.components != 3 && colours.components != 4) || colours.count != positions.count) {
				r.failed = .Bad_Data
				return
			}
		}
		colour_of :: proc(colours: Accessor, has: bool, at: u32) -> [4]u8 {
			if !has {
				return {255, 255, 255, 255}
			}
			out := [4]u8{255, 255, 255, 255}
			for k in 0 ..< colours.components {
				out[k] = u8(clamp(accessor_number(colours, int(at), k), 0, 1) * 255 + 0.5)
			}
			return out
		}
		uv_of :: proc(uvs: Accessor, has: bool, at: u32) -> [2]f32 {
			if !has {
				return {}
			}
			return {f32(accessor_number(uvs, int(at), 0)), f32(accessor_number(uvs, int(at), 1))}
		}
		// the corners of the triangles, as indices into the primitive's own vertices
		corners := make([dynamic]u32, context.temp_allocator)
		raw := make([dynamic]u32, context.temp_allocator)
		if indices_index, has := primitive["indices"]; has {
			indices, indices_ok := open_accessor(r, int(number_value(indices_index)))
			if !indices_ok || indices.components != 1 {
				r.failed = .Bad_Data
				return
			}
			for i in 0 ..< indices.count {
				v := accessor_number(indices, i, 0)
				if v < 0 || int(v) >= positions.count {
					r.failed = .Bad_Data
					return
				}
				append(&raw, u32(v))
			}
		} else {
			for i in 0 ..< positions.count {
				append(&raw, u32(i))
			}
		}
		switch mode {
		case 4:
			for i := 0; i + 2 < len(raw); i += 3 {
				append(&corners, raw[i], raw[i + 1], raw[i + 2])
			}
		case 5:
			for i := 0; i + 2 < len(raw); i += 1 {
				if i % 2 == 0 {
					append(&corners, raw[i], raw[i + 1], raw[i + 2])
				} else {
					append(&corners, raw[i + 1], raw[i], raw[i + 2])
				}
			}
		case 6:
			for i := 1; i + 1 < len(raw); i += 1 {
				append(&corners, raw[0], raw[i], raw[i + 1])
			}
		}
		if len(corners) == 0 {
			continue
		}
		place :: proc(r: ^Reading, world: matrix[4, 4]f32, positions: Accessor, at: u32) -> [3]f32 {
			p := [3]f64{accessor_number(positions, int(at), 0), accessor_number(positions, int(at), 1), accessor_number(positions, int(at), 2)}
			v := [4]f32{f32(p.x), f32(p.y), f32(p.z), 1}
			x := f64(world[0, 0] * v[0] + world[0, 1] * v[1] + world[0, 2] * v[2] + world[0, 3])
			y := f64(world[1, 0] * v[0] + world[1, 1] * v[1] + world[1, 2] * v[2] + world[1, 3])
			z := f64(world[2, 0] * v[0] + world[2, 1] * v[1] + world[2, 2] * v[2] + world[2, 3])
			out := [3]f32{f32(x), f32(-y), f32(z)} // into the sketch's world, where y is down
			if !r.have_box {
				r.model.low, r.model.high, r.have_box = out, out, true
			}
			for axis in 0 ..< 3 {
				r.model.low[axis] = min(r.model.low[axis], out[axis])
				r.model.high[axis] = max(r.model.high[axis], out[axis])
			}
			return out
		}
		first_index := u32(len(r.model.indices))
		if has_normals {
			// shared vertices, with the normals the file gives
			base := u32(len(r.model.vertices))
			for i in 0 ..< positions.count {
				n := [3]f64{accessor_number(normals, i, 0), accessor_number(normals, i, 1), accessor_number(normals, i, 2)}
				n = transform_normal(world, n)
				append(&r.model.vertices, Vertex3{place(r, world, positions, u32(i)), {f32(n.x), f32(-n.y), f32(n.z)}, 0, uv_of(uvs, has_uvs, u32(i)), uv_of(uvs1, has_uvs1, u32(i)), colour_of(colours, has_colours, u32(i))})
			}
			for c in corners {
				append(&r.model.indices, base + c)
			}
		} else {
			// no normals: each triangle is flat, so each has corners of its own
			for t := 0; t + 2 < len(corners); t += 3 {
				a := place(r, world, positions, corners[t])
				b := place(r, world, positions, corners[t + 1])
				c := place(r, world, positions, corners[t + 2])
				// the sketch's world is the glTF one mirrored in y, which turns every triangle over, so the normal is the other way
				n := -normalize3f(cross3f(b - a, c - a))
				base := u32(len(r.model.vertices))
				append(&r.model.vertices, Vertex3{a, n, 0, uv_of(uvs, has_uvs, corners[t]), uv_of(uvs1, has_uvs1, corners[t]), colour_of(colours, has_colours, corners[t])}, Vertex3{b, n, 0, uv_of(uvs, has_uvs, corners[t + 1]), uv_of(uvs1, has_uvs1, corners[t + 1]), colour_of(colours, has_colours, corners[t + 1])}, Vertex3{c, n, 0, uv_of(uvs, has_uvs, corners[t + 2]), uv_of(uvs1, has_uvs1, corners[t + 2]), colour_of(colours, has_colours, corners[t + 2])})
				append(&r.model.indices, base, base + 1, base + 2)
			}
		}
		part := model_part_default()
		part.first_index, part.index_count = first_index, u32(len(r.model.indices)) - first_index
		if material_index, has := primitive["material"]; has {
			read_material(r, int(number_value(material_index)), &part)
		}
		append(&r.model.parts, part)
	}
}

cross3f :: proc(a, b: [3]f32) -> [3]f32 {
	return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}
}

@(private = "file")
read_material :: proc(r: ^Reading, index: int, part: ^Model_Part) {
	materials := array_of(r.root, "materials")
	if index < 0 || index >= len(materials) {
		return
	}
	material, ok := materials[index].(json.Object)
	if !ok {
		return
	}
	if pbr, has := material["pbrMetallicRoughness"].(json.Object); has {
		colour: [4]f64
		if numbers_of(pbr, "baseColorFactor", colour[:]) {
			part.colour = {f32(clamp(colour[0], 0, 1)), f32(clamp(colour[1], 0, 1)), f32(clamp(colour[2], 0, 1)), f32(clamp(colour[3], 0, 1))}
		}
		part.metallic = f32(clamp(number_of(pbr, "metallicFactor", 1), 0, 1))
		part.roughness = f32(clamp(number_of(pbr, "roughnessFactor", 1), 0, 1))
		read_texture(r, part, .Colour, pbr, "baseColorTexture")
		read_texture(r, part, .Metal_Rough, pbr, "metallicRoughnessTexture")
	}
	emissive: [3]f64
	if numbers_of(material, "emissiveFactor", emissive[:]) {
		part.emissive = f32(clamp(max(emissive[0], emissive[1], emissive[2]), 0, 20))
	}
	read_texture(r, part, .Emissive, material, "emissiveTexture")
	read_texture(r, part, .Normal, material, "normalTexture")
	if info, has := material["normalTexture"].(json.Object); has {
		part.normal_scale = f32(clamp(number_of(info, "scale", 1), -4, 4))
	}
	// an alpha that cuts (a leaf, a fence) is a pixel there or not; one that blends is drawn solid, as the alpha of a color is
	if mode, has := material["alphaMode"].(json.String); has && string(mode) == "MASK" {
		part.alpha_cutoff = f32(clamp(number_of(material, "alphaCutoff", 0.5), 0.001, 1))
	}
	// the extensions that change what a still picture of the material is: how strongly it glows, whether it is lit at all, and
	// how much a surface that is not metal reflects (its index of refraction, and a factor on that); the rest (clearcoat,
	// transmission, sheen, volume, anisotropy) are left out
	if extensions, has_extensions := material["extensions"].(json.Object); has_extensions {
		if strength, has_strength := extensions["KHR_materials_emissive_strength"].(json.Object); has_strength {
			brightest := max(emissive[0], emissive[1], emissive[2])
			part.emissive = f32(clamp(brightest * number_of(strength, "emissiveStrength", 1), 0, 20))
		}
		if _, unlit := extensions["KHR_materials_unlit"]; unlit {
			part.unlit = true
		}
		if ior, has_ior := extensions["KHR_materials_ior"].(json.Object); has_ior {
			n := clamp(number_of(ior, "ior", 1.5), 1, 5)
			part.dielectric = f32(((n - 1) / (n + 1)) * ((n - 1) / (n + 1)))
		}
		if specular, has_specular := extensions["KHR_materials_specular"].(json.Object); has_specular {
			part.dielectric = part.dielectric * f32(clamp(number_of(specular, "specularFactor", 1), 0, 1))
		}
	}
}

// Reads the picture a material names under `key` (`{ "index": 2, "texCoord": 1 }`) into the slot of the part: the
// picture, which set of coordinates it is read with (0 or 1), and `KHR_texture_transform`, which moves the
// coordinates (its own `texCoord` wins). A set of coordinates past the second leaves the picture out.
@(private = "file")
read_texture :: proc(r: ^Reading, part: ^Model_Part, slot: Texture_Slot, holder: json.Object, key: string) {
	info, has := holder[key].(json.Object)
	if !has {
		return
	}
	set := int(number_of(info, "texCoord", 0))
	transform := [6]f32{1, 0, 0, 0, 1, 0}
	if extensions, has_extensions := info["extensions"].(json.Object); has_extensions {
		if moved, has_transform := extensions["KHR_texture_transform"].(json.Object); has_transform {
			offset, scale := [2]f64{0, 0}, [2]f64{1, 1}
			_ = numbers_of(moved, "offset", offset[:])
			_ = numbers_of(moved, "scale", scale[:])
			turn := number_of(moved, "rotation", 0)
			c, s := math.cos(turn), math.sin(turn)
			transform = {f32(c * scale.x), f32(s * scale.y), f32(offset.x), f32(-s * scale.x), f32(c * scale.y), f32(offset.y)}
			set = int(number_of(moved, "texCoord", f64(set)))
		}
	}
	if set < 0 || set > 1 {
		return
	}
	if id := texture_picture(r, info); id != 0 {
		part.textures[slot], part.uv_set[slot], part.uv_transform[slot] = id, u8(set), transform
	}
}

// The picture a texture entry (`{ "index": 2 }`) names, read once however many materials use it; 0 when it is not
// there or the file of the picture cannot be had, which is counted in `lost_textures`.
@(private = "file")
texture_picture :: proc(r: ^Reading, info: json.Object) -> Image_Id {	textures := array_of(r.root, "textures")
	ti := int(number_of(info, "index", -1))
	if ti < 0 || ti >= len(textures) {
		return 0
	}
	texture, is_texture := textures[ti].(json.Object)
	if !is_texture {
		return 0
	}
	si := int(number_of(texture, "source", -1))
	if si < 0 {
		return 0
	}
	if id, done := r.pictures[si]; done {
		return id
	}
	id: Image_Id
	defer r.pictures[si] = id
	images := array_of(r.root, "images")
	if si >= len(images) {
		return 0
	}
	image_object, is_image := images[si].(json.Object)
	if !is_image {
		return 0
	}
	bytes: []byte
	found := false
	if uri, has_uri := image_object["uri"].(json.String); has_uri {
		if strings.has_prefix(string(uri), "data:") {
			if comma := strings.index_byte(string(uri), ','); comma >= 0 {
				decoded, decode_error := base64.decode(string(uri)[comma + 1:], allocator = context.temp_allocator)
				bytes, found = decoded, decode_error == nil
			}
		} else if r.reader != nil {
			bytes, found = r.reader(percent_decoded(string(uri)))
		}
	} else if view, has_view := image_object["bufferView"]; has_view {
		bytes, found = view_bytes(r, int(number_value(view)))
	}
	if found {
		if picture, ok := image_add(bytes); ok {
			id = picture
		}
	}
	if id == 0 {
		r.model.lost_textures += 1
	}
	return id
}

// A uri's `%20` and the like, back into the characters they stand for.
percent_decoded :: proc(uri: string) -> string {
	if !strings.contains_rune(uri, '%') {
		return uri
	}
	out := make([dynamic]byte, context.temp_allocator)
	i := 0
	for i < len(uri) {
		if uri[i] == '%' && i + 2 < len(uri) {
			hi, lo := hex_value(uri[i + 1]), hex_value(uri[i + 2])
			if hi >= 0 && lo >= 0 {
				append(&out, byte(hi * 16 + lo))
				i += 3
				continue
			}
		}
		append(&out, uri[i])
		i += 1
	}
	return string(out[:])
}

@(private = "file")
hex_value :: proc(c: byte) -> int {
	switch c {
	case '0' ..= '9': return int(c - '0')
	case 'a' ..= 'f': return int(c - 'a') + 10
	case 'A' ..= 'F': return int(c - 'A') + 10
	}
	return -1
}

// The bytes of a buffer view: a picture kept inside the file's own data.
@(private = "file")
view_bytes :: proc(r: ^Reading, index: int) -> ([]byte, bool) {
	views := array_of(r.root, "bufferViews")
	if index < 0 || index >= len(views) {
		return nil, false
	}
	view, is_view := views[index].(json.Object)
	if !is_view {
		return nil, false
	}
	bi := int(number_of(view, "buffer", 0))
	if bi < 0 || bi >= len(r.buffers) {
		return nil, false
	}
	start, length := int(number_of(view, "byteOffset", 0)), int(number_of(view, "byteLength", 0))
	buffer := r.buffers[bi]
	if start < 0 || length <= 0 || start + length > len(buffer) {
		return nil, false
	}
	return buffer[start:start + length], true
}

// A model's box: its middle and its longest side, which is what `model` fits to a size.
model_extent :: proc(m: ^Model_Data) -> (centre: [3]f32, longest: f32) {
	centre = (m.low + m.high) / 2
	size := m.high - m.low
	return centre, max(size.x, size.y, size.z)
}
