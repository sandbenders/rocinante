// SPDX-License-Identifier: 0BSD
package gfx

import "core:encoding/base64"
import "core:math"
import "core:strings"
import "core:testing"

// A PNG of 2 by 2 pixels, each one the given color, as a model's picture.
test_png :: proc(colours: [4][4]u8) -> []byte {
	pixels := make([]u8, 16, context.temp_allocator)
	for c, i in colours {
		c := c
		copy(pixels[i * 4:], c[:])
	}
	png, ok := png_encode({width = 2, height = 2, pixels = pixels}, context.temp_allocator)
	if !ok {
		return nil
	}
	return png
}

PLAIN_PNG :: [4][4]u8{{255, 0, 0, 255}, {0, 255, 0, 255}, {0, 0, 255, 255}, {255, 255, 255, 255}}

// A glb of one triangle with texture coordinates, whose material is the JSON given and which names the
// pictures in `images` (the JSON of the images array).
textured_glb :: proc(material, textures, images: string, extra_primitive := "") -> []byte {
	text := fill(`{
  "asset": {"version": "2.0"},
  "scene": 0,
  "scenes": [{"nodes": [0]}],
  "nodes": [{"mesh": 0}],
  "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "TEXCOORD_0": 1}, "material": 0@EXTRA@}]}],
  "materials": [@MATERIAL@],
  "textures": [@TEXTURES@],
  "images": [@IMAGES@],
  "accessors": [
    {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"},
    {"bufferView": 1, "componentType": 5126, "count": 3, "type": "VEC2"}
  ],
  "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": 36}, {"buffer": 0, "byteOffset": 36, "byteLength": 24}],
  "buffers": [{"byteLength": 60}]
}`, {{"@MATERIAL@", material}, {"@TEXTURES@", textures}, {"@IMAGES@", images}, {"@EXTRA@", extra_primitive}})
	return make_glb(text, floats_as_bytes({0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1}))
}

data_uri :: proc(bytes: []byte) -> string {
	encoded, _ := base64.encode(bytes, allocator = context.temp_allocator)
	return strings.concatenate({"data:image/png;base64,", encoded}, context.temp_allocator)
}

@(test)
test_a_material_names_pictures_that_are_read_and_kept_with_the_corners_coordinates :: proc(t: ^testing.T) {
	defer images_stop()
	uri := data_uri(test_png(PLAIN_PNG))
	images := strings.concatenate({`{"uri": "`, uri, `"}`}, context.temp_allocator)
	material := `{"pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicRoughnessTexture": {"index": 1}}, "normalTexture": {"index": 2, "scale": 0.5}, "emissiveTexture": {"index": 3}}`
	m, e := gltf_read(textured_glb(material, `{"source": 0}, {"source": 0}, {"source": 0}, {"source": 0}`, images))
	defer model_data_destroy(&m)
	testing.expect_value(t, e, Gltf_Error.None)
	part := m.parts[0]
	for slot in Texture_Slot {
		testing.expectf(t, part.textures[slot] != 0, "the %v picture is there", slot)
		width, height := image_size(part.textures[slot])
		testing.expect_value(t, width, 2)
		testing.expect_value(t, height, 2)
	}
	// one image used four ways is read once
	testing.expect_value(t, part.textures[.Colour], part.textures[.Normal])
	testing.expect_value(t, part.normal_scale, 0.5)
	testing.expect_value(t, m.lost_textures, 0)
	// the coordinates stay as the file gives them: a glTF picture starts at the top left, as ours do
	testing.expect_value(t, m.vertices[0].uv, [2]f32{0, 0})
	testing.expect_value(t, m.vertices[1].uv, [2]f32{1, 0})
	testing.expect_value(t, m.vertices[2].uv, [2]f32{0, 1})
}

