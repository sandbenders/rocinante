// SPDX-License-Identifier: 0BSD
//
// `webcam`: the picture of the computer's camera (roci/webcam.odin makes it). When the camera
// cannot be used it says why, once, at the line that asked, and the sketch goes on with the
// dark picture.
package interp

import "core:fmt"
import "core:strings"

import "../"
import "../lang"

@(private)
webcam_value :: proc(it: ^Interp, span: lang.Span) -> Value {
	picture := roci.webcam()
	stand_in := "photo = load \"photo.png\""
	switch roci.webcam_problem() {
	case .None:
	case .No_Camera:
		fail(it, .Webcam_Unavailable, span, "no camera is connected", "Plug one in and run the sketch again.", "", stand_in)
	case .Denied:
		fail(it, .Webcam_Unavailable, span, "it was not allowed", "Allow rocinante (or the program that runs it, such as your terminal) to use the camera in the system's privacy settings, and run the sketch again.", "", stand_in)
	case .Not_Found:
		picked := roci.webcam_picked()
		reason := fmt.tprintf("there is no camera %s", picked) if len(picked) > 0 && picked[0] >= '0' && picked[0] <= '9' else fmt.tprintf("no camera has `%s` in its name", picked)
		names := roci.webcam_cameras(context.temp_allocator)
		known := strings.join(names, ", ", context.temp_allocator) if len(names) > 0 else "none"
		fail(it, .Webcam_Unavailable, span, reason, fmt.tprintf("The cameras are: %s. `webcam cameras` lists them and `webcam pick` chooses one.", known), "", "webcam pick 1")
	case .Unreadable:
		fail(it, .Webcam_Unavailable, span, "its pictures cannot be read", fmt.tprintf("The camera said: %s. Another camera may work: `webcam cameras` lists them and `webcam pick` chooses one.", roci.webcam_error()), "", "webcam pick 2")
	}
	return picture
}

// `webcam pick 2` or `webcam pick "USB"`: a number is the place in `webcam cameras`, a text a part of a name.
@(private)
webcam_pick_verb :: proc(it: ^Interp, call: lang.IR_Call) {
	#partial switch pick in eval(it, call.args[0]) {
	case f64:
		roci.webcam_pick(int(pick))
	case string:
		roci.webcam_pick(pick)
	}
}

// `webcam cameras`: the names as a list of text.
@(private)
webcam_cameras_verb :: proc(it: ^Interp) -> Value {
	names := roci.webcam_cameras(context.temp_allocator)
	items := make([]Value, len(names), context.temp_allocator)
	for n, i in names {
		items[i] = strings.clone(n, it.alloc)
	}
	return new_list(it, ..items)
}
