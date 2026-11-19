// SPDX-License-Identifier: 0BSD
package roci

import "core:testing"
import "gfx"

// `w` by `h` of one colour.
@(private = "file")
flat_frame :: proc(w, h: int, r, g, b: u8) -> []u8 {
	pixels := make([]u8, w * h * 4, context.temp_allocator)
	for i in 0 ..< w * h {
		pixels[i * 4], pixels[i * 4 + 1], pixels[i * 4 + 2], pixels[i * 4 + 3] = r, g, b, 255
	}
	return pixels
}

@(test)
test_the_webcam_is_a_dark_picture_when_no_camera_is_open :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	defer gfx.images_stop()
	picture := webcam()
	testing.expect(t, picture != 0)
	testing.expect_value(t, image_size(picture), [2]f64{WEBCAM_STAND_IN_WIDTH, WEBCAM_STAND_IN_HEIGHT})
	c, ok := pixel_of(picture, 10, 10)
	testing.expect(t, ok)
	testing.expect_value(t, c, Colour{64, 64, 64, 255})
	testing.expect_value(t, webcam(), picture) // the same one again
	step()
	testing.expect_value(t, webcam(), picture) // and the next frame, with no camera to change it
	testing.expect_value(t, webcam_problem(), Webcam_Problem.None) // a headless run has none, and says nothing
}

@(test)
test_a_frame_from_the_camera_is_what_the_webcam_shows :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	defer gfx.images_stop()
	feed_webcam(3, 2, flat_frame(3, 2, 200, 100, 50))
	picture := webcam()
	testing.expect_value(t, image_size(picture), [2]f64{3, 2})
	c, _ := pixel_of(picture, 2, 1)
	testing.expect_value(t, c, Colour{200, 100, 50, 255})
	testing.expect_value(t, webcam(), picture) // one picture for the whole frame
}

@(test)
test_the_webcam_takes_a_new_frame_each_frame_and_a_kept_one_stays :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	defer gfx.images_stop()
	feed_webcam(2, 2, flat_frame(2, 2, 255, 0, 0))
	first := webcam()
	feed_webcam(2, 2, flat_frame(2, 2, 0, 255, 0)) // arrives while the frame is still going
	testing.expect_value(t, webcam(), first)       // and waits for the next one
	step()
	second := webcam()
	testing.expect(t, second != first)
	c, _ := pixel_of(second, 0, 0)
	testing.expect_value(t, c, Colour{0, 255, 0, 255})
	c, _ = pixel_of(first, 0, 0) // the one kept from before is as it was
	testing.expect_value(t, c, Colour{255, 0, 0, 255})
	step()
	testing.expect_value(t, webcam(), second) // no new frame: the last one stays
}

@(test)
test_frames_nothing_uses_are_let_go_but_the_newest_stays :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	defer gfx.images_stop()
	feed_webcam(2, 2, flat_frame(2, 2, 1, 2, 3))
	old := webcam()
	for i in 0 ..< WEBCAM_KEEP_FRAMES + 5 {
		step()
		feed_webcam(2, 2, flat_frame(2, 2, u8(i), 0, 0))
		webcam()
	}
	testing.expect(t, gfx.image_data(old) == nil, "an old frame nobody drew is let go")
	newest := webcam()
	testing.expect(t, gfx.image_data(newest) != nil)
	testing.expect(t, len(webcam_frames) <= WEBCAM_KEEP_FRAMES + 2, "the frames do not pile up")
}

@(test)
test_a_snapshot_that_is_used_is_not_let_go :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	defer gfx.images_stop()
	feed_webcam(2, 2, flat_frame(2, 2, 9, 9, 9))
	snapshot := webcam()
	for i in 0 ..< WEBCAM_KEEP_FRAMES + 5 {
		step()
		gfx.image_touch(snapshot) // drawn every frame
		feed_webcam(2, 2, flat_frame(2, 2, u8(i), 0, 0))
		webcam()
	}
	testing.expect(t, gfx.image_data(snapshot) != nil)
}

@(test)
test_a_frame_of_the_wrong_size_is_ignored :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	defer gfx.images_stop()
	feed_webcam(0, 0, nil)
	feed_webcam(2, 2, make([]u8, 5, context.temp_allocator))
	feed_webcam(-1, 2, make([]u8, 8, context.temp_allocator))
	testing.expect_value(t, image_size(webcam()), [2]f64{WEBCAM_STAND_IN_WIDTH, WEBCAM_STAND_IN_HEIGHT})
}

