// SPDX-License-Identifier: 0BSD
package codegen_spike

import "core:math"
import "core:strings"
import "core:testing"
import "verbs"

// Runs a program in the interpreter and returns what the verbs printed.
interpret_to_string :: proc(p: Program) -> string {
	captured: strings.Builder
	strings.builder_init(&captured)
	verbs.sink = &captured
	defer verbs.sink = nil
	interpret(p)
	return strings.to_string(captured)
}

// A program with one circle call whose three arguments are given.
circle_of :: proc(x, y, r: Expr) -> Stmt {
	return Call{verb = "circle", args = exprs(x, y, r), line = 1}
}

has_error :: proc(errors: []string, needle: string) -> bool {
	for message in errors {
		if strings.contains(message, needle) {
			return true
		}
	}
	return false
}

// eval

@(test)
test_eval_a_number :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	env := make(Env)
	testing.expect_value(t, eval(num(42.5), &env), 42.5)
	testing.expect_value(t, eval(num(-3), &env), -3)
	testing.expect_value(t, eval(num(0), &env), 0)
}

@(test)
test_eval_each_operator :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	env := make(Env)
	testing.expect_value(t, eval(bin(.Add, num(2), num(3)), &env), 5)
	testing.expect_value(t, eval(bin(.Sub, num(2), num(3)), &env), -1)
	testing.expect_value(t, eval(bin(.Mul, num(2), num(3)), &env), 6)
	testing.expect_value(t, eval(bin(.Div, num(3), num(2)), &env), 1.5)
}

@(test)
test_eval_nests_operators :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	env := make(Env)
	// (1 + 2) * (10 - 4) / 3
	expr := bin(.Div, bin(.Mul, bin(.Add, num(1), num(2)), bin(.Sub, num(10), num(4))), num(3))
	testing.expect_value(t, eval(expr, &env), 6)
}

@(test)
test_eval_reads_a_variable :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	env := make(Env)
	env["gap"] = 40
	testing.expect_value(t, eval(bin(.Mul, ref("gap"), num(2)), &env), 80)
}

@(test)
test_eval_an_unset_variable_reads_as_zero :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	env := make(Env)
	testing.expect_value(t, eval(ref("nothing"), &env), 0)
}

@(test)
test_eval_divides_by_zero_to_infinity :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	env := make(Env)
	testing.expect(t, math.is_inf(eval(bin(.Div, num(1), num(0)), &env)))
	testing.expect(t, math.is_nan(eval(bin(.Div, num(0), num(0)), &env)))
}

// interpreter

@(test)
test_interpret_the_circle_program :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	testing.expect_value(t, interpret_to_string(program_circle()), "circle 100 100 50\n")
}

@(test)
test_interpret_the_loop_program :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	want := "circle 40 100 4\ncircle 80 100 8\ncircle 120 100 12\ncircle 160 100 16\ncircle 200 100 20\n"
	testing.expect_value(t, interpret_to_string(program_loop()), want)
}

@(test)
test_interpret_an_empty_program :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	testing.expect_value(t, interpret_to_string(Program{name = "empty"}), "")
}

@(test)
test_interpret_a_loop_that_runs_once :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "once", body = stmts(For{var = "i", from = num(3), to = num(3), line = 1, body = stmts(circle_of(ref("i"), num(0), num(1)))})}
	testing.expect_value(t, interpret_to_string(p), "circle 3 0 1\n")
}

@(test)
test_interpret_a_loop_with_from_after_to_does_not_run :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "backwards", body = stmts(For{var = "i", from = num(5), to = num(1), line = 1, body = stmts(circle_of(ref("i"), num(0), num(1)))})}
	testing.expect_value(t, interpret_to_string(p), "")
}

@(test)
test_interpret_a_loop_with_fractional_bounds :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "fraction", body = stmts(For{var = "i", from = num(0.5), to = num(2.5), line = 1, body = stmts(circle_of(ref("i"), num(0), num(1)))})}
	testing.expect_value(t, interpret_to_string(p), "circle 0.5 0 1\ncircle 1.5 0 1\ncircle 2.5 0 1\n")
}

@(test)
test_interpret_nested_loops :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	inner := For{var = "j", from = num(1), to = num(2), line = 2, body = stmts(circle_of(ref("i"), ref("j"), num(1)))}
	p := Program{name = "nested", body = stmts(For{var = "i", from = num(1), to = num(2), line = 1, body = stmts(inner)})}
	testing.expect_value(t, interpret_to_string(p), "circle 1 1 1\ncircle 1 2 1\ncircle 2 1 1\ncircle 2 2 1\n")
}