@(test)
test_letting_a_model_go_lets_go_of_its_pictures :: proc(t: ^testing.T) {
	defer images_stop()
	images := strings.concatenate({`{"uri": "`, data_uri(test_png(PLAIN_PNG)), `"}`}, context.temp_allocator)
	m, e := gltf_read(textured_glb(`{"pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}}`, `{"source": 0}`, images))
	testing.expect_value(t, e, Gltf_Error.None)
	id := m.parts[0].textures[.Colour]
	testing.expect(t, image_data(id) != nil, "the picture is kept")
	model_data_destroy(&m)
	testing.expect(t, image_data(id) == nil, "and let go with the model")
}

@(test)
test_a_picture_can_be_in_the_files_own_data_or_beside_it :: proc(t: ^testing.T) {
	defer images_stop()
	png := test_png(PLAIN_PNG)
	// inside the binary chunk, after the triangle's numbers: a view of its own
	binary := make([]byte, 60 + len(png), context.temp_allocator)
	copy(binary, floats_as_bytes({0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1}))
	copy(binary[60:], png)
	text := fill(`{
  "asset": {"version": "2.0"},
  "nodes": [{"mesh": 0}],
  "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "TEXCOORD_0": 1}, "material": 0}]}],
  "materials": [{"pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}}],
  "textures": [{"source": 0}],
  "images": [{"bufferView": 2, "mimeType": "image/png"}],
  "accessors": [
    {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"},
    {"bufferView": 1, "componentType": 5126, "count": 3, "type": "VEC2"}
  ],
  "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": 36}, {"buffer": 0, "byteOffset": 36, "byteLength": 24}, {"buffer": 0, "byteOffset": 60, "byteLength": @LENGTH@}],
  "buffers": [{"byteLength": @TOTAL@}]
}`, {{"@LENGTH@", itoa(len(png))}, {"@TOTAL@", itoa(len(binary))}})
	m, e := gltf_read(make_glb(text, binary))
	defer model_data_destroy(&m)
	testing.expect_value(t, e, Gltf_Error.None)
	testing.expect(t, m.parts[0].textures[.Colour] != 0, "read from a buffer view")

	// a file beside the model, with a name that has a percent sign in it
	beside, _ := strings.replace(text, `{"bufferView": 2, "mimeType": "image/png"}`, `{"uri": "my%20picture.png"}`, 1, context.temp_allocator)
	reader :: proc(uri: string) -> ([]byte, bool) {
		if uri == "my picture.png" {
			return test_png(PLAIN_PNG), true
		}
		return nil, false
	}
	n, ne := gltf_read(make_glb(beside, binary), reader)
	defer model_data_destroy(&n)
	testing.expect_value(t, ne, Gltf_Error.None)
	testing.expect(t, n.parts[0].textures[.Colour] != 0, "read from a file beside the model")
	testing.expect_value(t, n.lost_textures, 0)
	// without the reader the picture is lost, and said so, and the model is still a model
	o, oe := gltf_read(make_glb(beside, binary))
	defer model_data_destroy(&o)
	testing.expect_value(t, oe, Gltf_Error.None)
	testing.expect_value(t, o.parts[0].textures[.Colour], Image_Id(0))
	testing.expect_value(t, o.lost_textures, 1)
}

@(test)
test_a_picture_that_is_not_one_or_a_second_set_of_coordinates_is_left_out :: proc(t: ^testing.T) {
	defer images_stop()
	garbage := `{"uri": "data:image/png;base64,AAAA"}`
	m, e := gltf_read(textured_glb(`{"pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}}`, `{"source": 0}`, garbage))
	defer model_data_destroy(&m)
	testing.expect_value(t, e, Gltf_Error.None)
	testing.expect_value(t, m.parts[0].textures[.Colour], Image_Id(0))
	testing.expect_value(t, m.lost_textures, 1)
	// texCoord 2 is not read, and is not a lost picture either
	images := strings.concatenate({`{"uri": "`, data_uri(test_png(PLAIN_PNG)), `"}`}, context.temp_allocator)
	n, ne := gltf_read(textured_glb(`{"pbrMetallicRoughness": {"baseColorTexture": {"index": 0, "texCoord": 2}}}`, `{"source": 0}`, images))
	defer model_data_destroy(&n)
	testing.expect_value(t, ne, Gltf_Error.None)
	testing.expect_value(t, n.parts[0].textures[.Colour], Image_Id(0))
	testing.expect_value(t, n.lost_textures, 0)
	// a texture or an image that is not in the file
	o, oe := gltf_read(textured_glb(`{"pbrMetallicRoughness": {"baseColorTexture": {"index": 5}}, "normalTexture": {"index": 0}}`, `{"source": 9}`, images))
	defer model_data_destroy(&o)
	testing.expect_value(t, oe, Gltf_Error.None)
	testing.expect_value(t, o.parts[0].textures[.Colour], Image_Id(0))
	testing.expect_value(t, o.parts[0].textures[.Normal], Image_Id(0))
}

