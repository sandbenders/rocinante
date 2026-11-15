#+build !linux
#+build !freebsd
#+build !openbsd
#+build !darwin
#+build !windows
// SPDX-License-Identifier: 0BSD
//
// Systems with no MIDI here yet: nothing is read, and nothing can be sent.
package platform

Midi_Backend :: struct {}

@(private)
midi_backend_start :: proc(m: ^Midi_In) {}

@(private)
midi_backend_stop :: proc(m: ^Midi_In) {}

Midi_Out_Backend :: struct {}

@(private)
midi_out_backend_start :: proc(out: ^Midi_Out) {}

@(private)
midi_out_backend_stop :: proc(out: ^Midi_Out) {}

@(private)
midi_out_backend_names :: proc(out: ^Midi_Out, allocator := context.allocator) -> []string {
	return nil
}

@(private)
midi_out_backend_send :: proc(out: ^Midi_Out, to: string, bytes: []u8) -> Midi_Send_Result {
	return .No_Device
}