@(test)
test_interpret_loop_bounds_use_variables :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "bounds", body = stmts(
		Assign{name = "n", value = num(2), line = 1},
		For{var = "i", from = num(1), to = ref("n"), line = 2, body = stmts(circle_of(ref("i"), num(0), num(1)))},
	)}
	testing.expect_value(t, interpret_to_string(p), "circle 1 0 1\ncircle 2 0 1\n")
}

@(test)
test_interpret_assignment_replaces_the_value :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "reassign", body = stmts(
		Assign{name = "x", value = num(1), line = 1},
		Assign{name = "x", value = bin(.Add, ref("x"), num(10)), line = 2},
		circle_of(ref("x"), num(0), num(0)),
	)}
	testing.expect_value(t, interpret_to_string(p), "circle 11 0 0\n")
}

@(test)
test_interpret_a_name_set_inside_a_loop_stays_set_after_it :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	// Section 5.15: a name assigned inside a block is sketch-wide.
	p := Program{name = "scope", body = stmts(
		For{var = "i", from = num(1), to = num(3), line = 1, body = stmts(Assign{name = "last", value = ref("i"), line = 2})},
		circle_of(ref("last"), num(0), num(0)),
	)}
	testing.expect_value(t, interpret_to_string(p), "circle 3 0 0\n")
}

// the checker

@(test)
test_check_accepts_the_programs :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	testing.expect_value(t, len(check_program(program_circle())), 0)
	testing.expect_value(t, len(check_program(program_loop())), 0)
}

@(test)
test_check_rejects_an_unknown_verb :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "x", body = stmts(Call{verb = "circel", args = exprs(num(1)), line = 3})}
	errors := check_program(p)
	testing.expect_value(t, len(errors), 1)
	testing.expect(t, has_error(errors[:], "line 3"))
	testing.expect(t, has_error(errors[:], "circel"))
}

@(test)
test_check_rejects_too_few_and_too_many_arguments :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	few := Program{name = "x", body = stmts(Call{verb = "circle", args = exprs(num(1), num(2)), line = 1})}
	many := Program{name = "x", body = stmts(Call{verb = "circle", args = exprs(num(1), num(2), num(3), num(4)), line = 1})}
	testing.expect(t, has_error(check_program(few)[:], "needs 3 values but got 2"))
	testing.expect(t, has_error(check_program(many)[:], "needs 3 values but got 4"))
}

@(test)
test_check_rejects_reading_a_name_before_it_is_set :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "x", body = stmts(circle_of(ref("gap"), num(0), num(0)))}
	errors := check_program(p)
	testing.expect_value(t, len(errors), 1)
	testing.expect(t, has_error(errors[:], "\"gap\" has no value yet"))
}

@(test)
test_check_accepts_a_name_after_it_is_set :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "x", body = stmts(Assign{name = "gap", value = num(1), line = 1}, circle_of(ref("gap"), num(0), num(0)))}
	testing.expect_value(t, len(check_program(p)), 0)
}

@(test)
test_check_rejects_a_name_used_in_its_own_assignment_before_it_is_set :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "x", body = stmts(Assign{name = "x", value = bin(.Add, ref("x"), num(1)), line = 1})}
	testing.expect(t, has_error(check_program(p)[:], "\"x\" has no value yet"))
}

@(test)
test_check_the_loop_name_exists_only_inside_the_loop :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "x", body = stmts(
		For{var = "i", from = num(1), to = num(2), line = 1, body = stmts(circle_of(ref("i"), num(0), num(0)))},
		circle_of(ref("i"), num(0), num(0)),
	)}
	errors := check_program(p)
	testing.expect_value(t, len(errors), 1)
	testing.expect(t, has_error(errors[:], "\"i\" has no value yet"))
}

@(test)
test_check_a_loop_name_hides_nothing_when_it_was_already_set :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "x", body = stmts(
		Assign{name = "i", value = num(9), line = 1},
		For{var = "i", from = num(1), to = num(2), line = 2, body = stmts()},
		circle_of(ref("i"), num(0), num(0)),
	)}
	testing.expect_value(t, len(check_program(p)), 0)
}

@(test)
test_check_loop_bounds_are_checked :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "x", body = stmts(For{var = "i", from = ref("a"), to = ref("b"), line = 4, body = stmts()})}
	testing.expect_value(t, len(check_program(p)), 2)
}

@(test)
test_check_reports_every_problem :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "x", body = stmts(
		Call{verb = "nope", args = exprs(), line = 1},
		circle_of(ref("a"), ref("b"), num(1)),
	)}
	testing.expect_value(t, len(check_program(p)), 3)
}

