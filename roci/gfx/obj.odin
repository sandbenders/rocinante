// SPDX-License-Identifier: 0BSD
//
// Wavefront OBJ models, read in plain Odin: the `.obj` file (positions `v`, texture coordinates `vt`,
// normals `vn` and faces `f`, which are cut into triangles from their first corner) and the `.mtl` file
// it names with `mtllib`, which says how each `usemtl` material looks: `Kd` the color, `Ke` the light it
// gives, `Ns` how sharp its highlight is (turned into a roughness the way Blender writes it, so
// roughness = 1 - sqrt(Ns / 1000)), `Pr` and `Pm` (the roughness and metal that Blender writes with its
// PBR extension), and the pictures `map_Kd`, `map_Bump` (or `bump`, `norm`) and `map_Ke`. When a material has a
// `map_Kd` the picture gives the color and `Kd` is not used, because Blender writes a gray `Kd` beside
// every picture it exports. A material that names no picture has none: a texture the `.mtl` does not
// mention is not guessed from the folders around it, so add its `map_Kd` line.
//
// OBJ has no units and no up, but nearly every file is y up like glTF, so the model is put into the
// sketch's world the same way (y down, `model` fits the size). Faces of one material become one part,
// however they are spread through the file, so a model is a draw for each material.
package gfx

import "../geom"
import "core:math"
import "core:strconv"
import "core:strings"

// One material of an `.mtl` file.
@(private = "file")
Obj_Material :: struct {
	name:      string,
	part:      Model_Part,
	has_color: bool, // the picture gave it
	alpha_map: Image_Id, // `map_d`: a picture whose brightness is how much of the material is there
}

@(private = "file")
Obj_Corner :: [3]i32 // position, texture coordinate and normal, each as an index (-1: none)

