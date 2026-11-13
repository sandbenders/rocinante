// SPDX-License-Identifier: 0BSD
package gfx

import "core:encoding/base64"
import "core:fmt"
import "core:math"
import "core:strings"
import "core:testing"

// The bytes of floats, little endian as glTF has them.
floats_as_bytes :: proc(values: []f32) -> []byte {
	out := make([]byte, len(values) * 4, context.temp_allocator)
	for v, i in values {
		bits := transmute(u32)v
		out[i * 4], out[i * 4 + 1], out[i * 4 + 2], out[i * 4 + 3] = u8(bits), u8(bits >> 8), u8(bits >> 16), u8(bits >> 24)
	}
	return out
}

shorts_as_bytes :: proc(values: []u16) -> []byte {
	out := make([]byte, len(values) * 2, context.temp_allocator)
	for v, i in values {
		out[i * 2], out[i * 2 + 1] = u8(v), u8(v >> 8)
	}
	return out
}

// A glb file from its JSON and its binary chunk.
make_glb :: proc(json_text: string, binary: []byte) -> []byte {
	pad :: proc(n: int) -> int {return (n + 3) &~ 3}
	json_length := pad(len(json_text))
	bin_length := pad(len(binary))
	total := 12 + 8 + json_length + (8 + bin_length if len(binary) > 0 else 0)
	out := make([]byte, total, context.temp_allocator)
	put :: proc(out: []byte, at: int, v: u32) {
		out[at], out[at + 1], out[at + 2], out[at + 3] = u8(v), u8(v >> 8), u8(v >> 16), u8(v >> 24)
	}
	copy(out[0:4], "glTF")
	put(out, 4, 2)
	put(out, 8, u32(total))
	put(out, 12, u32(json_length))
	put(out, 16, 0x4E4F534A)
	copy(out[20:], json_text)
	for i in len(json_text) ..< json_length {
		out[20 + i] = ' '
	}
	if len(binary) > 0 {
		at := 20 + json_length
		put(out, at, u32(bin_length))
		put(out, at + 4, 0x004E4942)
		copy(out[at + 8:], binary)
	}
	return out
}

// One triangle with no normals and no indices, at the origin: corners (0 0 0), (1 0 0), (0 1 0).
TRIANGLE_JSON :: `{
  "asset": {"version": "2.0"},
  "scene": 0,
  "scenes": [{"nodes": [0]}],
  "nodes": [{"mesh": 0@NODE@}],
  "meshes": [{"primitives": [{"attributes": {"POSITION": 0}@PRIMITIVE@}]}],
  "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"}],
  "bufferViews": [{"buffer": 0, "byteLength": 36}],
  "buffers": [{"byteLength": 36}]@ROOT@
}`

// A template with its @TOKENS@ replaced (fmt would take the braces of JSON for its own).
fill :: proc(template: string, pairs: [][2]string) -> string {
	text := template
	for pair in pairs {
		text, _ = strings.replace_all(text, pair[0], pair[1], context.temp_allocator)
	}
	return text
}

triangle_glb :: proc(node_extra, primitive_extra, root_extra: string) -> []byte {
	text := fill(TRIANGLE_JSON, {{"@NODE@", node_extra}, {"@PRIMITIVE@", primitive_extra}, {"@ROOT@", root_extra}})
	return make_glb(text, floats_as_bytes({0, 0, 0, 1, 0, 0, 0, 1, 0}))
}

@(test)
test_a_triangle_is_read_with_a_flat_normal_and_put_upright :: proc(t: ^testing.T) {
	m, e := gltf_read(triangle_glb("", "", ""))
	defer model_data_destroy(&m)
	if !testing.expect_value(t, e, Gltf_Error.None) {
		return
	}
	testing.expect_value(t, len(m.vertices), 3)
	testing.expect_value(t, len(m.indices), 3)
	testing.expect_value(t, len(m.parts), 1)
	// glTF's y is up and the sketch's is down: the corner at y = 1 is at -1
	testing.expect_value(t, m.vertices[2].position, [3]f32{0, -1, 0})
	// the face is turned towards +z, as the file's winding faces it
	testing.expect_value(t, m.vertices[0].normal, [3]f32{0, 0, 1})
	testing.expect_value(t, m.low, [3]f32{0, -1, 0})
	testing.expect_value(t, m.high, [3]f32{1, 0, 0})
	// a part with no material is white and, as glTF says, fully metal and rough
	testing.expect_value(t, m.parts[0].colour, [4]f32{1, 1, 1, 1})
	testing.expect_value(t, m.parts[0].metallic, 1)
	testing.expect_value(t, m.parts[0].roughness, 1)
	testing.expect_value(t, m.parts[0].index_count, 3)
	centre, longest := model_extent(&m)
	testing.expect_value(t, centre, [3]f32{0.5, -0.5, 0})
	testing.expect_value(t, longest, 1)
}

