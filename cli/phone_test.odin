// SPDX-License-Identifier: 0BSD
package main

import "../tools/term"
import "core:fmt"
import "core:testing"

@(test)
test_the_lines_of_a_phone_script_become_steps_results_and_problems :: proc(t: ^testing.T) {
	step := parse_phone_line("step compile Compiling the sketch for Android")
	testing.expect_value(t, step.kind, Phone_Line_Kind.Step)
	testing.expect_value(t, step.step, term.Step_Kind.Compile)
	testing.expect_value(t, step.text, "Compiling the sketch for Android")
	// every kind a script may name
	kinds := [?]struct {
		word: string,
		kind: term.Step_Kind,
	}{{"libraries", .Libraries}, {"phone", .Phone}, {"compile", .Compile}, {"bundle", .Bundle}, {"sign", .Sign}, {"install", .Install}, {"start", .Start}}
	for k in kinds {
		said := parse_phone_line(fmt.tprintf("step %s Doing it", k.word))
		testing.expectf(t, said.kind == .Step && said.step == k.kind, "step %s", k.word)
	}
	result := parse_phone_line("result app /tmp/sketch.apk")
	testing.expect(t, result.kind == .Result && result.name == "app" && result.text == "/tmp/sketch.apk", fmt.tprint(result))
	finished := parse_phone_line("finished wildvex is running on the phone.")
	testing.expect(t, finished.kind == .Finished && finished.text == "wildvex is running on the phone.", fmt.tprint(finished))
	problem := parse_phone_line("problem The phone would not take the app.")
	testing.expect(t, problem.kind == .Problem && problem.text == "The phone would not take the app.", fmt.tprint(problem))
	// anything else is what a tool said: an unknown kind, a step with no words, a bare word, an empty line, Java's warnings
	for line in ([]string{"step dance Dancing", "step compile", "result", "finished", "problem", "", "WARNING: A restricted method in java.lang.System has been called", "stepping out"}) {
		said := parse_phone_line(line)
		testing.expectf(t, said.kind == .Other && said.text == line, "%q is a tool's line", line)
	}
}

@(test)
test_a_phone_target_is_named_in_words :: proc(t: ^testing.T) {
	testing.expect_value(t, phone_name("ios"), "the iPhone")
	testing.expect_value(t, phone_name("android"), "the Android phone")
	testing.expect_value(t, phone_name("android-emulator"), "the Android emulator")
	testing.expect_value(t, phone_name("other"), "other")
}