@(test)
test_check_looks_inside_nested_expressions :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "x", body = stmts(circle_of(bin(.Add, bin(.Mul, num(1), ref("deep")), num(2)), num(0), num(0)))}
	testing.expect(t, has_error(check_program(p)[:], "\"deep\" has no value yet"))
}

// the code generator

@(test)
test_generate_the_circle_program_exactly :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	want := `// Generated by the rocinante code generator from circle.roci. Do not edit.
//
//   circle 100 100 50
package sketch

import "verbs"

main :: proc() {
	verbs.circle(100.0, 100.0, 50.0) // circle.roci:1
}
`
	testing.expect_value(t, generate(program_circle()), want)
}

@(test)
test_generate_the_loop_program_exactly :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	want := `// Generated by the rocinante code generator from loop.roci. Do not edit.
//
//   gap = 40
//   for i from 1 to 5 [
//     circle (i * gap) 100 (i * 4)
//   ]
package sketch

import "verbs"

main :: proc() {
	gap: f64

	gap = 40.0 // loop.roci:1
	for i := 1.0; i <= 5.0; i += 1 { // loop.roci:2
		verbs.circle(i * gap, 100.0, i * 4.0) // loop.roci:3
	}
}
`
	testing.expect_value(t, generate(program_loop()), want)
}

@(test)
test_generate_an_empty_program :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	out := generate(Program{name = "empty"})
	testing.expect(t, strings.contains(out, "main :: proc() {\n}\n"))
}

@(test)
test_generate_numbers_are_always_floats :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	// An Odin literal without a dot would be an untyped integer.
	cases := [?]struct{value: f64, text: string}{{40, "40.0"}, {0, "0.0"}, {-3, "-3.0"}, {0.5, "0.5"}, {2.25, "2.25"}}
	for c in cases {
		b: strings.Builder
		strings.builder_init(&b)
		emit_expr(&b, num(c.value), true)
		testing.expect_value(t, strings.to_string(b), c.text)
	}
}

@(test)
test_generate_exponent_numbers_need_no_extra_dot :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	b: strings.Builder
	strings.builder_init(&b)
	emit_expr(&b, num(1e20), true)
	text := strings.to_string(b)
	testing.expect(t, strings.contains(text, "e"))
	testing.expect(t, !strings.has_suffix(text, ".0"))
}

@(test)
test_generate_brackets_only_nested_expressions :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	b: strings.Builder
	strings.builder_init(&b)
	emit_expr(&b, bin(.Mul, bin(.Add, ref("a"), num(1)), ref("c")), true)
	testing.expect_value(t, strings.to_string(b), "(a + 1.0) * c")
}

@(test)
test_generate_declares_each_assigned_name_once :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "twice", body = stmts(
		Assign{name = "x", value = num(1), line = 1},
		Assign{name = "x", value = num(2), line = 2},
		For{var = "i", from = num(1), to = num(2), line = 3, body = stmts(Assign{name = "y", value = ref("i"), line = 4})},
	)}
	out := generate(p)
	testing.expect_value(t, strings.count(out, "\tx: f64\n"), 1)
	testing.expect_value(t, strings.count(out, "\ty: f64\n"), 1)
	testing.expect_value(t, strings.count(out, "i: f64"), 0) // the loop name is declared by the loop
}

@(test)
test_generate_nested_loops_indent_each_level :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	inner := For{var = "j", from = num(1), to = num(2), line = 2, body = stmts(circle_of(ref("i"), ref("j"), num(1)))}
	p := Program{name = "nested", body = stmts(For{var = "i", from = num(1), to = num(2), line = 1, body = stmts(inner)})}
	out := generate(p)
	testing.expect(t, strings.contains(out, "\tfor i := 1.0; i <= 2.0; i += 1 { // nested.roci:1\n"))
	testing.expect(t, strings.contains(out, "\t\tfor j := 1.0; j <= 2.0; j += 1 { // nested.roci:2\n"))
	testing.expect(t, strings.contains(out, "\t\t\tverbs.circle(i, j, 1.0) // nested.roci:1\n"))
}

@(test)
test_collect_assigned_finds_names_once_in_order :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	body := stmts(
		Assign{name = "b", value = num(1), line = 1},
		For{var = "i", from = num(1), to = num(2), line = 2, body = stmts(Assign{name = "a", value = num(1), line = 3}, Assign{name = "b", value = num(2), line = 4})},
	)
	names: [dynamic]string
	collect_assigned(body, &names)
	testing.expect_value(t, len(names), 2)
	testing.expect_value(t, names[0], "b")
	testing.expect_value(t, names[1], "a")
}