// Reads a model from the bytes of an `.obj` file. `reader` gives the files named beside it (the
// `.mtl` and the pictures). Everything it makes temporarily is in the temporary allocator; the model's
// own arrays are in `allocator`.
obj_read :: proc(bytes: []byte, reader: Gltf_Reader = nil, allocator := context.allocator) -> (model: Model_Data, error: Gltf_Error) {
	text := string(bytes)
	positions := make([dynamic][3]f32, context.temp_allocator)
	colours := make([dynamic][4]u8, context.temp_allocator) // of each position: white unless the file gives `v x y z r g b`
	uvs := make([dynamic][2]f32, context.temp_allocator)
	normals := make([dynamic][3]f32, context.temp_allocator)
	materials := make([dynamic]Obj_Material, context.temp_allocator)
	pictures := make(map[string]Image_Id, context.temp_allocator)
	lost := 0
	// the indices of each material's triangles, then put one after the other
	per_material := make([dynamic][dynamic]u32, context.temp_allocator)
	current := -1
	corners := make(map[Obj_Corner]u32, context.temp_allocator)
	vertices := make([dynamic]Vertex3, context.temp_allocator)
	seen_face := false

	material_of :: proc(materials: ^[dynamic]Obj_Material, per_material: ^[dynamic][dynamic]u32, name: string) -> int {
		for m, i in materials {
			if m.name == name {
				return i
			}
		}
		append(materials, Obj_Material{name = name, part = default_part()})
		append(per_material, make([dynamic]u32, context.temp_allocator))
		return len(materials^) - 1
	}

	lines := strings.split_lines(text, context.temp_allocator)
	for line_index := 0; line_index < len(lines); line_index += 1 {
		line := lines[line_index]
		// a line that ends in a backslash goes on in the next
		for strings.has_suffix(strings.trim_right_space(line), "\\") && line_index + 1 < len(lines) {
			line_index += 1
			line = strings.concatenate({strings.trim_right_space(line)[:len(strings.trim_right_space(line)) - 1], " ", lines[line_index]}, context.temp_allocator)
		}
		if hash := strings.index_byte(line, '#'); hash >= 0 {
			line = line[:hash]
		}
		words := strings.fields(line, context.temp_allocator)
		if len(words) == 0 {
			continue
		}
		switch words[0] {
		case "v":
			if len(words) < 4 {
				return {}, .Bad_Data
			}
			append(&positions, [3]f32{number(words[1]), number(words[2]), number(words[3])})
			colour := [4]u8{255, 255, 255, 255}
			if len(words) >= 7 {
				for k in 0 ..< 3 {
					colour[k] = u8(clamp(number(words[4 + k]), 0, 1) * 255 + 0.5)
				}
			}
			append(&colours, colour)
		case "vt":
			if len(words) < 2 {
				return {}, .Bad_Data
			}
			// an OBJ picture starts at the bottom left and ours at the top left
			append(&uvs, [2]f32{number(words[1]), 1 - (number(words[2]) if len(words) > 2 else 0)})
		case "vn":
			if len(words) < 4 {
				return {}, .Bad_Data
			}
			append(&normals, [3]f32{number(words[1]), number(words[2]), number(words[3])})
		case "mtllib":
			if reader != nil && len(words) > 1 {
				name := strings.trim_space(strings.trim_prefix(strings.trim_space(line), "mtllib"))
				if file, found := reader(percent_decoded(name)); found {
					read_mtl(string(file), &materials, &per_material, &pictures, &lost, reader)
				} else {
					lost += 1
				}
			}
		case "usemtl":
			name := strings.trim_space(strings.trim_prefix(strings.trim_space(line), "usemtl"))
			current = material_of(&materials, &per_material, name)
		case "f":
			if len(words) < 4 {
				continue
			}
			if current < 0 {
				current = material_of(&materials, &per_material, "")
			}
			seen_face = true
			face := make([dynamic]Obj_Corner, context.temp_allocator)
			for word in words[1:] {
				corner, ok := parse_corner(word, len(positions), len(uvs), len(normals))
				if !ok {
					return {}, .Bad_Data
				}
				append(&face, corner)
			}
			// the face's own normal, for corners the file gives none
			face_normal := [3]f32{0, 0, 0}
			for corner in face {
				if corner.z < 0 {
					a, b, c := positions[face[0].x], positions[face[1].x], positions[face[2].x]
					face_normal = normalize3f(cross3f(b - a, c - a))
					break
				}
			}
			corner_vertex :: proc(vertices: ^[dynamic]Vertex3, corners: ^map[Obj_Corner]u32, positions: [][3]f32, colours: [][4]u8, uvs: [][2]f32, normals: [][3]f32, corner: Obj_Corner, face_normal: [3]f32) -> u32 {
				if corner.z >= 0 {
					if found, has := corners[corner]; has {
						return found
					}
				}
				position := positions[corner.x]
				n := face_normal if corner.z < 0 else normalize3f(normals[corner.z])
				uv := [2]f32{} if corner.y < 0 else uvs[corner.y]
				// into the sketch's world, where y is down
				index := u32(len(vertices^))
				append(vertices, Vertex3{{position.x, -position.y, position.z}, {n.x, -n.y, n.z}, 0, uv, uv, colours[corner.x]})
				if corner.z >= 0 {
					corners[corner] = index
				}
				return index
			}
			made := make([]u32, len(face), context.temp_allocator)
			places := make([][3]f32, len(face), context.temp_allocator)
			for corner, k in face {
				made[k] = corner_vertex(&vertices, &corners, positions[:], colours[:], uvs[:], normals[:], corner, face_normal)
				places[k] = positions[corner.x]
			}
			cut := face_triangles(places)
			for t := 0; t + 2 < len(cut); t += 3 {
				append(&per_material[current], made[cut[t]], made[cut[t + 1]], made[cut[t + 2]])
			}
		}
	}
	if !seen_face || len(vertices) == 0 {
		return {}, .No_Triangles if len(positions) > 0 else .Not_Obj
	}
	// a `map_d` becomes the alpha of the color picture, and the part cuts where it is under half
	for &m in materials {
		if m.alpha_map != 0 {
			if merged := merge_alpha(m.part.textures[.Colour], m.alpha_map); merged != 0 {
				m.part.textures[.Colour] = merged
				m.part.alpha_cutoff = 0.5
			}
		}
	}

	model.vertices = make([dynamic]Vertex3, allocator)
	model.indices = make([dynamic]u32, allocator)
	model.parts = make([dynamic]Model_Part, allocator)
	model.lost_textures = lost
	append(&model.vertices, ..vertices[:])
	for m, i in materials {
		if len(per_material[i]) == 0 {
			continue
		}
		part := m.part
		part.first_index = u32(len(model.indices))
		part.index_count = u32(len(per_material[i]))
		append(&model.indices, ..per_material[i][:])
		append(&model.parts, part)
	}
	// a texture one material loaded and no part uses is let go now rather than held for nothing
	for _, id in pictures {
		used := false
		for part in model.parts {
			for slot in part.textures {
				used ||= slot == id
			}
		}
		if !used && id != 0 {
			image_release(id)
		}
	}
	low, high := model.vertices[0].position, model.vertices[0].position
	for v in model.vertices {
		for axis in 0 ..< 3 {
			low[axis] = min(low[axis], v.position[axis])
			high[axis] = max(high[axis], v.position[axis])
		}
	}
	model.low, model.high = low, high
	return model, .None
}

