// SPDX-License-Identifier: 0BSD
//
// The installer is a Windows program; elsewhere it only says so, so the package is still checked on every system.
#+build !windows
package setup

import "core:fmt"
import "core:os"

main :: proc() {
	fmt.eprintln("This installer puts an app on a Windows computer, and runs only there.")
	os.exit(2)
}
