// SPDX-License-Identifier: 0BSD
package roci

import "core:strings"
import "core:testing"

import "gfx"
import "platform"

@(test)
test_c_fetch_gives_an_answer_once_it_has_come_and_forgets_it :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	request := abi_fetch("https://example.org/a", nil, nil)
	testing.expect(t, request > 0)
	testing.expect_value(t, abi_fetch_done(request), 0) // headless: nothing is fetched until a test answers
	testing.expect_value(t, abi_fetch_status(request), 0)
	platform.fetch_deliver(int(request), 200, transmute([]u8)string("hello"), "")
	testing.expect_value(t, abi_fetch_done(request), 1)
	testing.expect_value(t, abi_fetch_done(request), 1) // asking again does not lose it
	testing.expect_value(t, abi_fetch_status(request), 200)
	testing.expect_value(t, string(abi_fetch_text(request)), "hello")
	testing.expect_value(t, string(abi_fetch_problem(request)), "")
	abi_fetch_forget(request)
	testing.expect_value(t, abi_fetch_done(request), 1) // a request that is forgotten is a failed one
	testing.expect_value(t, abi_fetch_status(request), 0)
	abi_fetch_forget(request)
}

@(test)
test_c_fetch_says_why_nothing_came_and_posts_with_a_header :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	request := abi_fetch("https://example.org/p", "ada 120", "Content-Type: text/plain")
	platform.fetch_deliver(int(request), 0, nil, "Could not resolve host")
	testing.expect_value(t, abi_fetch_done(request), 1)
	testing.expect_value(t, abi_fetch_status(request), 0)
	testing.expect_value(t, string(abi_fetch_problem(request)), "Could not resolve host")
	testing.expect_value(t, abi_fetch_picture(request), 0)
	abi_fetch_forget(request)
}

@(test)
test_c_fetch_reads_a_picture_from_what_came :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	colour := []u8{255, 0, 0, 255}
	png, encoded := gfx.png_encode(gfx.Image{1, 1, colour}, context.temp_allocator)
	testing.expect(t, encoded)
	request := abi_fetch("https://example.org/a.png", nil, nil)
	platform.fetch_deliver(int(request), 200, png, "")
	testing.expect(t, abi_fetch_picture(request) != 0)
	text := abi_fetch_text(request)
	testing.expect(t, strings.has_prefix(string(text), "\x89PNG"))
	abi_fetch_forget(request)
	other := abi_fetch("https://example.org/b.png", nil, nil)
	platform.fetch_deliver(int(other), 200, transmute([]u8)string("no"), "")
	testing.expect_value(t, abi_fetch_picture(other), 0)
	abi_fetch_forget(other)
}
