// SPDX-License-Identifier: 0BSD
//
// Box2D, built as a static library by tools/physics-libs.sh into .cache/physics. Every program with 2D physics
// links it, and `roci` is one.
package build

import "core:fmt"
import "core:os"
import "core:time"

import "../tools/term"

PHYSICS_LIBRARY :: ".cache/physics/lib/libbox2d.a" when ODIN_OS != .Windows else ".cache/physics/lib/box2d.lib"

// Builds the library (`physics-libs`).
physics_libs :: proc() -> bool {
	state, stdout, stderr, err := os.process_exec({command = {"sh", "tools/physics-libs.sh"}}, context.allocator)
	fmt.print(string(stdout))
	if err != nil || state.exit_code != 0 {
		fmt.eprint(string(stderr))
		fmt.eprintfln("%s", term.err("physics-libs failed", .Bold_Red))
		return false
	}
	return true
}

// Builds the library before the packages are checked when it is missing or older than the scripts that make it (a
// clone that has built it since the scripts last changed skips this).
check_physics :: proc() -> bool {
	if os.exists(PHYSICS_LIBRARY) {
		library, library_err := os.stat(PHYSICS_LIBRARY, context.temp_allocator)
		fresh := library_err == nil
		for name in ([]string{"tools/physics-libs.sh", "tools/fetch-physics.sh"}) {
			source, source_err := os.stat(name, context.temp_allocator)
			if source_err == nil && time.diff(source.modification_time, library.modification_time) < 0 {
				fresh = false
			}
		}
		if fresh {
			return true
		}
	}
	fmt.printfln("%s", term.out("== building Box2D (tools/physics-libs.sh)", .Bold_Cyan))
	return physics_libs()
}
