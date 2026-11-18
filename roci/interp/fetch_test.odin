// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "../gfx"
import "../platform"
import "core:os"
import "core:testing"

// Plays the server: answers the open fetch that was asked `which`th.
@(private = "file")
serve :: proc(p: ^Interp, which: int, status: int, body: string, problem := "") {
	if which < len(p.fetches) {
		platform.fetch_deliver(p.fetches[which].id, status, transmute([]u8)body, problem)
	}
}

@(test)
test_the_block_of_fetch_runs_when_the_answer_has_come_and_reply_is_the_answer :: proc(t: ^testing.T) {
	p := run_text(t, "w = window size 10 10\nfetch \"https://example.org/hi\" [\n  print reply.status\n  print reply.ok\n  print reply.text\n  print reply.problem\n]\nprint \"asked\"", 2)
	defer finish(p)
	testing.expect_value(t, printed(p), "asked")
	testing.expect_value(t, len(p.fetches), 1)
	serve(p, 0, 200, "hello")
	roci.step()
	testing.expect_value(t, printed(p), "asked\n200\ntrue\nhello\n")
	testing.expect_value(t, len(p.fetches), 0)
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_a_fetch_that_got_nothing_says_why_in_reply_problem :: proc(t: ^testing.T) {
	p := run_text(t, "w = window size 10 10\nfetch \"https://example.org/x\" [\n  print reply.status\n  print reply.ok\n  print reply.problem\n]", 2)
	defer finish(p)
	serve(p, 0, 0, "", "Could not resolve host")
	roci.step()
	testing.expect_value(t, printed(p), "0\nfalse\nCould not resolve host")
}

@(test)
test_a_status_that_is_not_a_success_is_ok_false :: proc(t: ^testing.T) {
	p := run_text(t, "w = window size 10 10\nfetch \"https://example.org/x\" [ print reply.ok\n print reply.status ]", 2)
	defer finish(p)
	serve(p, 0, 404, "gone")
	roci.step()
	testing.expect_value(t, printed(p), "false\n404")
}

@(test)
test_fetch_picture_reads_what_came_as_a_picture_and_says_when_it_is_not_one :: proc(t: ^testing.T) {
	p := run_text(t, "w = window size 10 10\nlogo = picture from [ red ] size 1 1\nbad = 0\nfetch picture \"https://example.org/a.png\" [\n  logo = reply.picture\n  print reply.problem\n]\nfetch picture \"https://example.org/b.png\" [ print reply.problem ]", 2)
	defer finish(p)
	// a real picture: a one pixel PNG
	colour := []u8{255, 0, 0, 255}
	png, encoded := gfx.png_encode(gfx.Image{1, 1, colour}, context.temp_allocator)
	testing.expect(t, encoded)
	if len(p.fetches) == 2 {
		platform.fetch_deliver(p.fetches[0].id, 200, png, "")
		serve(p, 1, 200, "not a picture")
	}
	roci.step()
	testing.expect_value(t, printed(p), "\nwhat came is not a picture this can read")
}

@(test)
test_post_sends_its_text_and_runs_its_block_like_fetch :: proc(t: ^testing.T) {
	p := run_text(t, "w = window size 10 10\npost \"https://example.org/p\" \"ada 120\" [ print reply.status ] header \"X-A: 1\"", 2)
	defer finish(p)
	testing.expect_value(t, len(p.fetches), 1)
	serve(p, 0, 201, "")
	roci.step()
	testing.expect_value(t, printed(p), "201")
}

@(test)
test_reply_outside_a_fetch_block_is_an_answer_of_nothing :: proc(t: ^testing.T) {
	p := run_text(t, "print reply.status\nprint reply.ok\nprint reply.text")
	defer finish(p)
	testing.expect_value(t, printed(p), "0\nfalse\n")
}

@(test)
test_a_sketch_has_at_most_eight_fetches_open :: proc(t: ^testing.T) {
	p := run_text(t, "w = window size 10 10\nfor i from 1 to 20 [\n  fetch \"https://example.org/x\" [ print reply.status ]\n]", 2)
	defer finish(p)
	testing.expect_value(t, len(p.fetches), MAX_OPEN_FETCHES)
}

@(test)
test_the_fetches_a_sketch_left_open_are_let_go_with_it :: proc(t: ^testing.T) {
	p := run_text(t, "w = window size 10 10\nfetch \"https://example.org/x\" [ print 1 ]", 2)
	testing.expect_value(t, len(p.fetches), 1)
	finish(p)
}

@(test)
test_the_fetch_example_shows_what_came :: proc(t: ^testing.T) {
	bytes, err := os.read_entire_file("examples/fetch/sketch.roci", context.temp_allocator)
	if !testing.expect(t, err == nil) {
		return
	}
	p := run_text(t, string(bytes), 2)
	defer finish(p)
	testing.expect_value(t, len(p.fetches), 2)
	colour := []u8{0, 128, 255, 255}
	png, encoded := gfx.png_encode(gfx.Image{1, 1, colour}, context.temp_allocator)
	testing.expect(t, encoded)
	serve(p, 0, 200, "<html>hello</html>")
	platform.fetch_deliver(p.fetches[1].id, 200, png, "")
	roci.step()
	testing.expect_value(t, len(p.fetches), 0)
	testing.expect_value(t, len(p.errors), 0)
	global_text :: proc(p: ^Interp, name: string) -> string {
		return as_text(global_named(p, name))
	}
	testing.expect_value(t, global_text(p, "status"), "the page came: 200")
	testing.expect_value(t, as_bool(global_named(p, "got_logo")), true)
	testing.expect_value(t, as_number(global_named(p, "page_length")), 18)
}
