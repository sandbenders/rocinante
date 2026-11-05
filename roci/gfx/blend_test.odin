// SPDX-License-Identifier: 0BSD
package gfx

import "core:testing"
import sdl "vendor:sdl3"

@(test)
test_blend_and_clip_start_off_and_are_part_of_the_style :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	circle(&list, 0, 0, 5)
	style := command_at(&list, 0).style
	testing.expect_value(t, style.blend, Blend_Mode.Normal)
	testing.expect(t, !style.clip.on)
	set_blend(&list, .Add)
	set_clip(&list, 10, 20, 30, 40)
	circle(&list, 0, 0, 5)
	style = command_at(&list, 1).style
	testing.expect_value(t, style.blend, Blend_Mode.Add)
	testing.expect_value(t, style.clip, Clip{on = true, rect = {10, 20, 40, 60}})
	// The earlier command keeps what it was recorded with.
	testing.expect_value(t, command_at(&list, 0).style.blend, Blend_Mode.Normal)
	no_clip(&list)
	set_blend(&list, .Normal)
	circle(&list, 0, 0, 5)
	testing.expect_value(t, command_at(&list, 2).style, command_at(&list, 0).style)
}

@(test)
test_a_new_frame_and_a_style_scope_put_blend_and_clip_back :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	push(&list, .Style)
	set_blend(&list, .Screen)
	set_clip(&list, 0, 0, 10, 10)
	circle(&list, 0, 0, 5)
	pop(&list)
	circle(&list, 0, 0, 5)
	testing.expect_value(t, command_at(&list, 0).style.blend, Blend_Mode.Screen)
	testing.expect(t, command_at(&list, 0).style.clip.on)
	testing.expect_value(t, command_at(&list, 1).style.blend, Blend_Mode.Normal)
	testing.expect(t, !command_at(&list, 1).style.clip.on)
	set_blend(&list, .Multiply)
	set_clip(&list, 0, 0, 10, 10)
	begin_frame(&list)
	circle(&list, 0, 0, 5)
	testing.expect_value(t, command_at(&list, 0).style.blend, Blend_Mode.Normal)
	testing.expect(t, !command_at(&list, 0).style.clip.on)
}

@(test)
test_a_clip_is_the_box_the_transform_gives_it :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	move(&list, 100, 50)
	grow(&list, 2, 2)
	set_clip(&list, 5, 5, 10, 20)
	testing.expect_value(t, list.style.clip, Clip{on = true, rect = {110, 60, 130, 100}})
	// A turned box clips to the upright box round it: a quarter turn swaps its sides.
	begin_frame(&list)
	turn(&list, 90)
	set_clip(&list, 0, 0, 10, 20)
	c := list.style.clip
	testing.expect(t, c.on)
	testing.expect(t, abs(c.rect[2] - c.rect[0] - 20) < 0.001)
	testing.expect(t, abs(c.rect[3] - c.rect[1] - 10) < 0.001)
}

@(test)
test_a_clip_with_numbers_that_are_not_numbers_clips_everything :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	nan := transmute(f32)u32(0x7fc00000)
	set_clip(&list, nan, 0, 10, 10)
	testing.expect_value(t, list.style.clip, Clip{on = true})
	testing.expect_value(t, scissor_for(list.style.clip, 1, {100, 100}).w, i32(0))
}

@(test)
test_a_change_of_blend_or_clip_starts_a_new_batch_of_the_same_pipeline :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	circle(&list, 0, 0, 5)
	circle(&list, 10, 0, 5)
	set_blend(&list, .Add)
	circle(&list, 20, 0, 5)
	circle(&list, 30, 0, 5)
	set_clip(&list, 0, 0, 50, 50)
	circle(&list, 40, 0, 5)
	set_clip(&list, 0, 0, 60, 50)
	circle(&list, 50, 0, 5)
	no_clip(&list)
	set_blend(&list, .Normal)
	circle(&list, 60, 0, 5)
	b := drawn(&list)
	defer batcher_destroy(&b)
	testing.expect_value(t, len(b.batches), 5)
	counts := [5]int{2, 2, 1, 1, 1}
	for batch, i in b.batches {
		testing.expect_value(t, batch.pipeline, Pipeline.Shapes)
		testing.expect_value(t, batch.count, counts[i])
	}
	testing.expect_value(t, b.batches[1].blend, Blend_Mode.Add)
	testing.expect(t, !b.batches[1].clip.on)
	testing.expect_value(t, b.batches[2].clip.rect, [4]f32{0, 0, 50, 50})
	testing.expect_value(t, b.batches[3].clip.rect, [4]f32{0, 0, 60, 50})
	testing.expect_value(t, b.batches[4].blend, Blend_Mode.Normal)
	testing.expect(t, !b.batches[4].clip.on)
}

