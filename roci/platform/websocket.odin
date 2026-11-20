// SPDX-License-Identifier: 0BSD
//
// Web sockets for `websocket connect`: a connection to a ws:// or wss:// address that carries messages both ways, made and read
// by a thread of its own through libcurl (which does the handshake, the framing and the TLS). What happens (opened, a
// message arrived, closed) waits in a locked queue until the sketch takes it once a frame, in the same shape as a TCP
// connection's (`Tcp_Happened`, with `Line` meaning a message); the sketch never waits. A message is text, or
// binary bytes, which are given to the sketch as text too.
package platform

import "base:runtime"
import "core:c"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

import curl "../../vendor/curl"

// The longest message taken; a longer one closes the connection.
WS_MAX_MESSAGE :: 8 << 20

@(private)
Ws_Out :: struct {
	data:   []byte,
	binary: bool,
}

// What `websocket connect` made: the thread, what happened and what waits to be sent.
Ws_Endpoint :: struct {
	lock:     sync.Mutex,
	queue:    [dynamic]Tcp_Happened,
	outbox:   [dynamic]Ws_Out,
	url:      string,
	stop:     bool, // told to end, as the sketch ends
	closing:  bool, // told to close the connection and say so
	done:     bool, // the connection ended or could not be made (atomic)
	finished: bool, // the thread has done with the endpoint (atomic)
	worker:   ^thread.Thread, // joined and freed by ws_close_endpoint once finished
}

// Starts a connection to an address (`ws://host/path` or `wss://host/path`). The thread makes it, so nothing waits here:
// the queue gets `.Open` when it is made, or `.Close` with the reason when it could not be.
ws_open :: proc(url: string, allocator := context.allocator) -> ^Ws_Endpoint {
	e := new(Ws_Endpoint, allocator)
	e.url = strings.clone(url, allocator)
	e.queue = make([dynamic]Tcp_Happened, 0, 16, allocator)
	e.outbox = make([dynamic]Ws_Out, 0, 4, allocator)
	e.worker = thread.create_and_start_with_data(e, ws_thread)
	return e
}

// Ends the connection and lets go of everything the endpoint held. The thread notices within a few thousandths of a
// second, even while it is still connecting.
ws_close_endpoint :: proc(e: ^Ws_Endpoint) {
	if e == nil {
		return
	}
	sync.atomic_store(&e.stop, true)
	for _ in 0 ..< 3000 {
		if sync.atomic_load(&e.finished) {
			break
		}
		time.sleep(time.Millisecond)
	}
	if sync.atomic_load(&e.finished) {
		thread.join(e.worker)
		thread.destroy(e.worker)
	}
	heap := runtime.heap_allocator()
	for h in e.queue {
		delete(h.text, heap)
		delete(h.from, heap)
	}
	for o in e.outbox {
		delete(o.data, heap)
	}
	allocator := e.queue.allocator
	delete(e.queue)
	delete(e.outbox)
	delete(e.url, allocator)
	free(e, allocator)
}

// Whether the connection can still be used: it is being made or is open.
ws_alive :: proc(e: ^Ws_Endpoint) -> bool {
	return e != nil && !sync.atomic_load(&e.done)
}

// Moves what happened into `out`, oldest first, the text copied with `allocator`: the caller frees it.
ws_take :: proc(e: ^Ws_Endpoint, out: ^[dynamic]Tcp_Happened, allocator := context.allocator) {
	if e == nil {
		return
	}
	sync.guard(&e.lock)
	heap := runtime.heap_allocator()
	for h in e.queue {
		append(out, Tcp_Happened{kind = h.kind, client = h.client, text = strings.clone(h.text, allocator), from = strings.clone(h.from, allocator)})
		delete(h.text, heap)
		delete(h.from, heap)
	}
	clear(&e.queue)
}

// Gives a message to the connection to send: text, or (`binary`) bytes. False when it is over.
ws_send_message :: proc(e: ^Ws_Endpoint, data: []byte, binary := false) -> bool {
	if e == nil || len(data) == 0 || sync.atomic_load(&e.done) {
		return false
	}
	sync.guard(&e.lock)
	heap := runtime.heap_allocator()
	copied := make([]byte, len(data), heap)
	copy(copied, data)
	append(&e.outbox, Ws_Out{data = copied, binary = binary})
	return true
}

// Asks the connection to close: it sends the close message, and `.Close` comes when it is over.
ws_end :: proc(e: ^Ws_Endpoint) {
	if e != nil {
		sync.atomic_store(&e.closing, true)
	}
}

@(private)
ws_push :: proc(e: ^Ws_Endpoint, kind: Tcp_Kind, text, from: string) {
	heap := runtime.heap_allocator()
	sync.guard(&e.lock)
	append(&e.queue, Tcp_Happened{kind = kind, client = 1, text = strings.clone(text, heap), from = strings.clone(from, heap)})
}