@(private = "file")
default_part :: proc() -> Model_Part {
	p := model_part_default()
	p.colour, p.metallic, p.roughness = {0.8, 0.8, 0.8, 1}, 0, 0.7
	return p
}

@(private = "file")
number :: proc(word: string) -> f32 {
	value, _ := strconv.parse_f32(word)
	return value
}

// `5`, `5/2`, `5//3` or `5/2/3`: the 1-based indices of a corner, a negative one counting back from the
// last so far. Out of range is false.
@(private = "file")
parse_corner :: proc(word: string, positions, uvs, normals: int) -> (corner: Obj_Corner, ok: bool) {
	parts := strings.split(word, "/", context.temp_allocator)
	if len(parts) == 0 || len(parts) > 3 {
		return {}, false
	}
	counts := [3]int{positions, uvs, normals}
	corner = {-1, -1, -1}
	for part, k in parts {
		if part == "" {
			if k == 0 {
				return {}, false
			}
			continue
		}
		n, parsed := strconv.parse_int(part, 10)
		if !parsed || n == 0 {
			return {}, false
		}
		index := n - 1 if n > 0 else counts[k] + n
		if index < 0 || index >= counts[k] {
			return {}, false
		}
		corner[k] = i32(index)
	}
	return corner, true
}

// Reads a `.mtl` file: each `newmtl` becomes a material the `usemtl` lines find by name.
@(private = "file")
read_mtl :: proc(text: string, materials: ^[dynamic]Obj_Material, per_material: ^[dynamic][dynamic]u32, pictures: ^map[string]Image_Id, lost: ^int, reader: Gltf_Reader) {
	text := text
	current := -1
	for line in strings.split_lines_iterator(&text) {
		line := line
		if hash := strings.index_byte(line, '#'); hash >= 0 {
			line = line[:hash]
		}
		words := strings.fields(line, context.temp_allocator)
		if len(words) == 0 {
			continue
		}
		if words[0] == "newmtl" {
			name := strings.trim_space(strings.trim_prefix(strings.trim_space(line), "newmtl"))
			current = -1
			for m, i in materials {
				if m.name == name {
					current = i
				}
			}
			if current < 0 {
				append(materials, Obj_Material{name = name, part = default_part()})
				append(per_material, make([dynamic]u32, context.temp_allocator))
				current = len(materials^) - 1
			}
			continue
		}
		if current < 0 {
			continue
		}
		m := &materials[current]
		switch words[0] {
		case "Kd":
			if len(words) >= 4 && !m.has_color {
				m.part.colour = {clamp(number(words[1]), 0, 1), clamp(number(words[2]), 0, 1), clamp(number(words[3]), 0, 1), 1}
			}
		case "Ke":
			if len(words) >= 4 {
				m.part.emissive = clamp(max(number(words[1]), number(words[2]), number(words[3])), 0, 1)
			}
		case "Ns":
			if len(words) >= 2 {
				m.part.roughness = clamp(1 - math.sqrt(clamp(number(words[1]) / 1000, 0, 1)), 0, 1)
			}
		case "Pr":
			if len(words) >= 2 {
				m.part.roughness = clamp(number(words[1]), 0, 1)
			}
		case "Pm":
			if len(words) >= 2 {
				m.part.metallic = clamp(number(words[1]), 0, 1)
			}
		case "map_Kd":
			if id := mtl_picture(line, words, pictures, lost, reader); id != 0 {
				m.part.textures[.Colour] = id
				m.part.colour = {1, 1, 1, 1}
				m.has_color = true
			}
		case "map_Bump", "map_bump", "bump", "norm":
			if id := mtl_picture(line, words, pictures, lost, reader); id != 0 {
				m.part.textures[.Normal] = id
				for word, k in words {
					if word == "-bm" && k + 1 < len(words) {
						m.part.normal_scale = clamp(number(words[k + 1]), -4, 4)
					}
				}
			}
		case "map_d":
			m.alpha_map = mtl_picture(line, words, pictures, lost, reader)
		case "map_Ke":
			if id := mtl_picture(line, words, pictures, lost, reader); id != 0 {
				m.part.textures[.Emissive] = id
				m.part.emissive = 1
			}
		}
	}
}

