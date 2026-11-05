// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "../gfx"
import "../lang"
import "core:os"
import "core:testing"
import "../platform"

// The commands of the first window, whole, in the order they were drawn.
drawn_commands :: proc() -> []gfx.Command {
	return roci.recorded(first_window())
}

@(test)
test_blend_is_a_style_that_lasts_until_it_is_changed :: proc(t: ^testing.T) {
	p := run_text(t, "circle at 10 10 radius 5\nblend add\ncircle at 20 10 radius 5\nblend multiply\ncircle at 30 10 radius 5\nblend normal\ncircle at 40 10 radius 5")
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	found := drawn_commands()
	if !testing.expect_value(t, len(found), 4) {
		return
	}
	want := [4]gfx.Blend_Mode{.Normal, .Add, .Multiply, .Normal}
	for w, i in want {
		testing.expect_value(t, found[i].style.blend, w)
	}
}

@(test)
test_one_shape_can_say_its_blend_and_leave_the_style_alone :: proc(t: ^testing.T) {
	p := run_text(t, "circle at 10 10 radius 5 blend screen\ncircle at 20 10 radius 5\nrect at 0 0 size 5 5 blend add\ntext \"hi\" at 0 20 blend subtract")
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	found := drawn_commands()
	if !testing.expect(t, len(found) >= 4) {
		return
	}
	testing.expect_value(t, found[0].style.blend, gfx.Blend_Mode.Screen)
	testing.expect_value(t, found[1].style.blend, gfx.Blend_Mode.Normal)
	testing.expect_value(t, found[2].style.blend, gfx.Blend_Mode.Add)
	testing.expect_value(t, found[3].style.blend, gfx.Blend_Mode.Subtract)
}

@(test)
test_with_can_blend_a_group_and_a_blend_word_may_be_a_verb :: proc(t: ^testing.T) {
	// `add` is a verb, and here it is the word `blend` asks for.
	p := run_text(t, "with blend add [\n  circle at 10 10 radius 5\n]\ncircle at 20 10 radius 5\nwith fill red blend lighten [ circle at 30 10 radius 5 ]")
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	found := drawn_commands()
	if !testing.expect_value(t, len(found), 3) {
		return
	}
	testing.expect_value(t, found[0].style.blend, gfx.Blend_Mode.Add)
	testing.expect_value(t, found[1].style.blend, gfx.Blend_Mode.Normal)
	testing.expect_value(t, found[2].style.blend, gfx.Blend_Mode.Lighten)
}

@(test)
test_a_picture_is_blended_by_its_own_word :: proc(t: ^testing.T) {
	p := run_picture_sketch(t, "blend_picture", "photo = load \"cat.png\"\nimage photo at 0 0 blend add\nimage photo at 5 5")
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	found := image_commands()
	defer delete(found)
	if testing.expect_value(t, len(found), 2) {
		testing.expect_value(t, found[0].style.blend, gfx.Blend_Mode.Add)
		testing.expect_value(t, found[1].style.blend, gfx.Blend_Mode.Normal)
	}
}

@(test)
test_clip_keeps_drawing_in_a_box_until_no_clip :: proc(t: ^testing.T) {
	p := run_text(t, "circle at 1 1 radius 1\nclip at 10 20 size 30 40\ncircle at 2 2 radius 1\nclip at { 5, 6 } size { 7, 8 }\ncircle at 3 3 radius 1\nclip at 1 2 size 3 4\ncircle at 4 4 radius 1\nno clip\ncircle at 5 5 radius 1")
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	found := drawn_commands()
	if !testing.expect_value(t, len(found), 5) {
		return
	}
	testing.expect(t, !found[0].style.clip.on)
	testing.expect_value(t, found[1].style.clip, gfx.Clip{on = true, rect = {10, 20, 40, 60}})
	testing.expect_value(t, found[2].style.clip, gfx.Clip{on = true, rect = {5, 6, 12, 14}})
	testing.expect_value(t, found[3].style.clip, gfx.Clip{on = true, rect = {1, 2, 4, 6}})
	testing.expect(t, !found[4].style.clip.on)
}

@(test)
test_a_clip_follows_the_transform_and_is_restored_by_a_scope :: proc(t: ^testing.T) {
	p := run_text(t, "push [\n  move 100 100\n  clip at 0 0 size 10 10\n  circle at 5 5 radius 2\n]\ncircle at 5 5 radius 2")
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	found := drawn_commands()
	if !testing.expect_value(t, len(found), 2) {
		return
	}
	testing.expect_value(t, found[0].style.clip, gfx.Clip{on = true, rect = {100, 100, 110, 110}})
	testing.expect(t, !found[1].style.clip.on)
}

@(test)
test_a_frame_starts_with_normal_blend_and_no_clip :: proc(t: ^testing.T) {
	p := run_text(t, "draw [\n  circle at 1 1 radius 1\n  blend add\n  clip at 0 0 size 5 5\n]", 3)
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	found := drawn_commands()
	if testing.expect_value(t, len(found), 1) {
		testing.expect_value(t, found[0].style.blend, gfx.Blend_Mode.Normal)
		testing.expect(t, !found[0].style.clip.on)
	}
}

@(test)
test_a_word_that_is_no_blend_is_said_with_the_ones_there_are :: proc(t: ^testing.T) {
	p, ok := load("test.roci", "blend glow\ncircle at 1 1 radius 1 blend sub")
	defer finish(p)
	testing.expect(t, !ok)
	count := 0
	for d in p.checked.diagnostics {
		if d.id == .Unknown_Choice {
			count += 1
		}
	}
	testing.expect_value(t, count, 2)
	_ = lang.Message_Id.Unknown_Choice
}

@(test)
test_the_blend_example_draws_each_pair_blended_and_moves_its_clip_with_the_mouse :: proc(t: ^testing.T) {
	text, read := os.read_entire_file("examples/blend/sketch.roci", context.temp_allocator)
	testing.expect(t, read == nil)
	p := run_text(t, string(text), 2)
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	seen: [gfx.Blend_Mode]bool
	for c in drawn_commands() {
		seen[c.style.blend] = true
	}
	for mode in gfx.Blend_Mode {
		testing.expectf(t, seen[mode], "no shape is drawn with %v", mode)
	}
	clip_of :: proc() -> (box: [4]f32, found: bool) {
		for c in drawn_commands() {
			if c.style.clip.on {
				return c.style.clip.rect, true
			}
		}
		return
	}
	box, found := clip_of()
	testing.expect(t, found)
	testing.expect_value(t, box, [4]f32{240, 250, 400, 370}) // around the spot it starts at
	w := first_window()
	roci.step({platform.Mouse_Moved{window = platform.Window_Id(w), x = 100, y = 300}, click_event(w, 100, 300)})
	box, found = clip_of()
	testing.expect(t, found)
	testing.expect_value(t, box, [4]f32{20, 240, 180, 360})
}
