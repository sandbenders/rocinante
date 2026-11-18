// SPDX-License-Identifier: 0BSD
//
// Web sockets, a connection to a ws:// or wss:// address that carries messages both ways: `websocket_connect` makes one under a
// label the sketch chooses, and what happens on it (opened, a message arrived, closed) is a thing that happened in the frame
// (`Ws_Open`, `Ws_Message`, `Ws_Close`, with what happened in `Happened.tcp`, as a TCP connection's is), so the language's
// `on websocket "label"` runs once for each. Nothing waits: the connection is made and read by a thread (`platform/websocket.odin`).
// A headless sketch and a test open nothing; they give it what would happen with `feed_websocket` and read what was sent with
// `websocket_sent_messages`.
package roci

import "core:strings"

import "platform"

// The most web sockets a sketch has open at once.
WEBSOCKET_MAX :: 8

// What became of asking for a connection or a send.
Websocket_Result :: enum {
	Ok,
	Bad_Name, // a connection needs a name
	Bad_Address, // an address begins with ws:// or wss://
	Too_Many, // as many connections as a sketch may have are open
	Unknown_Label, // no connection has that name
	Empty, // there is nothing to send
	Not_Sent, // the connection is not open
}

// What a headless sketch sent, for tests to read.
Websocket_Sent :: struct {
	label:  string,
	data:   []byte,
	binary: bool,
}

// What a headless sketch asked to connect to, for tests to read.
Websocket_Asked :: struct {
	label: string,
	url:   string,
}

@(private)
Websocket_Entry :: struct {
	endpoint: ^platform.Ws_Endpoint, // nil in a headless sketch
	url:      string,
	closing:  bool, // `websocket_close` was asked: it is let go of once it says it is closed
}

@(private)
Websocket_Fed :: struct {
	kind:    platform.Tcp_Kind,
	message: Tcp_Message,
}

@(thread_local) @(private) websocket_entries: map[string]Websocket_Entry
@(thread_local) @(private) websocket_fed: [dynamic]Websocket_Fed
@(thread_local) @(private) websocket_sent: [dynamic]Websocket_Sent
@(thread_local) @(private) websocket_asked: [dynamic]Websocket_Asked
// The text of the frame's happenings, kept until the next frame's replaces it (a test reads the log after `step`).
@(thread_local) @(private) websocket_kept: [dynamic]string

// Makes a connection to an address under a label. A connection already made under it to the same address is left alone; to another
// address it is ended and replaced. Nothing waits: whether it was made comes as a happening.
websocket_connect :: proc(label, url: string) -> Websocket_Result {
	if !tcp_check_name(label) {
		return .Bad_Name
	}
	if !(strings.has_prefix(url, "ws://") || strings.has_prefix(url, "wss://")) || len(url) <= 5 {
		return .Bad_Address
	}
	if old, found := websocket_entries[label]; found && old.url == url && !old.closing && (old.endpoint == nil || platform.ws_alive(old.endpoint)) {
		return .Ok
	}
	if _, replacing := websocket_entries[label]; !replacing && len(websocket_entries) >= WEBSOCKET_MAX {
		return .Too_Many
	}
	allocator := osc_allocator()
	entry := Websocket_Entry{url = strings.clone(url, allocator)}
	if tcp_pretend() {
		if websocket_asked == nil {
			websocket_asked = make([dynamic]Websocket_Asked, allocator)
		}
		append(&websocket_asked, Websocket_Asked{label = strings.clone(label, allocator), url = strings.clone(url, allocator)})
	} else {
		entry.endpoint = platform.ws_open(url, allocator)
	}
	if websocket_entries == nil {
		websocket_entries = make(map[string]Websocket_Entry, allocator)
	}
	if old, found := websocket_entries[label]; found {
		websocket_release(old)
		websocket_entries[label] = entry
	} else {
		websocket_entries[strings.clone(label, allocator)] = entry
	}
	return .Ok
}

@(private)
websocket_release :: proc(entry: Websocket_Entry) {
	platform.ws_close_endpoint(entry.endpoint)
	delete(entry.url, osc_allocator())
}

// Sends a message on a connection: text, or (`binary`) bytes. A headless sketch sends nothing and keeps what it sent.
websocket_send :: proc(label: string, data: []u8, binary := false) -> Websocket_Result {
	entry, found := websocket_entries[label]
	if !found {
		return .Unknown_Label
	}
	if len(data) == 0 {
		return .Empty
	}
	if entry.endpoint == nil {
		allocator := osc_allocator()
		if websocket_sent == nil {
			websocket_sent = make([dynamic]Websocket_Sent, allocator)
		}
		copied := make([]u8, len(data), allocator)
		copy(copied, data)
		append(&websocket_sent, Websocket_Sent{label = strings.clone(label, allocator), data = copied, binary = binary})
		return .Ok
	}
	return .Ok if platform.ws_send_message(entry.endpoint, data, binary) else .Not_Sent
}