// The picture a `map_` line names: its last word, with the options before it (`-bm 0.5`) left out, from the
// file beside the model, read once however many materials name it. 0 when it cannot be had.
@(private = "file")
mtl_picture :: proc(line: string, words: []string, pictures: ^map[string]Image_Id, lost: ^int, reader: Gltf_Reader) -> Image_Id {
	// the file name is what is left after the key and the options (`-bm 0.5`), and may have spaces in it
	k := 1
	for k < len(words) && strings.has_prefix(words[k], "-") {
		k += 1
		for k < len(words) - 1 && is_number(words[k]) {
			k += 1
		}
	}
	name := strings.join(words[k:], " ", context.temp_allocator)
	name, _ = strings.replace_all(name, "\\", "/", context.temp_allocator)
	if slash := strings.last_index_byte(name, '/'); slash >= 0 {
		name = name[slash + 1:] // the picture is looked for beside the model, whatever folder the file named
	}
	if name == "" {
		return 0
	}
	if id, done := pictures[name]; done {
		return id
	}
	id: Image_Id
	if reader != nil {
		if bytes, found := reader(percent_decoded(name)); found {
			if picture, ok := image_add(bytes); ok {
				id = picture
			}
		}
	}
	if id == 0 {
		lost^ += 1
	}
	pictures[strings.clone(name, context.temp_allocator)] = id
	return id
}


@(private = "file")
is_number :: proc(word: string) -> bool {
	_, ok := strconv.parse_f64(word)
	return ok
}

// How a face of three or more corners is cut into triangles, as the places of the corners three at a time. A
// face that is convex (all its turns the same way about its normal, which is nearly every face) is a fan from its
// first corner; a concave one is flattened along the largest part of its normal and cut by ear clipping, so a
// notch is not covered.
@(private)
face_triangles :: proc(points: [][3]f32) -> []int {
	n := len(points)
	out := make([dynamic]int, context.temp_allocator)
	if n < 3 {
		return out[:]
	}
	fan :: proc(out: ^[dynamic]int, n: int) {
		for k in 1 ..< n - 1 {
			append(out, 0, k, k + 1)
		}
	}
	if n == 3 {
		fan(&out, n)
		return out[:]
	}
	// the normal of the whole face (Newell), and whether every corner turns the way it does
	normal := [3]f32{}
	for i in 0 ..< n {
		a, b := points[i], points[(i + 1) % n]
		normal += {(a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)}
	}
	convex := true
	for i in 0 ..< n {
		a, b, c := points[i], points[(i + 1) % n], points[(i + 2) % n]
		turn := cross3f(b - a, c - b)
		if turn.x * normal.x + turn.y * normal.y + turn.z * normal.z < 0 {
			convex = false
			break
		}
	}
	if convex {
		fan(&out, n)
		return out[:]
	}
	axis := 0
	if abs(normal.y) > abs(normal[axis]) {axis = 1}
	if abs(normal.z) > abs(normal[axis]) {axis = 2}
	flat := make([]geom.Point, n, context.temp_allocator)
	for p, i in points {
		switch axis {
		case 0: flat[i] = {f64(p.y), f64(p.z)}
		case 1: flat[i] = {f64(p.z), f64(p.x)}
		case 2: flat[i] = {f64(p.x), f64(p.y)}
		}
	}
	t: geom.Triangulation
	defer geom.triangulation_destroy(&t)
	if geom.triangulate({flat}, &t) == 0 {
		fan(&out, n)
		return out[:]
	}
	// the triangulation keeps the corners it uses as they were, so each is found again by where it is
	original :: proc(flat: []geom.Point, p: geom.Point) -> int {
		for q, i in flat {
			if q == p {
				return i
			}
		}
		return 0
	}
	for index in t.indices {
		append(&out, original(flat, t.points[index]))
	}
	return out[:]
}

// A new picture made of the color picture (white when there is none) with the red of the alpha picture as its
// alpha, the alpha picture read at the same place of itself as each pixel is of the color one. 0 when either
// cannot be had.
@(private)
merge_alpha :: proc(colour, alpha: Image_Id) -> Image_Id {
	a := image_data(alpha)
	if a == nil || a.pixels == nil {
		return 0
	}
	c := image_data(colour) if colour != 0 else nil
	width, height := a.width, a.height
	if c != nil && c.pixels != nil {
		width, height = c.width, c.height
	}
	pixels := make([]u8, width * height * 4, context.temp_allocator)
	for y in 0 ..< height {
		for x in 0 ..< width {
			at := (y * width + x) * 4
			if c != nil && c.pixels != nil {
				copy(pixels[at:at + 3], c.pixels[at:at + 3])
			} else {
				pixels[at], pixels[at + 1], pixels[at + 2] = 255, 255, 255
			}
			ax, ay := x * a.width / width, y * a.height / height
			pixels[at + 3] = a.pixels[(ay * a.width + ax) * 4]
		}
	}
	id, _ := image_add_pixels(width, height, pixels)
	return id
}
