// SPDX-License-Identifier: 0BSD
//
// Packets reach a listener on a thread of its own and are taken by the sketch's thread, while any number of senders write. This test
// sends from several threads at once and takes while they do, and checks that what comes out is whole and each packet comes once. How
// a full queue keeps to its size is tested in osc_test.odin: a flood from several threads here slowed the other tests' own network
// threads enough to fail their memory checks.
package platform

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"

SENDERS :: 4
PACKETS_EACH :: 60

Send_Job :: struct {
	port:     int,
	who:      int,
	count:    int,
	finished: ^int,
	memory:   runtime.Allocator, // the test's, so its leak check sees what the thread makes
}

// Gives back packets taken from a listener.
free_taken :: proc(got: [dynamic]Osc_Packet) {
	for p in got {
		delete(p.data)
		delete(p.from)
	}
	delete(got)
}

// What sender `who` writes as packet `i`: a address, then a number that tells them apart.
osc_payload :: proc(who, i: int) -> string {
	return fmt.tprintf("/s%d/p%d", who, i)
}

send_many :: proc(job: ^Send_Job) {
	context.allocator = job.memory
	out := open_osc_out()
	defer close_osc_out(out)
	for i in 0 ..< job.count {
		text := osc_payload(job.who, i)
		osc_send(out, "127.0.0.1", job.port, transmute([]byte)text)
	}
	sync.atomic_add(job.finished, 1)
}

@(test)
test_packets_sent_from_many_threads_while_the_sketch_takes_come_out_whole_and_once :: proc(t: ^testing.T) {
	listener := open_osc(0)
	defer close_osc(listener)
	if !testing.expect_value(t, listener.error, Osc_Problem.None) {
		return
	}
	finished := 0
	jobs: [SENDERS]Send_Job
	threads: [SENDERS]^thread.Thread
	for i in 0 ..< SENDERS {
		jobs[i] = {port = listener.port, who = i, count = PACKETS_EACH, finished = &finished, memory = context.allocator}
		threads[i] = thread.create_and_start_with_poly_data(&jobs[i], send_many)
	}
	got := make([dynamic]Osc_Packet)
	defer free_taken(got)
	// taken while the senders write, then until nothing more arrives for a moment
	quiet := 0
	for quiet < 100 {
		before := len(got)
		osc_take(listener, &got)
		if len(got) == before && sync.atomic_load(&finished) == SENDERS {
			quiet += 1
		} else {
			quiet = 0
		}
		time.sleep(time.Millisecond)
	}
	for th in threads {
		thread.join(th)
		thread.destroy(th)
	}
	seen := make(map[string]int, context.temp_allocator)
	for p in got {
		seen[string(p.data)] += 1
	}
	for text, times in seen {
		testing.expectf(t, times == 1, "`%s` arrived %d times", text, times)
		valid := false
		for who in 0 ..< SENDERS {
			for i in 0 ..< PACKETS_EACH {
				if text == osc_payload(who, i) {
					valid = true
				}
			}
		}
		testing.expectf(t, valid, "`%s` is not a packet anybody sent: it was cut or mixed", text)
	}
	// What arrives is up to the system's UDP, which drops packets when a computer is busy (19 of 240 on ORION's runner), and the queue itself
	// drops none at this size (it holds 1024): so the test asks only that every sender got something through, and that nothing is missing
	// from a packet that did.
	came := [SENDERS]int{}
	for text in seen {
		for who in 0 ..< SENDERS {
			if strings.has_prefix(text, fmt.tprintf("/s%d/", who)) {
				came[who] += 1
			}
		}
	}
	for who in 0 ..< SENDERS {
		testing.expectf(t, came[who] > 0, "no packet of sender %d came", who)
	}
	for p in got {
		testing.expect(t, strings.has_prefix(p.from, "127."), "the sender is this computer")
	}
}
