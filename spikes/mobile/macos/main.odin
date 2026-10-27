// SPDX-License-Identifier: 0BSD
//
// Runs the phones' sketch on the desktop, so it can be tried without a phone:
// `odin run spikes/mobile/macos`. It stops after five seconds.
package spike_macos

import sketch "../sketch"

main :: proc() {
	sketch.run(frames = 300)
}
