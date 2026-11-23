// SPDX-License-Identifier: 0BSD
package platform

import "core:sync"
import "core:testing"
import "core:time"

@(private = "file")
gather :: proc(e: ^Tcp_Endpoint, want: int, got: ^[dynamic]Tcp_Happened) {
	for _ in 0 ..< 600 {
		tcp_take(e, got)
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
test_a_client_and_a_server_talk_in_lines :: proc(t: ^testing.T) {
	server := tcp_open_server(0)
	defer tcp_close_endpoint(server)
	if !testing.expect_value(t, server.error, Tcp_Problem.None) {
		return
	}
	testing.expect(t, server.port > 0)
	client := tcp_open_client("127.0.0.1", server.port)
	defer tcp_close_endpoint(client)

	at_client := make([dynamic]Tcp_Happened)
	defer free_happened(at_client)
	at_server := make([dynamic]Tcp_Happened)
	defer free_happened(at_server)
	gather(client, 1, &at_client)
	gather(server, 1, &at_server)
	testing.expect_value(t, len(at_client), 1)
	testing.expect_value(t, len(at_server), 1)
	if len(at_client) < 1 || len(at_server) < 1 {
		return
	}
	testing.expect_value(t, at_client[0].kind, Tcp_Kind.Open)
	testing.expect_value(t, at_server[0].kind, Tcp_Kind.Open)
	testing.expect_value(t, at_server[0].client, 1)
	testing.expect_value(t, at_server[0].from, "127.0.0.1")
	testing.expect(t, tcp_alive(client))

	// lines in, a carriage return before the newline left off, a line cut in two sends joined again
	testing.expect_value(t, tcp_send_to(client, transmute([]byte)string("hello\r\nworld\npart"), 0), 1)
	gather(server, 3, &at_server)
	testing.expect_value(t, len(at_server), 3)
	if len(at_server) == 3 {
		testing.expect_value(t, at_server[1].kind, Tcp_Kind.Line)
		testing.expect_value(t, at_server[1].text, "hello")
		testing.expect_value(t, at_server[2].text, "world")
	}
	testing.expect_value(t, tcp_send_to(client, transmute([]byte)string("ial\n"), 0), 1)
	gather(server, 4, &at_server)
	if len(at_server) == 4 {
		testing.expect_value(t, at_server[3].text, "partial")
	}

	// the server answers one client, and then all of them
	testing.expect_value(t, tcp_send_to(server, transmute([]byte)string("pong\n"), 1), 1)
	testing.expect_value(t, tcp_send_to(server, transmute([]byte)string("everyone\n"), 0), 1)
	testing.expect_value(t, tcp_send_to(server, transmute([]byte)string("nobody\n"), 9), 0) // no such client
	gather(client, 3, &at_client)
	testing.expect_value(t, len(at_client), 3)
	if len(at_client) == 3 {
		testing.expect_value(t, at_client[1].text, "pong")
		testing.expect_value(t, at_client[2].text, "everyone")
	}

	// the client ends it: both sides say so
	tcp_end_client(client)
	gather(client, 4, &at_client)
	gather(server, 5, &at_server)
	testing.expect_value(t, at_client[len(at_client) - 1].kind, Tcp_Kind.Close)
	testing.expect_value(t, at_server[len(at_server) - 1].kind, Tcp_Kind.Close)
	testing.expect_value(t, at_server[len(at_server) - 1].client, 1)
	testing.expect(t, !tcp_alive(client))
	testing.expect_value(t, tcp_send_to(client, transmute([]byte)string("late\n"), 0), 0)
}

@(test)
test_a_connection_that_cannot_be_made_says_so :: proc(t: ^testing.T) {
	client := tcp_open_client("127.0.0.1", 1) // nothing listens on port 1
	defer tcp_close_endpoint(client)
	got := make([dynamic]Tcp_Happened)
	defer free_happened(got)
	gather(client, 1, &got)
	testing.expect_value(t, len(got), 1)
	if len(got) == 1 {
		testing.expect_value(t, got[0].kind, Tcp_Kind.Close)
		testing.expect(t, len(got[0].text) > 0)
	}
	for _ in 0 ..< 200 {
		if !tcp_alive(client) {
			break
		}
		time.sleep(5 * time.Millisecond)
	}
	testing.expect(t, !tcp_alive(client))
}

@(test)
test_a_port_that_is_taken_is_said :: proc(t: ^testing.T) {
	first := tcp_open_server(0)
	defer tcp_close_endpoint(first)
	testing.expect_value(t, first.error, Tcp_Problem.None)
	second := tcp_open_server(first.port)
	defer tcp_close_endpoint(second)
	testing.expect_value(t, second.error, Tcp_Problem.Port_Busy)
	testing.expect(t, !tcp_alive(second))
	testing.expect_value(t, tcp_send_to(second, transmute([]byte)string("x"), 0), 0)
}

@(test)
test_a_client_let_go_of_while_it_is_dialing_is_cleaned_up_by_its_thread :: proc(t: ^testing.T) {
	// the connection is refused at once, so the thread is through almost as soon as it starts; whichever
	// of the two gets there first, nothing is left over and nothing is freed twice
	for _ in 0 ..< 20 {
		client := tcp_open_client("127.0.0.1", 1)
		tcp_close_endpoint(client)
	}
	// Windows tries a refused connection again for about two seconds before it gives up, so the threads are
	// waited for (the other tests' clients count too, and end within the wait); then a moment for each thread
	// to free its own record after its procedure returns
	for _ in 0 ..< 1000 {
		if sync.atomic_load(&tcp_client_threads) == 0 {
			break
		}
		time.sleep(10 * time.Millisecond)
	}
	testing.expect_value(t, sync.atomic_load(&tcp_client_threads), 0)
	time.sleep(100 * time.Millisecond)
}
