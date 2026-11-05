// SPDX-License-Identifier: 0BSD
package roci

import "core:testing"

// A picture of `w` by `h` pixels, solid (alpha `a`) inside the box x0..x1, y0..y1.
@(private = "file")
picture_with_box :: proc(w, h, x0, y0, x1, y1: int, a: u8) -> Image {
	pixels := make([]u8, w * h * 4, context.temp_allocator)
	for y in y0 ..< y1 {
		for x in x0 ..< x1 {
			pixels[(y * w + x) * 4 + 3] = a
		}
	}
	id, _ := add_image_pixels(w, h, pixels)
	return id
}

@(test)
test_the_outline_of_a_box_is_its_corners_where_the_picture_is_drawn :: proc(t: ^testing.T) {
	defer shutdown()
	picture := picture_with_box(10, 10, 2, 3, 6, 8, 255)
	points := outline_of(picture)
	defer delete(points)
	testing.expect_value(t, len(points), 4)
	for p in points {
		testing.expect(t, p.x == 2 || p.x == 6)
		testing.expect(t, p.y == 3 || p.y == 8)
	}
	moved := outline_of(picture, at = {100, 50})
	defer delete(moved)
	for p in moved {
		testing.expect(t, p.x == 102 || p.x == 106)
		testing.expect(t, p.y == 53 || p.y == 58)
	}
	doubled := outline_of(picture, size = [2]f64{20, 20})
	defer delete(doubled)
	for p in doubled {
		testing.expect(t, p.x == 4 || p.x == 12)
		testing.expect(t, p.y == 6 || p.y == 16)
	}
}

@(test)
test_a_pixel_is_solid_when_it_is_more_solid_than_the_alpha_asked :: proc(t: ^testing.T) {
	defer shutdown()
	faint := picture_with_box(4, 4, 0, 0, 4, 4, 51) // 20 percent
	none := outline_of(faint) // more than 50 percent
	testing.expect(t, none == nil)
	some := outline_of(faint, alpha = 10)
	defer delete(some)
	testing.expect_value(t, len(some), 4)
	any := outline_of(faint, alpha = 0)
	defer delete(any)
	testing.expect_value(t, len(any), 4)
	solid := picture_with_box(4, 4, 0, 0, 4, 4, 255)
	nothing := outline_of(solid, alpha = 100) // nothing is more solid than all of it
	testing.expect(t, nothing == nil)
	over := outline_of(solid, alpha = 250) // clamped to 100
	testing.expect(t, over == nil)
}

@(test)
test_there_is_no_outline_of_what_is_no_picture :: proc(t: ^testing.T) {
	testing.expect(t, outline_of(0) == nil)
	testing.expect(t, outline_of(Image(9999)) == nil)
	defer shutdown()
	blank := picture_with_box(3, 3, 0, 0, 0, 0, 0)
	testing.expect(t, outline_of(blank) == nil)
}