@(test)
test_an_alpha_that_cuts_is_a_cutoff_and_one_that_blends_is_not :: proc(t: ^testing.T) {
	m, _ := gltf_read(textured_glb(`{"alphaMode": "MASK", "alphaCutoff": 0.3}`, "", ""))
	defer model_data_destroy(&m)
	testing.expect_value(t, m.parts[0].alpha_cutoff, 0.3)
	n, _ := gltf_read(textured_glb(`{"alphaMode": "MASK"}`, "", ""))
	defer model_data_destroy(&n)
	testing.expect_value(t, n.parts[0].alpha_cutoff, 0.5) // glTF's default
	o, _ := gltf_read(textured_glb(`{"alphaMode": "BLEND"}`, "", ""))
	defer model_data_destroy(&o)
	testing.expect_value(t, o.parts[0].alpha_cutoff, 0)
}

@(test)
test_a_percent_sign_in_a_name_is_decoded :: proc(t: ^testing.T) {
	testing.expect_value(t, percent_decoded("a b.png"), "a b.png")
	testing.expect_value(t, percent_decoded("a%20b.png"), "a b.png")
	testing.expect_value(t, percent_decoded("100%.png"), "100%.png") // not two hex digits
	testing.expect_value(t, percent_decoded("%e4%7A"), "\xe4z")
	testing.expect_value(t, percent_decoded("end%2"), "end%2")
}

@(test)
test_how_many_sizes_a_picture_has :: proc(t: ^testing.T) {
	testing.expect_value(t, mip_levels(1, 1), 1)
	testing.expect_value(t, mip_levels(2, 2), 2)
	testing.expect_value(t, mip_levels(1024, 256), 11)
	testing.expect_value(t, mip_levels(5, 3), 3)
}

// ---- OBJ ----

obj_files :: proc(uri: string) -> ([]byte, bool) {
	switch uri {
	case "ship.mtl":
		return transmute([]byte)string(`# comment
newmtl hull
Kd 0.2 0.4 0.6
Ns 750
Pm 0.5
Ke 0 0.5 0.2

newmtl painted
Kd 0.5 0.5 0.5
Ns 96
map_Kd Textures\paint.png
map_Bump -bm 0.5 normals.png
map_Ke glow.png

newmtl rough
Pr 0.9
`), true
	case "paint.png", "normals.png", "glow.png":
		return test_png(PLAIN_PNG), true
	}
	return nil, false
}

