// SPDX-License-Identifier: 0BSD
//
// Spike 2, Android half: an Odin shared library
// that SDL's Java activity loads and starts. The sketch is in
// ../shared. Build and install it with spikes/mobile/android/build.sh.
package spike_android

import "base:runtime"
import "core:c"
import sketch "../sketch"

// SDL's Java side finds this by name in libmain.so and calls it on its own
// thread. It is not called SDL_main, because vendor:sdl3 already declares that
// name as an import (an app is expected to define it in C), and the two clash.
// SpikeActivity tells SDL the name to look for.
@(export, link_name = "rocinante_main")
rocinante_main :: proc "c" (argc: c.int, argv: [^]cstring) -> c.int {
	context = runtime.default_context()
	sketch.run()
	return 0
}

// Odin links the NDK's native_app_glue into every Android library, and that
// glue refers to an `android_main` that the app is meant to define for
// NativeActivity. SDL's activity never goes through the glue, so this is never
// called; it exists so the library can be loaded at all.
@(export, link_name = "android_main")
android_main :: proc "c" (app: rawptr) {}
