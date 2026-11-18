// SPDX-License-Identifier: 0BSD
package platform

import "core:crypto/legacy/sha1"
import "core:encoding/base64"
import "core:fmt"
import "core:net"
import "core:strings"
import "core:testing"
import "core:thread"
import "core:time"

// A web socket server for one connection, as small as the protocol allows: it does the handshake, says "welcome", answers each
// text message with "echo " and the text, each binary message with itself, and a close with a close.
@(private = "file")
Echo_Server :: struct {
	listener: net.TCP_Socket,
	port:     int,
	thread:   ^thread.Thread,
	silent:   bool, // accept and never answer the handshake
}

@(private = "file")
start_echo :: proc(silent := false) -> ^Echo_Server {
	s := new(Echo_Server)
	s.silent = silent
	socket, _ := net.listen_tcp(net.Endpoint{address = net.IP4_Loopback, port = 0})
	s.listener = socket
	endpoint, _ := net.bound_endpoint(socket)
	s.port = endpoint.port
	s.thread = thread.create_and_start_with_data(s, echo_serve)
	return s
}

@(private = "file")
stop_echo :: proc(s: ^Echo_Server) {
	net.close(s.listener)
	thread.join(s.thread)
	thread.destroy(s.thread)
	free(s)
}

@(private = "file")
read_exact :: proc(socket: net.TCP_Socket, n: int) -> (data: []byte, ok: bool) {
	data = make([]byte, n)
	got := 0
	for got < n {
		read, err := net.recv_tcp(socket, data[got:])
		if err != nil || read <= 0 {
			delete(data)
			return nil, false
		}
		got += read
	}
	return data, true
}

@(private = "file")
send_frame :: proc(socket: net.TCP_Socket, opcode: byte, payload: []byte) {
	header := []byte{0x80 | opcode, byte(len(payload))}
	net.send_tcp(socket, header)
	if len(payload) > 0 {
		net.send_tcp(socket, payload)
	}
}