@(test)
test_op_text :: proc(t: ^testing.T) {
	testing.expect_value(t, op_text(.Add), "+")
	testing.expect_value(t, op_text(.Sub), "-")
	testing.expect_value(t, op_text(.Mul), "*")
	testing.expect_value(t, op_text(.Div), "/")
}

// the stand-in doctor: which host can build which target (CLAUDE.md section 7)

HOSTS :: []string{"linux-amd64", "linux-arm64", "freebsd-amd64", "freebsd-arm64", "macos-arm64", "macos-amd64", "windows-amd64", "windows-arm64"}

target_named :: proc(name: string) -> Target {
	for target in TARGETS {
		if target.name == name {
			return target
		}
	}
	panic("no such target")
}

hosts_that_can :: proc(name: string) -> (count: int) {
	for host in HOSTS {
		if can_package(target_named(name), host) {
			count += 1
		}
	}
	return
}

@(test)
test_there_are_six_targets :: proc(t: ^testing.T) {
	testing.expect_value(t, len(TARGETS), 6)
}

@(test)
test_ios_is_packaged_on_macos_only :: proc(t: ^testing.T) {
	ios := target_named("ios")
	for host in HOSTS {
		want := strings.has_prefix(host, "macos-")
		testing.expectf(t, can_package(ios, host) == want, "ios on %s", host)
	}
}

@(test)
test_android_is_packaged_on_macos_linux_x86_and_windows_x86 :: proc(t: ^testing.T) {
	android := target_named("android")
	for host in HOSTS {
		want := host == "macos-arm64" || host == "macos-amd64" || host == "linux-amd64" || host == "windows-amd64"
		testing.expectf(t, can_package(android, host) == want, "android on %s", host)
	}
}

@(test)
test_android_cannot_be_packaged_on_freebsd_or_arm_linux :: proc(t: ^testing.T) {
	android := target_named("android")
	testing.expect(t, !can_package(android, "freebsd-amd64"))
	testing.expect(t, !can_package(android, "freebsd-arm64"))
	testing.expect(t, !can_package(android, "linux-arm64"))
}

@(test)
test_desktop_targets_are_packaged_on_their_own_system_only :: proc(t: ^testing.T) {
	for pair in ([]struct{target, prefix: string}{{"linux", "linux-"}, {"freebsd", "freebsd-"}, {"macos", "macos-"}, {"windows", "windows-"}}) {
		target := target_named(pair.target)
		for host in HOSTS {
			if strings.has_prefix(host, pair.prefix) && host != "windows-arm64" {
				testing.expectf(t, can_package(target, host), "%s on %s", pair.target, host)
			} else if !strings.has_prefix(host, pair.prefix) {
				testing.expectf(t, !can_package(target, host), "%s must not be packaged on %s", pair.target, host)
			}
		}
	}
}

@(test)
test_every_target_has_a_reason_and_a_host :: proc(t: ^testing.T) {
	for target in TARGETS {
		testing.expectf(t, len(target.says) > 0, "%s needs a reason", target.name)
		testing.expectf(t, hosts_that_can(target.name) > 0, "%s needs at least one host", target.name)
	}
}

@(test)
test_an_unknown_host_builds_nothing :: proc(t: ^testing.T) {
	for target in TARGETS {
		testing.expect(t, !can_package(target, "haiku-amd64"))
		testing.expect(t, !can_package(target, ""))
	}
}

@(test)
test_host_labels_are_plain_words :: proc(t: ^testing.T) {
	testing.expect_value(t, host_label("macos-arm64"), "a Mac")
	testing.expect_value(t, host_label("macos-amd64"), "a Mac")
	testing.expect_value(t, host_label("linux-amd64"), "a Linux x86-64 computer")
	testing.expect_value(t, host_label("linux-arm64"), "a Linux arm64 computer")
	testing.expect_value(t, host_label("freebsd-amd64"), "a FreeBSD computer")
	testing.expect_value(t, host_label("windows-amd64"), "a Windows computer")
	testing.expect_value(t, host_label("haiku-amd64"), "haiku-amd64") // unknown hosts are shown as given
}

@(test)
test_host_id_names_this_computer :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	id := host_id()
	os_part, _, arch_part := strings.partition(id, "-")
	known := os_part == "macos" || os_part == "linux" || os_part == "freebsd" || os_part == "windows" || os_part == "other"
	testing.expect(t, known)
	testing.expect(t, arch_part == "amd64" || arch_part == "arm64")
}

@(test)
test_probe_finds_a_command_and_misses_a_missing_one :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	_, found := probe("odin", "version")
	testing.expect(t, found, "odin must be on the PATH to run the tests")
	_, missing := probe("a-command-that-does-not-exist-anywhere")
	testing.expect(t, !missing)
}
