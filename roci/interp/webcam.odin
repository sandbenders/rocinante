// SPDX-License-Identifier: 0BSD
//
// `webcam`: the picture of the computer's camera (roci/webcam.odin makes it). When the camera
// cannot be used it says why, once, at the line that asked, and the sketch goes on with the
// dark picture.
package interp

import "../lang"
import "../"

@(private)
webcam_value :: proc(it: ^Interp, span: lang.Span) -> Value {
	picture := roci.webcam()
	switch roci.webcam_problem() {
	case .None:
	case .No_Camera:
		fail(it, .Webcam_Unavailable, span, "no camera is connected", "Plug one in and run the sketch again.", "", "photo = load \"photo.png\"")
	case .Denied:
		fail(it, .Webcam_Unavailable, span, "it was not allowed", "Allow rocinante (or the program that runs it, such as your terminal) to use the camera in the system's privacy settings, and run the sketch again.", "", "photo = load \"photo.png\"")
	}
	return picture
}