@(private = "file")
echo_serve :: proc(data: rawptr) {
	s := (^Echo_Server)(data)
	client, _, err := net.accept_tcp(s.listener)
	if err != nil {
		return
	}
	defer net.close(client)
	request := make([dynamic]byte)
	defer delete(request)
	one: [1]byte
	for !strings.has_suffix(string(request[:]), "\r\n\r\n") {
		n, read_err := net.recv_tcp(client, one[:])
		if read_err != nil || n <= 0 {
			return
		}
		append(&request, one[0])
	}
	if s.silent {
		// never answers: the client waits until it is told to stop
		for {
			n, read_err := net.recv_tcp(client, one[:])
			if read_err != nil || n <= 0 {
				return
			}
		}
	}
	key := ""
	rest := string(request[:])
	for line in strings.split_lines_iterator(&rest) {
		if strings.has_prefix(strings.to_lower(line, context.temp_allocator), "sec-websocket-key:") {
			key = strings.trim_space(line[len("sec-websocket-key:"):])
		}
	}
	ctx: sha1.Context
	sha1.init(&ctx)
	sha1.update(&ctx, transmute([]byte)key)
	sha1.update(&ctx, transmute([]byte)string("258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
	digest: [20]byte
	sha1.final(&ctx, digest[:])
	accept, _ := base64.encode(digest[:], allocator = context.temp_allocator)
	reply := fmt.tprintf("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n\r\n", accept)
	net.send_tcp(client, transmute([]byte)reply)
	send_frame(client, 1, transmute([]byte)string("welcome"))
	for {
		head, ok := read_exact(client, 2)
		if !ok {
			return
		}
		opcode, length := head[0] & 15, int(head[1] & 127)
		delete(head)
		mask, mask_ok := read_exact(client, 4)
		if !mask_ok {
			return
		}
		payload: []byte
		if length > 0 {
			payload, ok = read_exact(client, length)
			if !ok {
				delete(mask)
				return
			}
			for i in 0 ..< length {
				payload[i] ~= mask[i % 4]
			}
		}
		delete(mask)
		switch opcode {
		case 1:
			send_frame(client, 1, transmute([]byte)fmt.tprintf("echo %s", string(payload)))
		case 2:
			send_frame(client, 2, payload)
		case 8:
			send_frame(client, 8, payload)
			delete(payload)
			return
		}
		delete(payload)
	}
}

@(private = "file")
gather :: proc(e: ^Ws_Endpoint, want: int, got: ^[dynamic]Tcp_Happened) {
	for _ in 0 ..< 600 {
		ws_take(e, got)
		if len(got) >= want {
			return
		}
		time.sleep(5 * time.Millisecond)
	}
}

@(private = "file")
free_happened :: proc(got: [dynamic]Tcp_Happened) {
	for h in got {
		delete(h.text)
		delete(h.from)
	}
	delete(got)
}

@(test)
test_a_web_socket_talks_both_ways_and_closes :: proc(t: ^testing.T) {
	server := start_echo()
	defer stop_echo(server)
	e := ws_open(fmt.tprintf("ws://127.0.0.1:%d/chat", server.port))
	defer ws_close_endpoint(e)
	got := make([dynamic]Tcp_Happened)
	defer free_happened(got)
	gather(e, 2, &got)
	testing.expect_value(t, len(got), 2)
	if len(got) < 2 {
		return
	}
	testing.expect_value(t, got[0].kind, Tcp_Kind.Open)
	testing.expect_value(t, got[0].from, fmt.tprintf("127.0.0.1:%d", server.port))
	testing.expect_value(t, got[1].kind, Tcp_Kind.Line)
	testing.expect_value(t, got[1].text, "welcome")
	testing.expect(t, ws_alive(e))
	testing.expect(t, ws_send_message(e, transmute([]byte)string("hi")))
	testing.expect(t, ws_send_message(e, []byte{65, 66, 67}, binary = true))
	gather(e, 4, &got)
	testing.expect_value(t, len(got), 4)
	if len(got) == 4 {
		testing.expect_value(t, got[2].text, "echo hi")
		testing.expect_value(t, got[3].text, "ABC")
	}
	ws_end(e)
	gather(e, 5, &got)
	testing.expect_value(t, len(got), 5)
	if len(got) == 5 {
		testing.expect_value(t, got[4].kind, Tcp_Kind.Close)
	}
	for _ in 0 ..< 200 {
		if !ws_alive(e) {
			break
		}
		time.sleep(5 * time.Millisecond)
	}
	testing.expect(t, !ws_alive(e))
	testing.expect(t, !ws_send_message(e, transmute([]byte)string("late")))
}

@(test)
test_a_web_socket_that_cannot_be_made_says_so :: proc(t: ^testing.T) {
	e := ws_open("ws://127.0.0.1:1/nothing")
	defer ws_close_endpoint(e)
	got := make([dynamic]Tcp_Happened)
	defer free_happened(got)
	gather(e, 1, &got)
	testing.expect_value(t, len(got), 1)
	if len(got) == 1 {
		testing.expect_value(t, got[0].kind, Tcp_Kind.Close)
		testing.expect(t, len(got[0].text) > 0)
	}
	// only the web socket schemes are taken
	other := ws_open("http://127.0.0.1:1/")
	defer ws_close_endpoint(other)
	more := make([dynamic]Tcp_Happened)
	defer free_happened(more)
	gather(other, 1, &more)
	testing.expect_value(t, len(more), 1)
}

@(test)
test_a_web_socket_let_go_of_while_it_connects_stops_at_once :: proc(t: ^testing.T) {
	server := start_echo(silent = true)
	defer stop_echo(server)
	e := ws_open(fmt.tprintf("ws://127.0.0.1:%d/", server.port))
	time.sleep(50 * time.Millisecond)
	started := time.tick_now()
	ws_close_endpoint(e)
	testing.expect(t, time.duration_seconds(time.tick_since(started)) < 2, "closing does not wait for the handshake")
}
