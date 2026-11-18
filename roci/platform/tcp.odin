// SPDX-License-Identifier: 0BSD
//
// TCP connections for `tcp connect` and `tcp listen`: each connection is read by a thread of its own that waits
// on nothing but the socket (a short timeout, so it also looks at what is to be sent and whether it was told to
// stop), and what happens (a connection opened, a line of text arrived, a connection closed) waits in a locked
// queue until the sketch takes it once a frame. The sketch never waits. A line is the bytes up to a newline, the
// newline and a carriage return before it left off. TCP is in Odin's `core:net` on every desktop system and both
// phones, so there is one file and no backend for each system.
package platform

import "base:runtime"
import "core:fmt"
import "core:net"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

// What happened on a connection.
Tcp_Kind :: enum {
	Open, // connected (a client), or a client came in (a server)
	Line, // a line of text arrived
	Close, // the connection ended, or could not begin: `text` says why
}

// One thing that happened: which of the endpoint's connections it was (1 for the one a client makes, and the
// numbers a server gives its clients, counting from 1), the text of a line or the reason a connection ended, and
// who is at the other end ("192.168.0.7").
Tcp_Happened :: struct {
	kind:   Tcp_Kind,
	client: int,
	text:   string,
	from:   string,
}

Tcp_Problem :: enum {
	None,
	Port_Busy, // another program has the port
	Port_Refused, // the system would not let this program listen there
}

// The most connections one server keeps, and the longest line read (a longer one comes in pieces).
TCP_MAX_CLIENTS :: 16
TCP_MAX_LINE :: 1 << 20

// What `tcp connect` or `tcp listen` made: one connection (a client) or a listener and its connections.
Tcp_Endpoint :: struct {
	lock:     sync.Mutex,
	queue:    [dynamic]Tcp_Happened,
	conns:    [dynamic]^Tcp_Conn,
	listener: net.TCP_Socket,
	thread:   ^thread.Thread, // the one that dials, or the one that accepts
	server:   bool,
	stop:     bool,
	port:     int,
	host:     string,
	error:    Tcp_Problem,
	next:     int, // the number the next connection gets, less one
	dialing:  bool, // a client whose thread is still making the connection (under the lock)
	abandoned: bool, // closed while dialing: the thread lets go of it when it is through (under the lock)
	done:     bool, // a client whose connection has ended or could not be made
	finished: bool, // a client's thread has done with the endpoint (atomic): it frees its own thread
}

@(private)
Tcp_Conn :: struct {
	endpoint: ^Tcp_Endpoint,
	id:       int,
	socket:   net.TCP_Socket,
	thread:   ^thread.Thread,
	outbox:   [dynamic][]byte, // under the endpoint's lock
	closing:  bool, // told to end
	ended:    bool, // the thread has finished
	from:     string,
}

// Starts a connection to a host and a port. It is made by a thread, so nothing waits here: the queue gets `.Open`
// when it is made, or `.Close` with the reason when it could not be.
tcp_open_client :: proc(host: string, port: int, allocator := context.allocator) -> ^Tcp_Endpoint {
	e := new(Tcp_Endpoint, allocator)
	e.host, e.port = strings.clone(host, allocator), port
	e.queue = make([dynamic]Tcp_Happened, 0, 16, allocator)
	e.conns = make([dynamic]^Tcp_Conn, 0, 1, allocator)
	e.dialing = true
	// the thread frees its own record when it ends, so a client let go of while it is dialing can be left to it
	thread.create_and_start_with_data(e, tcp_dial_thread, self_cleanup = true)
	return e
}

// Starts listening on every network interface at `port` (0 lets the system choose). On failure `error` says why
// and nothing is left open.
tcp_open_server :: proc(port: int, allocator := context.allocator) -> ^Tcp_Endpoint {
	e := new(Tcp_Endpoint, allocator)
	e.server = true
	e.queue = make([dynamic]Tcp_Happened, 0, 16, allocator)
	e.conns = make([dynamic]^Tcp_Conn, 0, 4, allocator)
	socket, err := net.listen_tcp(net.Endpoint{address = net.IP4_Any, port = port}, 16)
	if err != nil {
		busy := false
		if bind_err, is_bind := err.(net.Bind_Error); is_bind && bind_err == .Address_In_Use {
			busy = true
		}
		if listen_err, is_listen := err.(net.Listen_Error); is_listen && listen_err == .Address_In_Use {
			busy = true
		}
		e.error = .Port_Busy if busy else .Port_Refused
		return e
	}
	net.set_blocking(socket, false)
	e.listener, e.port = socket, port
	if endpoint, got := net.bound_endpoint(socket); got == nil {
		e.port = endpoint.port
	}
	e.thread = thread.create_and_start_with_data(e, tcp_accept_thread)
	return e
}

