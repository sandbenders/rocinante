// SPDX-License-Identifier: 0BSD
package term

import "core:strings"
import "core:testing"

@(test)
test_a_time_reads_in_seconds_or_minutes :: proc(t: ^testing.T) {
	testing.expect_value(t, format_seconds(0), "0.00 s")
	testing.expect_value(t, format_seconds(0.049), "0.05 s")
	testing.expect_value(t, format_seconds(48.25), "48.2 s")
	testing.expect_value(t, format_seconds(0.999), "1.00 s")
	testing.expect_value(t, format_seconds(1), "1.0 s")
	testing.expect_value(t, format_seconds(59.9), "59.9 s")
	testing.expect_value(t, format_seconds(60), "1 min 0 s")
	testing.expect_value(t, format_seconds(62.7), "1 min 2 s")
	testing.expect_value(t, format_seconds(3725), "62 min 5 s")
	testing.expect_value(t, format_seconds(-3), "0.00 s") // a clock that went back reads as nothing
}

@(test)
test_every_kind_of_step_has_its_emoji :: proc(t: ^testing.T) {
	seen := make(map[string]bool, context.temp_allocator)
	for kind in Step_Kind {
		e := step_emoji(kind)
		testing.expectf(t, e != "" && e != "•", "%v has an emoji", kind)
		testing.expectf(t, !seen[e], "%v has an emoji of its own", kind)
		seen[e] = true
	}
}

@(test)
test_a_step_line_has_its_mark_name_and_time :: proc(t: ^testing.T) {
	// plain: the mark, the name padded so the times line up, the time right-aligned
	running := step_line(.Compile, "Compiling the sketch", 12.4, "⠹", .Running, false)
	testing.expect_value(t, running, "  🔨 Compiling the sketch                     12.4 s ⠹")
	done := step_line(.Compile, "Compiling the sketch", 48.2, "", .Done, false)
	testing.expect_value(t, done, "  ✅ Compiling the sketch                     48.2 s")
	failed := step_line(.Bundle, "Making the app", 2, "", .Failed, false)
	testing.expect_value(t, failed, "  ❌ Making the app                            2.0 s")
	// the times of a long and a short name start in the same column, accents counted as one character
	a := step_line(.Try, "Trying the app", 1, "", .Done, false)
	b := step_line(.Try, "Árvore está pronta", 1, "", .Done, false)
	testing.expect_value(t, strings.rune_count(a), strings.rune_count(b))
	// coloured: the same words with escape codes around them
	coloured := step_line(.Compile, "Compiling the sketch", 12.4, "⠹", .Running, true)
	testing.expect(t, strings.contains(coloured, "\x1b[") && strings.contains(coloured, "Compiling the sketch"), coloured)
}

@(test)
test_plain_progress_is_a_line_when_a_step_starts_and_one_when_it_ends :: proc(t: ^testing.T) {
	b := strings.builder_make(context.temp_allocator)
	p: Progress
	progress_begin(&p, .Bundle, "Packaging Voyage 1.0.0 for Linux", &b)
	progress_step(&p, .Compile, "Compiling the sketch")
	progress_step(&p, .Bundle, "Making the app")
	redraw(&p) // nothing is redrawn when it is not live
	progress_finish(&p)
	progress_result(&p, "tar.gz", "voyage.tar.gz (17.6 MB)")
	lines := strings.split_lines(strings.trim_right(strings.to_string(b), "\n"), context.temp_allocator)
	testing.expect_value(t, len(lines), 7)
	testing.expect_value(t, lines[0], "Packaging Voyage 1.0.0 for Linux")
	testing.expect_value(t, lines[1], "Compiling the sketch ...")
	testing.expect(t, strings.has_prefix(lines[2], "Compiling the sketch: done in 0.0"), lines[2])
	testing.expect_value(t, lines[3], "Making the app ...")
	testing.expect(t, strings.has_prefix(lines[4], "Making the app: done in "), lines[4])
	testing.expect(t, strings.has_prefix(lines[5], "Ready in 0.0"), lines[5])
	testing.expect_value(t, lines[6], "tar.gz      voyage.tar.gz (17.6 MB)")
	testing.expect(t, !strings.contains(strings.to_string(b), "\x1b"), "no escape codes and no emojis when plain")
	testing.expect(t, !strings.contains(strings.to_string(b), "✅"))
}

@(test)
test_a_failed_step_says_so_and_ends_the_process :: proc(t: ^testing.T) {
	b := strings.builder_make(context.temp_allocator)
	p: Progress
	progress_begin(&p, .Compile, "Compiling wildvex", &b)
	progress_step(&p, .Compile, "Compiling the sketch")
	progress_fail(&p)
	progress_fail(&p) // a second time does nothing more
	text := strings.to_string(b)
	testing.expect(t, strings.contains(text, "Compiling the sketch: failed after 0.0"), text)
	testing.expect_value(t, strings.count(text, "failed"), 1)
	testing.expect(t, !strings.contains(text, "Ready"), text)
	// a process with no step at all still begins and finishes
	empty := strings.builder_make(context.temp_allocator)
	q: Progress
	progress_begin(&q, .Check, "Checking", &empty)
	progress_finish(&q, "Done")
	testing.expect(t, strings.has_prefix(strings.to_string(empty), "Checking\nDone in 0.0"), strings.to_string(empty))
}

@(test)
test_live_progress_redraws_the_running_step_in_place :: proc(t: ^testing.T) {
	b := strings.builder_make(context.temp_allocator)
	p: Progress
	progress_begin(&p, .Phone, "Putting wildvex on the phone", &b, live = true)
	progress_step(&p, .Compile, "Compiling the sketch")
	redraw(&p)
	redraw(&p)
	progress_finish(&p)
	text := strings.to_string(b)
	testing.expect(t, strings.has_prefix(text, "📱 "), text)
	testing.expect(t, strings.contains(text, "🔨"), "the running step shows its emoji")
	testing.expect_value(t, strings.count(text, "\r\x1b[2K"), 3) // two redraws and the end of the step
	testing.expect(t, strings.contains(text, SPINNER[1]) && strings.contains(text, SPINNER[2]), "each redraw turns the spinner")
	testing.expect(t, strings.contains(text, "✅"), "the step ends with its mark")
	testing.expect(t, strings.contains(text, "✨"), text)
	testing.expect(t, strings.contains(text, "Ready in"), text)
}
