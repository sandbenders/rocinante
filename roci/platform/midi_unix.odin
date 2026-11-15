#+build linux, freebsd, openbsd
// SPDX-License-Identifier: 0BSD
//
// MIDI on Linux, FreeBSD and OpenBSD: a USB keyboard or controller is a device file that gives
// the bytes it sends, so no library is needed. Linux has /dev/snd/midiC<card>D<device> (raw MIDI,
// which ALSA makes for every MIDI port), FreeBSD /dev/umidi<unit>.<port> and OpenBSD /dev/rmidi<n>.
// One thread reads every file that opens, without waiting on any of them, and looks for new ones
// once a second; a file that fails (the device was unplugged) is closed. Android has no way to
// reach these files from an app, so there it reads nothing (its MIDI comes in Phase 8).
package platform

import "core:strings"
import "core:sync"
import "core:sys/posix"
import "core:thread"
import "core:time"
import "core:os"

Midi_Device :: struct {
	path:   string,
	fd:     posix.FD,
	parser: Midi_Parser,
}

Midi_Backend :: struct {
	thread:  ^thread.Thread,
	running: bool, // read and written with atomics
	devices: [dynamic]Midi_Device,
}

// The folder the system keeps its MIDI device files in, and how their names begin.
when ODIN_OS == .Linux {
	MIDI_FOLDER :: "/dev/snd"
	MIDI_PREFIX :: "midiC"
} else when ODIN_OS == .FreeBSD {
	MIDI_FOLDER :: "/dev"
	MIDI_PREFIX :: "umidi"
} else {
	MIDI_FOLDER :: "/dev"
	MIDI_PREFIX :: "rmidi"
}

@(private)
midi_backend_start :: proc(m: ^Midi_In) {
	when ODIN_PLATFORM_SUBTARGET == .Android {
		return
	} else {
		m.backend.devices = make([dynamic]Midi_Device, m.queue.allocator)
		sync.atomic_store(&m.backend.running, true)
		m.backend.thread = thread.create_and_start_with_data(m, midi_read_loop)
	}
}

@(private)
midi_backend_stop :: proc(m: ^Midi_In) {
	if m.backend.thread == nil {
		return
	}
	sync.atomic_store(&m.backend.running, false)
	thread.join(m.backend.thread)
	thread.destroy(m.backend.thread)
	m.backend.thread = nil
	for d in m.backend.devices {
		posix.close(d.fd)
		delete(d.path, m.queue.allocator)
	}
	delete(m.backend.devices)
}

@(private)
midi_read_loop :: proc(data: rawptr) {
	m := (^Midi_In)(data)
	b := &m.backend
	events := make([dynamic]Midi_Event, 0, 64)
	defer delete(events)
	buffer: [512]u8
	last_look: time.Tick
	looked := false
	for sync.atomic_load(&b.running) {
		if !looked || time.duration_seconds(time.tick_since(last_look)) >= 1 {
			midi_find_devices(m)
			last_look = time.tick_now()
			looked = true
		}
		for i := len(b.devices) - 1; i >= 0; i -= 1 {
			d := &b.devices[i]
			for {
				n := posix.read(d.fd, raw_data(buffer[:]), len(buffer))
				if n > 0 {
					for byte in buffer[:n] {
						midi_parse(&d.parser, byte, &events)
					}
					continue
				}
				if n < 0 && (posix.errno() == .EAGAIN || posix.errno() == .EINTR) {
					break
				}
				// gone: unplugged, or the file ended
				posix.close(d.fd)
				delete(d.path, m.queue.allocator)
				ordered_remove(&b.devices, i)
				break
			}
		}
		midi_push(m, events[:])
		clear(&events)
		time.sleep(time.Millisecond)
	}
}