@(test)
test_a_node_moves_turns_and_scales_what_it_holds :: proc(t: ^testing.T) {
	m, e := gltf_read(triangle_glb(`, "translation": [1, 2, 3], "scale": [2, 2, 2]`, "", ""))
	defer model_data_destroy(&m)
	if !testing.expect_value(t, e, Gltf_Error.None) {
		return
	}
	// (1 0 0) scaled by 2 and moved by (1 2 3), then y flipped: (3 -2 3)
	testing.expect_value(t, m.vertices[1].position, [3]f32{3, -2, 3})
	// a quarter turn about z (the quaternion 0 0 sin45 cos45) takes x to y: (1 0 0) becomes (0 1 0), then y flips
	n, ne := gltf_read(triangle_glb(`, "rotation": [0, 0, 0.7071068, 0.7071068]`, "", ""))
	defer model_data_destroy(&n)
	testing.expect_value(t, ne, Gltf_Error.None)
	p := n.vertices[1].position
	testing.expect(t, abs(p.x) < 1e-5 && abs(p.y + 1) < 1e-5, "x became y, which the sketch has pointing down")
	// a rotation of no length is no turn
	z, ze := gltf_read(triangle_glb(`, "rotation": [0, 0, 0, 0]`, "", ""))
	defer model_data_destroy(&z)
	testing.expect_value(t, ze, Gltf_Error.None)
	testing.expect_value(t, z.vertices[1].position, [3]f32{1, 0, 0})
}

@(test)
test_a_matrix_node_is_read_by_columns :: proc(t: ^testing.T) {
	// the matrix that moves by (5 6 7): glTF lists the columns, so the move is the last four numbers
	m, e := gltf_read(triangle_glb(`, "matrix": [1,0,0,0, 0,1,0,0, 0,0,1,0, 5,6,7,1]`, "", ""))
	defer model_data_destroy(&m)
	testing.expect_value(t, e, Gltf_Error.None)
	testing.expect_value(t, m.vertices[0].position, [3]f32{5, -6, 7})
}

@(test)
test_nodes_hold_nodes :: proc(t: ^testing.T) {
	text := `{
  "asset": {"version": "2.0"},
  "scenes": [{"nodes": [0]}],
  "nodes": [{"translation": [10, 0, 0], "children": [1]}, {"mesh": 0, "translation": [0, 5, 0]}],
  "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
  "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"}],
  "bufferViews": [{"buffer": 0, "byteLength": 36}],
  "buffers": [{"byteLength": 36}]
}`
	m, e := gltf_read(make_glb(text, floats_as_bytes({0, 0, 0, 1, 0, 0, 0, 1, 0})))
	defer model_data_destroy(&m)
	testing.expect_value(t, e, Gltf_Error.None)
	testing.expect_value(t, m.vertices[0].position, [3]f32{10, -5, 0})
}

