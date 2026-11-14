#+build !linux
#+build !freebsd
#+build !openbsd
#+build !darwin
#+build !windows
// SPDX-License-Identifier: 0BSD
//
// Systems with no MIDI here yet: nothing is read.
package platform

Midi_Backend :: struct {}

@(private)
midi_backend_start :: proc(m: ^Midi_In) {}

@(private)
midi_backend_stop :: proc(m: ^Midi_In) {}
