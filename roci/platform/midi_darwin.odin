#+build darwin
// SPDX-License-Identifier: 0BSD
//
// MIDI on macOS (and later iOS): CoreMIDI, which is part of the system. A client with an input
// port is connected to every source there is, and to every source again when the system says
// the setup changed (a device plugged in or out). CoreMIDI calls the read procedure on a thread
// of its own with a list of packets, whose bytes go through the parser. The packet list is read
// by hand, as the C macro MIDIPacketNext does: on Apple silicon each packet starts at the next
// multiple of four bytes. Written against CoreMIDI's headers (MIDIServices.h); checked by hand.
package platform

import "base:runtime"
import "core:c"
import "core:sync"

foreign import coremidi {"system:CoreMIDI.framework", "system:CoreFoundation.framework"}

@(private) OSStatus :: i32
@(private) MIDIObjectRef :: u32
@(private) CFStringRef :: rawptr
@(private) MIDINotifyProc :: #type proc "c" (message: rawptr, refCon: rawptr)
@(private) MIDIReadProc :: #type proc "c" (list: rawptr, readRefCon: rawptr, srcConnRefCon: rawptr)
@(private) kCFStringEncodingUTF8 :: 0x08000100
// MIDINotification's messageID when sources come or go
@(private) kMIDIMsgSetupChanged :: 1

@(default_calling_convention = "c")
@(private)
foreign coremidi {
	CFStringCreateWithCString :: proc(alloc: rawptr, cStr: cstring, encoding: u32) -> CFStringRef ---
	CFRelease :: proc(cf: rawptr) ---
	MIDIClientCreate :: proc(name: CFStringRef, notifyProc: MIDINotifyProc, notifyRefCon: rawptr, outClient: ^MIDIObjectRef) -> OSStatus ---
	MIDIClientDispose :: proc(client: MIDIObjectRef) -> OSStatus ---
	MIDIInputPortCreate :: proc(client: MIDIObjectRef, portName: CFStringRef, readProc: MIDIReadProc, refCon: rawptr, outPort: ^MIDIObjectRef) -> OSStatus ---
	MIDIGetNumberOfSources :: proc() -> c.ulong ---
	MIDIGetSource :: proc(index: c.ulong) -> MIDIObjectRef ---
	MIDIPortConnectSource :: proc(port: MIDIObjectRef, source: MIDIObjectRef, connRefCon: rawptr) -> OSStatus ---
	MIDIPortDisconnectSource :: proc(port: MIDIObjectRef, source: MIDIObjectRef) -> OSStatus ---
}

Midi_Backend :: struct {
	client:  MIDIObjectRef,
	port:    MIDIObjectRef,
	parser:  Midi_Parser, // one for all sources: CoreMIDI hands over whole messages in each packet
	lock:    sync.Mutex,  // the parser's, since sources may be read on more than one thread
	sources: [dynamic]MIDIObjectRef,
}

@(private)
midi_backend_start :: proc(m: ^Midi_In) {
	m.backend.sources = make([dynamic]MIDIObjectRef, m.queue.allocator)
	name := CFStringCreateWithCString(nil, "rocinante", kCFStringEncodingUTF8)
	defer CFRelease(name)
	if MIDIClientCreate(name, midi_notified, m, &m.backend.client) != 0 {
		return
	}
	port_name := CFStringCreateWithCString(nil, "rocinante in", kCFStringEncodingUTF8)
	defer CFRelease(port_name)
	if MIDIInputPortCreate(m.backend.client, port_name, midi_read, m, &m.backend.port) != 0 {
		return
	}
	midi_connect_sources(m)
}

@(private)
midi_backend_stop :: proc(m: ^Midi_In) {
	if m.backend.client != 0 {
		MIDIClientDispose(m.backend.client) // disposes of the port and its connections too
	}
	delete(m.backend.sources)
}

// Connects the input port to every source not connected yet.
@(private)
midi_connect_sources :: proc(m: ^Midi_In) {
	if m.backend.port == 0 {
		return
	}
	sync.guard(&m.backend.lock)
	count := MIDIGetNumberOfSources()
	outer: for i in 0 ..< count {
		source := MIDIGetSource(i)
		for known in m.backend.sources {
			if known == source {
				continue outer
			}
		}
		if MIDIPortConnectSource(m.backend.port, source, nil) == 0 {
			append(&m.backend.sources, source)
		}
	}
}

@(private)
midi_notified :: proc "c" (message: rawptr, refCon: rawptr) {
	context = runtime.default_context()
	// MIDINotification begins with its messageID, a 32-bit number
	if message != nil && (^i32)(message)^ == kMIDIMsgSetupChanged {
		midi_connect_sources((^Midi_In)(refCon))
	}
}

@(private)
midi_read :: proc "c" (list: rawptr, readRefCon: rawptr, srcConnRefCon: rawptr) {
	context = runtime.default_context()
	m := (^Midi_In)(readRefCon)
	events := make([dynamic]Midi_Event, 0, 32, context.temp_allocator)
	defer free_all(context.temp_allocator)
	// MIDIPacketList: numPackets (u32), then the packets; a packet is timeStamp (u64), length (u16), data
	count := (^u32)(list)^
	at := uintptr(list) + 4
	sync.lock(&m.backend.lock)
	for _ in 0 ..< count {
		length := int((^u16)(at + 8)^)
		data := ([^]u8)(rawptr(at + 10))
		for i in 0 ..< length {
			midi_parse(&m.backend.parser, data[i], &events)
		}
		// the next packet starts after this one's data, at a multiple of four on arm64
		at = (at + 10 + uintptr(length) + 3) & ~uintptr(3)
	}
	sync.unlock(&m.backend.lock)
	midi_push(m, events[:])
}
