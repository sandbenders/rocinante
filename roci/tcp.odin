// SPDX-License-Identifier: 0BSD
//
// TCP, a connection between two programs that carries lines of text: `tcp_connect` makes one to a host and
// a port, `tcp_listen` waits for others to make one, and each connection is named by a label the sketch chooses.
// What happens on them (a connection opened, a line arrived, a connection closed) is a thing that happened in the
// frame (`Tcp_Open`, `Tcp_Line`, `Tcp_Close`), logged against the window that has the focus (or the first), so the
// language's `on tcp "label"` runs once for each. Nothing waits: connections are made and read by threads
// (`platform/tcp.odin`). A headless sketch and a test open nothing; they give it what would happen with `feed_tcp`
// and read what was sent with `tcp_sent_messages`.
package roci

import "core:strings"

import "platform"

// The most connections and listeners a sketch has open at once, and the most a name may be long.
TCP_MAX_ENDPOINTS :: 8

// A thing that happened on a connection, as a handler reads it: the label it was made under, the text of a line
// (or why a connection ended), who is at the other end and, for a server, which of its clients it was (from 1).
Tcp_Message :: struct {
	label:  string,
	text:   string,
	from:   string,
	client: int,
}

// What became of asking for a connection, a listener or a send.
Tcp_Result :: enum {
	Ok,
	Bad_Name, // a connection needs a name
	Bad_Port, // a port is a whole number from 1 to 65535
	Host_Unknown, // no such computer was found
	Port_Busy, // another program has the port
	Port_Refused, // the system would not let this program listen there
	Too_Many, // as many connections as a sketch may have are open
	Unknown_Label, // no connection has that name
	Empty, // there is nothing to send
	Not_Sent, // nobody is connected to send to
}

// What a headless sketch sent, for tests to read: the label, the bytes, and which client (0 for every one).
Tcp_Sent :: struct {
	label:  string,
	data:   []byte,
	client: int,
}

// What a headless sketch asked to connect or listen to, for tests to read.
Tcp_Asked :: struct {
	label:  string,
	host:   string, // "" for a listener
	port:   int,
	server: bool,
}

@(private)
Tcp_Entry :: struct {
	endpoint: ^platform.Tcp_Endpoint, // nil in a headless sketch
	host:     string,
	port:     int,
	server:   bool,
	closing:  bool, // `tcp_close` was asked of a client: it is let go of once it says it is closed
}

@(private)
Tcp_Fed :: struct {
	kind:    platform.Tcp_Kind,
	message: Tcp_Message,
}

@(thread_local) @(private) tcp_entries: map[string]Tcp_Entry
@(thread_local) @(private) tcp_fed: [dynamic]Tcp_Fed
@(thread_local) @(private) tcp_sent: [dynamic]Tcp_Sent
@(thread_local) @(private) tcp_asked: [dynamic]Tcp_Asked
@(thread_local) @(private) tcp_pretend_busy: bool // for tests: every port is taken
// The text of the frame's happenings: it is read after the frame's own memory is let go of (a test reads the log
// after `step`), so it is kept here until the next frame's replaces it.
@(thread_local) @(private) tcp_kept: [dynamic]string

@(private)
tcp_pretend :: proc() -> bool {
	return the.headless || graphics_refused
}

@(private)
tcp_register :: proc(label: string, entry: Tcp_Entry) {
	allocator := osc_allocator()
	if tcp_entries == nil {
		tcp_entries = make(map[string]Tcp_Entry, allocator)
	}
	if old, found := tcp_entries[label]; found {
		tcp_release_entry(old)
		tcp_entries[label] = entry
		return
	}
	tcp_entries[strings.clone(label, allocator)] = entry
}

@(private)
tcp_release_entry :: proc(entry: Tcp_Entry) {
	platform.tcp_close_endpoint(entry.endpoint)
	delete(entry.host, osc_allocator())
}

@(private)
tcp_check_name :: proc(label: string) -> bool {
	return len(strings.trim_space(label)) > 0 && len(label) <= 64
}

