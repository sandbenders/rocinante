// SPDX-License-Identifier: 0BSD
//
// A sketch's state (its windows and their messages, its pictures, its random numbers) belongs to the thread that runs it, so
// sketches on several threads at once must never see each other's. These tests run many at the same time and check that each one
// hears its own messages in order, finds its own pictures and draws its own random numbers.
package roci

import "base:runtime"
import "core:fmt"
import "core:testing"
import "core:thread"
import "gfx"

SKETCH_THREADS :: 8
MESSAGES_EACH :: 120
PICTURES_EACH :: 24
DRAWS_EACH :: 4

Sketch_Job :: struct {
	who:     int,
	memory:  runtime.Allocator, // the test's, so its leak check sees what the thread makes
	problem: string, // what went wrong, or "" when nothing did
	before:  [DRAWS_EACH]f64, // the first random numbers it drew
	after:   [DRAWS_EACH]f64, // the next ones, drawn when everything else was done
}

// One whole sketch run on its own thread: messages sent to its window, pictures of its own, frames, and what it should find after.
run_one_sketch :: proc(job: ^Sketch_Job) {
	context.allocator = job.memory
	start_headless(u64(job.who + 1))
	defer finish()
	for i in 0 ..< DRAWS_EACH {
		job.before[i] = random(1000)
	}
	received = {}
	defer {
		for v in received {
			value_destroy(v)
		}
		delete(received)
	}
	w := window(100 + job.who, 80)
	on_receive(w, collect)
	for k in 0 ..< MESSAGES_EACH {
		if k % 2 == 0 {
			send(w, f64(job.who * 1000 + k))
		} else {
			send(w, fmt.tprintf("w%d-%d", job.who, k))
		}
	}
	pictures: [PICTURES_EACH]Image
	for i in 0 ..< PICTURES_EACH {
		pixels := make([]u8, 4 * 4 * 4, context.temp_allocator)
		for &p in pixels {
			p = u8(job.who * 30 + i) // no two pictures of any thread share it
		}
		made, ok := add_image_pixels(4, 4, pixels)
		if !ok {
			job.problem = "a picture was refused"
			return
		}
		pictures[i] = made
	}
	for _ in 0 ..< 3 {
		step()
	}
	if len(received) != MESSAGES_EACH {
		job.problem = fmt.aprintf("heard %d messages, not %d", len(received), MESSAGES_EACH)
		return
	}
	for v, k in received {
		if k % 2 == 0 {
			if number, is_number := v.(f64); !is_number || number != f64(job.who * 1000 + k) {
				job.problem = fmt.aprintf("message %d was %v", k, v)
				return
			}
		} else if text, is_text := v.(string); !is_text || text != fmt.tprintf("w%d-%d", job.who, k) {
			job.problem = fmt.aprintf("message %d was %v", k, v)
			return
		}
	}
	for i in 0 ..< PICTURES_EACH {
		data := gfx.image_data(pictures[i])
		if data == nil || data.width != 4 || data.pixels[0] != u8(job.who * 30 + i) {
			job.problem = fmt.aprintf("picture %d was not the one this sketch made", i)
			return
		}
	}
	for i in 0 ..< DRAWS_EACH {
		job.after[i] = random(1000)
	}
}

@(test)
test_sketches_on_many_threads_keep_their_own_messages_pictures_and_random_numbers :: proc(t: ^testing.T) {
	jobs: [SKETCH_THREADS]Sketch_Job
	threads: [SKETCH_THREADS]^thread.Thread
	for i in 0 ..< SKETCH_THREADS {
		jobs[i].who, jobs[i].memory = i, context.allocator
		threads[i] = thread.create_and_start_with_poly_data(&jobs[i], run_one_sketch)
	}
	for th in threads {
		thread.join(th)
		thread.destroy(th)
	}
	for job in jobs {
		testing.expectf(t, job.problem == "", "sketch %d: %s", job.who, job.problem)
		delete(job.problem)
		// the numbers a sketch drew are those its seed gives alone, whatever the others did meanwhile
		start_headless(u64(job.who + 1))
		for i in 0 ..< DRAWS_EACH {
			testing.expect_value(t, job.before[i], random(1000))
		}
		for i in 0 ..< DRAWS_EACH {
			testing.expect_value(t, job.after[i], random(1000))
		}
		finish()
	}
}
