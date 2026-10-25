// SPDX-License-Identifier: 0BSD
//
// Spike 2, iOS half (CLAUDE.md section 8, Phase 0): an Odin executable for the
// iPhone. SDL starts UIKit's application loop and calls sdl_main from it; the
// window and GPU work is in ../shared. Build and install it with
// spikes/mobile/ios/build.sh.
package spike_ios

import "base:runtime"
import "core:c"
import shared "../shared"
import sdl "vendor:sdl3"

sdl_main :: proc "c" (argc: c.int, argv: [^]cstring) -> c.int {
	context = runtime.default_context()
	return 0 if shared.run({.MSL}) else 1
}

main :: proc() {
	sdl.RunApp(0, nil, sdl_main, nil)
}
