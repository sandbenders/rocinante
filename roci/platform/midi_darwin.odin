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
import "core:strings"
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
	MIDIOutputPortCreate :: proc(client: MIDIObjectRef, portName: CFStringRef, outPort: ^MIDIObjectRef) -> OSStatus ---
	MIDIGetNumberOfDestinations :: proc() -> c.ulong ---
	MIDIGetDestination :: proc(index: c.ulong) -> MIDIObjectRef ---
	MIDISend :: proc(port: MIDIObjectRef, dest: MIDIObjectRef, list: rawptr) -> OSStatus ---
	MIDIObjectGetStringProperty :: proc(obj: MIDIObjectRef, propertyID: CFStringRef, str: ^CFStringRef) -> OSStatus ---
	CFStringGetCString :: proc(str: CFStringRef, buffer: [^]u8, size: c.long, encoding: u32) -> u8 ---
}

foreign coremidi {
	// a name's key, for MIDIObjectGetStringProperty
	kMIDIPropertyName: CFStringRef
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

// ---- out ----

Midi_Out_Backend :: struct {
	client: MIDIObjectRef,
	port:   MIDIObjectRef,
}

@(private)
midi_out_backend_start :: proc(out: ^Midi_Out) {
	// made when something is first sent, so a sketch that never sends opens nothing
}

@(private)
midi_out_backend_stop :: proc(out: ^Midi_Out) {
	if out.backend.client != 0 {
		MIDIClientDispose(out.backend.client) // disposes of the port too
	}
}

// Makes the client and its output port, once. False when CoreMIDI would not.
@(private)
midi_out_ready :: proc(out: ^Midi_Out) -> bool {
	if out.backend.port != 0 {
		return true
	}
	name := CFStringCreateWithCString(nil, "rocinante out", kCFStringEncodingUTF8)
	defer CFRelease(name)
	if MIDIClientCreate(name, nil, nil, &out.backend.client) != 0 {
		return false
	}
	port_name := CFStringCreateWithCString(nil, "rocinante out port", kCFStringEncodingUTF8)
	defer CFRelease(port_name)
	return MIDIOutputPortCreate(out.backend.client, port_name, &out.backend.port) == 0
}

// The name CoreMIDI gives a destination, or "" when it has none.
@(private)
midi_destination_name :: proc(destination: MIDIObjectRef, allocator := context.allocator) -> string {
	text: CFStringRef
	if MIDIObjectGetStringProperty(destination, kMIDIPropertyName, &text) != 0 || text == nil {
		return ""
	}
	defer CFRelease(text)
	buffer: [256]u8
	if CFStringGetCString(text, raw_data(buffer[:]), len(buffer), kCFStringEncodingUTF8) == 0 {
		return ""
	}
	return strings.clone(string(cstring(raw_data(buffer[:]))), allocator)
}

@(private)
midi_out_backend_names :: proc(out: ^Midi_Out, allocator := context.allocator) -> []string {
	count := int(MIDIGetNumberOfDestinations())
	names := make([]string, count, allocator)
	for i in 0 ..< count {
		names[i] = midi_destination_name(MIDIGetDestination(c.ulong(i)), allocator)
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
	if !midi_out_ready(out) {
		return .Not_Sent
	}
	// a MIDIPacketList of one packet, laid out as the reader above reads them: the number of packets (u32), then
	// the packet's time (u64, 0 is now), its length (u16) and its bytes, with the packet starting at 4
	list: [32]u8
	(^u32)(&list[0])^ = 1
	(^u64)(&list[4])^ = 0
	(^u16)(&list[12])^ = u16(len(bytes))
	copy(list[14:], bytes)
	return .Sent if MIDISend(out.backend.port, MIDIGetDestination(c.ulong(at)), &list[0]) == 0 else .Not_Sent
}