@(test)
test_the_webcam_says_why_it_cannot_be_used :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	defer gfx.images_stop()
	testing.expect_value(t, webcam_problem(), Webcam_Problem.None)
	set_webcam_problem(.No_Camera)
	testing.expect_value(t, webcam_problem(), Webcam_Problem.No_Camera)
	set_webcam_problem(.Denied)
	testing.expect_value(t, webcam_problem(), Webcam_Problem.Denied)
	set_webcam_problem(.None)
	testing.expect_value(t, webcam_problem(), Webcam_Problem.None)
}

@(test)
test_the_webcam_after_every_picture_was_let_go_is_a_picture_again :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	feed_webcam(2, 2, flat_frame(2, 2, 7, 7, 7))
	before := webcam()
	gfx.images_stop() // as a restart does
	after := webcam()
	testing.expect(t, gfx.image_data(after) != nil)
	testing.expect(t, gfx.image_data(before) == nil || before == after)
	gfx.images_stop()
}

@(test)
test_the_webcam_is_in_the_c_api :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	defer gfx.images_stop()
	picture := abi_webcam()
	testing.expect(t, picture != 0)
	testing.expect_value(t, Image(u32(picture)), webcam())
	testing.expect_value(t, abi_image_width(picture), WEBCAM_STAND_IN_WIDTH)
}

@(test)
test_the_cameras_are_listed_and_one_is_picked :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	defer gfx.images_stop()
	testing.expect_value(t, len(webcam_cameras(context.temp_allocator)), 0) // a headless run has none
	set_webcam_cameras({"FaceTime HD Camera", "USB Capture"})
	names := webcam_cameras(context.temp_allocator)
	if testing.expect_value(t, len(names), 2) {
		testing.expect_value(t, names[0], "FaceTime HD Camera")
		testing.expect_value(t, names[1], "USB Capture")
	}
	testing.expect_value(t, webcam_picked(context.temp_allocator), "")
	webcam_pick(2)
	testing.expect_value(t, webcam_picked(context.temp_allocator), "2")
	webcam_pick("usb")
	testing.expect_value(t, webcam_picked(context.temp_allocator), "usb")
	webcam_pick("") // back to the first
	testing.expect_value(t, webcam_picked(context.temp_allocator), "")
	webcam_pick(-3)
	testing.expect_value(t, webcam_picked(context.temp_allocator), "")
}

@(test)
test_picking_a_camera_shows_the_stand_in_until_its_frame_comes :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	defer gfx.images_stop()
	feed_webcam(2, 2, flat_frame(2, 2, 1, 2, 3))
	live := webcam()
	testing.expect_value(t, image_size(live), [2]f64{2, 2})
	webcam_pick(2)
	picture := webcam()
	testing.expect_value(t, image_size(picture), [2]f64{WEBCAM_STAND_IN_WIDTH, WEBCAM_STAND_IN_HEIGHT})
	feed_webcam(3, 3, flat_frame(3, 3, 4, 5, 6)) // the chosen camera's first frame, which comes in the next frame
	step()
	testing.expect_value(t, image_size(webcam()), [2]f64{3, 3})
}

@(test)
test_the_camera_can_say_why_its_pictures_cannot_be_read :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	set_webcam_problem(.Unreadable, "no conversion")
	testing.expect_value(t, webcam_problem(), Webcam_Problem.Unreadable)
	testing.expect_value(t, webcam_error(), "no conversion")
	set_webcam_problem(.Not_Found)
	testing.expect_value(t, webcam_problem(), Webcam_Problem.Not_Found)
	set_webcam_problem(.None)
	testing.expect_value(t, webcam_error(), "")
}

@(test)
test_the_camera_functions_are_in_the_c_api :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	set_webcam_cameras({"Built-in", "External"})
	testing.expect_value(t, abi_webcam_camera_count(), 2)
	out: [16]u8
	testing.expect_value(t, abi_webcam_camera_name(1, raw_data(out[:]), 16), 8)
	testing.expect_value(t, string(cstring(raw_data(out[:]))), "External")
	testing.expect_value(t, abi_webcam_camera_name(2, raw_data(out[:]), 16), 0)
	testing.expect_value(t, abi_webcam_camera_name(0, nil, 16), 0)
	testing.expect_value(t, abi_webcam_camera_name(0, raw_data(out[:]), 0), 0)
	testing.expect_value(t, abi_webcam_camera_name(0, raw_data(out[:]), 4), 3) // cut to fit, with its end
	abi_webcam_pick_number(2)
	testing.expect_value(t, webcam_picked(context.temp_allocator), "2")
	abi_webcam_pick("ext")
	testing.expect_value(t, webcam_picked(context.temp_allocator), "ext")
}