@(test)
test_indices_normals_and_a_stride_are_read :: proc(t: ^testing.T) {
	// two triangles of a square from four corners, positions and normals interleaved: 24 bytes to each corner
	vertices := floats_as_bytes({
		0, 0, 0, 0, 0, 1,
		1, 0, 0, 0, 0, 1,
		1, 1, 0, 0, 0, 1,
		0, 1, 0, 0, 0, 1,
	})
	indices := shorts_as_bytes({0, 1, 2, 0, 2, 3})
	binary := make([]byte, len(vertices) + len(indices), context.temp_allocator)
	copy(binary, vertices)
	copy(binary[len(vertices):], indices)
	text := fill(`{
  "asset": {"version": "2.0"},
  "scenes": [{"nodes": [0]}],
  "nodes": [{"mesh": 0}],
  "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1}, "indices": 2}]}],
  "accessors": [
    {"bufferView": 0, "componentType": 5126, "count": 4, "type": "VEC3"},
    {"bufferView": 0, "byteOffset": 12, "componentType": 5126, "count": 4, "type": "VEC3"},
    {"bufferView": 1, "componentType": 5123, "count": 6, "type": "SCALAR"}
  ],
  "bufferViews": [{"buffer": 0, "byteLength": @V@, "byteStride": 24}, {"buffer": 0, "byteOffset": @V@, "byteLength": 12}],
  "buffers": [{"byteLength": @B@}]
}`, {{"@V@", fmt.tprint(len(vertices))}, {"@B@", fmt.tprint(len(binary))}})
	m, e := gltf_read(make_glb(text, binary))
	defer model_data_destroy(&m)
	if !testing.expect_value(t, e, Gltf_Error.None) {
		return
	}
	testing.expect_value(t, len(m.vertices), 4) // shared, with the file's normals
	testing.expect_value(t, len(m.indices), 6)
	testing.expect_value(t, m.vertices[2].position, [3]f32{1, -1, 0})
	testing.expect_value(t, m.vertices[2].normal, [3]f32{0, 0, 1})
	testing.expect_value(t, m.indices[3], 0)
	testing.expect_value(t, m.indices[4], 2)
}

@(test)
test_a_material_gives_color_metal_rough_and_glow :: proc(t: ^testing.T) {
	m, e := gltf_read(triangle_glb("", `, "material": 0`, `, "materials": [{"pbrMetallicRoughness": {"baseColorFactor": [0.5, 0.25, 1, 0.5], "metallicFactor": 0.3, "roughnessFactor": 2}, "emissiveFactor": [0, 0.8, 0.1]}]`))
	defer model_data_destroy(&m)
	testing.expect_value(t, e, Gltf_Error.None)
	part := m.parts[0]
	testing.expect_value(t, part.colour, [4]f32{0.5, 0.25, 1, 0.5})
	testing.expect_value(t, part.metallic, 0.3)
	testing.expect_value(t, part.roughness, 1) // kept in range
	testing.expect_value(t, part.emissive, 0.8)
	// a material that is not there is the plain one
	n, ne := gltf_read(triangle_glb("", `, "material": 7`, `, "materials": []`))
	defer model_data_destroy(&n)
	testing.expect_value(t, ne, Gltf_Error.None)
	testing.expect_value(t, n.parts[0].colour, [4]f32{1, 1, 1, 1})
}

@(test)
test_a_gltf_file_can_hold_its_buffer_as_data_or_beside_it :: proc(t: ^testing.T) {
	bytes := floats_as_bytes({0, 0, 0, 1, 0, 0, 0, 1, 0})
	encoded, _ := base64.encode(bytes, allocator = context.temp_allocator)
	with_data := fill(`{
  "asset": {"version": "2.0"},
  "nodes": [{"mesh": 0}],
  "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
  "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"}],
  "bufferViews": [{"buffer": 0, "byteLength": 36}],
  "buffers": [{"byteLength": 36, "uri": "data:application/octet-stream;base64,@DATA@"}]
}`, {{"@DATA@", encoded}})
	m, e := gltf_read(transmute([]byte)with_data)
	defer model_data_destroy(&m)
	testing.expect_value(t, e, Gltf_Error.None) // no scenes: every node nothing else holds
	testing.expect_value(t, len(m.indices), 3)

	beside := `{
  "asset": {"version": "2.0"},
  "nodes": [{"mesh": 0}],
  "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
  "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"}],
  "bufferViews": [{"buffer": 0, "byteLength": 36}],
  "buffers": [{"byteLength": 36, "uri": "triangle.bin"}]
}`
	reader :: proc(uri: string) -> ([]byte, bool) {
		if uri == "triangle.bin" {
			return floats_as_bytes({0, 0, 0, 1, 0, 0, 0, 1, 0}), true
		}
		return nil, false
	}
	n, ne := gltf_read(transmute([]byte)beside, reader)
	defer model_data_destroy(&n)
	testing.expect_value(t, ne, Gltf_Error.None)
	testing.expect_value(t, len(n.indices), 3)
	// with no reader, or a file that is not there, the buffer is missing
	_, missing := gltf_read(transmute([]byte)beside)
	testing.expect_value(t, missing, Gltf_Error.Missing_Buffer)
	other, _ := strings.replace(beside, "triangle.bin", "other.bin", 1, context.temp_allocator)
	_, missing = gltf_read(transmute([]byte)other, reader)
	testing.expect_value(t, missing, Gltf_Error.Missing_Buffer)
}

