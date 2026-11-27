// SPDX-License-Identifier: 0BSD
package gfx

import "core:testing"

import sdl "vendor:sdl3"

@(test)
the_mask_shader_translates_with_two_pictures_and_its_premultiplied_value :: proc(t: ^testing.T) {
	defer shaders_stop()
	id := mask_shader_id()
	testing.expect(t, id != 0, "the built-in mask shader translates")
	data := shader_data(id)
	if data == nil {
		return
	}
	testing.expect_value(t, data.kind, Shader_Use.Effect)
	testing.expect_value(t, data.textures, 2)
	found := false
	for p in data.params.list {
		if p.name == "premultiplied" {
			found = true
			testing.expect_value(t, p.floats, 2)
			testing.expect(t, p.offset + 8 <= data.params.size)
		}
	}
	testing.expect(t, found, "the shader reads `premultiplied`")
	// Asked again it is the same shader, not a second copy.
	testing.expect_value(t, mask_shader_id(), id)
	testing.expect_value(t, len(shader_store), 1)
}

@(test)
the_mask_shader_is_translated_again_after_the_shaders_are_let_go :: proc(t: ^testing.T) {
	defer shaders_stop()
	first := mask_shader_id()
	shaders_stop()
	testing.expect_value(t, len(shader_store), 0)
	again := mask_shader_id()
	testing.expect(t, again != 0 && first != 0)
	testing.expect(t, shader_ok(again), "the number names a translated shader in the new set")
	testing.expect_value(t, len(shader_store), 1)
}

@(test)
no_renderer_masks_nothing_on_the_graphics_card :: proc(t: ^testing.T) {
	defer images_stop()
	defer shaders_stop()
	testing.expect(t, !can_mask_on_gpu(nil))
	r: Renderer // no device
	testing.expect(t, !can_mask_on_gpu(&r))
	a, _ := image_add_canvas(4, 4, 1)
	b, _ := image_add_canvas(4, 4, 1)
	made, ok := mask_on_gpu(&r, a, b)
	testing.expect(t, !ok && made == 0)
	testing.expect_value(t, mask_bytes(&r, a), 0)
	testing.expect(t, !r.failed, "having no device is not a failure of the graphics")
}

@(test)
a_fixed_canvas_is_a_canvas_that_is_let_go_like_a_made_picture :: proc(t: ^testing.T) {
	defer images_stop()
	fixed, ok := image_add_fixed_canvas(30, 20, 2)
	testing.expect(t, ok)
	canvas := canvas_of(fixed)
	testing.expect(t, canvas != nil && canvas.fixed)
	testing.expect_value(t, canvas.density, f32(2))
	w, h := image_size(fixed)
	testing.expect(t, w == 30 && h == 20)
	testing.expect_value(t, image_bytes(fixed), 0) // its pixels are on the graphics card
	plain, _ := image_add_canvas(30, 20, 2)
	testing.expect(t, !canvas_of(plain).fixed)
	testing.expect(t, !image_release(plain), "a canvas the sketch draws into is never let go")
	before := len(released_images)
	testing.expect(t, image_release(fixed))
	testing.expect(t, image_data(fixed) == nil)
	testing.expect_value(t, len(released_images), before + 1) // so each renderer lets its texture go
	testing.expect_value(t, released_images[len(released_images) - 1], fixed)
	_, bad := image_add_fixed_canvas(0, 20, 2)
	testing.expect(t, !bad)
}

@(test)
taking_pixels_keeps_them_without_a_copy_and_frees_them_when_refused :: proc(t: ^testing.T) {
	defer images_stop()
	pixels := make([]u8, 2 * 3 * 4)
	pixels[0] = 9
	id, ok := image_take_pixels(2, 3, pixels)
	testing.expect(t, ok)
	data := image_data(id)
	testing.expect(t, data != nil && raw_data(data.pixels) == raw_data(pixels), "the same memory, not a copy")
	testing.expect_value(t, data.pixels[0], u8(9))
	// A size that does not match frees what it was given (the leak check would say otherwise).
	_, bad := image_take_pixels(2, 2, make([]u8, 2 * 3 * 4))
	testing.expect(t, !bad)
	_, bad = image_take_pixels(0, 3, make([]u8, 4))
	testing.expect(t, !bad)
	_, bad = image_take_pixels(2, 3, nil)
	testing.expect(t, !bad)
}

@(test)
the_mask_pool_gives_back_a_texture_of_the_same_size_and_spills_the_oldest :: proc(t: ^testing.T) {
	r: Renderer // no device: the pool only keeps the numbers of textures, and these are never drawn with
	defer delete(r.mask_pool)
	fake :: proc(n: uintptr) -> ^sdl.GPUTexture {return (^sdl.GPUTexture)(n)}
	testing.expect(t, mask_pool_take(&r, 10, 10) == nil, "an empty pool has nothing")
	testing.expect(t, mask_pool_put(&r, nil, 10, 10) == nil)
	testing.expect_value(t, len(r.mask_pool), 0)
	for i in 1 ..= MASK_POOL_MOST {
		testing.expect(t, mask_pool_put(&r, fake(uintptr(i * 16)), 10, u32(10 + i % 2)) == nil)
	}
	// One more spills the one kept longest.
	testing.expect_value(t, mask_pool_put(&r, fake(0x1000), 20, 20), fake(16))
	testing.expect_value(t, len(r.mask_pool), MASK_POOL_MOST)
	testing.expect(t, mask_pool_take(&r, 30, 30) == nil, "no texture of another size")
	testing.expect_value(t, mask_pool_take(&r, 20, 20), fake(0x1000))
	// Of several of one size, the one put last comes first.
	testing.expect_value(t, mask_pool_take(&r, 10, 10), fake(uintptr(MASK_POOL_MOST * 16)))
	testing.expect_value(t, len(r.mask_pool), MASK_POOL_MOST - 2)
}