// Makes a connection to a host (a name or a number, "127.0.0.1" for this computer) and a port, under a label. A
// connection already made under it to the same place is left alone; to another place it is ended and replaced.
// Nothing waits: whether it was made comes as a happening.
tcp_connect :: proc(label, host: string, port: f64) -> Tcp_Result {
	if !tcp_check_name(label) {
		return .Bad_Name
	}
	if port < 1 || port >= 65536 || port != f64(int(port)) {
		return .Bad_Port
	}
	if strings.has_suffix(host, ".invalid") || len(strings.trim_space(host)) == 0 {
		return .Host_Unknown
	}
	if old, found := tcp_entries[label]; found && !old.server && old.host == host && old.port == int(port) && !old.closing && (old.endpoint == nil || platform.tcp_alive(old.endpoint)) {
		return .Ok
	}
	if _, replacing := tcp_entries[label]; !replacing && len(tcp_entries) >= TCP_MAX_ENDPOINTS {
		return .Too_Many
	}
	allocator := osc_allocator()
	entry := Tcp_Entry{host = strings.clone(host, allocator), port = int(port)}
	if tcp_pretend() {
		if tcp_asked == nil {
			tcp_asked = make([dynamic]Tcp_Asked, allocator)
		}
		append(&tcp_asked, Tcp_Asked{label = strings.clone(label, allocator), host = strings.clone(host, allocator), port = int(port)})
	} else {
		entry.endpoint = platform.tcp_open_client(host, int(port), allocator)
	}
	tcp_register(label, entry)
	return .Ok
}

// Waits for connections on a port, under a label: each that comes is a client of the server, numbered from 1.
tcp_listen :: proc(label: string, port: f64) -> Tcp_Result {
	if !tcp_check_name(label) {
		return .Bad_Name
	}
	if port < 1 || port >= 65536 || port != f64(int(port)) {
		return .Bad_Port
	}
	if old, found := tcp_entries[label]; found && old.server && old.port == int(port) && (old.endpoint == nil || platform.tcp_alive(old.endpoint)) {
		return .Ok
	}
	if _, replacing := tcp_entries[label]; !replacing && len(tcp_entries) >= TCP_MAX_ENDPOINTS {
		return .Too_Many
	}
	allocator := osc_allocator()
	entry := Tcp_Entry{port = int(port), server = true}
	if tcp_pretend() {
		if tcp_pretend_busy {
			return .Port_Busy
		}
		if tcp_asked == nil {
			tcp_asked = make([dynamic]Tcp_Asked, allocator)
		}
		append(&tcp_asked, Tcp_Asked{label = strings.clone(label, allocator), port = int(port), server = true})
	} else {
		// a sketch that listens again on a port it listens on itself (a reload) lets the old listener go first
		if old, found := tcp_entries[label]; found && old.server && old.port == int(port) {
			tcp_release_entry(old)
			delete_key(&tcp_entries, label)
		}
		listener := platform.tcp_open_server(int(port), allocator)
		switch listener.error {
		case .None:
			entry.endpoint = listener
		case .Port_Busy:
			platform.tcp_close_endpoint(listener)
			return .Port_Busy
		case .Port_Refused:
			platform.tcp_close_endpoint(listener)
			return .Port_Refused
		}
	}
	tcp_register(label, entry)
	return .Ok
}

// A test knob: while it is on, a headless sketch finds every port taken, as it would when another program has
// the one it asks for.
set_tcp_port_busy :: proc(busy: bool) {
	tcp_pretend_busy = busy
}

// Sends bytes on a connection: to the other end of a client, or to one client of a server (a number, from 1) or
// to all of them (0). A headless sketch sends nothing and keeps what it sent for `tcp_sent_messages`.
tcp_send :: proc(label: string, data: []u8, client := 0) -> Tcp_Result {
	entry, found := tcp_entries[label]
	if !found {
		return .Unknown_Label
	}
	if len(data) == 0 {
		return .Empty
	}
	if entry.endpoint == nil {
		allocator := osc_allocator()
		if tcp_sent == nil {
			tcp_sent = make([dynamic]Tcp_Sent, allocator)
		}
		copied := make([]u8, len(data), allocator)
		copy(copied, data)
		append(&tcp_sent, Tcp_Sent{label = strings.clone(label, allocator), data = copied, client = client})
		return .Ok
	}
	return .Ok if platform.tcp_send_to(entry.endpoint, data, client) > 0 else .Not_Sent
}

// Ends a connection, or a listener and every client of it (or one client of a server, a number from 1). A client
// connection says it is closed, as a happening, and is let go of then.
tcp_close :: proc(label: string, client := 0) -> Tcp_Result {
	entry, found := &tcp_entries[label]
	if !found {
		return .Unknown_Label
	}
	if entry.server && client == 0 {
		tcp_release_entry(entry^)
		for key, _ in tcp_entries {
			if key == label {
				delete(key, osc_allocator())
				delete_key(&tcp_entries, label)
				break
			}
		}
		return .Ok
	}
	if entry.endpoint != nil {
		platform.tcp_end_client(entry.endpoint, client)
	}
	if !entry.server {
		entry.closing = true
	}
	return .Ok
}

// Whether a connection under the label can still send: a client that is connected or being made, or a listener.
tcp_is_open :: proc(label: string) -> bool {
	entry, found := tcp_entries[label]
	if !found {
		return false
	}
	return entry.endpoint == nil || platform.tcp_alive(entry.endpoint)
}