@(test)
test_strips_fans_and_lines_are_turned_into_triangles_or_left_out :: proc(t: ^testing.T) {
	// five corners in a strip make three triangles, and in a fan three
	positions := floats_as_bytes({0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0, 0, 2, 0})
	text := proc(mode: int) -> string {
		return fill(`{
  "asset": {"version": "2.0"},
  "nodes": [{"mesh": 0}],
  "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "mode": @MODE@}]}],
  "accessors": [{"bufferView": 0, "componentType": 5126, "count": 5, "type": "VEC3"}],
  "bufferViews": [{"buffer": 0, "byteLength": 60}],
  "buffers": [{"byteLength": 60}]
}`, {{"@MODE@", fmt.tprint(mode)}})
	}
	strip, se := gltf_read(make_glb(text(5), positions))
	defer model_data_destroy(&strip)
	testing.expect_value(t, se, Gltf_Error.None)
	testing.expect_value(t, len(strip.indices), 9)
	fan, fe := gltf_read(make_glb(text(6), positions))
	defer model_data_destroy(&fan)
	testing.expect_value(t, fe, Gltf_Error.None)
	testing.expect_value(t, len(fan.indices), 9)
	// lines have no triangles
	_, le := gltf_read(make_glb(text(1), positions))
	testing.expect_value(t, le, Gltf_Error.No_Triangles)
}

@(test)
test_files_that_are_not_models_are_said_in_words :: proc(t: ^testing.T) {
	_, e := gltf_read(transmute([]byte)string("not json at all"))
	testing.expect_value(t, e, Gltf_Error.Not_Gltf)
	_, e = gltf_read(nil)
	testing.expect_value(t, e, Gltf_Error.Not_Gltf)
	_, e = gltf_read(transmute([]byte)string("[1, 2]"))
	testing.expect_value(t, e, Gltf_Error.Not_Gltf)
	_, e = gltf_read(transmute([]byte)string(`{"hello": 1}`))
	testing.expect_value(t, e, Gltf_Error.Not_Gltf)
	_, e = gltf_read(transmute([]byte)string(`{"asset": {"version": "1.0"}}`))
	testing.expect_value(t, e, Gltf_Error.Version)
	_, e = gltf_read(transmute([]byte)string(`{"asset": {"version": "2.0"}, "extensionsRequired": ["KHR_draco_mesh_compression"]}`))
	testing.expect_value(t, e, Gltf_Error.Compressed)
	_, e = gltf_read(transmute([]byte)string(`{"asset": {"version": "2.0"}}`))
	testing.expect_value(t, e, Gltf_Error.No_Triangles)
	// a glb of another version, one cut short, one with no JSON
	glb := make_glb("{}", nil)
	glb[4] = 1
	_, e = gltf_read(glb)
	testing.expect_value(t, e, Gltf_Error.Version)
	short := make_glb(`{"asset": {"version": "2.0"}}`, nil)
	_, e = gltf_read(short[:len(short) - 6])
	testing.expect_value(t, e, Gltf_Error.Bad_Data)
	for error in Gltf_Error {
		if error != .None {
			testing.expect(t, len(gltf_error_words(error)) > 10, "every error has words")
		}
	}
	testing.expect_value(t, gltf_error_words(.None), "")
}

