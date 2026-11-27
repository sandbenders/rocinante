// SPDX-License-Identifier: 0BSD
//
// What the threads of a connection or a fetch hand the sketch's thread: a server's connections each push the lines they read into
// the one queue the sketch takes from, and fetches finishing on their own threads put their answers in one table. These tests have
// several of them at work at once and check that every line and every answer comes once, whole and from the right place. Both go
// over loopback TCP, which loses nothing, so the counts are exact; they are kept small, since a heavy test here disturbed the memory
// checks of the other tests' own network threads.
package platform

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:testing"
import "core:thread"
import "core:time"

TCP_PEERS :: 4
LINES_EACH :: 60

@(test)
test_the_lines_of_several_clients_reach_a_server_whole_once_and_in_each_clients_order :: proc(t: ^testing.T) {
	server := tcp_open_server(0)
	defer tcp_close_endpoint(server)
	if !testing.expect_value(t, server.error, Tcp_Problem.None) {
		return
	}
	clients: [TCP_PEERS]^Tcp_Endpoint
	for i in 0 ..< TCP_PEERS {
		clients[i] = tcp_open_client("127.0.0.1", server.port)
	}
	defer for c in clients {
		tcp_close_endpoint(c)
	}
	at_server := make([dynamic]Tcp_Happened)
	defer release_happened(at_server)
	wait_until(server, TCP_PEERS, &at_server) // every client has come in
	opened := 0
	for h in at_server {
		opened += int(h.kind == .Open)
	}
	if !testing.expect_value(t, opened, TCP_PEERS) {
		return
	}
	// all of them write at once: each line says who wrote it and which it is
	for i in 0 ..< LINES_EACH {
		for c, who in clients {
			line := fmt.tprintf("c%d-%d\n", who, i)
			testing.expect_value(t, tcp_send_to(c, transmute([]byte)line, 0), 1)
		}
	}
	wait_until(server, TCP_PEERS + TCP_PEERS * LINES_EACH, &at_server)
	next := make(map[int]int, context.temp_allocator) // the line each of the server's connections should send next
	seen := make(map[string]int, context.temp_allocator)
	for h in at_server {
		if h.kind != .Line {
			continue
		}
		seen[h.text] += 1
		parts := strings.split(strings.trim_prefix(h.text, "c"), "-", context.temp_allocator)
		who, i := 0, 0
		who_ok, i_ok := false, false
		if len(parts) == 2 {
			who, who_ok = strconv.parse_int(parts[0])
			i, i_ok = strconv.parse_int(parts[1])
		}
		if !who_ok || !i_ok || !strings.has_prefix(h.text, "c") || who < 0 || who >= TCP_PEERS {
			testing.expectf(t, false, "`%s` is not a line anybody wrote: it was cut or mixed", h.text)
			continue
		}
		testing.expectf(t, i == next[h.client], "connection %d sent `%s` when line %d was due", h.client, h.text, next[h.client])
		next[h.client] = i + 1
	}
	testing.expect_value(t, len(seen), TCP_PEERS * LINES_EACH)
	for text, times in seen {
		testing.expectf(t, times == 1, "`%s` arrived %d times", text, times)
	}
	testing.expect_value(t, len(next), TCP_PEERS) // four connections, each of whose lines came in a row
}

@(private = "file")
release_happened :: proc(got: [dynamic]Tcp_Happened) {
	for h in got {
		delete(h.text)
		delete(h.from)
	}
	delete(got)
}

// Takes from `e` until `want` things have come, for six seconds at most.
@(private = "file")
wait_until :: proc(e: ^Tcp_Endpoint, want: int, got: ^[dynamic]Tcp_Happened) {
	for _ in 0 ..< 1200 {
		tcp_take(e, got)
		if len(got) >= want {
			return
		}
		time.sleep(5 * time.Millisecond)
	}
}

FETCHES :: 4

@(test)
test_fetches_that_finish_on_their_own_threads_each_give_their_own_answer :: proc(t: ^testing.T) {
	servers: [FETCHES]^Test_Server
	ports: [FETCHES]int
	threads: [FETCHES]^thread.Thread
	for i in 0 ..< FETCHES {
		reply := fmt.tprintf("HTTP/1.1 200 OK\r\nContent-Length: 7\r\nConnection: close\r\n\r\nanswer%d", i)
		ok: bool
		servers[i], ports[i], threads[i], ok = start_server(strings.clone(reply, context.temp_allocator))
		if !testing.expect(t, ok, "a test server could not listen") {
			for j in 0 ..< i {
				stop_server(servers[j], threads[j])
			}
			return
		}
	}
	defer for i in 0 ..< FETCHES {
		stop_server(servers[i], threads[i])
	}
	ids: [FETCHES]int
	for i in 0 ..< FETCHES {
		ids[i] = fetch_ask(fmt.tprintf("http://127.0.0.1:%d/%d", ports[i], i))
	}
	for i in 0 ..< FETCHES {
		result := wait_for_fetch(ids[i])
		testing.expect_value(t, result.state, Fetch_State.Done)
		testing.expect_value(t, result.status, 200)
		testing.expect_value(t, string(result.body), fmt.tprintf("answer%d", i))
		delete(result.body)
		delete(result.problem)
	}
	for i in 1 ..< FETCHES {
		testing.expect(t, ids[i] != ids[i - 1], "each fetch has its own number")
	}
}
