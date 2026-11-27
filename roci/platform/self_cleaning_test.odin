// SPDX-License-Identifier: 0BSD
package platform

import "core:mem"
import "core:strings"
import "core:testing"

// A thread that frees its own record as it ends does so when it likes, which may be after the allocator of whoever started it
// has been looked at (a test's leak check did, and counted 288 bytes as a leak about one run in a hundred, or a free it did not
// know in the next test of that worker). So a record made by the code that starts one of these must not come from the caller's
// allocator.
@(private = "file")
starts_threads_under :: proc(track: ^mem.Tracking_Allocator, client: ^^Tcp_Endpoint, fetch: ^int) {
	context.allocator = mem.tracking_allocator(track)
	fetch^ = fetch_ask("http://127.0.0.1:1/") // refused at once; its thread cleans itself up
	client^ = tcp_open_client("127.0.0.1", 1) // so does the dialing thread of a client
}

@(test)
test_the_record_of_a_thread_that_frees_itself_is_not_made_by_the_callers_allocator :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	client: ^Tcp_Endpoint
	fetch := 0
	starts_threads_under(&track, &client, &fetch)
	for _, entry in track.allocation_map {
		in_thread_code := strings.contains(entry.location.file_path, "thread")
		testing.expectf(t, !in_thread_code, "%d bytes made at %v by the caller's allocator would be freed by a thread after the check", entry.size, entry.location)
	}
	// what the caller owns is its own: the client's endpoint is let go of with the allocator that made it
	{
		context.allocator = mem.tracking_allocator(&track)
		tcp_close_endpoint(client)
	}
	result := wait_for_fetch(fetch)
	delete(result.body)
	delete(result.problem)
	testing.expect(t, len(track.bad_free_array) == 0, "nothing was freed that this allocator did not make")
}
