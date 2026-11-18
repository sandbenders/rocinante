// SPDX-License-Identifier: 0BSD
//
// `fetch`: getting what is at a web address without making the sketch wait. Asking starts the fetch on a
// thread and keeps the block; the frame hook looks once a frame for answers, and when one has come the block
// runs with `reply` the answer: its status, its text, and its picture when the fetch said `as picture`.
package interp

import "../"
import "../lang"
import "../platform"
import "core:strings"

// A fetch that is open, and the block to run when its answer has come.
Fetching :: struct {
	id:      int,
	body:    ^lang.IR_Block,
	picture: bool, // read the answer as a picture
}

// What `reply` holds while a block runs.
Reply :: struct {
	status:  int,
	text:    string, // on the frame's memory
	problem: string,
	picture: roci.Image,
}

// How many fetches a sketch may have open at once.
MAX_OPEN_FETCHES :: 8

@(private)
fetch_verb :: proc(it: ^Interp, call: lang.IR_Call, code: Verb_Code) {
	if len(call.args) < 2 {
		return
	}
	block, is_block := &call.args[len(call.args) - 1].kind.(lang.IR_Block_Value)
	if !is_block {
		return
	}
	if len(it.fetches) >= MAX_OPEN_FETCHES {
		return // a sketch that fetches every frame gets eight at a time, not a pile of them
	}
	address := as_text(eval(it, call.args[0]))
	posting := code == .Post
	send := ""
	if posting && len(call.args) > 2 {
		send = as_text(eval(it, call.args[1]))
	}
	headers: []string
	if line, found := option_value(it, call.options, "header"); found {
		headers = {as_text(line)}
	}
	id := roci.ask_fetch(address, posting, send, headers)
	append(&it.fetches, Fetching{id = id, body = &block.block, picture = code == .Fetch_Picture})
}

// Called once a frame: runs the block of every fetch whose answer has come.
@(private)
run_fetches :: proc(p: ^Interp) {
	for i := 0; i < len(p.fetches); {
		open := p.fetches[i]
		got := platform.fetch_take(open.id, context.temp_allocator)
		if got.state == .Waiting {
			i += 1
			continue
		}
		ordered_remove(&p.fetches, i)
		reply := Reply{status = got.status, problem = got.problem}
		reply.text = strings.clone(string(got.body), p.alloc)
		if open.picture && len(got.body) > 0 {
			if picture, ok := roci.add_image(got.body); ok {
				reply.picture = picture
			} else {
				reply.problem = "what came is not a picture this can read"
			}
		}
		p.reply = reply
		run_block(p, open.body)
		p.reply = {}
	}
}

// Forgets every fetch the sketch left open.
@(private)
drop_fetches :: proc(p: ^Interp) {
	for open in p.fetches {
		platform.fetch_forget(open.id)
	}
	delete(p.fetches)
}

// `reply`: the answer the running block was given, as a record of the checker's type.
reply_record :: proc(it: ^Interp, type: lang.Type_Id) -> Value {
	shape := lang.shape_of(it.types, type)
	if shape < 0 {
		return nil
	}
	r := new_record(it, shape)
	set :: proc(it: ^Interp, r: ^Record, shape: int, name: string, value: Value) {
		if at := field_index(it, shape, name); at >= 0 {
			r.fields[at] = value
		}
	}
	set(it, r, shape, "status", f64(it.reply.status))
	set(it, r, shape, "ok", it.reply.status >= 200 && it.reply.status < 300)
	set(it, r, shape, "text", strings.clone(it.reply.text, it.alloc))
	set(it, r, shape, "problem", strings.clone(it.reply.problem, it.alloc))
	set(it, r, shape, "picture", it.reply.picture)
	return r
}
