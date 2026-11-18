// SPDX-License-Identifier: 0BSD
//
// Fetching a web address for C: roci_fetch starts it and gives a number, roci_fetch_done says when it has
// finished, and the answer is read with roci_fetch_status, roci_fetch_text and roci_fetch_picture until
// roci_fetch_forget lets it go.
package roci

import "core:c"

import "platform"

abi_fetch_group :: proc(all: ^[dynamic]Abi_Entry) {
	append(all, abi_entry("roci_fetch", typeid_of(type_of(abi_fetch)), "int roci_fetch(const char *address, const char *send, const char *header)", "Starts fetching a web address (http or https) on a thread and gives the number of the request. `send` is a text to post (NULL to get) and `header` a header line to send with it (NULL for none). It does not wait: ask roci_fetch_done."))
	append(all, abi_entry("roci_fetch_done", typeid_of(type_of(abi_fetch_done)), "int roci_fetch_done(int request)", "1 when a request has finished, whether an answer came or not, and 0 while it is still going. After 1, the answer is read with roci_fetch_status, roci_fetch_text and roci_fetch_picture."))
	append(all, abi_entry("roci_fetch_status", typeid_of(type_of(abi_fetch_status)), "int roci_fetch_status(int request)", "The status the server answered a finished request with (200 for a good one), or 0 when nothing came, in which case roci_fetch_problem says why."))
	append(all, abi_entry("roci_fetch_text", typeid_of(type_of(abi_fetch_text)), "const char *roci_fetch_text(int request)", "What a finished request got, as text; empty when nothing came. The text stays valid until the next function that gives text back."))
	append(all, abi_entry("roci_fetch_problem", typeid_of(type_of(abi_fetch_problem)), "const char *roci_fetch_problem(int request)", "Why a finished request got nothing, in words; empty when it did. The text stays valid until the next function that gives text back."))
	append(all, abi_entry("roci_fetch_picture", typeid_of(type_of(abi_fetch_picture)), "roci_image_id roci_fetch_picture(int request)", "What a finished request got, read as a picture, or 0 when it is not one. The picture is the caller's, as one from roci_load."))
	append(all, abi_entry("roci_fetch_forget", typeid_of(type_of(abi_fetch_forget)), "void roci_fetch_forget(int request)", "Lets go of a request and its answer."))
}

// What a finished request got, kept until C forgets it.
@(thread_local) @(private) fetched: map[int]platform.Fetch_Result

@(private)
fetch_finish :: proc(request: int) -> (^platform.Fetch_Result, bool) {
	if got, found := &fetched[request]; found {
		return got, true
	}
	got := platform.fetch_take(request)
	if got.state == .Waiting {
		return nil, false
	}
	if fetched == nil {
		fetched = make(map[int]platform.Fetch_Result)
	}
	fetched[request] = got
	return &fetched[request], true
}

@(export, link_name = "roci_fetch")
abi_fetch :: proc "c" (address, send, header: cstring) -> c.int {
	context = abi_context()
	headers: []string
	if header != nil {
		headers = {text_from_abi(header)}
	}
	return c.int(ask_fetch(text_from_abi(address), send != nil, text_from_abi(send), headers))
}

@(export, link_name = "roci_fetch_done")
abi_fetch_done :: proc "c" (request: c.int) -> c.int {
	context = abi_context()
	_, ready := fetch_finish(int(request))
	return 1 if ready else 0
}

@(export, link_name = "roci_fetch_status")
abi_fetch_status :: proc "c" (request: c.int) -> c.int {
	context = abi_context()
	if got, ready := fetch_finish(int(request)); ready {
		return c.int(got.status)
	}
	return 0
}

@(export, link_name = "roci_fetch_text")
abi_fetch_text :: proc "c" (request: c.int) -> cstring {
	context = abi_context()
	if got, ready := fetch_finish(int(request)); ready {
		return abi_give_text(string(got.body))
	}
	return abi_give_text("")
}

@(export, link_name = "roci_fetch_problem")
abi_fetch_problem :: proc "c" (request: c.int) -> cstring {
	context = abi_context()
	if got, ready := fetch_finish(int(request)); ready {
		return abi_give_text(got.problem)
	}
	return abi_give_text("")
}

@(export, link_name = "roci_fetch_picture")
abi_fetch_picture :: proc "c" (request: c.int) -> c.int {
	context = abi_context()
	if got, ready := fetch_finish(int(request)); ready && len(got.body) > 0 {
		if picture, ok := add_image(got.body); ok {
			return c.int(picture)
		}
	}
	return 0
}

@(export, link_name = "roci_fetch_forget")
abi_fetch_forget :: proc "c" (request: c.int) {
	context = abi_context()
	if got, found := fetched[int(request)]; found {
		delete(got.body)
		delete(got.problem)
		delete_key(&fetched, int(request))
	}
	platform.fetch_forget(int(request))
}

// Lets go of every answer C did not forget (the end of the sketch).
fetch_stop :: proc() {
	for _, got in fetched {
		delete(got.body)
		delete(got.problem)
	}
	delete(fetched)
	fetched = nil
}
