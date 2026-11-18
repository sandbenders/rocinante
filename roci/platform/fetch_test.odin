// SPDX-License-Identifier: 0BSD
package platform

import "core:fmt"
import "core:net"
import "core:strings"
import "core:testing"
import "core:thread"
import "core:time"

// A web server for one request: it reads what is sent and answers with `reply`.
Test_Server :: struct {
	socket:  net.TCP_Socket,
	reply:   string,
	request: [4096]u8,
	length:  int,
}

serve_once :: proc(server: ^Test_Server) {
	client, _, err := net.accept_tcp(server.socket)
	if err != nil {
		return
	}
	defer net.close(client)
	// the request ends at the empty line after its headers (a post's body is not waited for)
	for server.length < len(server.request) {
		n, read_err := net.recv_tcp(client, server.request[server.length:])
		if read_err != nil || n == 0 {
			break
		}
		server.length += n
		if strings.contains(string(server.request[:server.length]), "\r\n\r\n") {
			break
		}
	}
	net.send_tcp(client, transmute([]u8)server.reply)
}

start_server :: proc(reply: string) -> (server: ^Test_Server, port: int, thread_: ^thread.Thread, ok: bool) {
	server = new(Test_Server)
	server.reply = reply
	socket, err := net.listen_tcp({address = net.IP4_Loopback, port = 0})
	if err != nil {
		free(server)
		return nil, 0, nil, false
	}
	server.socket = socket
	endpoint, _ := net.bound_endpoint(socket)
	thread_ = thread.create_and_start_with_poly_data(server, serve_once, self_cleanup = false)
	return server, endpoint.port, thread_, true
}

stop_server :: proc(server: ^Test_Server, thread_: ^thread.Thread) {
	net.close(server.socket)
	thread.join(thread_)
	thread.destroy(thread_)
	free(server)
}

wait_for_fetch :: proc(id: int, allocator := context.allocator) -> Fetch_Result {
	for _ in 0 ..< 500 {
		result := fetch_take(id, allocator)
		if result.state != .Waiting {
			return result
		}
		time.sleep(10 * time.Millisecond)
	}
	return {state = .Waiting}
}

@(test)
test_a_fetch_gets_the_status_and_the_bytes_without_waiting :: proc(t: ^testing.T) {
	server, port, th, started := start_server("HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello")
	if !testing.expect(t, started, "the test server could not listen") {
		return
	}
	defer stop_server(server, th)
	id := fetch_ask(strings.concatenate({"http://127.0.0.1:", itoa(port), "/hi"}, context.temp_allocator))
	result := wait_for_fetch(id)
	defer delete(result.body)
	defer delete(result.problem)
	testing.expect_value(t, result.state, Fetch_State.Done)
	testing.expect_value(t, result.status, 200)
	testing.expect_value(t, string(result.body), "hello")
	testing.expect(t, strings.has_prefix(string(server.request[:server.length]), "GET /hi HTTP/1.1"), string(server.request[:server.length]))
	testing.expect(t, strings.contains(string(server.request[:server.length]), "User-Agent: rocinante"))
}

@(test)
test_a_fetch_says_the_status_of_an_answer_that_is_not_a_success :: proc(t: ^testing.T) {
	server, port, th, started := start_server("HTTP/1.1 404 Not Found\r\nContent-Length: 4\r\nConnection: close\r\n\r\ngone")
	if !testing.expect(t, started) {
		return
	}
	defer stop_server(server, th)
	result := wait_for_fetch(fetch_ask(strings.concatenate({"http://127.0.0.1:", itoa(port), "/"}, context.temp_allocator)))
	defer delete(result.body)
	testing.expect_value(t, result.state, Fetch_State.Done)
	testing.expect_value(t, result.status, 404)
	testing.expect_value(t, string(result.body), "gone")
}

@(test)
test_a_fetch_posts_its_body_and_headers :: proc(t: ^testing.T) {
	server, port, th, started := start_server("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
	if !testing.expect(t, started) {
		return
	}
	defer stop_server(server, th)
	url := strings.concatenate({"http://127.0.0.1:", itoa(port), "/send"}, context.temp_allocator)
	result := wait_for_fetch(fetch_ask(url, true, "{\"a\":1}", {"Content-Type: application/json"}))
	defer delete(result.body)
	testing.expect_value(t, result.status, 200)
	sent := string(server.request[:server.length])
	testing.expect(t, strings.has_prefix(sent, "POST /send HTTP/1.1"), sent)
	testing.expect(t, strings.contains(sent, "Content-Type: application/json"), sent)
}

@(test)
test_a_request_let_go_takes_no_answer :: proc(t: ^testing.T) {
	id := fetch_new()
	fetch_forget(id)
	fetch_deliver(id, 200, transmute([]u8)string("late"), "")
	got := fetch_take(id)
	defer delete(got.problem)
	testing.expect_value(t, got.state, Fetch_State.Failed)
	fetch_forget(id) // twice is harmless
}

@(test)
test_a_fetch_that_cannot_connect_or_uses_another_protocol_fails_with_a_reason :: proc(t: ^testing.T) {
	// a port nothing listens on: open one and close it
	socket, _ := net.listen_tcp({address = net.IP4_Loopback, port = 0})
	endpoint, _ := net.bound_endpoint(socket)
	net.close(socket)
	refused := wait_for_fetch(fetch_ask(strings.concatenate({"http://127.0.0.1:", itoa(endpoint.port), "/"}, context.temp_allocator)))
	defer delete(refused.problem)
	testing.expect_value(t, refused.state, Fetch_State.Failed)
	testing.expect(t, refused.problem != "")
	testing.expect_value(t, refused.status, 0)
	// only http and https are followed
	other := wait_for_fetch(fetch_ask("file:///etc/passwd"))
	defer delete(other.problem)
	testing.expect_value(t, other.state, Fetch_State.Failed)
}

@(test)
test_the_table_gives_each_answer_once :: proc(t: ^testing.T) {
	id := fetch_new()
	testing.expect_value(t, fetch_take(id).state, Fetch_State.Waiting)
	fetch_deliver(id, 200, transmute([]u8)string("abc"), "")
	fetch_deliver(id, 500, nil, "") // a second answer changes nothing
	got := fetch_take(id)
	defer delete(got.body)
	testing.expect_value(t, got.status, 200)
	testing.expect_value(t, string(got.body), "abc")
	again := fetch_take(id)
	defer delete(again.problem)
	testing.expect_value(t, again.state, Fetch_State.Failed) // taken already
	failed := fetch_new()
	fetch_deliver(failed, 0, nil, "no network")
	lost := fetch_take(failed)
	defer delete(lost.problem)
	testing.expect_value(t, lost.problem, "no network")
}

itoa :: proc(n: int) -> string {
	return fmt.tprintf("%d", n)
}
