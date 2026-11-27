// SPDX-License-Identifier: 0BSD
//
// An interpreter keeps everything it asks and remembers (the trees it makes for the lists it is asked about, its tweens, its
// names) in itself, so interpreters on several threads at once must give each sketch the answers it gives alone. These tests run
// sketches that ask the collision verbs about lists that stay the same for many frames, which is when a kept tree is used, on
// several threads, and compare what each prints with a run of the same sketch on one thread.
package interp

import "../"
import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:testing"
import "core:thread"

COLLIDING_THREADS :: 6
COLLIDING_FRAMES :: 60

// A sketch whose answers depend on `who`: twenty walls, moved along by `who`, asked about a point that moves along them.
colliding_sketch :: proc(who: int) -> string {
	return fmt.tprintf(
		`walls = []
for i from 0 to 19 [ add {{ pos: {{ i * 30 + %d, 100 }}, size: {{ 24, 10 }} }} to walls ]
n = 0
draw [
  n = n + 1
  print (count (hits {{ (n * 7) %% 600, 105 }} walls))
]`,
		who * 4,
	)
}

// What a sketch prints in its frames, run on this thread; "problem: ..." when it has errors.
run_and_print :: proc(text: string) -> string {
	roci.start_headless(1)
	p, ok := load("test.roci", text)
	defer {
		forget_decoded_pictures()
		forget_decoded_sounds()
		roci.shutdown()
	}
	defer destroy(p)
	if !ok {
		return strings.clone("problem: the sketch has errors")
	}
	start(p)
	for _ in 0 ..< COLLIDING_FRAMES {
		roci.step()
	}
	return strings.join(p.printed[:], "\n")
}

Colliding_Job :: struct {
	who:    int,
	memory: runtime.Allocator, // the test's, so its leak check sees what the thread makes
	output: string,
}

run_colliding :: proc(job: ^Colliding_Job) {
	context.allocator = job.memory
	job.output = run_and_print(colliding_sketch(job.who))
}

@(test)
test_interpreters_on_many_threads_answer_the_collision_questions_as_one_does_alone :: proc(t: ^testing.T) {
	jobs: [COLLIDING_THREADS]Colliding_Job
	threads: [COLLIDING_THREADS]^thread.Thread
	for i in 0 ..< COLLIDING_THREADS {
		jobs[i] = {who = i, memory = context.allocator}
		threads[i] = thread.create_and_start_with_poly_data(&jobs[i], run_colliding)
	}
	for th in threads {
		thread.join(th)
		thread.destroy(th)
	}
	answers := make(map[string]bool, context.temp_allocator)
	for job in jobs {
		alone := run_and_print(colliding_sketch(job.who))
		testing.expect(t, !strings.has_prefix(alone, "problem"), "the sketch loads")
		testing.expectf(t, job.output == alone, "sketch %d on a thread beside others printed other answers than alone", job.who)
		testing.expect(t, len(strings.split_lines(alone, context.temp_allocator)) >= COLLIDING_FRAMES - 1, "a line is printed in each frame")
		answers[alone] = true
		delete(job.output)
		delete(alone)
	}
	testing.expect(t, len(answers) > 1, "the sketches differ, so a mix-up between threads would show")
}
