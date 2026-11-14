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