@(test)
test_an_obj_face_is_cut_into_triangles_with_its_coordinates_and_normals_put_in_our_world :: proc(t: ^testing.T) {
	text := `# a square
v 0 0 0
v 2 0 0
v 2 2 0
v 0 2 0
vt 0 0
vt 1 0
vt 1 1
vt 0 1
vn 0 0 1
f 1/1/1 2/2/1 3/3/1 4/4/1
`
	m, e := obj_read(transmute([]byte)text)
	defer model_data_destroy(&m)
	testing.expect_value(t, e, Gltf_Error.None)
	testing.expect_value(t, len(m.indices), 6) // two triangles from the first corner
	testing.expect_value(t, len(m.vertices), 4) // the corners are shared
	testing.expect_value(t, m.indices[0], 0)
	testing.expect_value(t, m.indices[1], 1)
	testing.expect_value(t, m.indices[2], 2)
	testing.expect_value(t, m.indices[3], 0)
	testing.expect_value(t, m.indices[5], 3)
	testing.expect_value(t, m.vertices[2].position, [3]f32{2, -2, 0}) // y is down in our world
	testing.expect_value(t, m.vertices[2].normal, [3]f32{0, -0, 1})
	// an OBJ picture starts at the bottom, ours at the top
	testing.expect_value(t, m.vertices[0].uv, [2]f32{0, 1})
	testing.expect_value(t, m.vertices[2].uv, [2]f32{1, 0})
	testing.expect_value(t, m.low, [3]f32{0, -2, 0})
	testing.expect_value(t, m.high, [3]f32{2, 0, 0})
	testing.expect_value(t, len(m.parts), 1)
	testing.expect_value(t, m.parts[0].index_count, 6)
}

@(test)
test_obj_indices_can_count_back_and_leave_out_coordinates_and_normals :: proc(t: ^testing.T) {
	// negative numbers count from the last, `1//1` has no coordinate, `1` alone has neither
	text := "v 0 0 0\nv 1 0 0\nv 0 1 0\nvn 0 0 1\nf -3//1 -2//1 -1//1\nf 1 2 3\n"
	m, e := obj_read(transmute([]byte)text)
	defer model_data_destroy(&m)
	testing.expect_value(t, e, Gltf_Error.None)
	testing.expect_value(t, len(m.indices), 6)
	// the first face has the file's normal and shares its corners; the second has none and each corner is its own
	testing.expect_value(t, len(m.vertices), 6)
	testing.expect_value(t, m.vertices[0].normal.z, 1)
	// a face with no normals is flat, facing as the glTF reader makes a flat face of the same corners face
	testing.expect_value(t, m.vertices[3].normal, [3]f32{0, 0, 1})
	testing.expect_value(t, m.vertices[3].uv, [2]f32{0, 0})
}

@(test)
test_obj_faces_of_one_material_are_one_part_wherever_they_are_in_the_file :: proc(t: ^testing.T) {
	defer images_stop()
	text := "mtllib ship.mtl\nv 0 0 0\nv 1 0 0\nv 0 1 0\nv 1 1 0\nusemtl hull\nf 1 2 3\nusemtl painted\nf 2 4 3\nusemtl hull\nf 3 2 1\n"
	m, e := obj_read(transmute([]byte)text, obj_files)
	defer model_data_destroy(&m)
	testing.expect_value(t, e, Gltf_Error.None)
	if !testing.expect_value(t, len(m.parts), 2) {
		return
	}
	hull, painted := m.parts[0], m.parts[1]
	testing.expect_value(t, hull.index_count, 6)
	testing.expect_value(t, painted.index_count, 3)
	testing.expect_value(t, painted.first_index, 6)
	testing.expect_value(t, hull.colour, [4]f32{0.2, 0.4, 0.6, 1})
	// Blender's way of writing sharpness: 1 - sqrt(750 / 1000)
	testing.expect(t, abs(hull.roughness - 0.1340) < 1e-3, "Ns is a roughness")
	testing.expect_value(t, hull.metallic, 0.5)
	testing.expect_value(t, hull.emissive, 0.5)
	// the picture gives the color, so Kd is not used; the bump picture has its strength; the emissive one lights
	testing.expect(t, painted.textures[.Colour] != 0 && painted.textures[.Normal] != 0 && painted.textures[.Emissive] != 0, "the pictures are there")
	testing.expect_value(t, painted.colour, [4]f32{1, 1, 1, 1})
	testing.expect_value(t, painted.normal_scale, 0.5)
	testing.expect_value(t, painted.emissive, 1)
	testing.expect_value(t, m.lost_textures, 0)
}

