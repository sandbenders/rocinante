// SPDX-License-Identifier: 0BSD
//
// The sound file decoders: miniaudio's and stb_vorbis from the vendor folder of the Odin in use,
// built by tools/sound-libs.sh into .cache/sound.
package build

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

import "../tools/term"

SOUND_LIBRARY :: ".cache/sound/libroci_sound.a" when ODIN_OS != .Windows else ".cache/sound/roci_sound.lib"

// Builds the library (`sound-libs`).
sound_libs :: proc() -> bool {
	// On Windows the script runs in Git Bash and builds with MSVC, whose cl and lib must be on the PATH.
	state, stdout, stderr, err := os.process_exec({command = {"sh", "tools/sound-libs.sh"}}, context.allocator)
	fmt.print(string(stdout))
	if err != nil || state.exit_code != 0 {
		fmt.eprint(string(stderr))
		fmt.eprintfln("%s", term.err("sound-libs failed", .Bold_Red))
		return false
	}
	return true
}

// Every program that plays a sound links the decoders, and `roci` is one, so the library is
// built before the packages are checked when it is missing or older than its source (the pipelines
// and a clone that has built it since the source last changed skip this).
check_sound :: proc() -> bool {
	if os.exists(SOUND_LIBRARY) {
		library, library_err := os.stat(SOUND_LIBRARY, context.temp_allocator)
		// the C source and the headers it includes: the library is stale when any of them is newer
		fresh := library_err == nil
		for name in ([]string{"roci_sound.c", "roci_aiff.h", "roci_opus.h"}) {
			source, source_err := os.stat(strings.concatenate({"vendor/sound/c/", name}, context.temp_allocator), context.temp_allocator)
			if source_err != nil {
				if name == "roci_sound.c" {
					fresh = false
				}
				continue
			}
			if time.diff(source.modification_time, library.modification_time) < 0 {
				fresh = false
			}
		}
		if fresh {
			return true
		}
	}
	fmt.printfln("%s", term.out("== building the sound decoders (tools/sound-libs.sh)", .Bold_Cyan))
	return sound_libs()
}