// Opens every MIDI device file not open yet.
@(private)
midi_find_devices :: proc(m: ^Midi_In) {
	entries, err := os.read_all_directory_by_path(MIDI_FOLDER, context.temp_allocator)
	if err != nil {
		return
	}
	outer: for entry in entries {
		if !strings.has_prefix(entry.name, MIDI_PREFIX) {
			continue
		}
		path := strings.concatenate({MIDI_FOLDER, "/", entry.name}, context.temp_allocator)
		for d in m.backend.devices {
			if d.path == path {
				continue outer
			}
		}
		fd := posix.open(strings.clone_to_cstring(path, context.temp_allocator), {.NONBLOCK, .CLOEXEC})
		if fd < 0 {
			continue // not there (an OpenBSD rmidi with nothing behind it), or not ours to read
		}
		append(&m.backend.devices, Midi_Device{path = strings.clone(path, m.queue.allocator), fd = fd})
	}
	free_all(context.temp_allocator)
}

// ---- out ----

// A device file open for writing, and the name a sketch knows it by (its file's name).
@(private)
Midi_Out_Device :: struct {
	name: string,
	fd:   posix.FD,
}

Midi_Out_Backend :: struct {
	devices:   [dynamic]Midi_Out_Device,
	looked:    bool,
	last_look: time.Tick,
}

@(private)
midi_out_backend_start :: proc(out: ^Midi_Out) {
	out.backend.devices = make([dynamic]Midi_Out_Device, out.allocator)
}

@(private)
midi_out_backend_stop :: proc(out: ^Midi_Out) {
	for d in out.backend.devices {
		posix.close(d.fd)
		delete(d.name, out.allocator)
	}
	delete(out.backend.devices)
}

// Looks for MIDI device files not open yet, at most once a second: a keyboard plugged in is found by the
// next message, and one that was unplugged has already been dropped by the write that failed.
@(private)
midi_out_look :: proc(out: ^Midi_Out) {
	b := &out.backend
	if b.looked && time.duration_seconds(time.tick_since(b.last_look)) < 1 {
		return
	}
	b.looked = true
	b.last_look = time.tick_now()
	when ODIN_PLATFORM_SUBTARGET == .Android {
		return
	} else {
		entries, err := os.read_all_directory_by_path(MIDI_FOLDER, context.temp_allocator)
		if err != nil {
			return
		}
		outer: for entry in entries {
			if !strings.has_prefix(entry.name, MIDI_PREFIX) {
				continue
			}
			for d in b.devices {
				if d.name == entry.name {
					continue outer
				}
			}
			path := strings.concatenate({MIDI_FOLDER, "/", entry.name}, context.temp_allocator)
			fd := posix.open(strings.clone_to_cstring(path, context.temp_allocator), {.WRONLY, .NONBLOCK, .CLOEXEC})
			if fd < 0 {
				continue // a port with nothing to write to, or not ours
			}
			append(&b.devices, Midi_Out_Device{name = strings.clone(entry.name, out.allocator), fd = fd})
		}
		free_all(context.temp_allocator)
	}
}

@(private)
midi_out_backend_names :: proc(out: ^Midi_Out, allocator := context.allocator) -> []string {
	midi_out_look(out)
	names := make([]string, len(out.backend.devices), allocator)
	for d, i in out.backend.devices {
		names[i] = strings.clone(d.name, allocator)
	}
	return names
}

@(private)
midi_out_backend_send :: proc(out: ^Midi_Out, to: string, bytes: []u8) -> Midi_Send_Result {
	midi_out_look(out)
	names := make([]string, len(out.backend.devices), context.temp_allocator)
	for d, i in out.backend.devices {
		names[i] = d.name
	}
	at := midi_pick(names, to)
	if at < 0 {
		return .No_Device
	}
	d := out.backend.devices[at]
	// a message goes whole or not at all; a full buffer is waited for a moment (a few thousandths of a second)
	for _ in 0 ..< 10 {
		n := posix.write(d.fd, raw_data(bytes), len(bytes))
		if n == len(bytes) {
			return .Sent
		}
		if n < 0 && (posix.errno() == .EAGAIN || posix.errno() == .EINTR) {
			time.sleep(time.Millisecond)
			continue
		}
		break
	}
	// unplugged, or the device is not taking anything: let go of it, a later look may find it again
	posix.close(d.fd)
	delete(d.name, out.allocator)
	ordered_remove(&out.backend.devices, at)
	return .Not_Sent
}