@(test)
test_an_obj_material_with_a_roughness_of_its_own_and_one_that_is_missing :: proc(t: ^testing.T) {
	defer images_stop()
	text := "mtllib ship.mtl\nv 0 0 0\nv 1 0 0\nv 0 1 0\nusemtl rough\nf 1 2 3\nf 1 3 2\nusemtl nowhere\nf 1 2 3\n"
	m, e := obj_read(transmute([]byte)text, obj_files)
	defer model_data_destroy(&m)
	testing.expect_value(t, e, Gltf_Error.None)
	testing.expect_value(t, len(m.parts), 2)
	testing.expect_value(t, m.parts[0].roughness, 0.9)
	// a material the file never describes is a plain light gray
	testing.expect_value(t, m.parts[1].colour, [4]f32{0.8, 0.8, 0.8, 1})
}

@(test)
test_an_obj_picture_that_is_not_there_is_counted_and_a_missing_mtl_too :: proc(t: ^testing.T) {
	defer images_stop()
	reader :: proc(uri: string) -> ([]byte, bool) {
		if uri == "a.mtl" {
			return transmute([]byte)string("newmtl a\nmap_Kd nothing.png\nKd 1 0 0\n"), true
		}
		return nil, false
	}
	text := "mtllib a.mtl\nv 0 0 0\nv 1 0 0\nv 0 1 0\nusemtl a\nf 1 2 3\n"
	m, e := obj_read(transmute([]byte)text, reader)
	defer model_data_destroy(&m)
	testing.expect_value(t, e, Gltf_Error.None)
	testing.expect_value(t, m.lost_textures, 1)
	testing.expect_value(t, m.parts[0].colour, [4]f32{1, 0, 0, 1}) // Kd stays, with no picture to give the color
	n, ne := obj_read(transmute([]byte)string("mtllib gone.mtl\nv 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n"), reader)
	defer model_data_destroy(&n)
	testing.expect_value(t, ne, Gltf_Error.None)
	testing.expect_value(t, n.lost_textures, 1)
}

@(test)
test_an_obj_that_is_damaged_or_empty_is_said_so :: proc(t: ^testing.T) {
	_, e := obj_read(transmute([]byte)string("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 9\n"))
	testing.expect_value(t, e, Gltf_Error.Bad_Data)
	_, e = obj_read(transmute([]byte)string("v 0 0 0\nv 1 0\nf 1 1 1\n"))
	testing.expect_value(t, e, Gltf_Error.Bad_Data)
	_, e = obj_read(transmute([]byte)string("v 0 0 0\nf 1/x 1 1\n"))
	testing.expect_value(t, e, Gltf_Error.Bad_Data)
	_, e = obj_read(transmute([]byte)string("v 0 0 0\nv 1 0 0\n"))
	testing.expect_value(t, e, Gltf_Error.No_Triangles)
	_, e = obj_read(transmute([]byte)string("not a model\n"))
	testing.expect_value(t, e, Gltf_Error.Not_Obj)
	_, e = obj_read(nil)
	testing.expect_value(t, e, Gltf_Error.Not_Obj)
	// a face of two corners is no face, and a face past the numbers there are is damaged
	_, e = obj_read(transmute([]byte)string("v 0 0 0\nv 1 0 0\nf 1 2\n"))
	testing.expect_value(t, e, Gltf_Error.No_Triangles)
}

@(test)
test_a_line_ending_in_a_backslash_goes_on_and_a_comment_ends_a_line :: proc(t: ^testing.T) {
	text := "v 0 0 0 # the first\nv 1 0 0\nv 0 \\\n 1 0\nf 1 2 \\\n 3\n"
	m, e := obj_read(transmute([]byte)text)
	defer model_data_destroy(&m)
	testing.expect_value(t, e, Gltf_Error.None)
	testing.expect_value(t, len(m.indices), 3)
	testing.expect_value(t, m.vertices[2].position, [3]f32{0, -1, 0})
}

@(test)
test_the_kind_of_model_file_is_told_by_its_name :: proc(t: ^testing.T) {
	m, e := model_read("Ship.OBJ", transmute([]byte)string("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n"))
	defer model_data_destroy(&m)
	testing.expect_value(t, e, Gltf_Error.None)
	_, ge := model_read("ship.glb", transmute([]byte)string("v 0 0 0\n"))
	testing.expect_value(t, ge, Gltf_Error.Not_Gltf)
}

