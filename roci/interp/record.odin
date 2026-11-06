// SPDX-License-Identifier: 0BSD
//
// `record "clip.mp4"` and `no record`: every frame of the window as a movie (roci/record.odin).
// A plain name goes into the sketch's `output` folder, as `save` does. A recording that cannot
// start is said at once; one that fails later (ffmpeg stopped, a disk that filled) is said on
// the next frame, because that is when it is found out, and one that ends well is told to the
// console with how many frames it holds.
package interp

import "../"
import "../lang"
import "core:fmt"

RECORD_EXAMPLE :: "record \"clip.apng\""

@(private)
record_start :: proc(it: ^Interp, e: ^lang.IR, name: string) {
	it.record_span = e.span
	ok, why := roci.record(save_path(it, name))
	if !ok {
		fail(it, .Record_Failed, e.span, name, why, "", RECORD_EXAMPLE)
	}
}

// Says what became of the recordings that ended since the last frame.
@(private)
say_record_results :: proc(it: ^Interp) {
	for result in roci.take_record_results() {
		if result.ok {
			text := fmt.tprintf("recorded %d frames into %s", result.frames, result.path)
			if result.why != "" {
				text = fmt.tprintf("%s. %s", text, result.why)
			}
			notice(it, text)
			continue
		}
		fail(it, .Record_Failed, it.record_span, result.path, result.why, "", RECORD_EXAMPLE)
	}
}
