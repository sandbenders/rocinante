// SPDX-License-Identifier: 0BSD
//
// The sound file decoders: miniaudio's and stb_vorbis from the vendor folder of the Odin in use,
// built by tools/sound-libs.sh into .cache/sound.
package build

import "core:fmt"
import "core:os"

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
// built before the packages are checked when it is missing (the pipelines and a clone that has
// built it before skip this).
check_sound :: proc() -> bool {
	if os.exists(SOUND_LIBRARY) {
		return true
	}
	fmt.printfln("%s", term.out("== building the sound decoders (tools/sound-libs.sh)", .Bold_Cyan))
	return sound_libs()
}
