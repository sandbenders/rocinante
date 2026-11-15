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
import "core:strings"
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
	midiOutGetNumDevs :: proc() -> win.UINT ---
	midiOutGetDevCapsW :: proc(uDeviceID: win.UINT_PTR, pmoc: ^MIDIOUTCAPSW, cbmoc: win.UINT) -> win.UINT ---
	midiOutOpen :: proc(phmo: ^HMIDIOUT, uDeviceID: win.UINT, dwCallback: win.DWORD_PTR, dwInstance: win.DWORD_PTR, fdwOpen: win.DWORD) -> win.UINT ---
	midiOutShortMsg :: proc(hmo: HMIDIOUT, dwMsg: win.DWORD) -> win.UINT ---
	midiOutReset :: proc(hmo: HMIDIOUT) -> win.UINT ---
	midiOutClose :: proc(hmo: HMIDIOUT) -> win.UINT ---
}

@(private) HMIDIOUT :: distinct rawptr
// what midiOutGetDevCaps says of a device; only the name is used
@(private)
MIDIOUTCAPSW :: struct {
	wMid:           u16,
	wPid:           u16,
	vDriverVersion: u32,
	szPname:        [32]u16,
	wTechnology:    u16,
	wVoices:        u16,
	wNotes:         u16,
	wChannelMask:   u16,
	dwSupport:      u32,
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
	// only the bytes the message has: a clock tick is one, and the others in the number are noise that
	// would be read as the data of whatever status came before
	for i in 0 ..< midi_packed_length(u8(packed)) {
		midi_parse(parser, u8(packed >> u32(8 * i)), &events)
	}
	midi_push(m, events[:])
}

// ---- out ----

Midi_Out_Backend :: struct {
	handles: [dynamic]HMIDIOUT, // one for each device, opened when a message first goes to it (0 until then)
	count:   win.UINT, // how many devices there were when they were last counted
}

@(private)
midi_out_backend_start :: proc(out: ^Midi_Out) {
	out.backend.handles = make([dynamic]HMIDIOUT, out.allocator)
}

@(private)
midi_out_backend_stop :: proc(out: ^Midi_Out) {
	midi_out_close_all(out)
	delete(out.backend.handles)
}

@(private)
midi_out_close_all :: proc(out: ^Midi_Out) {
	for h in out.backend.handles {
		if h != nil {
			midiOutReset(h)
			midiOutClose(h)
		}
	}
	clear(&out.backend.handles)
}

// Counts the devices; when their number changed (one plugged in or out) every handle is let go of and made
// again as needed, since the numbers WinMM gives devices can change too.
@(private)
midi_out_count :: proc(out: ^Midi_Out) -> int {
	count := midiOutGetNumDevs()
	if count != out.backend.count {
		midi_out_close_all(out)
		out.backend.count = count
	}
	for len(out.backend.handles) < int(count) {
		append(&out.backend.handles, nil)
	}
	return int(count)
}

@(private)
midi_out_backend_names :: proc(out: ^Midi_Out, allocator := context.allocator) -> []string {
	count := midi_out_count(out)
	names := make([]string, count, allocator)
	for i in 0 ..< count {
		caps: MIDIOUTCAPSW
		if midiOutGetDevCapsW(win.UINT_PTR(i), &caps, size_of(caps)) != 0 {
			continue
		}
		name, err := win.utf16_to_utf8(caps.szPname[:], allocator)
		if err == nil {
			names[i] = strings.trim_right_null(name)
		}
	}
	return names
}

@(private)
midi_out_backend_send :: proc(out: ^Midi_Out, to: string, bytes: []u8) -> Midi_Send_Result {
	names := midi_out_backend_names(out, context.temp_allocator)
	at := midi_pick(names, to)
	if at < 0 {
		return .No_Device
	}
	if out.backend.handles[at] == nil {
		h: HMIDIOUT
		if midiOutOpen(&h, win.UINT(at), 0, 0, 0) != 0 {
			return .Not_Sent
		}
		out.backend.handles[at] = h
	}
	// a short message packed into a number: the status, then the two data bytes
	packed: u32
	for b, i in bytes {
		packed |= u32(b) << u32(8 * i)
	}
	return .Sent if midiOutShortMsg(out.backend.handles[at], win.DWORD(packed)) == 0 else .Not_Sent
}