// Closes a connection: it sends the close message, says it is closed as a happening and is let go of then.
websocket_close :: proc(label: string) -> Websocket_Result {
	entry, found := &websocket_entries[label]
	if !found {
		return .Unknown_Label
	}
	platform.ws_end(entry.endpoint)
	entry.closing = true
	return .Ok
}

// Whether a connection under the label can still send: it is being made or is open.
websocket_is_open :: proc(label: string) -> bool {
	entry, found := websocket_entries[label]
	if !found {
		return false
	}
	return entry.endpoint == nil || platform.ws_alive(entry.endpoint)
}

// Gives the sketch something that happened on a connection as the network would, for the next frame: for tests.
feed_websocket :: proc(kind: platform.Tcp_Kind, label, text: string, from := "example.org") {
	allocator := osc_allocator()
	if websocket_fed == nil {
		websocket_fed = make([dynamic]Websocket_Fed, allocator)
	}
	append(&websocket_fed, Websocket_Fed{kind = kind, message = Tcp_Message{label = strings.clone(label, allocator), text = strings.clone(text, allocator), from = strings.clone(from, allocator), client = 1}})
}

// What a headless sketch has sent and asked to connect to since the last clear, oldest first.
websocket_sent_messages :: proc() -> []Websocket_Sent {
	return websocket_sent[:]
}

websocket_asked_for :: proc() -> []Websocket_Asked {
	return websocket_asked[:]
}

websocket_clear_sent :: proc() {
	allocator := osc_allocator()
	for m in websocket_sent {
		delete(m.label, allocator)
		delete(m.data, allocator)
	}
	clear(&websocket_sent)
	for a in websocket_asked {
		delete(a.label, allocator)
		delete(a.url, allocator)
	}
	clear(&websocket_asked)
}

@(private)
websocket_forget_frame :: proc() {
	allocator := osc_allocator()
	for s in websocket_kept {
		delete(s, allocator)
	}
	clear(&websocket_kept)
}

@(private)
websocket_keep :: proc(s: string) -> string {
	if s == "" {
		return ""
	}
	if websocket_kept == nil {
		websocket_kept = make([dynamic]string, osc_allocator())
	}
	copied := strings.clone(s, osc_allocator())
	append(&websocket_kept, copied)
	return copied
}

@(private)
websocket_happening :: proc(kind: platform.Tcp_Kind) -> Happening {
	switch kind {
	case .Open:
		return .Ws_Open
	case .Line:
		return .Ws_Message
	case .Close:
		return .Ws_Close
	}
	return .Ws_Message
}

// Turns what happened on the connections and what `feed_websocket` gave since the last frame into the frame's happenings. A
// connection that has ended is let go of once its last happening is taken. Called by `step`.
@(private)
websocket_step :: proc() {
	websocket_forget_frame()
	if len(websocket_entries) == 0 && len(websocket_fed) == 0 {
		return
	}
	allocator := osc_allocator()
	target := midi_target()
	log :: proc(target: ^Win, kind: platform.Tcp_Kind, label, text, from: string, client: int) {
		if target == nil {
			return
		}
		append(&the.log, Happened{kind = websocket_happening(kind), window = target.id, tcp = Tcp_Message{label = websocket_keep(label), text = websocket_keep(text), from = websocket_keep(from), client = client}})
	}
	finished := make([dynamic]string, context.temp_allocator)
	for label, entry in websocket_entries {
		if entry.endpoint == nil {
			continue
		}
		// whether it was over is read before what it did is taken, so nothing it did last is lost
		over := !platform.ws_alive(entry.endpoint)
		taken := make([dynamic]platform.Tcp_Happened, context.temp_allocator)
		platform.ws_take(entry.endpoint, &taken, context.temp_allocator)
		for h in taken {
			log(target, h.kind, label, h.text, h.from, h.client)
		}
		if over {
			append(&finished, label)
		}
	}
	for label in finished {
		websocket_release(websocket_entries[label])
		for key, _ in websocket_entries {
			if key == label {
				delete(key, allocator)
				delete_key(&websocket_entries, label)
				break
			}
		}
	}
	for f in websocket_fed {
		log(target, f.kind, f.message.label, f.message.text, f.message.from, f.message.client)
		delete(f.message.label, allocator)
		delete(f.message.text, allocator)
		delete(f.message.from, allocator)
	}
	clear(&websocket_fed)
}

// Ends every connection and lets go of everything that was kept. Called by `shutdown`.
@(private)
websocket_stop :: proc() {
	allocator := osc_allocator()
	for label, entry in websocket_entries {
		websocket_release(entry)
		delete(label, allocator)
	}
	delete(websocket_entries)
	websocket_entries = nil
	for f in websocket_fed {
		delete(f.message.label, allocator)
		delete(f.message.text, allocator)
		delete(f.message.from, allocator)
	}
	delete(websocket_fed)
	websocket_fed = nil
	websocket_forget_frame()
	delete(websocket_kept)
	websocket_kept = nil
	websocket_clear_sent()
	delete(websocket_sent)
	delete(websocket_asked)
	websocket_sent, websocket_asked = nil, nil
}
