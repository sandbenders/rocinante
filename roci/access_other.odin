// SPDX-License-Identifier: 0BSD
#+build !darwin
#+build !windows
#+build !linux
#+build !freebsd
#+build !openbsd
package roci

// No adapter is written for this system (macOS, Windows, Linux, FreeBSD and OpenBSD have one), so a
// window has no screen-reader bridge here.
@(private)
platform_access_attach :: proc(w: ^Win, a: ^Access) -> bool {
	return false
}

@(private)
platform_access_update :: proc(a: ^Access) {}

@(private)
platform_access_focus :: proc(a: ^Access, gained: bool) {}

@(private)
platform_access_detach :: proc(a: ^Access) {}

@(private)
platform_access_bounds :: proc(a: ^Access) {}