// Gives the sketch something that happened on a connection as the network would, for the next frame: for tests.
feed_tcp :: proc(kind: platform.Tcp_Kind, label, text: string, from := "127.0.0.1", client := 1) {
	allocator := osc_allocator()
	if tcp_fed == nil {
		tcp_fed = make([dynamic]Tcp_Fed, allocator)
	}
	append(&tcp_fed, Tcp_Fed{kind = kind, message = Tcp_Message{label = strings.clone(label, allocator), text = strings.clone(text, allocator), from = strings.clone(from, allocator), client = client}})
}

// What a headless sketch has sent, and asked to connect to, since the last clear, oldest first.
tcp_sent_messages :: proc() -> []Tcp_Sent {
	return tcp_sent[:]
}

tcp_asked_for :: proc() -> []Tcp_Asked {
	return tcp_asked[:]
}

tcp_clear_sent :: proc() {
	allocator := osc_allocator()
	for m in tcp_sent {
		delete(m.label, allocator)
		delete(m.data, allocator)
	}
	clear(&tcp_sent)
	for a in tcp_asked {
		delete(a.label, allocator)
		delete(a.host, allocator)
	}
	clear(&tcp_asked)
}

@(private)
tcp_forget_frame :: proc() {
	allocator := osc_allocator()
	for s in tcp_kept {
		delete(s, allocator)
	}
	clear(&tcp_kept)
}

@(private)
tcp_keep :: proc(s: string) -> string {
	if s == "" {
		return ""
	}
	if tcp_kept == nil {
		tcp_kept = make([dynamic]string, osc_allocator())
	}
	copied := strings.clone(s, osc_allocator())
	append(&tcp_kept, copied)
	return copied
}

@(private)
tcp_happening :: proc(kind: platform.Tcp_Kind) -> Happening {
	switch kind {
	case .Open:
		return .Tcp_Open
	case .Line:
		return .Tcp_Line
	case .Close:
		return .Tcp_Close
	}
	return .Tcp_Line
}

// Turns what happened on the connections and what `feed_tcp` gave since the last frame into the frame's
// happenings. A client that has ended is let go of once its last happening is taken. Called by `step`.
@(private)
tcp_step :: proc() {
	tcp_forget_frame()
	if len(tcp_entries) == 0 && len(tcp_fed) == 0 {
		return
	}
	allocator := osc_allocator()
	target := midi_target()
	log :: proc(target: ^Win, kind: platform.Tcp_Kind, label, text, from: string, client: int) {
		if target == nil {
			return
		}
		append(&the.log, Happened{kind = tcp_happening(kind), window = target.id, tcp = Tcp_Message{label = tcp_keep(label), text = tcp_keep(text), from = tcp_keep(from), client = client}})
	}
	finished := make([dynamic]string, context.temp_allocator)
	for label, &entry in tcp_entries {
		if entry.endpoint == nil {
			continue
		}
		// whether it was over is read before what it did is taken, so nothing it did last is lost
		over := !platform.tcp_alive(entry.endpoint)
		taken := make([dynamic]platform.Tcp_Happened, context.temp_allocator)
		platform.tcp_take(entry.endpoint, &taken, context.temp_allocator)
		for h in taken {
			log(target, h.kind, label, h.text, h.from, h.client)
		}
		if over && !entry.server {
			append(&finished, label)
		}
	}
	for label in finished {
		entry := tcp_entries[label]
		tcp_release_entry(entry)
		for key, _ in tcp_entries {
			if key == label {
				delete(key, allocator)
				delete_key(&tcp_entries, label)
				break
			}
		}
	}
	for f in tcp_fed {
		log(target, f.kind, f.message.label, f.message.text, f.message.from, f.message.client)
		delete(f.message.label, allocator)
		delete(f.message.text, allocator)
		delete(f.message.from, allocator)
	}
	clear(&tcp_fed)
}

// Ends every connection and lets go of everything that was kept. Called by `shutdown`.
@(private)
tcp_stop :: proc() {
	allocator := osc_allocator()
	for label, entry in tcp_entries {
		tcp_release_entry(entry)
		delete(label, allocator)
	}
	delete(tcp_entries)
	tcp_entries = nil
	for f in tcp_fed {
		delete(f.message.label, allocator)
		delete(f.message.text, allocator)
		delete(f.message.from, allocator)
	}
	delete(tcp_fed)
	tcp_fed = nil
	tcp_forget_frame()
	delete(tcp_kept)
	tcp_kept = nil
	tcp_clear_sent()
	delete(tcp_sent)
	delete(tcp_asked)
	tcp_sent, tcp_asked = nil, nil
}