// ---- the rest of what a glTF material can say ----

// A glb of one triangle with two sets of texture coordinates and a color for each corner.
rich_glb :: proc(material, textures, images: string) -> []byte {
	text := fill(`{
  "asset": {"version": "2.0"},
  "scene": 0,
  "scenes": [{"nodes": [0]}],
  "nodes": [{"mesh": 0}],
  "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "TEXCOORD_0": 1, "TEXCOORD_1": 2, "COLOR_0": 3}, "material": 0}]}],
  "materials": [@MATERIAL@],
  "textures": [@TEXTURES@],
  "images": [@IMAGES@],
  "accessors": [
    {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"},
    {"bufferView": 1, "componentType": 5126, "count": 3, "type": "VEC2"},
    {"bufferView": 2, "componentType": 5126, "count": 3, "type": "VEC2"},
    {"bufferView": 3, "componentType": 5121, "normalized": true, "count": 3, "type": "VEC3"}
  ],
  "bufferViews": [
    {"buffer": 0, "byteOffset": 0, "byteLength": 36},
    {"buffer": 0, "byteOffset": 36, "byteLength": 24},
    {"buffer": 0, "byteOffset": 60, "byteLength": 24},
    {"buffer": 0, "byteOffset": 84, "byteStride": 4, "byteLength": 12}
  ],
  "buffers": [{"byteLength": 96}]
}`, {{"@MATERIAL@", material}, {"@TEXTURES@", textures}, {"@IMAGES@", images}})
	binary := make([]byte, 96, context.temp_allocator)
	copy(binary, floats_as_bytes({0, 0, 0, 1, 0, 0, 0, 1, 0}))
	copy(binary[36:], floats_as_bytes({0, 0, 1, 0, 0, 1}))
	copy(binary[60:], floats_as_bytes({0.25, 0.5, 0.75, 0.5, 0.25, 0.5}))
	copy(binary[84:], []byte{255, 0, 0, 0, 0, 255, 0, 0, 0, 0, 255, 0}) // red, green and blue, each with a byte of padding
	return make_glb(text, binary)
}

@(test)
test_a_corner_has_its_second_coordinates_and_its_own_color :: proc(t: ^testing.T) {
	m, e := gltf_read(rich_glb("{}", "", ""))
	defer model_data_destroy(&m)
	testing.expect_value(t, e, Gltf_Error.None)
	testing.expect_value(t, m.vertices[0].uv1, [2]f32{0.25, 0.5})
	testing.expect_value(t, m.vertices[1].uv1, [2]f32{0.75, 0.5})
	testing.expect_value(t, m.vertices[0].colour, [4]u8{255, 0, 0, 255}) // three numbers: opaque
	testing.expect_value(t, m.vertices[1].colour, [4]u8{0, 255, 0, 255})
	testing.expect_value(t, m.vertices[2].colour, [4]u8{0, 0, 255, 255})
	// a model with no colors has white corners, which change nothing
	plain, pe := gltf_read(textured_glb("{}", "", ""))
	defer model_data_destroy(&plain)
	testing.expect_value(t, pe, Gltf_Error.None)
	testing.expect_value(t, plain.vertices[0].colour, [4]u8{255, 255, 255, 255})
	testing.expect_value(t, plain.vertices[0].uv1, [2]f32{0, 0})
}

