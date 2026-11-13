// SPDX-License-Identifier: 0BSD
//
// A model made in code and painted with every kind of picture a material can have, so the golden
// images check the part of the 3D shader that reads them with no file to download or keep: the left
// part has a checkered color, a normal map of round bumps, roughness in stripes and metal in its right
// half, and a light of its own in a square; the right part has a color with holes cut through it.
package golden

import "core:math"

import "../../roci/gfx"
import "../../roci/maths"

PICTURE_SIDE :: 64

// A picture of PICTURE_SIDE squared pixels, each one given by the procedure from its column and row.
painted :: proc(pixel: proc(x, y: int) -> [4]u8) -> gfx.Image_Id {
	pixels := make([]u8, PICTURE_SIDE * PICTURE_SIDE * 4, context.temp_allocator)
	for y in 0 ..< PICTURE_SIDE {
		for x in 0 ..< PICTURE_SIDE {
			c := pixel(x, y)
			copy(pixels[(y * PICTURE_SIDE + x) * 4:], c[:])
		}
	}
	id, _ := gfx.image_add_pixels(PICTURE_SIDE, PICTURE_SIDE, pixels)
	return id
}

checkers :: proc(x, y: int) -> [4]u8 {
	if (x / 8 + y / 8) % 2 == 0 {
		return {240, 140, 40, 255}
	}
	return {30, 50, 120, 255}
}

// Round bumps 16 pixels across: the normal of a dome, which leans away from the middle of each.
bumps :: proc(x, y: int) -> [4]u8 {
	dx := f32(x % 16) - 7.5
	dy := f32(y % 16) - 7.5
	lean := [2]f32{dx / 8, dy / 8}
	flat := lean.x * lean.x + lean.y * lean.y
	if flat >= 1 {
		return {128, 128, 255, 255}
	}
	nz := math.sqrt(1 - flat * 0.5)
	return {u8((lean.x * 0.5 + 0.5) * 255), u8((-lean.y * 0.5 + 0.5) * 255), u8((nz * 0.5 + 0.5) * 255), 255}
}

// Roughness in green: stripes of a smooth and a rough surface; metal in blue: none on the left half.
stripes :: proc(x, y: int) -> [4]u8 {
	rough := u8(50) if (y / 8) % 2 == 0 else u8(230)
	metal := u8(0) if x < PICTURE_SIDE / 2 else u8(255)
	return {255, rough, metal, 255}
}

glow_square :: proc(x, y: int) -> [4]u8 {
	if x > 20 && x < 44 && y > 20 && y < 44 {
		return {60, 255, 255, 255}
	}
	return {0, 0, 0, 255}
}

holes :: proc(x, y: int) -> [4]u8 {
	if (x / 8 + y / 8) % 2 == 0 {
		return {90, 200, 90, 255}
	}
	return {90, 200, 90, 0}
}

// Two upright squares side by side, one corner at a time: position, normal (toward the viewer) and the
// place in the pictures.
model_pictures :: proc(list: ^gfx.Command_List) {
	gfx.background(list, maths.Colour{18, 20, 36, 255})
	data: gfx.Model_Data
	square :: proc(data: ^gfx.Model_Data, left, right: f32) {
		base := u32(len(data.vertices))
		append(&data.vertices,
			gfx.Vertex3{{left, -0.5, 0}, {0, 0, 1}, 0, {0, 0}},
			gfx.Vertex3{{right, -0.5, 0}, {0, 0, 1}, 0, {1, 0}},
			gfx.Vertex3{{right, 0.5, 0}, {0, 0, 1}, 0, {1, 1}},
			gfx.Vertex3{{left, 0.5, 0}, {0, 0, 1}, 0, {0, 1}},
		)
		first := u32(len(data.indices))
		append(&data.indices, base, base + 1, base + 2, base, base + 2, base + 3)
		append(&data.parts, gfx.Model_Part{first_index = first, index_count = 6, colour = {1, 1, 1, 1}, metallic = 1, roughness = 1, normal_scale = 1})
	}
	square(&data, -1.1, -0.05)
	square(&data, 0.05, 1.1)
	data.low, data.high = {-1.1, -0.5, 0}, {1.1, 0.5, 0}
	data.parts[0].textures = {.Colour = painted(checkers), .Normal = painted(bumps), .Metal_Rough = painted(stripes), .Emissive = painted(glow_square)}
	data.parts[0].emissive = 1
	data.parts[1].textures[.Colour] = painted(holes)
	data.parts[1].alpha_cutoff = 0.5
	data.parts[1].metallic = 0
	data.parts[1].roughness = 0.6
	id := gfx.model_add("golden:model_pictures", 1, data)
	// something behind them, so the holes show it
	gfx.scene_add(&list.scene, .Box, {0, 0, -30}, {220, 40, 4}, maths.Colour{200, 60, 60, 255})
	_ = gfx.scene_light(&list.scene, {kind = .Ambient, colour = {0.3, 0.32, 0.4}})
	_ = gfx.scene_light(&list.scene, {kind = .Sun, at = {0.7, -0.5, 0.6}, colour = {1, 0.96, 0.9}})
	gfx.scene_add_loaded_model(&list.scene, id, {0, 0, 0}, 150)
}
