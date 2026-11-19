// SPDX-License-Identifier: 0BSD
package interp

import "core:testing"

import "../"
import "../gfx"
import "../lang"

// `w` by `h` of one colour.
@(private = "file")
flat :: proc(w, h: int, r, g, b: u8) -> []u8 {
	pixels := make([]u8, w * h * 4, context.temp_allocator)
	for i in 0 ..< w * h {
		pixels[i * 4], pixels[i * 4 + 1], pixels[i * 4 + 2], pixels[i * 4 + 3] = r, g, b, 255
	}
	return pixels
}

// Loads and starts a sketch in a headless run that is already going, so the camera has been given what it shows first.
@(private = "file")
start_fed :: proc(t: ^testing.T, text: string, frames := 0) -> ^Interp {
	p, ok := load("test.roci", text)
	testing.expectf(t, ok, "the sketch has errors")
	start(p)
	for _ in 0 ..< frames {
		roci.step()
	}
	return p
}

// `webcam` is a picture a sketch can read the size and the pixels of; a headless run has no camera, so
// it is the dark stand-in.
@(test)
test_webcam_is_a_picture_with_a_size :: proc(t: ^testing.T) {
	text := `w = webcam.width
h = webcam.height
same = webcam is webcam
draw [ image webcam at 0 0 ]
`
	p := run_text(t, text)
	defer finish(p)
	defer gfx.images_stop()
	testing.expect_value(t, as_number(global_named(p, "w")), f64(roci.WEBCAM_STAND_IN_WIDTH))
	testing.expect_value(t, as_number(global_named(p, "h")), f64(roci.WEBCAM_STAND_IN_HEIGHT))
	testing.expect_value(t, len(p.errors), 0)
}

// A frame the camera gives is the picture, in the same size, and a picture kept in a variable stays what it was.
@(test)
test_webcam_frames_are_pictures_and_a_kept_one_is_a_snapshot :: proc(t: ^testing.T) {
	text := `live = webcam
kept = webcam
on key "k" [ kept = webcam ]
draw [ live = webcam ]
`
	roci.start_headless(1)
	roci.feed_webcam(4, 3, flat(4, 3, 255, 0, 0))
	p := start_fed(t, text)
	defer finish(p)
	defer gfx.images_stop()
	testing.expect_value(t, roci.image_size(as_image(global_named(p, "live"))), [2]f64{4, 3})
	first := as_image(global_named(p, "kept"))
	roci.feed_webcam(4, 3, flat(4, 3, 0, 0, 255))
	roci.step()
	live := as_image(global_named(p, "live"))
	testing.expect(t, live != first, "the next frame is another picture")
	c, _ := roci.pixel_of(live, 1, 1)
	testing.expect_value(t, c, roci.Colour{0, 0, 255, 255})
	c, _ = roci.pixel_of(first, 1, 1)
	testing.expect_value(t, c, roci.Colour{255, 0, 0, 255}) // the one kept is as it was
	testing.expect_value(t, len(p.errors), 0)
}

// The webcam example keeps a snapshot at each click, four at most, each the picture of its moment.
@(test)
test_the_webcam_example_keeps_snapshots :: proc(t: ^testing.T) {
	roci.start_headless(1)
	roci.feed_webcam(8, 6, flat(8, 6, 10, 20, 30))
	p := start_fed(t, example_text("webcam"), 2)
	defer finish(p)
	defer gfx.images_stop()
	w := first_window()
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, len(as_list(global_named(p, "shots")).items), 0)
	for i in 0 ..< 6 {
		roci.feed_webcam(8, 6, flat(8, 6, u8(i * 40), 0, 0))
		roci.step({click_event(w, 5, 5)})
		roci.step({click_event(w, 5, 5, false)})
	}
	shots := as_list(global_named(p, "shots"))
	if testing.expect_value(t, len(shots.items), 4) {
		// the oldest were let go: what is left are the last four clicks, in order
		for shot, i in shots.items {
			c, _ := roci.pixel_of(as_image(shot), 0, 0)
			testing.expect_value(t, c.r, f32((i + 2) * 40))
		}
	}
	commands := roci.recorded(w)
	testing.expect(t, len(commands) > 0)
	testing.expect_value(t, len(p.errors), 0)
}

// A camera that cannot be used is said once, at the line that read `webcam`, and the sketch goes on.
@(test)
test_a_camera_that_cannot_be_used_is_said_once :: proc(t: ^testing.T) {
	roci.start_headless(1)
	roci.set_webcam_problem(.No_Camera)
	defer roci.set_webcam_problem(.None)
	p := start_fed(t, "draw [ image webcam at 0 0 ]", 5)
	defer finish(p)
	defer gfx.images_stop()
	if testing.expect_value(t, len(p.errors), 1) {
		testing.expect_value(t, p.errors[0].id, lang.Message_Id.Webcam_Unavailable)
	}
}

// `webcam cameras` lists the cameras by name, `webcam pick` chooses by number or by part of a name.
@(test)
test_webcam_cameras_and_pick_in_a_sketch :: proc(t: ^testing.T) {
	roci.start_headless(1)
	roci.set_webcam_cameras({"Built-in", "USB Camera"})
	p := start_fed(t, `names = webcam cameras
count_of = count names
second = item 2 of names
webcam pick 2
webcam pick "usb"
draw [ image webcam at 0 0 ]
`)
	defer finish(p)
	defer gfx.images_stop()
	testing.expect_value(t, as_number(global_named(p, "count_of")), 2)
	testing.expect_value(t, as_text(global_named(p, "second")), "USB Camera")
	testing.expect_value(t, roci.webcam_picked(context.temp_allocator), "usb")
	testing.expect_value(t, len(p.errors), 0)
}

// Writing a snapshot as `add webcam to shots` is the verb `add` and the value `webcam`, not a `webcam` verb.
@(test)
test_add_webcam_to_a_list_adds_the_picture :: proc(t: ^testing.T) {
	roci.start_headless(1)
	p := start_fed(t, "shots = []\nadd webcam to shots\nn = count shots\n")
	defer finish(p)
	defer gfx.images_stop()
	testing.expect_value(t, as_number(global_named(p, "n")), 1)
}

// With cameras to choose from, the example's drop-down starts on the first and picks it by name.
@(test)
test_the_webcam_example_picks_the_camera_of_its_drop_down :: proc(t: ^testing.T) {
	roci.start_headless(1)
	roci.set_webcam_cameras({"Built-in", "USB Camera"})
	p := start_fed(t, example_text("webcam"), 3)
	defer finish(p)
	defer gfx.images_stop()
	testing.expect_value(t, as_text(global_named(p, "chosen")), "Built-in")
	testing.expect_value(t, roci.webcam_picked(context.temp_allocator), "Built-in")
	testing.expect_value(t, len(p.errors), 0)
}
