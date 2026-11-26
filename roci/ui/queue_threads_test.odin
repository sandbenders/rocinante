// SPDX-License-Identifier: 0BSD
//
// What a screen reader asks of a widget may arrive from another thread while the sketch's frames begin. These tests push actions from
// many threads while frames take them, and check that every action arrives once with its own number and text, and that none is left
// holding memory when the state is let go.
package ui

import "base:runtime"
import "core:fmt"
import "core:sync"
import "core:testing"
import "core:thread"

PUSHERS :: 8
PER_PUSHER :: 250

Push_Job :: struct {
	s:        ^State,
	who:      int,
	finished: ^int, // how many pushers are done, for the frames to know when to stop
	memory:   runtime.Allocator, // the test's, so its leak check sees what the thread makes
}

push_many :: proc(job: ^Push_Job) {
	context.allocator = job.memory
	for i in 0 ..< PER_PUSHER {
		node := u64(job.who * 1000 + i)
		push_action(job.s, node, .Set_Value, f64(node), fmt.tprintf("n%d", node))
	}
	sync.atomic_add(job.finished, 1)
}

@(test)
test_actions_pushed_from_many_threads_while_frames_begin_each_arrive_once_whole :: proc(t: ^testing.T) {
	s: State
	defer free_actions(&s)
	finished := 0
	jobs: [PUSHERS]Push_Job
	threads: [PUSHERS]^thread.Thread
	seen := make(map[u64]int, context.temp_allocator)
	wrong := 0
	collect_frame :: proc(s: ^State, seen: ^map[u64]int, wrong: ^int) {
		for p in s.actions {
			seen[p.node] += 1
			if p.number != f64(p.node) || p.text != fmt.tprintf("n%d", p.node) || p.action != .Set_Value {
				wrong^ += 1
			}
		}
	}
	for i in 0 ..< PUSHERS {
		jobs[i] = {s = &s, who = i, finished = &finished, memory = context.allocator}
		threads[i] = thread.create_and_start_with_poly_data(&jobs[i], push_many)
	}
	// frames begin while the pushers are at work
	for sync.atomic_load(&finished) < PUSHERS {
		take_queue(&s)
		collect_frame(&s, &seen, &wrong)
	}
	for th in threads {
		thread.join(th)
		thread.destroy(th)
	}
	take_queue(&s) // what came after the last frame
	collect_frame(&s, &seen, &wrong)
	testing.expect_value(t, len(seen), PUSHERS * PER_PUSHER)
	testing.expect_value(t, wrong, 0)
	for node, times in seen {
		testing.expectf(t, times == 1, "the action of node %d arrived %d times", node, times)
	}
	take_queue(&s)
	testing.expect_value(t, len(s.actions), 0)
}

@(test)
test_actions_that_were_never_taken_are_given_back_with_the_state :: proc(t: ^testing.T) {
	s: State
	finished := 0
	jobs: [PUSHERS]Push_Job
	threads: [PUSHERS]^thread.Thread
	for i in 0 ..< PUSHERS {
		jobs[i] = {s = &s, who = i, finished = &finished, memory = context.allocator}
		threads[i] = thread.create_and_start_with_poly_data(&jobs[i], push_many)
	}
	for th in threads {
		thread.join(th)
		thread.destroy(th)
	}
	testing.expect_value(t, len(s.queue), PUSHERS * PER_PUSHER)
	free_actions(&s) // the test runner's leak check sees any text left behind
}
