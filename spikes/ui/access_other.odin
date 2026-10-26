// SPDX-License-Identifier: 0BSD
#+build !darwin
package spike_ui

import sdl "vendor:sdl3"

// Only the macOS adapter is wired up so far; Windows, Linux and FreeBSD follow
// in the same shape (CLAUDE.md section 4.8), so the spike runs without it there.
access_init :: proc(window: ^sdl.Window) -> bool { return false }
access_update :: proc() {}
access_window_focus :: proc(focused: bool) {}
access_shutdown :: proc() {}