// Ends every connection and lets go of everything the endpoint held. A client that is still making its
// connection (which cannot be called off) is left to its thread, which lets go of it when it is through.
tcp_close_endpoint :: proc(e: ^Tcp_Endpoint) {
	if e == nil {
		return
	}
	sync.atomic_store(&e.stop, true)
	{
		sync.guard(&e.lock)
		if e.dialing {
			e.abandoned = true
			return
		}
	}
	if !e.server {
		// the thread notices it was told to stop within a read's timeout
		for _ in 0 ..< 2000 {
			if sync.atomic_load(&e.finished) {
				break
			}
			time.sleep(time.Millisecond)
		}
	}
	tcp_release(e, true)
}

@(private)
tcp_release :: proc(e: ^Tcp_Endpoint, join_main: bool) {
	if e.thread != nil && join_main {
		thread.join(e.thread)
		thread.destroy(e.thread)
	}
	if e.server && e.error == .None {
		net.close(e.listener)
	}
	heap := runtime.heap_allocator()
	for c in e.conns {
		if c.thread != nil {
			thread.join(c.thread)
			thread.destroy(c.thread)
		}
		for b in c.outbox {
			delete(b, heap)
		}
		delete(c.outbox)
		delete(c.from, heap)
		free(c, heap)
	}
	for h in e.queue {
		delete(h.text, heap)
		delete(h.from, heap)
	}
	allocator := e.queue.allocator
	delete(e.queue)
	delete(e.conns)
	delete(e.host, allocator)
	free(e, allocator)
}

// Whether the endpoint can still do something: a listener always, a client until its connection ended.
tcp_alive :: proc(e: ^Tcp_Endpoint) -> bool {
	if e == nil || e.error != .None {
		return false
	}
	return e.server || !sync.atomic_load(&e.done)
}

