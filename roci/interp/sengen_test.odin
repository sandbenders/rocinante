// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "core:os"
import "core:testing"

// Whether the errors the sengen example may have are the only ones it has: Helvetica Neue
// Condensed Black is a Mac's font, which is said where it is missing (the words are set in
// Inter) and, where it is installed, is a font not known to be free to share. Nothing else.
only_the_fonts_message :: proc(t: ^testing.T, p: ^Interp) {
	for e in p.errors {
		testing.expect(t, e.id == .Font_Missing || e.id == .Font_Licence, "an unexpected message")
	}
}

@(test)
test_the_sengen_example_writes_a_new_poem_on_space_and_saves_it_on_s_and_p :: proc(t: ^testing.T) {
	p := run_text(t, example_text("sengen"), 2)
	defer finish(p)
	only_the_fonts_message(t, p)
	testing.expect_value(t, len(as_list(global_named(p, "poem")).items), 5)
	// the size makes the widest word fit the window across, or five lines fit down
	big := as_number(global_named(p, "big"))
	testing.expect(t, big > 0 && big <= 600 / (5 * 0.71) + 1e-9, "five lines fit down the window")
	// space chooses again: five words and a size, whatever they are
	w := first_window()
	for _ in 0 ..< 3 {
		roci.step({key_event(w, .SPACE)})
		roci.step({key_event(w, .SPACE, false)})
		testing.expect_value(t, len(as_list(global_named(p, "poem")).items), 5)
		testing.expect(t, as_number(global_named(p, "big")) > 0)
	}
	// s and p save the shapes, which needs no graphics
	roci.step({key_event(w, .S)})
	roci.step({key_event(w, .S, false)})
	roci.step({key_event(w, .P)})
	roci.step({key_event(w, .P, false)})
	roci.step()
	roci.step()
	testing.expect(t, os.exists("output/sengen.svg"))
	testing.expect(t, os.exists("output/sengen.pdf"))
}

// The words a frame shows and how solid each is, as 0 to 255, for the sengen example.
words_shown :: proc() -> (count: int, alphas: [dynamic]f32) {
	found := typeset_commands()
	defer delete(found)
	for c in found {
		append(&alphas, c.style.alpha)
	}
	return len(found), alphas
}

@(test)
test_in_the_sengen_example_a_word_is_replaced_every_30_to_60_seconds_and_fades_in_as_the_old_one_fades_out :: proc(t: ^testing.T) {
	p := run_text(t, example_text("sengen"), 1)
	defer finish(p)
	only_the_fonts_message(t, p)
	// two minutes of the poem, a frame at a time
	frames := 125 * 60
	fading_since := -1
	swaps: [dynamic]int // the frame each fade began at
	defer delete(swaps)
	for frame in 0 ..< frames {
		roci.step()
		count, alphas := words_shown()
		defer delete(alphas)
		switch count {
		case 5:
			// still: every word fully solid
			for a in alphas {
				if !testing.expectf(t, a == 255, "frame %d: a word with alpha %v when none is fading", frame, a) {
					return
				}
			}
			if fading_since >= 0 {
				// the fade is over: it took about two seconds
				length := frame - fading_since
				testing.expectf(t, length >= 115 && length <= 125, "a fade of %d frames", length)
				fading_since = -1
			}
		case 6:
			if fading_since < 0 {
				fading_since = frame
				append(&swaps, frame)
			}
			// the word that goes and the word that comes are together always one whole word, so the six
			// add up to five solid ones
			total := f32(0)
			for a in alphas {
				total += a
			}
			if !testing.expectf(t, abs(total - 5 * 255) < 4, "frame %d: the six words add up to %v", frame, total) {
				return
			}
		case:
			testing.expectf(t, false, "frame %d shows %d words", frame, count)
			return
		}
	}
	// in two minutes: the first change between 30 and 60 seconds in, then one every 30 to 60
	if testing.expect(t, len(swaps) >= 2 && len(swaps) <= 4, "two to four changes in two minutes") {
		testing.expect(t, swaps[0] >= 30 * 60 - 2 && swaps[0] <= 60 * 60 + 2, "the first change comes 30 to 60 seconds in")
		for i in 1 ..< len(swaps) {
			gap := swaps[i] - swaps[i - 1]
			testing.expectf(t, gap >= 30 * 60 - 2 && gap <= 60 * 60 + 2, "%d frames between two changes", gap)
		}
	}
}

@(test)
test_in_the_sengen_example_space_during_a_fade_gives_a_whole_new_poem :: proc(t: ^testing.T) {
	p := run_text(t, example_text("sengen"), 1)
	defer finish(p)
	// run until a fade is on, but no longer than a minute and a half
	w := first_window()
	faded := false
	for _ in 0 ..< 90 * 60 {
		roci.step()
		count, alphas := words_shown()
		delete(alphas)
		if count == 6 {
			faded = true
			break
		}
	}
	if !testing.expect(t, faded, "a word was replaced within 90 seconds") {
		return
	}
	roci.step({key_event(w, .SPACE)})
	roci.step({key_event(w, .SPACE, false)})
	count, alphas := words_shown()
	defer delete(alphas)
	testing.expect_value(t, count, 5)
	for a in alphas {
		testing.expect_value(t, a, f32(255))
	}
}
