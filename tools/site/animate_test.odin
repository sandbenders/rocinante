// SPDX-License-Identifier: 0BSD
package site_tool

import "core:testing"
import "../../roci/gfx"
import "../../roci/platform"

@(test)
uses_input_finds_whole_words_only :: proc(t: ^testing.T) {
	testing.expect(t, uses_input("circle at mouse radius 5"))
	testing.expect(t, uses_input("on touch down [ add finger.pos to dots ]"))
	testing.expect(t, uses_input("x = wheel.y"))
	testing.expect(t, uses_input("if pressed [ ]"))
	testing.expect(t, !uses_input("circle at 1 1 radius 5"))
	testing.expect(t, !uses_input("mousetrap = 1  fingers = 2"), "a longer name is not the word")
	testing.expect(t, !uses_input(""))
}

@(test)
the_visitor_clicks_for_a_quarter_of_a_second :: proc(t: ^testing.T) {
	testing.expect(t, !visitor_at(0.99, 800, 600).pressed)
	testing.expect(t, visitor_at(1.0, 800, 600).pressed)
	testing.expect(t, visitor_at(1.2, 800, 600).pressed)
	testing.expect(t, !visitor_at(1.25, 800, 600).pressed)
	testing.expect(t, visitor_at(6.0, 800, 600).pressed, "one press is a two-second drag")
	testing.expect(t, !visitor_at(7.0, 800, 600).pressed)
	for s in ([]f64{0, 2.7, 5.1, 9.9}) {
		v := visitor_at(s, 800, 600)
		testing.expectf(t, v.pos.x >= 0 && v.pos.x <= 800 && v.pos.y >= 0 && v.pos.y <= 600, "at %v s the mouse is in the window", s)
	}
}

@(test)
the_visitors_events_move_press_release_and_scroll :: proc(t: ^testing.T) {
	w := platform.Window_Id(1)
	kinds :: proc(events: []platform.Event) -> (moves, buttons, fingers, wheels: int, down: bool) {
		for e in events {
			switch v in e {
			case platform.Mouse_Moved:          moves += 1
			case platform.Mouse_Button_Changed: buttons += 1; down = v.down
			case platform.Finger_Changed:       fingers += 1
			case platform.Wheel:                wheels += 1
			case platform.Quit, platform.Close_Requested, platform.Resized, platform.Pixel_Size_Changed, platform.Scale_Changed, platform.Moved, platform.Focus_Changed, platform.Key_Changed:
			}
		}
		return
	}
	steps_per_second := ANIMATION_RATE * STEPS_PER_FRAME
	m, b, f, wh, _ := kinds(visitor_events(10, w, 800, 600))
	testing.expect(t, m == 1 && b == 0 && f == 0 && wh == 0, "an ordinary step only moves the mouse")
	down: bool
	_, b, f, _, down = kinds(visitor_events(steps_per_second, w, 800, 600)) // one second in: a click starts
	testing.expect(t, b == 1 && f == 1 && down, "the button and the finger go down together")
	_, b, f, _, _ = kinds(visitor_events(steps_per_second + 3, w, 800, 600))
	testing.expect(t, b == 0 && f == 1, "while it is down the finger moves")
	_, b, _, _, down = kinds(visitor_events(steps_per_second + 15, w, 800, 600)) // a quarter of a second later
	testing.expect(t, b == 1 && !down, "and then both come up")
	_, _, _, wh, _ = kinds(visitor_events(steps_per_second * 3, w, 800, 600))
	testing.expect_value(t, wh, 1)
}

@(test)
the_pointer_is_drawn_where_the_mouse_is :: proc(t: ^testing.T) {
	img := gfx.Image{width = 40, height = 40, pixels = make([]u8, 40 * 40 * 4, context.temp_allocator)}
	draw_pointer(img, Visitor{pos = {20, 10}}, 0.5) // a frame at half the window's size
	at :: proc(img: gfx.Image, x, y: int) -> u8 {return img.pixels[(y * img.width + x) * 4]}
	testing.expect_value(t, at(img, 11, 10), 255) // inside the arrow, just below its tip at 10, 5
	testing.expect_value(t, at(img, 35, 35), 0) // far from it, untouched
	draw_pointer(img, Visitor{pos = {1000, 1000}, pressed = true}, 1) // off the picture: nothing breaks
}

@(test)
halved_averages_each_four_pixels :: proc(t: ^testing.T) {
	img := gfx.Image{width = 2, height = 2, pixels = make([]u8, 16, context.temp_allocator)}
	for c in 0 ..< 4 {
		img.pixels[c], img.pixels[4 + c], img.pixels[8 + c], img.pixels[12 + c] = 0, 100, 200, 100
	}
	half := halved(img)
	defer gfx.image_destroy(&half)
	testing.expect(t, half.width == 1 && half.height == 1)
	testing.expect_value(t, half.pixels[0], 100)
}