@(test)
test_blend_and_clip_change_the_hash_so_the_gpu_copy_is_made_again :: proc(t: ^testing.T) {
	plain := fresh()
	defer destroy(&plain)
	circle(&plain, 0, 0, 5)
	blended := fresh()
	defer destroy(&blended)
	set_blend(&blended, .Multiply)
	circle(&blended, 0, 0, 5)
	clipped := fresh()
	defer destroy(&clipped)
	set_clip(&clipped, 0, 0, 5, 5)
	circle(&clipped, 0, 0, 5)
	other_clip := fresh()
	defer destroy(&other_clip)
	set_clip(&other_clip, 0, 0, 6, 5)
	circle(&other_clip, 0, 0, 5)
	hashes := [4]u64{command_hash(command_at(&plain, 0)), command_hash(command_at(&blended, 0)), command_hash(command_at(&clipped, 0)), command_hash(command_at(&other_clip, 0))}
	for a in 0 ..< 4 {
		for b in a + 1 ..< 4 {
			testing.expectf(t, hashes[a] != hashes[b], "%d and %d hash alike", a, b)
		}
	}
}

@(test)
test_text_and_pictures_batch_by_blend_and_clip_too :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	debug_text(&list, "a", 0, 0, 1)
	set_blend(&list, .Add)
	debug_text(&list, "b", 0, 10, 1)
	b := drawn(&list)
	defer batcher_destroy(&b)
	testing.expect_value(t, len(b.batches), 2)
	testing.expect_value(t, b.batches[0].pipeline, Pipeline.Text)
	testing.expect_value(t, b.batches[1].blend, Blend_Mode.Add)
}

@(test)
test_every_blend_has_its_own_blend_state :: proc(t: ^testing.T) {
	normal := blend_state_for(.Normal)
	testing.expect_value(t, normal.src_color_blendfactor, sdl.GPUBlendFactor.ONE)
	testing.expect_value(t, normal.dst_color_blendfactor, sdl.GPUBlendFactor.ONE_MINUS_SRC_ALPHA)
	testing.expect(t, normal.enable_blend)
	// Each other mode changes the colour half and leaves the alpha as normal does.
	seen := [Blend_Mode]sdl.GPUColorTargetBlendState{}
	for mode in Blend_Mode {
		state := blend_state_for(mode)
		testing.expect(t, state.enable_blend)
		testing.expect_value(t, state.src_alpha_blendfactor, normal.src_alpha_blendfactor)
		testing.expect_value(t, state.dst_alpha_blendfactor, normal.dst_alpha_blendfactor)
		testing.expect_value(t, state.alpha_blend_op, normal.alpha_blend_op)
		seen[mode] = state
	}
	for a in Blend_Mode {
		for b in Blend_Mode {
			if a < b {
				testing.expectf(t, seen[a] != seen[b], "%v and %v are the same state", a, b)
			}
		}
	}
	testing.expect_value(t, blend_state_for(.Add).dst_color_blendfactor, sdl.GPUBlendFactor.ONE)
	testing.expect_value(t, blend_state_for(.Multiply).src_color_blendfactor, sdl.GPUBlendFactor.DST_COLOR)
	testing.expect_value(t, blend_state_for(.Screen).dst_color_blendfactor, sdl.GPUBlendFactor.ONE_MINUS_SRC_COLOR)
	testing.expect_value(t, blend_state_for(.Subtract).color_blend_op, sdl.GPUBlendOp.REVERSE_SUBTRACT)
	testing.expect_value(t, blend_state_for(.Lighten).color_blend_op, sdl.GPUBlendOp.MAX)
}

@(test)
test_a_clip_becomes_a_scissor_in_device_pixels_cut_to_the_target :: proc(t: ^testing.T) {
	clip := Clip{on = true, rect = {10.4, 20.5, 50.2, 60}}
	testing.expect_value(t, scissor_for(clip, 1, {100, 100}), sdl.Rect{10, 20, 41, 40}) // rounded outwards
	testing.expect_value(t, scissor_for(clip, 2, {200, 200}), sdl.Rect{20, 41, 81, 79}) // twice the pixels
	testing.expect_value(t, scissor_for(Clip{on = true, rect = {-20, -20, 500, 500}}, 1, {100, 80}), sdl.Rect{0, 0, 100, 80}) // cut to the target
	testing.expect_value(t, scissor_for(Clip{on = true, rect = {200, 200, 300, 300}}, 1, {100, 100}).w, i32(0)) // outside: nothing
	testing.expect_value(t, scissor_for(Clip{on = true, rect = {30, 30, 10, 10}}, 1, {100, 100}).w, i32(0)) // upside down: nothing
}
