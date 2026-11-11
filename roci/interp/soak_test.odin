// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "../gfx"
import "../maths"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"

// A sketch that makes a new picture every frame for ten thousand frames holds a bounded
// number of pictures, however long it runs: the made pictures are capped, a slot let go is
// reused, and what the renderers have seen is cut off.
@(test)
test_a_sketch_that_makes_a_picture_every_frame_holds_a_bounded_number_of_them :: proc(t: ^testing.T) {
	p := run_picture_sketch(t, "pictures_soak", "photo = load \"cat.png\"\ndraw [\n  made = filter photo as threshold by (frame * 0.01)\n  image made at 0 0\n]")
	defer finish(p)
	// a picture that is drawn each frame is a texture of the renderer, which says it has seen it
	reader := 0
	gfx.image_reader_add(&reader)
	defer gfx.image_reader_remove(&reader)
	most_stored := 0
	for _ in 0 ..< 10_000 {
		roci.step()
		reader = gfx.released_base + len(gfx.released_images)
		most_stored = max(most_stored, len(gfx.image_store))
	}
	testing.expect_value(t, len(p.errors), 0)
	testing.expectf(t, most_stored <= roci.MAX_DERIVED_PICTURES + gfx.REUSE_AFTER_FREE_SLOTS + 16, "%d pictures were held at once", most_stored)
	testing.expectf(t, len(gfx.released_images) <= 2 * roci.MAX_DERIVED_PICTURES, "%d let-go pictures are still listed", len(gfx.released_images))
}

// ---- mutated examples ----

// The kinds of change a typing mistake makes, applied to a text.
@(private = "file")
mutate :: proc(text: string, rng: ^maths.Rng) -> string {
	if len(text) == 0 {
		return text
	}
	characters := "[]{}()\"#=!&|<>-+*/.,: \n0123456789abcxyz"
	// the bounds of `rng_int` are both included
	pick := proc(rng: ^maths.Rng, n: int) -> int {
		return int(maths.rng_int(rng, 0, i64(n - 1)))
	}
	at := pick(rng, len(text))
	b := strings.builder_make(context.temp_allocator)
	switch pick(rng, 5) {
	case 0: // a few characters gone
		gone := 1 + pick(rng, 8)
		strings.write_string(&b, text[:at])
		strings.write_string(&b, text[min(len(text), at + gone):])
	case 1: // one character is another
		strings.write_string(&b, text[:at])
		strings.write_byte(&b, characters[pick(rng, len(characters))])
		strings.write_string(&b, text[min(len(text), at + 1):])
	case 2: // a character put in
		strings.write_string(&b, text[:at])
		strings.write_byte(&b, characters[pick(rng, len(characters))])
		strings.write_string(&b, text[at:])
	case 3: // a stretch said twice
		stretch := 1 + pick(rng, 40)
		end := min(len(text), at + stretch)
		strings.write_string(&b, text[:end])
		strings.write_string(&b, text[at:end])
		strings.write_string(&b, text[end:])
	case 4: // a stretch moved
		stretch := 1 + pick(rng, 40)
		end := min(len(text), at + stretch)
		to := pick(rng, len(text))
		moved := text[at:end]
		without := strings.concatenate({text[:at], text[end:]}, context.temp_allocator)
		to = min(to, len(without))
		strings.write_string(&b, without[:to])
		strings.write_string(&b, moved)
		strings.write_string(&b, without[to:])
	}
	return strings.to_string(b)
}

// What comes of a mistyped sketch is a message, never a crash or a hang: every example, changed a
// hundred ways by a generator with a fixed seed, is read, checked and (when it has no mistake)
// run for three frames. A crash stops the whole run, so this test fails by not finishing.
@(test)
test_mutated_examples_are_checked_and_run_without_a_crash :: proc(t: ^testing.T) {
	roci.set_graphics_refused(true)
	// what the loop keeps is made with the test's own allocator, because it frees the temporary
	// memory after each run
	names := make([dynamic]string)
	defer {
		for name in names {
			delete(name)
		}
		delete(names)
	}
	entries, _ := os.read_all_directory_by_path("examples", context.temp_allocator)
	for entry in entries {
		if entry.type == .Directory && os.exists(fmt.tprintf("examples/%s/sketch.roci", entry.name)) {
			append(&names, strings.clone(entry.name))
		}
	}
	testing.expect(t, len(names) > 20, "the examples were found: tests run from the repository root")
	// the order of a folder is the system's own: sorted, every computer makes the same changes
	slice.sort(names[:])
	rng := maths.rng_make(20261111)
	ran, said := 0, 0
	for name in names {
		original := strings.clone(example_text(name))
		defer delete(original)
		for _ in 0 ..< 24 {
			text := original
			for _ in 0 ..< 1 + int(maths.rng_int(&rng, 0, 2)) {
				text = mutate(text, &rng)
			}
			roci.start_headless(1)
			p, ok := load("fuzz.roci", text)
			if ok {
				p.budget = 0.05 // a mutation may make a loop that never ends: the block's time limit ends it
				start(p)
				for _ in 0 ..< 3 {
					roci.step()
				}
				ran += 1
			} else {
				said += 1
			}
			finish(p)
			free_all(context.temp_allocator)
		}
	}
	testing.expectf(t, ran > 0 && said > 0, "%d ran and %d were refused: the changes should give both", ran, said)
}