@(test)
test_a_picture_can_be_read_with_the_second_coordinates_and_moved :: proc(t: ^testing.T) {
	defer images_stop()
	images := strings.concatenate({`{"uri": "`, data_uri(test_png(PLAIN_PNG)), `"}`}, context.temp_allocator)
	material := `{"pbrMetallicRoughness": {"baseColorTexture": {"index": 0, "texCoord": 1}, "metallicRoughnessTexture": {"index": 0, "extensions": {"KHR_texture_transform": {"offset": [0.5, 0.25], "scale": [2, 4], "rotation": 0}}}}, "normalTexture": {"index": 0, "extensions": {"KHR_texture_transform": {"texCoord": 1, "rotation": 1.5707963267948966}}}}`
	m, e := gltf_read(rich_glb(material, `{"source": 0}`, images))
	defer model_data_destroy(&m)
	testing.expect_value(t, e, Gltf_Error.None)
	part := m.parts[0]
	testing.expect_value(t, part.uv_set[.Colour], 1)
	testing.expect_value(t, part.uv_set[.Metal_Rough], 0)
	testing.expect_value(t, part.uv_transform[.Colour], [6]f32{1, 0, 0, 0, 1, 0}) // none said
	testing.expect_value(t, part.uv_transform[.Metal_Rough], [6]f32{2, 0, 0.5, 0, 4, 0.25})
	// the transform's own texCoord wins, and a quarter turn takes u to -v and v to u (glTF's rotation matrix)
	testing.expect_value(t, part.uv_set[.Normal], 1)
	turn := part.uv_transform[.Normal]
	testing.expect(t, abs(turn[0]) < 1e-6 && abs(turn[1] - 1) < 1e-6 && abs(turn[3] + 1) < 1e-6 && abs(turn[4]) < 1e-6, "a quarter turn")
}

@(test)
test_the_material_extensions_that_change_a_still_picture_are_read :: proc(t: ^testing.T) {
	m, e := gltf_read(triangle_glb("", `, "material": 0`, `, "materials": [
	  {"emissiveFactor": [0.5, 0.2, 0.1], "extensions": {"KHR_materials_emissive_strength": {"emissiveStrength": 4}}},
	  {"extensions": {"KHR_materials_unlit": {}}},
	  {"extensions": {"KHR_materials_ior": {"ior": 2.0}}},
	  {"extensions": {"KHR_materials_specular": {"specularFactor": 0.5}}}
	]`))
	defer model_data_destroy(&m)
	testing.expect_value(t, e, Gltf_Error.None)
	testing.expect_value(t, m.parts[0].emissive, 2) // the brightest channel times the strength
	testing.expect(t, !m.parts[0].unlit, "lit")
	testing.expect_value(t, m.parts[0].dielectric, 0.04)
	read :: proc(index: int) -> Model_Data {
		text := fill(`, "material": @I@`, {{"@I@", tprint_int(index)}})
		result, _ := gltf_read(triangle_glb("", text, `, "materials": [
	  {"emissiveFactor": [0.5, 0.2, 0.1], "extensions": {"KHR_materials_emissive_strength": {"emissiveStrength": 4}}},
	  {"extensions": {"KHR_materials_unlit": {}}},
	  {"extensions": {"KHR_materials_ior": {"ior": 2.0}}},
	  {"extensions": {"KHR_materials_specular": {"specularFactor": 0.5}}}
	]`))
		return result
	}
	unlit := read(1)
	defer model_data_destroy(&unlit)
	testing.expect(t, unlit.parts[0].unlit, "the unlit extension")
	ior := read(2)
	defer model_data_destroy(&ior)
	testing.expect(t, abs(ior.parts[0].dielectric - 1.0 / 9.0) < 1e-6, "an index of 2 reflects (1/3)^2")
	specular := read(3)
	defer model_data_destroy(&specular)
	testing.expect(t, abs(specular.parts[0].dielectric - 0.02) < 1e-6, "half the usual")
}

@(private = "file")
tprint_int :: proc(n: int) -> string {
	return itoa(n)
}

// ---- OBJ: colors, alpha and faces that are not convex ----

