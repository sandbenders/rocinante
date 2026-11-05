// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "../gfx"
import "core:testing"

@(test)
test_stroke_takes_a_picture_as_a_statement_one_shape_or_a_group :: proc(t: ^testing.T) {
	p := run_picture_sketch(t, "paint_stroke", `photo = load "cat.png"
no fill
stroke photo
circle at 10 10 radius 5
stroke photo as tile size 20 at 3 4
circle at 20 10 radius 5
stroke red
rect at 30 10 size 5 5 stroke photo as fit
circle at 40 10 radius 5
with stroke photo as center [ circle at 50 10 radius 5 ]
circle at 60 10 radius 5`)
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	found := drawn_commands()
	if !testing.expect_value(t, len(found), 6) {
		return
	}
	image := found[0].style.stroke_image.image
	testing.expect(t, image != 0)
	testing.expect_value(t, found[0].style.stroke_image, gfx.Image_Fill{image = image})
	testing.expect_value(t, found[1].style.stroke_image, gfx.Image_Fill{image = image, fit = .Tile, tile = 20, at = {3, 4}})
	testing.expect_value(t, found[2].style.stroke_image.fit, gfx.Image_Fit.Fit) // one shape's own picture
	testing.expect_value(t, found[3].style.stroke_image.image, gfx.Image_Id(0)) // back to the red the style holds
	testing.expect_value(t, found[4].style.stroke_image.fit, gfx.Image_Fit.Center)
	testing.expect_value(t, found[5].style.stroke_image.image, gfx.Image_Id(0)) // the group is over
}

@(test)
test_background_takes_a_picture_and_a_colour_takes_it_back :: proc(t: ^testing.T) {
	p := run_picture_sketch(t, "paint_background", "photo = load \"cat.png\"\nbackground photo as tile size 40 at 1 2\ncircle at 1 1 radius 1")
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	testing.expect(t, roci.window_background_set(first_window()))
	picture := roci.recorded_background_picture(first_window())
	testing.expect(t, picture.image != 0)
	testing.expect_value(t, picture.fit, gfx.Image_Fit.Tile)
	testing.expect_value(t, picture.tile, f32(40))
	testing.expect_value(t, picture.at, [2]f32{1, 2})
}

@(test)
test_a_text_takes_a_picture_for_its_fill_as_a_statement_or_a_word :: proc(t: ^testing.T) {
	p := run_picture_sketch(t, "paint_text", `photo = load "cat.png"
text "one" at 0 0 size 30 fill photo as cover
text "two" at 0 40
fill photo as stretch
text "three" at 0 80`)
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	found := drawn_commands()
	if !testing.expect_value(t, len(found), 3) {
		return
	}
	for c in found {
		testing.expect_value(t, c.kind, gfx.Kind.Typeset)
	}
	testing.expect_value(t, found[0].style.fill_image.fit, gfx.Image_Fit.Cover)
	testing.expect_value(t, found[1].style.fill_image.image, gfx.Image_Id(0))
	testing.expect_value(t, found[2].style.fill_image.fit, gfx.Image_Fit.Stretch)
}