// Moves what happened into `out`, oldest first, the text copied with `allocator`: the caller frees it.
tcp_take :: proc(e: ^Tcp_Endpoint, out: ^[dynamic]Tcp_Happened, allocator := context.allocator) {
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

// Sends bytes to one client of the endpoint (a number, from 1) or to all of them (0). Gives how many connections
// were given them: 0 when there is none to send to.
tcp_send_to :: proc(e: ^Tcp_Endpoint, data: []byte, client := 0) -> int {
	if e == nil || len(data) == 0 {
		return 0
	}
	sync.guard(&e.lock)
	heap := runtime.heap_allocator()
	given := 0
	for c in e.conns {
		if sync.atomic_load(&c.ended) || c.closing || (client != 0 && c.id != client) {
			continue
		}
		copied := make([]byte, len(data), heap)
		copy(copied, data)
		append(&c.outbox, copied)
		given += 1
	}
	return given
}

// Ends one client of a server (a number, from 1), or the connection of a client endpoint (0).
tcp_end_client :: proc(e: ^Tcp_Endpoint, client := 0) {
	if e == nil {
		return
	}
	sync.guard(&e.lock)
	for c in e.conns {
		if client == 0 || c.id == client {
			c.closing = true
		}
	}
}

@(private)
tcp_push :: proc(e: ^Tcp_Endpoint, kind: Tcp_Kind, client: int, text, from: string) {
	heap := runtime.heap_allocator()
	sync.guard(&e.lock)
	append(&e.queue, Tcp_Happened{kind = kind, client = client, text = strings.clone(text, heap), from = strings.clone(from, heap)})
}

@(private)
tcp_dial_thread :: proc(data: rawptr) {
	e := (^Tcp_Endpoint)(data)
	context.allocator = runtime.heap_allocator()
	if tcp_dial(e) {
		// let go while it was dialing: nobody will read what happened
		tcp_release(e, false)
		return
	}
	sync.atomic_store(&e.finished, true)
}

// Makes the connection and serves it. Gives true when the sketch let go of the endpoint while it was dialing.
@(private)
tcp_dial :: proc(e: ^Tcp_Endpoint) -> (abandoned: bool) {
	defer free_all(context.temp_allocator)
	address := fmt.tprintf("%s:%d", e.host, e.port)
	socket, err := net.dial_tcp_from_hostname_and_port_string(address)
	{
		sync.guard(&e.lock)
		e.dialing = false
		abandoned = e.abandoned
	}
	if abandoned {
		if err == nil {
			net.close(socket)
		}
		return true
	}
	if err != nil {
		tcp_push(e, .Close, 1, "the connection could not be made", e.host)
		sync.atomic_store(&e.done, true)
		return false
	}
	conn := new(Tcp_Conn)
	conn.endpoint, conn.id, conn.socket = e, 1, socket
	conn.from = strings.clone(e.host)
	{
		sync.guard(&e.lock)
		append(&e.conns, conn)
	}
	net.set_option(socket, .Receive_Timeout, 20 * time.Millisecond)
	tcp_push(e, .Open, 1, "", e.host)
	tcp_serve(conn)
	sync.atomic_store(&e.done, true)
	return false
}

@(private)
tcp_accept_thread :: proc(data: rawptr) {
	e := (^Tcp_Endpoint)(data)
	context.allocator = runtime.heap_allocator()
	for !sync.atomic_load(&e.stop) {
		client, source, err := net.accept_tcp(e.listener)
		if err != nil {
			time.sleep(2 * time.Millisecond)
			continue
		}
		from := strings.clone(net.address_to_string(source.address, context.temp_allocator))
		free_all(context.temp_allocator)
		alive := 0
		{
			sync.guard(&e.lock)
			for c in e.conns {
				if !sync.atomic_load(&c.ended) {
					alive += 1
				}
			}
		}
		if alive >= TCP_MAX_CLIENTS {
			net.close(client)
			delete(from)
			continue
		}
		conn := new(Tcp_Conn)
		e.next += 1
		conn.endpoint, conn.id, conn.socket, conn.from = e, e.next, client, from
		net.set_option(client, .Receive_Timeout, 20 * time.Millisecond)
		{
			sync.guard(&e.lock)
			append(&e.conns, conn)
		}
		tcp_push(e, .Open, conn.id, "", from)
		conn.thread = thread.create_and_start_with_data(conn, tcp_conn_thread)
	}
}

@(private)
tcp_conn_thread :: proc(data: rawptr) {
	context.allocator = runtime.heap_allocator()
	tcp_serve((^Tcp_Conn)(data))
}

// Reads a connection until it ends, sending what is waiting to go between reads.
@(private)
tcp_serve :: proc(conn: ^Tcp_Conn) {
	e := conn.endpoint
	chunk := make([]byte, 4096)
	pending := make([dynamic]byte)
	defer {
		delete(chunk)
		delete(pending)
	}
	reason := "the connection was closed"
	loop: for !sync.atomic_load(&e.stop) {
		n, err := net.recv_tcp(conn.socket, chunk)
		switch {
		case err == .Timeout || err == .Would_Block || err == .Interrupted:
		case err != nil:
			reason = "the connection was lost"
			break loop
		case n == 0:
			break loop
		case:
			append(&pending, ..chunk[:n])
			for {
				newline := -1
				for b, i in pending {
					if b == '\n' {
						newline = i
						break
					}
				}
				if newline < 0 {
					if len(pending) >= TCP_MAX_LINE {
						tcp_push(e, .Line, conn.id, string(pending[:]), conn.from)
						clear(&pending)
					}
					break
				}
				line := pending[:newline]
				if len(line) > 0 && line[len(line) - 1] == '\r' {
					line = line[:len(line) - 1]
				}
				tcp_push(e, .Line, conn.id, string(line), conn.from)
				remove_range(&pending, 0, newline + 1)
			}
		}
		// what is waiting to go
		outgoing: [dynamic][]byte
		closing: bool
		{
			sync.guard(&e.lock)
			outgoing = conn.outbox
			conn.outbox = make([dynamic][]byte)
			closing = conn.closing
		}
		failed := false
		for b in outgoing {
			if !failed {
				if _, send_err := net.send_tcp(conn.socket, b); send_err != nil {
					failed = true
				}
			}
			delete(b)
		}
		delete(outgoing)
		if failed {
			reason = "the connection was lost"
			break loop
		}
		if closing {
			reason = "the connection was closed here"
			break loop
		}
	}
	// the last of a line that never got its newline is a line too
	if len(pending) > 0 {
		tcp_push(e, .Line, conn.id, string(pending[:]), conn.from)
	}
	net.close(conn.socket)
	tcp_push(e, .Close, conn.id, reason, conn.from)
	sync.atomic_store(&conn.ended, true)
}
