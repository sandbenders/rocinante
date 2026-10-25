// SPDX-License-Identifier: 0BSD
//
// Runs the shared spike code on the desktop (here with Metal), so the shaders
// can be tried without a phone: `odin run spikes/mobile/macos`. It stops after
// five seconds.
package spike_macos

import "core:os"
import shared "../shared"

main :: proc() {
	if !shared.run({.MSL}, 5000) {
		os.exit(1)
	}
}