@(test)
test_an_obj_corner_can_have_a_color_of_its_own :: proc(t: ^testing.T) {
	text := "v 0 0 0 1 0 0\nv 1 0 0 0 1 0\nv 0 1 0 0 0 0.5\nf 1 2 3\n"
	m, e := obj_read(transmute([]byte)text)
	defer model_data_destroy(&m)
	testing.expect_value(t, e, Gltf_Error.None)
	testing.expect_value(t, m.vertices[0].colour, [4]u8{255, 0, 0, 255})
	testing.expect_value(t, m.vertices[1].colour, [4]u8{0, 255, 0, 255})
	testing.expect_value(t, m.vertices[2].colour, [4]u8{0, 0, 128, 255})
	// without them the corners are white
	plain, _ := obj_read(transmute([]byte)string("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n"))
	defer model_data_destroy(&plain)
	testing.expect_value(t, plain.vertices[0].colour, [4]u8{255, 255, 255, 255})
}

@(test)
test_an_obj_map_d_is_the_alpha_of_the_color :: proc(t: ^testing.T) {
	defer images_stop()
	reader :: proc(uri: string) -> ([]byte, bool) {
		switch uri {
		case "leaf.mtl":
			return transmute([]byte)string("newmtl leaf\nmap_Kd green.png\nmap_d cut.png\n"), true
		case "green.png":
			return test_png({{0, 200, 0, 255}, {0, 200, 0, 255}, {0, 200, 0, 255}, {0, 200, 0, 255}}), true
		case "cut.png":
			return test_png({{255, 255, 255, 255}, {0, 0, 0, 255}, {0, 0, 0, 255}, {255, 255, 255, 255}}), true
		}
		return nil, false
	}
	text := "mtllib leaf.mtl\nv 0 0 0\nv 1 0 0\nv 0 1 0\nusemtl leaf\nf 1 2 3\n"
	m, e := obj_read(transmute([]byte)text, reader)
	defer model_data_destroy(&m)
	testing.expect_value(t, e, Gltf_Error.None)
	testing.expect_value(t, m.parts[0].alpha_cutoff, 0.5)
	merged := image_data(m.parts[0].textures[.Colour])
	if !testing.expect(t, merged != nil, "a color picture") {
		return
	}
	// the colors of the green one with the red of the other as alpha
	testing.expect_value(t, merged.pixels[0], 0)
	testing.expect_value(t, merged.pixels[1], 200)
	testing.expect_value(t, merged.pixels[3], 255)
	testing.expect_value(t, merged.pixels[7], 0)
	testing.expect_value(t, merged.pixels[11], 0)
	testing.expect_value(t, merged.pixels[15], 255)
}

@(test)
test_a_face_that_is_not_convex_is_cut_so_the_notch_stays_empty :: proc(t: ^testing.T) {
	// an L: a square 2 by 2 with a 1 by 1 corner taken out, six corners, area 3
	text := "v 0 0 0\nv 2 0 0\nv 2 1 0\nv 1 1 0\nv 1 2 0\nv 0 2 0\nf 1 2 3 4 5 6\n"
	m, e := obj_read(transmute([]byte)text)
	defer model_data_destroy(&m)
	testing.expect_value(t, e, Gltf_Error.None)
	testing.expect_value(t, len(m.indices), 12) // four triangles
	area := 0.0
	for i := 0; i + 2 < len(m.indices); i += 3 {
		a, b, c := m.vertices[m.indices[i]].position, m.vertices[m.indices[i + 1]].position, m.vertices[m.indices[i + 2]].position
		cross := cross3f(b - a, c - a)
		area += f64(math.sqrt(cross.x * cross.x + cross.y * cross.y + cross.z * cross.z)) / 2
		// no triangle has its middle in the notch, where x and y are both over 1
		middle := (a + b + c) / 3
		testing.expect(t, !(middle.x > 1 && -middle.y > 1), "a triangle covers the notch")
	}
	testing.expect(t, abs(area - 3) < 1e-6, "the area is three squares")
	// a convex quad is still a fan: its triangles are (1 2 3) and (1 3 4)
	quad, _ := obj_read(transmute([]byte)string("v 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\nf 1 2 3 4\n"))
	defer model_data_destroy(&quad)
	testing.expect_value(t, len(quad.indices), 6)
	testing.expect_value(t, quad.indices[0], 0)
	testing.expect_value(t, quad.indices[3], 0)
}
