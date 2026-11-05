// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "../folder"
import "../gfx"
import "../lang"
import "core:os"
import "core:testing"

// Runs a sketch in a folder whose `assets/images/block.png` is 10 by 10 pixels, solid
// (the given alpha) in the box from 2, 3 to 6, 8 and clear everywhere else.
run_block_sketch :: proc(t: ^testing.T, folder_name, text: string, alpha: u8 = 255) -> ^Interp {
	root := concat("output/tests/", folder_name)
	_ = os.remove_all(root)
	testing.expect(t, folder.ensure_directory(concat(root, "/assets/images")))
	pixels := make([]u8, 10 * 10 * 4, context.temp_allocator)
	for y in 3 ..< 8 {
		for x in 2 ..< 6 {
			pixels[(y * 10 + x) * 4 + 3] = alpha
		}
	}
	png, ok := gfx.png_encode(gfx.Image{10, 10, pixels})
	testing.expect(t, ok)
	defer delete(png)
	testing.expect(t, os.write_entire_file(concat(root, "/assets/images/block.png"), png) == nil)
	path := concat(root, "/sketch.roci")
	testing.expect(t, os.write_entire_file(path, transmute([]byte)text) == nil)
	roci.start_headless(1)
	p, loaded := load(path, text)
	if !testing.expectf(t, loaded, "the sketch has errors:\n%s", lang.render_all(p.src, p.checked.diagnostics, context.temp_allocator)) {
		return p
	}
	watch(p, path)
	start(p)
	return p
}

@(test)
test_the_outline_of_a_picture_is_a_list_of_corners_where_it_is_drawn :: proc(t: ^testing.T) {
	p := run_block_sketch(t, "outline_corners", `photo = load "block.png"
corners = outline photo at { 100, 50 }
print (count corners)
for each c in corners [ print c ]`)
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	lines := printed(p)
	testing.expect(t, len(lines) > 0 && lines[0] == '4', "the box has four corners")
	for corner in ([]string{"{ 102, 53 }", "{ 106, 53 }", "{ 106, 58 }", "{ 102, 58 }"}) {
		testing.expectf(t, contains_line(lines, corner), "%s is a corner:\n%s", corner, lines)
	}
}

@(test)
test_at_and_size_move_and_stretch_the_outline_like_image_does :: proc(t: ^testing.T) {
	p := run_block_sketch(t, "outline_words", `photo = load "block.png"
a = outline photo at 100 50
b = outline photo at { 100, 50 } size { 20, 20 }
c = outline photo size 5 5
print (item 1 of a)
print (item 3 of b)
print (item 3 of c)`)
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, printed(p), "{ 106, 53 }\n{ 104, 66 }\n{ 1, 4 }")
}

@(test)
test_a_picture_outline_is_a_shape_the_collision_verbs_use :: proc(t: ^testing.T) {
	p := run_block_sketch(t, "outline_collision", `photo = load "block.png"
hull = { points: outline photo at { 100, 50 } }
whole = { pos: { 100, 50 }, size: { photo.width, photo.height } }
inside_block = { pos: { 104, 55 }, radius: 1 }
in_corner = { pos: { 101, 51 }, radius: 0.5 }
print (touching inside_block hull)
print (touching in_corner hull)
print (touching in_corner whole)
print (inside { 104, 55 } hull)`)
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, printed(p), "true\nfalse\ntrue\ntrue")
}

@(test)
test_alpha_says_how_solid_a_pixel_has_to_be :: proc(t: ^testing.T) {
	p := run_block_sketch(t, "outline_alpha", `photo = load "block.png"
print (count (outline photo))
print (count (outline photo alpha 10))
print (count (outline photo alpha 0))`, 51) // 20 percent
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, printed(p), "0\n4\n4")
}

@(test)
test_a_picture_that_is_not_there_has_an_empty_outline :: proc(t: ^testing.T) {
	p := run_block_sketch(t, "outline_missing", `photo = load "nothing.png"
print (count (outline photo))
c = canvas 20 20
print (count (outline c))`)
	defer finish(p)
	// The missing picture is said once; the sketch carries on with empty outlines.
	testing.expect_value(t, printed(p), "0\n0")
}

contains_line :: proc(text, line: string) -> bool {
	start := 0
	for i in 0 ..= len(text) {
		if i == len(text) || text[i] == '\n' {
			if text[start:i] == line {
				return true
			}
			start = i + 1
		}
	}
	return false
}
