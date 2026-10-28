// SPDX-License-Identifier: 0BSD
//
// The smallest sketch: one circle. It opens the default
// window, draws it and keeps the window open until it is closed, with nothing set
// up. This is rocinante's first regression test, and it must work for ever.
//
//     odin run examples/circle            runs until the window is closed
//     odin run examples/circle -- 3       runs for 3 seconds
//
// Windows (the operating system) needs SDL3.dll beside the program.
package circle_example

import "core:os"
import "core:strconv"
import "../../roci"

main :: proc() {
	roci.circle(100, 100, 50)
	// `odin run examples/circle -- 3` shows it for 3 seconds, for scripts.
	seconds := 0
	if len(os.args) > 1 {
		seconds, _ = strconv.parse_int(os.args[1])
	}
	roci.run(frames = seconds * 60)
}
