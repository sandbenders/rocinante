#+build windows
// SPDX-License-Identifier: 0BSD
//
// MIDI on Windows: WinMM's MIDI input, which is part of the system. Every input device is
// opened with a callback, which WinMM calls on a thread of its own with each short message
// packed into a number (status, then the two data bytes). A thread looks once a second at how
// many devices there are, and when the number changes (one plugged in or out) closes every
// device and opens them all again, since the numbers WinMM gives them can change too. Written
// against the documentation of midiInOpen and MidiInProc; checked by hand.
package platform

import "base:runtime"
import "core:sync"
import "core:thread"
import "core:time"
import win "core:sys/windows"

foreign import winmm "system:Winmm.lib"

@(private) HMIDIIN :: distinct rawptr
@(private) CALLBACK_FUNCTION :: 0x00030000
@(private) MIM_DATA :: 0x3C3

@(default_calling_convention = "system")
@(private)
foreign winmm {
	midiInGetNumDevs :: proc() -> win.UINT ---
	midiInOpen :: proc(phmi: ^HMIDIIN, uDeviceID: win.UINT, dwCallback: win.DWORD_PTR, dwInstance: win.DWORD_PTR, fdwOpen: win.DWORD) -> win.UINT ---
	midiInStart :: proc(hmi: HMIDIIN) -> win.UINT ---
	midiInStop :: proc(hmi: HMIDIIN) -> win.UINT ---
	midiInReset :: proc(hmi: HMIDIIN) -> win.UINT ---
	midiInClose :: proc(hmi: HMIDIIN) -> win.UINT ---
}

Midi_Backend :: struct {
	thread:  ^thread.Thread,
	running: bool, // read and written with atomics
	handles: [dynamic]HMIDIIN,
	parsers: [64]Midi_Parser, // one for each device, by its place in `handles`
	count:   win.UINT,
}

@(private)
midi_backend_start :: proc(m: ^Midi_In) {
	m.backend.handles = make([dynamic]HMIDIIN, m.queue.allocator)
	sync.atomic_store(&m.backend.running, true)
	m.backend.thread = thread.create_and_start_with_data(m, midi_watch_loop)
}

@(private)
midi_backend_stop :: proc(m: ^Midi_In) {
	if m.backend.thread != nil {
		sync.atomic_store(&m.backend.running, false)
		thread.join(m.backend.thread)
		thread.destroy(m.backend.thread)
		m.backend.thread = nil
	}
	midi_close_all(m)
	delete(m.backend.handles)
}

@(private)
midi_close_all :: proc(m: ^Midi_In) {
	for h in m.backend.handles {
		midiInStop(h)
		midiInReset(h)
		midiInClose(h)
	}
	clear(&m.backend.handles)
}

@(private)
midi_watch_loop :: proc(data: rawptr) {
	m := (^Midi_In)(data)
	first := true
	for sync.atomic_load(&m.backend.running) {
		count := midiInGetNumDevs()
		if first || count != m.backend.count {
			first = false
			midi_close_all(m)
			m.backend.count = count
			for id in 0 ..< min(count, len(m.backend.parsers)) {
				h: HMIDIIN
				if midiInOpen(&h, win.UINT(id), win.DWORD_PTR(uintptr(rawptr(midi_in_proc))), win.DWORD_PTR(uintptr(m)), CALLBACK_FUNCTION) != 0 {
					continue
				}
				append(&m.backend.handles, h)
				midiInStart(h)
			}
		}
		time.sleep(time.Second)
	}
}

@(private)
midi_in_proc :: proc "system" (hmi: HMIDIIN, msg: win.UINT, instance: win.DWORD_PTR, param1: win.DWORD_PTR, param2: win.DWORD_PTR) {
	if msg != MIM_DATA {
		return
	}
	context = runtime.default_context()
	m := (^Midi_In)(rawptr(uintptr(instance)))
	// which device: its parser keeps running status apart from the others'
	place := 0
	for h, i in m.backend.handles {
		if h == hmi {
			place = i
		}
	}
	events: [dynamic]Midi_Event
	events.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	packed := u32(param1)
	parser := &m.backend.parsers[place]
	midi_parse(parser, u8(packed), &events)
	midi_parse(parser, u8(packed >> 8), &events)
	midi_parse(parser, u8(packed >> 16), &events)
	midi_push(m, events[:])
}
