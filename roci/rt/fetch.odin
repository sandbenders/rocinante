// SPDX-License-Identifier: 0BSD
//
// `fetch`, `fetch picture` and `post` in a compiled sketch: asking starts the fetch on a thread and keeps the procedure the
// block became; once a frame looks for answers, and the procedure of each that has come runs with `reply` holding what
// came back.
package rt

import "../"
import "../platform"

@(private)
Fetching :: struct {
	id:      int,
	body:    proc(),
	picture: bool,
}

// What `reply` holds while a block runs.
Reply :: struct {
	status:  int,
	text:    string,
	problem: string,
	picture: roci.Image,
}

@(thread_local) reply: Reply
@(thread_local) @(private) fetches: [dynamic]Fetching

MAX_OPEN_FETCHES :: 8

// `fetch "url" [ ... ]`, `post "url" "text" [ ... ] header "line"`.
fetch :: proc(address: string, posting: bool, send, header: string, picture: bool, body: proc()) {
	if len(fetches) >= MAX_OPEN_FETCHES {
		return
	}
	headers: []string
	if header != "" {
		headers = {header}
	}
	append(&fetches, Fetching{id = roci.ask_fetch(address, posting, send, headers), body = body, picture = picture})
}

// Once a frame: runs the block of every fetch whose answer has come.
step_fetches :: proc() {
	for i := 0; i < len(fetches); {
		open := fetches[i]
		got := platform.fetch_take(open.id, context.temp_allocator)
		if got.state == .Waiting {
			i += 1
			continue
		}
		ordered_remove(&fetches, i)
		answer := Reply{status = got.status, problem = got.problem}
		answer.text = keep(string(got.body))
		if open.picture && len(got.body) > 0 {
			if picture, ok := roci.add_image(got.body); ok {
				answer.picture = picture
			} else {
				answer.problem = "what came is not a picture this can read"
			}
		}
		reply = answer
		open.body()
		reply = {}
	}
}