// Called by libcurl while it connects: stopping it as soon as the sketch says stop.
@(private)
ws_progress :: proc "c" (data: rawptr, dl_total, dl_now, ul_total, ul_now: curl.off_t) -> c.int {
	e := (^Ws_Endpoint)(data)
	return 1 if sync.atomic_load(&e.stop) else 0
}

@(private)
ws_thread :: proc(data: rawptr) {
	e := (^Ws_Endpoint)(data)
	context.allocator = runtime.heap_allocator()
	ws_run(e)
	// the very last thing: the sketch may free the endpoint once this is set
	sync.atomic_store(&e.done, true)
	sync.atomic_store(&e.finished, true)
}

@(private)
ws_run :: proc(e: ^Ws_Endpoint) {
	defer free_all(context.temp_allocator)
	curl_start()
	handle := curl.easy_init()
	if handle == nil {
		ws_push(e, .Close, "libcurl could not start", "")
		return
	}
	defer curl.easy_cleanup(handle)
	curl.easy_setopt(handle, .URL, strings.clone_to_cstring(e.url, context.temp_allocator))
	curl.easy_setopt(handle, .PROTOCOLS_STR, cstring("ws,wss"))
	curl.easy_setopt(handle, .CONNECT_ONLY, c.long(2))
	curl.easy_setopt(handle, .NOSIGNAL, c.long(1))
	curl.easy_setopt(handle, .CONNECTTIMEOUT_MS, c.long(10_000))
	curl.easy_setopt(handle, .USERAGENT, cstring("rocinante"))
	curl.easy_setopt(handle, .NOPROGRESS, c.long(0))
	curl.easy_setopt(handle, .XFERINFOFUNCTION, curl.xferinfo_callback(ws_progress))
	curl.easy_setopt(handle, .XFERINFODATA, rawptr(e))
	curl_trust(handle)
	host := ws_host(e.url)
	if code := curl.easy_perform(handle); code != .E_OK {
		if !sync.atomic_load(&e.stop) {
			ws_push(e, .Close, string(curl.easy_strerror(code)), host)
		}
		return
	}
	ws_push(e, .Open, "", host)
	chunk := make([]byte, 64 * 1024)
	message := make([dynamic]byte)
	defer {
		delete(chunk)
		delete(message)
	}
	reason := "the connection was closed"
	loop: for !sync.atomic_load(&e.stop) {
		// what has arrived
		busy := false
		for {
			received: c.size_t
			meta: ^curl.ws_frame
			code := curl.ws_recv(handle, raw_data(chunk), len(chunk), &received, &meta)
			if code == .E_AGAIN {
				break
			}
			if code != .E_OK {
				reason = "the connection was lost"
				break loop
			}
			busy = true
			if .CLOSE in meta.flags {
				break loop
			}
			if .PING in meta.flags || .PONG in meta.flags {
				continue
			}
			append(&message, ..chunk[:received])
			if len(message) > WS_MAX_MESSAGE {
				reason = "a message was longer than 8 megabytes"
				break loop
			}
			// a message is whole when its frame is and no other follows it
			if meta.bytesleft == 0 && .CONT not_in meta.flags {
				ws_push(e, .Line, string(message[:]), host)
				clear(&message)
			}
		}
		// what is waiting to go
		outgoing: [dynamic]Ws_Out
		closing: bool
		{
			sync.guard(&e.lock)
			outgoing = e.outbox
			e.outbox = make([dynamic]Ws_Out)
			closing = sync.atomic_load(&e.closing)
		}
		failed := false
		for o in outgoing {
			if !failed {
				sent_total: c.size_t
				for sent_total < len(o.data) {
					sent: c.size_t
					flags := curl.WS_BINARY if o.binary else curl.WS_TEXT
					code := curl.ws_send(handle, raw_data(o.data[sent_total:]), len(o.data) - sent_total, &sent, 0, flags)
					sent_total += sent
					if code == .E_AGAIN {
						time.sleep(time.Millisecond)
						continue
					}
					if code != .E_OK {
						failed = true
						break
					}
				}
			}
			delete(o.data)
		}
		delete(outgoing)
		if failed {
			reason = "the connection was lost"
			break loop
		}
		if closing {
			sent: c.size_t
			curl.ws_send(handle, nil, 0, &sent, 0, curl.WS_CLOSE)
			reason = "the connection was closed here"
			break loop
		}
		if !busy {
			time.sleep(5 * time.Millisecond)
		}
	}
	if !sync.atomic_load(&e.stop) {
		ws_push(e, .Close, reason, host)
	}
}

// The host part of an address, for the sketch to say who is at the other end.
@(private)
ws_host :: proc(url: string) -> string {
	rest := url
	if at := strings.index(rest, "://"); at >= 0 {
		rest = rest[at + 3:]
	}
	if end := strings.index_any(rest, "/?#"); end >= 0 {
		rest = rest[:end]
	}
	if at := strings.last_index(rest, "@"); at >= 0 {
		rest = rest[at + 1:]
	}
	return rest
}