@(test)
test_a_model_that_points_outside_its_data_is_damaged :: proc(t: ^testing.T) {
	// an accessor that reads past its buffer view
	text := fill(TRIANGLE_JSON, {{"@NODE@", ""}, {"@PRIMITIVE@", ""}, {"@ROOT@", ""}})
	too_many, _ := strings.replace(text, `"count": 3`, `"count": 300`, 1, context.temp_allocator)
	_, e := gltf_read(make_glb(too_many, floats_as_bytes({0, 0, 0, 1, 0, 0, 0, 1, 0})))
	testing.expect_value(t, e, Gltf_Error.Bad_Data)
	// a node that is not there, a mesh that is not there
	_, e = gltf_read(make_glb(`{"asset": {"version": "2.0"}, "scenes": [{"nodes": [4]}]}`, nil))
	testing.expect_value(t, e, Gltf_Error.Bad_Data)
	_, e = gltf_read(make_glb(`{"asset": {"version": "2.0"}, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 3}]}`, nil))
	testing.expect_value(t, e, Gltf_Error.Bad_Data)
	// nodes that hold themselves are cut, not followed for ever
	_, e = gltf_read(make_glb(`{"asset": {"version": "2.0"}, "scenes": [{"nodes": [0]}], "nodes": [{"children": [0]}]}`, nil))
	testing.expect(t, e == .No_Triangles || e == .Bad_Data, "a loop ends")
	// an index that names a corner that is not there
	indexed := `{
  "asset": {"version": "2.0"},
  "nodes": [{"mesh": 0}],
  "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1}]}],
  "accessors": [
    {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"},
    {"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"}
  ],
  "bufferViews": [{"buffer": 0, "byteLength": 36}, {"buffer": 0, "byteOffset": 36, "byteLength": 6}],
  "buffers": [{"byteLength": 42}]
}`
	binary := make([]byte, 42, context.temp_allocator)
	copy(binary, floats_as_bytes({0, 0, 0, 1, 0, 0, 0, 1, 0}))
	copy(binary[36:], shorts_as_bytes({0, 1, 9}))
	_, e = gltf_read(make_glb(indexed, binary))
	testing.expect_value(t, e, Gltf_Error.Bad_Data)
	_ = math.PI
}

@(test)
test_models_are_kept_by_path_and_replaced_when_the_file_changes :: proc(t: ^testing.T) {
	defer models_stop()
	a, _ := gltf_read(triangle_glb("", "", ""))
	id := model_add("a.glb", 100, a)
	testing.expect(t, id != 0, "a number")
	testing.expect_value(t, model_version(id), 1)
	found, ok := model_find("a.glb", 100)
	testing.expect(t, ok && found == id, "found by path and stamp")
	_, ok = model_find("a.glb", 101)
	testing.expect(t, !ok, "not by another stamp")
	// the same path again, as the edited file: the same number and a new version
	b, _ := gltf_read(triangle_glb(`, "scale": [3, 3, 3]`, "", ""))
	again := model_add("a.glb", 200, b)
	testing.expect_value(t, again, id)
	testing.expect_value(t, model_version(id), 2)
	testing.expect_value(t, model_data(id).vertices[1].position.x, 3)
	other, _ := gltf_read(triangle_glb("", "", ""))
	testing.expect(t, model_add("b.glb", 1, other) != id, "another path is another model")
	// numbers that name nothing
	testing.expect(t, model_data(0) == nil && model_data(99) == nil, "no data")
	testing.expect_value(t, model_version(0), 0)
	testing.expect_value(t, model_version(99), 0)
	epoch := model_epoch()
	models_stop()
	testing.expect(t, model_epoch() != epoch, "letting go changes the epoch")
	testing.expect(t, model_data(id) == nil, "and the numbers mean nothing")
}

@(test)
test_a_loaded_model_is_fitted_to_a_size_and_a_place_as_items_of_a_scene :: proc(t: ^testing.T) {
	defer models_stop()
	data, _ := gltf_read(triangle_glb("", "", ""))
	id := model_add("t.glb", 1, data)
	s: Scene3
	defer scene_destroy(&s)
	testing.expect_value(t, scene_add_loaded_model(&s, id, {10, 20, 30}, 200), 1)
	item := s.items[0]
	testing.expect_value(t, item.shape, Shape3.Model)
	testing.expect_value(t, item.model_id, id)
	// the triangle's box is 1 by 1, so it grows 200 times; its middle (0.5, -0.5) goes to the place
	testing.expect_value(t, item.model[0][0], 200)
	testing.expect(t, close(item.model[0][3], 10 - 0.5 * 200, 1e-3) || close(item.model[0][3], 10 - 100, 1e-3), "moved so its middle is at the place")
	// a number that is no model adds nothing, nor does a size that is not a number
	testing.expect_value(t, scene_add_loaded_model(&s, 99, {}, 100), 0)
	testing.expect_value(t, scene_add_loaded_model(&s, id, {}, math.nan_f64()), 0)
	testing.expect_value(t, len(s.items), 1)
	// `no lights` makes it flat
	scene_no_lights(&s)
	scene_add_loaded_model(&s, id, {}, 10)
	testing.expect_value(t, s.items[1].material[2], 1)
	// the box that holds the scene holds the model
	centre, radius := scene_bounds(&s)
	testing.expect(t, radius >= 100, "the bounds hold a model 200 wide")
	_ = centre
}
