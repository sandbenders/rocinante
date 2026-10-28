// SPDX-License-Identifier: 0BSD
package lang

import "core:fmt"
import "core:strings"
import "core:testing"

@(private = "file")
types_of :: proc(text: string) -> (names: string, ids: []Message_Id) {
	got := check_text(text)
	list := make([dynamic]Message_Id, context.temp_allocator)
	for d in got.checked.diagnostics {
		append(&list, d.id)
	}
	return describe_names(got.checked, context.temp_allocator), list[:]
}

@(private = "file")
expect_types :: proc(t: ^testing.T, text, want: string, loc := #caller_location) {
	names, ids := types_of(text)
	testing.expectf(t, len(ids) == 0, "`%s` gave %v", text, ids, loc = loc)
	testing.expect_value(t, strings.trim_space(names), strings.trim_space(want), loc = loc)
}

@(private = "file")
expect_errors :: proc(t: ^testing.T, text: string, want: []Message_Id, loc := #caller_location) {
	_, ids := types_of(text)
	if !testing.expectf(t, len(ids) == len(want), "`%s`: got %v, want %v", text, ids, want, loc = loc) {
		return
	}
	for id, i in want {
		testing.expectf(t, ids[i] == id, "`%s` message %d: got %v, want %v", text, i, ids[i], id, loc = loc)
	}
}

// ---- types ----

@(test)
test_unify_binds_variables_and_rejects_different_kinds :: proc(t: ^testing.T) {
	ts := types_init(context.temp_allocator)
	v := fresh(&ts)
	testing.expect(t, unify(&ts, v, T_NUMBER))
	testing.expect_value(t, resolve(&ts, v), T_NUMBER)
	testing.expect(t, unify(&ts, v, T_NUMBER))
	testing.expect(t, !unify(&ts, v, T_TEXT))
	testing.expect(t, !unify(&ts, T_NUMBER, T_COLOUR))
	// Two variables become one.
	a, b := fresh(&ts), fresh(&ts)
	testing.expect(t, unify(&ts, a, b))
	testing.expect(t, unify(&ts, b, T_TEXT))
	testing.expect_value(t, resolve(&ts, a), T_TEXT)
}

@(test)
test_unify_treats_errors_and_boxed_values_as_fitting_everything :: proc(t: ^testing.T) {
	ts := types_init(context.temp_allocator)
	for type in ([]Type_Id{T_NUMBER, T_TEXT, T_COLOUR, T_BOOLEAN, T_WINDOW}) {
		testing.expect(t, unify(&ts, T_ERROR, type))
		testing.expect(t, unify(&ts, type, T_ERROR))
		testing.expect(t, unify(&ts, T_BOXED, type))
	}
}

@(test)
test_vectors_unify_only_with_the_same_size_and_lists_by_element :: proc(t: ^testing.T) {
	ts := types_init(context.temp_allocator)
	v2, v3 := vector_of(&ts, 2), vector_of(&ts, 3)
	testing.expect_value(t, v2, vector_of(&ts, 2))
	testing.expect(t, v2 != v3)
	testing.expect(t, !unify(&ts, v2, v3))
	testing.expect(t, unify(&ts, v2, vector_of(&ts, 2)))
	x := fresh(&ts)
	testing.expect(t, unify(&ts, list_of(&ts, x), list_of(&ts, T_NUMBER)))
	testing.expect_value(t, resolve(&ts, x), T_NUMBER)
	testing.expect(t, !unify(&ts, list_of(&ts, T_NUMBER), list_of(&ts, T_TEXT)))
}

@(test)
test_a_type_cannot_contain_itself :: proc(t: ^testing.T) {
	ts := types_init(context.temp_allocator)
	v := fresh(&ts)
	testing.expect(t, !unify(&ts, v, list_of(&ts, v)))
}

@(test)
test_types_are_described_in_plain_words :: proc(t: ^testing.T) {
	ts := types_init(context.temp_allocator)
	testing.expect_value(t, describe(&ts, T_NUMBER), "a number")
	testing.expect_value(t, describe(&ts, T_TEXT), "text")
	testing.expect_value(t, describe(&ts, T_BOOLEAN), "true or false")
	testing.expect_value(t, describe(&ts, vector_of(&ts, 3)), "a vector of 3 numbers")
	testing.expect_value(t, describe(&ts, list_of(&ts, T_COLOUR)), "a list of colours")
	testing.expect_value(t, describe(&ts, list_of(&ts, vector_of(&ts, 2))), "a list of vectors of 2 numbers")
	testing.expect_value(t, describe(&ts, list_of(&ts, fresh(&ts))), "a list")
	testing.expect_value(t, describe(&ts, T_NONE), "nothing")
}

// ---- names and their types ----

@(test)
test_names_take_the_type_of_what_they_are_given :: proc(t: ^testing.T) {
	expect_types(t, `
x = 10
name = "Ada"
v = { 3, 4 }
c = rgb 255 0 0
ok = x > 3
p = mouse
`, `
x: a number
name: text
v: a vector of 2 numbers
c: a colour
ok: true or false
p: a vector of 2 numbers
`)
}

@(test)
test_the_smallest_program_checks_cleanly :: proc(t: ^testing.T) {
	expect_types(t, "circle at 100 100 radius 50", "")
}

@(test)
test_arithmetic_follows_the_array_programming_rules :: proc(t: ^testing.T) {
	expect_types(t, `
a = 1 + 2 * 3
b = { 1, 2 } + { 3, 4 }
c = { 1, 2 } * 2
d = 2 * { 1, 2, 3 }
e = { 1, 2 } * { 3, 4 }
f = red * 0.5
g = "fps: " + fps
h = 7 % 2
i = -a
j = not true
k = a is 3 and b is { 0, 0 }
`, `
a: a number
b: a vector of 2 numbers
c: a vector of 2 numbers
d: a vector of 3 numbers
e: a vector of 2 numbers
f: a colour
g: text
h: a number
i: a number
j: true or false
k: true or false
`)
}

@(test)
test_swizzles_and_colour_channels :: proc(t: ^testing.T) {
	expect_types(t, `
p = { 1, 2, 3 }
a = p.x
b = p.xy
c = p.zyx
d = red.r
`, `
p: a vector of 3 numbers
a: a number
b: a vector of 2 numbers
c: a vector of 3 numbers
d: a number
`)
	expect_errors(t, "p = { 1, 2 }\nq = p.z", {.Bad_Field})
	expect_errors(t, "p = { 1, 2 }\nq = p.xyz", {.Bad_Field})
	expect_errors(t, "q = red.x", {.Bad_Field})
	expect_errors(t, "x = 1\ny = x.z", {.Bad_Field})
}

@(test)
test_a_name_is_read_before_it_is_written_only_when_the_sketch_runs_it_first :: proc(t: ^testing.T) {
	expect_errors(t, "a = b\nb = 1", {.No_Value_Yet})
	// Blocks that run later may use names given further down.
	expect_errors(t, "draw [ circle at x 100 radius 50 ]\nx = 10", {})
	expect_errors(t, "on key \"a\" [ y = x ]\nx = 1\ny = 2", {})
	expect_errors(t, "every 1 second [ circle at x 1 radius 2 ]\nx = 1", {})
	// A loop runs where it is written.
	expect_errors(t, "repeat 2 [ y = x ]\nx = 1\ny = 2", {.No_Value_Yet})
}

@(test)
test_unknown_names_get_a_suggestion_from_the_sketch_first :: proc(t: ^testing.T) {
	got := check_text("speed = 3\nx = sped + 1")
	d := got.checked.diagnostics[0]
	testing.expect_value(t, d.id, Message_Id.Unknown_Name)
	testing.expect_value(t, d.args[0], "sped")
	testing.expect_value(t, d.args[3], "x = speed + 1")
	far := check_text("circle at zzz 100 radius 50")
	testing.expect_value(t, far.checked.diagnostics[0].args[3], "zzz = 0\ncircle at zzz 100 radius 50")
}

@(test)
test_colour_names_and_built_in_values_are_names :: proc(t: ^testing.T) {
	expect_errors(t, "fill red\ncircle at mouse.x mouse.y radius 5\nx = pi + tau + fps + frame + time + width + height\nk = key\nflag = true", {})
}

@(test)
test_a_name_keeps_one_kind_of_value :: proc(t: ^testing.T) {
	got := check_text("x = 10\nx = \"ten\"")
	d := got.checked.diagnostics[0]
	testing.expect_value(t, d.id, Message_Id.Kind_Conflict)
	testing.expect_value(t, d.args[1], "a number, set on line 1")
	testing.expect_value(t, d.args[2], "text")
	testing.expect_value(t, d.args[3], "x2 = \"ten\"")
	expect_errors(t, "x = 1\nx = 2\nx = x + 1", {})
	expect_errors(t, "x = { 1, 2 }\nx = { 1, 2, 3 }", {.Kind_Conflict})
	expect_errors(t, "c = red\nc = 5", {.Kind_Conflict})
}

@(test)
test_a_name_used_in_a_block_before_its_value_settles_its_type_from_the_first_write :: proc(t: ^testing.T) {
	expect_types(t, "draw [ y = x + 1 ]\nx = 10", "y: a number\nx: a number")
}

@(test)
test_capital_names_are_constants :: proc(t: ^testing.T) {
	expect_errors(t, "SPEED = 4\nSPEED = 5", {.Constant_Changed})
	expect_errors(t, "SPEED = 4\nx = SPEED * 2", {})
	expect_errors(t, "P = { 1, 2 }\nP.x = 3", {.Constant_Changed})
	expect_errors(t, "MAX_PARTICLES = 200\nGRID_2 = 4", {})
}

@(test)
test_names_the_language_already_uses_cannot_be_assigned :: proc(t: ^testing.T) {
	expect_errors(t, "circle = 3", {.Reserved_Name})
	expect_errors(t, "width = 3", {.Reserved_Name})
	expect_errors(t, "red = 3", {.Reserved_Name})
	// `size` is both a value and a connecting word and stays free.
	expect_errors(t, "size = 3", {})
}

@(test)
test_two_names_that_differ_only_in_capitals_get_a_warning :: proc(t: ^testing.T) {
	got := check_text("speed = 1\nSpeed = 2")
	if testing.expect_value(t, len(got.checked.diagnostics), 1) {
		testing.expect_value(t, got.checked.diagnostics[0].id, Message_Id.Case_Only_Difference)
		testing.expect(t, !has_errors(got.checked.diagnostics))
	}
}

@(test)
test_field_assignment_checks_the_part_and_its_type :: proc(t: ^testing.T) {
	expect_errors(t, "p = { 1, 2 }\np.x = 5\np.y = p.x + 1", {})
	expect_errors(t, "p = { 1, 2 }\np.z = 5", {.Bad_Field})
	expect_errors(t, "p = { 1, 2 }\np.x = \"a\"", {.Wrong_Kind_Here})
}

// ---- vectors and lists ----

@(test)
test_vectors_need_two_to_four_numbers :: proc(t: ^testing.T) {
	expect_errors(t, "v = { 1 }", {.Wrong_Kind_Here})
	expect_errors(t, "v = { 1, 2, 3, 4, 5 }", {.Wrong_Kind_Here})
	expect_errors(t, "v = {}", {.Wrong_Kind_Here})
	expect_errors(t, "v = { 1, \"a\" }", {.Wrong_Kind_Here})
	expect_errors(t, "v = { 1, 2, 3, 4 }", {})
}

@(test)
test_lists_have_one_element_type_or_hold_mixed_values :: proc(t: ^testing.T) {
	expect_types(t, "a = [ 1 2 3 ]\nb = [ red teal ]\nc = [ { 1, 2 } { 3, 4 } ]\nd = []\ne = [ 1 \"a\" ]", `
a: a list of numbers
b: a list of colours
c: a list of vectors of 2 numbers
d: a list
e: a list of mixed values
`)
}

// ---- operators ----

@(test)
test_operators_that_do_not_fit_are_one_error_with_a_fix :: proc(t: ^testing.T) {
	got := check_text("v = { 1, 2 } + { 1, 2, 3 }")
	d := got.checked.diagnostics[0]
	testing.expect_value(t, d.id, Message_Id.Operator_Types)
	testing.expect_value(t, d.args[0], "+")
	testing.expect_value(t, d.args[3], "v = { 1, 2 } + { 0, 0 }")
	testing.expect_value(t, check_text("w = \"a\" - 1").checked.diagnostics[0].args[3], "w = 1 - 1")
	testing.expect_value(t, check_text("x = 3\ny = x - \"a\"").checked.diagnostics[0].args[3], "y = x - 1")
	testing.expect_value(t, check_text("x = 3\ny = x and true").checked.diagnostics[0].args[3], "y = true and true")
	expect_errors(t, "x = 1 < \"a\"", {.Operator_Types})
	expect_errors(t, "x = 1 is \"a\"", {.Operator_Types})
	expect_errors(t, "x = 1 % \"a\"", {.Operator_Types})
	expect_errors(t, "x = red + 1", {.Operator_Types})
	expect_errors(t, "x = not 3", {.Operator_Types})
	expect_errors(t, "x = -\"a\"", {.Operator_Types})
	expect_errors(t, "x = true or 3", {.Operator_Types})
}

@(test)
test_a_mistake_inside_an_expression_is_reported_once :: proc(t: ^testing.T) {
	expect_errors(t, "x = (yy + 1) * 2 + 3", {.Unknown_Name})
	expect_errors(t, "circle at yy 1 radius 2 fill zz", {.Unknown_Name, .Unknown_Name})
}

// ---- control flow ----

@(test)
test_conditions_have_to_be_true_or_false :: proc(t: ^testing.T) {
	expect_errors(t, "x = 1\nif x [ ]", {.Condition_Not_Boolean})
	expect_errors(t, "x = 1\nwhile x [ ]", {.Condition_Not_Boolean})
	expect_errors(t, "x = 1\nif x > 0 [ ] else [ ]", {})
	expect_errors(t, "ok = true\nif ok [ ]\nwhile not ok [ ]", {})
	got := check_text("x = 1\nif x [ ]")
	testing.expect_value(t, got.checked.diagnostics[0].args[3], "if x > 0 [ ]")
	got = check_text("s = \"a\"\nif s [ ]")
	testing.expect_value(t, got.checked.diagnostics[0].args[3], "if s is \"hello\" [ ]")
}

@(test)
test_counts_and_bounds_have_to_be_numbers :: proc(t: ^testing.T) {
	expect_errors(t, "repeat \"x\" [ ]", {.Wrong_Kind_Here})
	expect_errors(t, "for i from \"a\" to 3 [ ]", {.Wrong_Kind_Here})
	expect_errors(t, "for i from 1 to 3 by red [ ]", {.Wrong_Kind_Here})
	expect_errors(t, "every \"x\" seconds [ ]", {.Wrong_Kind_Here})
	expect_errors(t, "repeat 3 [ ]\nfor i from 1 to 3 by 2 [ ]", {})
}

@(test)
test_a_loop_variable_exists_only_inside_its_loop :: proc(t: ^testing.T) {
	expect_errors(t, "for i from 1 to 3 [ circle at i i radius 5 ]", {})
	expect_errors(t, "for i from 1 to 3 [ ]\ncircle at i 1 radius 2", {.Unknown_Name})
	// The same name may be used again by another loop.
	expect_errors(t, "for i from 1 to 3 [ ]\nfor i from 1 to 3 [ circle at i 1 radius 2 ]", {})
}

@(test)
test_for_each_gives_its_name_the_type_of_the_items :: proc(t: ^testing.T) {
	expect_errors(t, "ps = [ { 1, 2 } { 3, 4 } ]\nfor each p in ps [ circle at p radius 5 ]", {})
	expect_errors(t, "ps = [ { 1, 2 } { 3, 4 } ]\nfor each p in ps [ circle at p radius \"a\" ]", {.Wrong_Argument_Kind})
	expect_errors(t, "for each p in 5 [ ]", {.Wrong_Kind_Here})
}

@(test)
test_draw_every_and_on_blocks_are_checked :: proc(t: ^testing.T) {
	expect_errors(t, "draw [ background 0\n  circle at mouse radius 20 ]", {})
	expect_errors(t, "draw 3 [ ]", {.Wrong_Kind_Here})
	expect_errors(t, "w = window size 400 300\ndraw w [ ]\non w receive m [ x = m ]\nx = 1", {})
	expect_errors(t, "on key 5 [ ]", {.Wrong_Kind_Here})
	expect_errors(t, "on mouse down [ circle at mouse radius 5 ]", {})
	expect_errors(t, "x = 3\non x receive m [ ]", {.Wrong_Kind_Here})
}

@(test)
test_with_checks_its_style_words :: proc(t: ^testing.T) {
	expect_errors(t, "with fill cyan thickness 2 [ circle at 1 2 radius 3 ]", {})
	expect_errors(t, "with fill \"a\" [ ]", {.Wrong_Argument_Kind})
	expect_errors(t, "glow = { fill: cyan }\nwith glow [ ]", {})
}

// ---- calls ----

@(test)
test_a_verb_group_picks_its_shape_by_count_then_kinds :: proc(t: ^testing.T) {
	expect_errors(t, "circle at 1 2 radius 3\ncircle at mouse radius 5\nx = mix 1 2 0.5\nc = mix red blue 0.5", {})
	expect_types(t, "x = mix 1 2 0.5\nc = mix red blue 0.5", "x: a number\nc: a colour")
}

@(test)
test_the_wrong_number_of_arguments_names_what_the_verb_takes :: proc(t: ^testing.T) {
	got := check_text("dist 1")
	d := got.checked.diagnostics[0]
	testing.expect_value(t, d.id, Message_Id.Wrong_Argument_Count)
	testing.expect_value(t, d.args[1], "4 values (x1, y1, x2 and y2) or 2 values (a and b)")
	testing.expect_value(t, d.args[2], "1 value")
	testing.expect_value(t, d.args[3], "dist 1 b")
	expect_errors(t, "background", {.Wrong_Argument_Count})
	expect_errors(t, "x = random", {.Missing_Required_Word, .Missing_Required_Word})
}

@(test)
test_the_wrong_kind_of_argument_names_the_parameter :: proc(t: ^testing.T) {
	got := check_text("rgb 100 \"two\" 50")
	d := got.checked.diagnostics[0]
	testing.expect_value(t, d.id, Message_Id.Wrong_Argument_Kind)
	testing.expect_value(t, d.args[1], "a number for `green`")
	testing.expect_value(t, d.args[2], "text")
	testing.expect_value(t, d.args[3], "rgb 100 0 50")
	// A grey number, a gradient list and a colour all fit a colour parameter.
	expect_errors(t, "fill 128\nfill [ red teal ]\nfill red\nbackground (gradient [ red teal ])", {})
	expect_errors(t, "fill \"red\"", {.Wrong_Argument_Kind})
}

@(test)
test_a_call_that_gives_nothing_cannot_be_a_value :: proc(t: ^testing.T) {
	expect_errors(t, "x = clear", {.Value_Of_Nothing})
	expect_errors(t, "x = circle at 1 2 radius 3", {.Value_Of_Nothing})
	expect_errors(t, "circle at (clear) 2 radius 3", {.Value_Of_Nothing})
}

@(test)
test_connecting_words_are_checked_for_kind_repeats_and_required_ones :: proc(t: ^testing.T) {
	expect_errors(t, "window size 800 600 at 100 100", {})
	expect_errors(t, "window size 800 600 at \"a\" 100", {.Wrong_Argument_Kind})
	expect_errors(t, "circle at 1 2 radius 3 fill red fill blue", {.Word_Twice})
	expect_errors(t, "x = random from 1", {.Missing_Required_Word})
	expect_errors(t, "x = random from 1 to 3", {})
	expect_errors(t, "circle at 1 2 radius 3 as center fill red", {})
	expect_errors(t, "fill [ red teal ] angle 90 as radial", {})
}

@(test)
test_words_where_a_call_takes_a_word_are_not_names :: proc(t: ^testing.T) {
	expect_errors(t, "caps round\njoins bevel", {})
	expect_errors(t, "x = noise 1 2 as simplex", {})
}

@(test)
test_a_picked_item_has_the_type_of_the_list :: proc(t: ^testing.T) {
	expect_types(t, "colours = [ red teal ]\nc = pick colours", "colours: a list of colours\nc: a colour")
}

@(test)
test_a_window_is_a_value :: proc(t: ^testing.T) {
	expect_types(t, "w = window size 800 600", "w: a window")
}

@(test)
test_a_verb_taught_with_learn_is_not_checked_yet_but_its_calls_are_counted :: proc(t: ^testing.T) {
	expect_errors(t, "learn star size [ circle at 1 2 radius size ]\nstar 100", {})
	expect_errors(t, "learn star size [ ]\nstar 100 200", {.Unexpected_Token})
	got := check_text("learn star size [ ]\nstar")
	testing.expect_value(t, got.checked.diagnostics[0].id, Message_Id.Wrong_Argument_Count)
	testing.expect_value(t, got.checked.diagnostics[0].args[3], "star size")
}

// ---- parse errors do not cascade ----

@(test)
test_a_sketch_with_parse_errors_is_still_checked_without_extra_noise :: proc(t: ^testing.T) {
	expect_errors(t, "circel 1 2 3\ncircle at 4 5 radius 6", {.Unknown_Word})
	expect_errors(t, "x = \ny = x", {.Nothing_After_Equals, .Unknown_Name})
}

// ---- the IR ----

@(test)
test_blocks_list_what_they_capture :: proc(t: ^testing.T) {
	got := check_text("a = 1\nb = 2\nrepeat 3 [ a = a + 1\n  for i from 1 to 2 [ b = b + i ] ]")
	repeat := got.checked.program.stmts[2].kind.(IR_Repeat)
	names := make([dynamic]string, context.temp_allocator)
	for s in repeat.body.captures {
		append(&names, s.name)
	}
	testing.expect_value(t, strings.join(names[:], ",", context.temp_allocator), "a,b")
	inner := repeat.body.stmts[1].kind.(IR_For)
	inner_names := make([dynamic]string, context.temp_allocator)
	for s in inner.body.captures {
		append(&inner_names, s.name)
	}
	// The loop's own variable is inside the block, so it is not captured.
	testing.expect_value(t, strings.join(inner_names[:], ",", context.temp_allocator), "b")
}

@(test)
test_calls_carry_the_shape_that_was_chosen :: proc(t: ^testing.T) {
	got := check_text("circle at mouse radius 5")
	call := got.checked.program.stmts[0].kind.(IR_Expr_Stmt).expr.kind.(IR_Call)
	testing.expect_value(t, call.shape, 1)
	testing.expect_value(t, call.verb.name, "circle")
	testing.expect_value(t, len(call.args), 2)
}

@(test)
test_checking_the_same_sketch_twice_gives_the_same_answer :: proc(t: ^testing.T) {
	text := "x = 10\ndraw [ circle at x x radius 5 ]\nfor i from 1 to 3 [ x = x + i ]\n"
	a, b := check_text(text), check_text(text)
	testing.expect_value(t, describe_names(a.checked, context.temp_allocator), describe_names(b.checked, context.temp_allocator))
	testing.expect_value(t, len(a.checked.diagnostics), len(b.checked.diagnostics))
	testing.expect_value(t, fmt.tprintf("%d", len(a.checked.program.stmts)), fmt.tprintf("%d", len(b.checked.program.stmts)))
}

@(test)
test_diagnostics_come_in_reading_order :: proc(t: ^testing.T) {
	got := check_text("x = yy\nz = 1 +\ny = \"a\" - 1")
	last := -1
	for d in got.checked.diagnostics {
		testing.expect(t, d.span.start >= last, "diagnostics must be in reading order")
		last = d.span.start
	}
}

// ---- records and lists (step 3b) ----

@(test)
test_a_record_literal_makes_a_shape_and_its_fields_have_types :: proc(t: ^testing.T) {
	expect_types(t, "ball = { pos: { 1, 2 }, size: 5, name: \"b\" }\nx = ball.pos\ny = ball.size\nz = ball.name", `
ball: a record with pos, size and name
x: a vector of 2 numbers
y: a number
z: text
`)
}

@(test)
test_a_field_assigned_anywhere_joins_the_shape_even_above :: proc(t: ^testing.T) {
	// The read is above the assignment; the field still exists (two passes).
	expect_errors(t, "ball = { x: 1 }\nc = ball.colour\nball.colour = red", {})
	expect_types(t, "ball = { x: 1 }\nball.colour = red\nc = ball.colour", "ball: a record with x and colour\nc: a colour")
}

@(test)
test_a_field_nothing_ever_gives_is_an_error_with_a_suggestion :: proc(t: ^testing.T) {
	got := check_text("ball = { vel: 1 }\nx = ball.vell")
	d := got.checked.diagnostics[0]
	testing.expect_value(t, d.id, Message_Id.Unknown_Field)
	testing.expect_value(t, d.args[3], "x = ball.vel")
	expect_errors(t, "ball = { vel: 1 }\nball.vel = \"a\"", {.Wrong_Kind_Here})
}

@(test)
test_nested_fields_are_followed :: proc(t: ^testing.T) {
	expect_types(t, "b = { pos: { 1, 2 } }\nb.pos.x = 5\nq = b.pos.y", "b: a record with pos\nq: a number")
	expect_errors(t, "b = { pos: { 1, 2 } }\nb.pos.z = 5", {.Bad_Field})
	expect_errors(t, "b = { pos: { 1, 2 } }\nb.nope.x = 5", {.Unknown_Field})
	expect_errors(t, "nothing.x = 5", {.Unknown_Name})
}

@(test)
test_records_made_in_different_places_meet_in_one_list_with_all_the_fields :: proc(t: ^testing.T) {
	expect_types(t, "ps = []\nadd { a: 1 } to ps\nadd { b: 2 } to ps", "ps: a list of records with a and b")
	expect_errors(t, "ps = []\nadd { a: 1 } to ps\nadd { a: \"x\" } to ps", {.Kind_Conflict})
}

@(test)
test_a_list_that_starts_empty_learns_its_items_from_add :: proc(t: ^testing.T) {
	expect_types(t, "xs = []\nadd 1 to xs\nadd 2 to xs", "xs: a list of numbers")
	expect_errors(t, "xs = []\nadd 1 to xs\nadd \"a\" to xs", {.Wrong_Item_Kind})
	expect_errors(t, "xs = [ 1 2 ]\nremove \"a\" from xs", {.Wrong_Item_Kind})
	expect_errors(t, "add 1 to 5", {.Wrong_Argument_Kind})
}

@(test)
test_count_item_pick_and_copy_have_the_right_types :: proc(t: ^testing.T) {
	expect_types(t, "xs = [ 1 2 3 ]\nn = count xs\nfirst = item 1 of xs\nc = copy xs\nr = pick xs", `
xs: a list of numbers
n: a number
first: a number
c: a list of numbers
r: a number
`)
}

@(test)
test_list_verbs_check_their_block_with_it_and_result :: proc(t: ^testing.T) {
	expect_types(t, `
ps = [ { 1, 2 } { 3, 4 } ]
a = keep ps [ it.x > 1 ]
b = collect ps [ it.y * 2 ]
s = combine b from 0 [ result + it ]
f = find ps [ it.x is 3 ]
o = sort ps by [ it.y ]
`, `
ps: a list of vectors of 2 numbers
a: a list of vectors of 2 numbers
b: a list of numbers
s: a number
f: a vector of 2 numbers
o: a list of vectors of 2 numbers
`)
	expect_errors(t, "ps = [ 1 2 ]\nx = keep ps [ it ]", {.Block_Gives_Wrong_Kind})
	expect_errors(t, "ps = [ 1 2 ]\nx = skip ps [ it + 1 ]", {.Block_Gives_Wrong_Kind})
	expect_errors(t, "ps = [ 1 2 ]\nx = find ps [ it ]", {.Block_Gives_Wrong_Kind})
	expect_errors(t, "ps = [ 1 2 ]\nx = combine ps from \"a\" [ result + it ]", {})
	expect_errors(t, "ps = [ 1 2 ]\nx = combine ps from 0 [ \"a\" ]", {.Block_Gives_Wrong_Kind})
	expect_errors(t, "ps = [ red teal ]\nx = sort ps by [ it ]", {.Block_Gives_Wrong_Kind})
	expect_errors(t, "x = keep 5 [ it ]", {.Wrong_Argument_Kind})
}

@(test)
test_it_and_result_exist_only_inside_the_blocks_that_give_them :: proc(t: ^testing.T) {
	expect_errors(t, "x = it", {.It_Outside_Block})
	expect_errors(t, "ps = [ 1 ]\nx = keep ps [ result > 0 ]", {.It_Outside_Block})
	expect_errors(t, "ps = [ 1 ]\nx = combine ps from 0 [ result + it ]\ny = it", {.It_Outside_Block})
	expect_errors(t, "it = 3", {.Reserved_Name})
}

@(test)
test_a_list_cannot_change_while_for_each_walks_it :: proc(t: ^testing.T) {
	expect_errors(t, "ps = [ 1 2 ]\nfor each p in ps [ add p to ps ]", {.Changed_While_Walking})
	expect_errors(t, "ps = [ 1 2 ]\nfor each p in ps [ remove p from ps ]", {.Changed_While_Walking})
	expect_errors(t, "ps = [ 1 2 ]\nfor each p in ps [ ps = [] ]", {.Changed_While_Walking})
	// Another list, or a copy, is fine; so is changing it after the loop.
	expect_errors(t, "ps = [ 1 2 ]\nqs = []\nfor each p in ps [ add p to qs ]\nadd 3 to ps", {})
	expect_errors(t, "ps = [ 1 2 ]\nfor each p in copy ps [ add p to ps ]", {})
}

@(test)
test_the_loop_variable_of_for_each_is_a_record_with_the_fields_of_the_list :: proc(t: ^testing.T) {
	expect_errors(t, "ps = [ { x: 1 } ]\nfor each p in ps [ p.x = p.x + 1 ]", {})
	expect_errors(t, "ps = [ { x: 1 } ]\nfor each p in ps [ q = p.nope ]", {.Unknown_Field})
}

// ---- taught verbs (step 3b-2) ----

@(private = "file")
instances_of :: proc(got: Checked_Text, name: string) -> int {
	n := 0
	for inst in got.checked.program.instances {
		if inst.name == name && !inst.unused {
			n += 1
		}
	}
	return n
}

@(test)
test_a_taught_verb_takes_its_parameter_types_from_the_call :: proc(t: ^testing.T) {
	expect_types(t, "learn double n [ give n * 2 ]\na = double 21\nv = double { 1, 2 }", "a: a number\nv: a vector of 2 numbers")
	expect_errors(t, "learn show n [ circle at 1 2 radius n ]\nshow 5", {})
	expect_errors(t, "learn show n [ circle at 1 2 radius n ]\nshow \"a\"", {.Wrong_Argument_Kind})
}

@(test)
test_a_verb_is_checked_once_for_each_distinct_tuple_of_argument_types :: proc(t: ^testing.T) {
	got := check_text("learn double n [ give n * 2 ]\na = double 1\nb = double 2\nc = double { 1, 2 }")
	testing.expect_value(t, instances_of(got, "double"), 2)
	testing.expect_value(t, len(got.checked.diagnostics), 0)
}

@(test)
test_a_verb_used_with_two_record_shapes_gets_two_versions :: proc(t: ^testing.T) {
	got := check_text("learn step p [ p.pos = p.pos + p.vel ]\na = { pos: { 1, 2 }, vel: { 3, 4 }, name: \"a\" }\nb = { pos: { 1, 2 }, vel: { 3, 4 } }\nstep a\nstep b")
	testing.expect_value(t, instances_of(got, "step"), 2)
	testing.expect_value(t, len(got.checked.diagnostics), 0)
	// A record that lacks what the verb uses is the verb's mistake, reported where it is.
	expect_errors(t, "learn step p [ p.pos = p.pos + p.vel ]\nc = { pos: { 1, 2 } }\nstep c", {.Unknown_Field})
}

@(test)
test_a_verb_nobody_calls_is_still_checked :: proc(t: ^testing.T) {
	expect_errors(t, "learn lonely a [ x = nothing_here + 1 ]", {.Unknown_Name})
	expect_errors(t, "learn lonely a [ circle at 1 2 radius a ]", {})
	got := check_text("learn lonely a [ circle at 1 2 radius a ]")
	testing.expect_value(t, len(got.checked.program.instances), 1)
	testing.expect(t, got.checked.program.instances[0].unused)
}

@(test)
test_recursion_ends_and_settles_the_result_from_the_gives :: proc(t: ^testing.T) {
	expect_types(t, "learn fact n [\n  if n < 2 [ give 1 ]\n  give n * fact (n - 1)\n]\nx = fact 5", "x: a number")
	got := check_text("learn tree n [ if n > 0 [ circle at 1 2 radius n\n  tree (n - 1) ] ]\ntree 5")
	testing.expect_value(t, len(got.checked.diagnostics), 0)
	testing.expect_value(t, instances_of(got, "tree"), 1)
}

@(test)
test_names_made_inside_a_verb_are_local_and_top_level_names_are_changed :: proc(t: ^testing.T) {
	expect_types(t, "total = 0\nlearn add_up n [ total = total + n\n  scratch = n * 2 ]\nadd_up 5", "total: a number")
	// `scratch` does not exist outside the verb.
	expect_errors(t, "learn add_up n [ scratch = n * 2 ]\nadd_up 5\nx = scratch", {.Unknown_Name})
	expect_errors(t, "learn f n [ y = x ]\nf 1", {.Unknown_Name})
}

@(test)
test_a_verb_reads_top_level_names_given_further_down :: proc(t: ^testing.T) {
	expect_errors(t, "learn f n [ circle at n n radius size ]\nf 1\nsize = 5", {})
}

@(test)
test_defaults_with_words_are_typed_and_the_call_may_change_them :: proc(t: ^testing.T) {
	expect_errors(t, "learn star size with points 5 spin 0 [ repeat points [ circle at 1 2 radius size ]\n  turn spin ]\nstar 100\nstar 50 points 7 spin 15\nstar 1 spin 2", {})
	expect_errors(t, "learn star size with points 5 [ repeat points [ ] ]\nstar 100 points \"a\"", {.Wrong_Argument_Kind})
}

@(test)
test_a_verb_that_gives_has_to_give_on_every_path :: proc(t: ^testing.T) {
	expect_errors(t, "learn f n [ if n < 0 [ give 1 ] ]\nx = f 1", {.Give_Missing_On_Path})
	expect_errors(t, "learn f n [ if n < 0 [ stop ]\n  give n ]\nx = f 1", {.Give_Missing_On_Path})
	expect_errors(t, "learn f n [ if n < 0 [ give 1 ] else [ give 2 ] ]\nx = f 1", {})
	expect_errors(t, "learn f n [ if n < 0 [ give 1 ]\n  give 2 ]\nx = f 1", {})
	expect_errors(t, "learn f n [ repeat 3 [ give 1 ] ]\nx = f 1", {.Give_Missing_On_Path})
	expect_errors(t, "learn f n [ if n < 0 [ if n < 5 [ give 1 ] else [ give 2 ] ] else [ give 3 ] ]\nx = f 1", {})
}

@(test)
test_every_give_of_a_verb_gives_the_same_kind_of_value :: proc(t: ^testing.T) {
	expect_errors(t, "learn f n [ if n < 0 [ give 1 ] else [ give \"a\" ] ]\nx = f 1", {.Give_Kinds_Differ})
	expect_errors(t, "learn f n [ if n < 0 [ give { 1, 2 } ] else [ give { 3, 4, 5 } ] ]\nx = f 1", {.Give_Kinds_Differ})
	expect_errors(t, "learn f a b [ give { min: a, max: b } ]\nr = f 1 2\nlow = r.min", {})
}

@(test)
test_a_verb_with_and_without_give_is_used_the_right_way :: proc(t: ^testing.T) {
	expect_errors(t, "learn star size [ circle at 1 2 radius size ]\nx = star 3", {.Value_Of_Nothing})
	expect_errors(t, "learn double n [ give n * 2 ]\ndouble 3", {.Result_Dropped})
	got := check_text("learn double n [ give n * 2 ]\ndouble 3")
	testing.expect(t, !has_errors(got.checked.diagnostics))
	expect_errors(t, "learn star size [ circle at 1 2 radius size ]\nstar 3", {})
}

@(test)
test_a_constant_cannot_be_given_to_a_verb_that_changes_it :: proc(t: ^testing.T) {
	expect_errors(t, "learn tint p [ p.red = 255 ]\nPALETTE = { red: 0 }\ntint PALETTE", {.Constant_Changed_By_Verb})
	expect_errors(t, "learn tint p [ p.red = 255 ]\npalette = { red: 0 }\ntint palette", {})
	expect_errors(t, "learn fill_up xs [ add 1 to xs ]\nNUMBERS = [ 1 ]\nfill_up NUMBERS", {.Constant_Changed_By_Verb})
	// A constant given to a verb that only reads it is fine, and so is a copy.
	expect_errors(t, "learn show p [ circle at p.x p.x radius 5 ]\nP = { x: 1 }\nshow P", {})
	expect_errors(t, "learn tint p [ p.red = 255 ]\nPALETTE = { red: 0 }\ntint (copy PALETTE)", {})
	// The change is passed along: a parameter handed on to a verb that changes it.
	expect_errors(t, "learn inner p [ p.red = 1 ]\nlearn outer q [ inner q ]\nPALETTE = { red: 0 }\nouter PALETTE", {.Constant_Changed_By_Verb})
}

@(test)
test_a_call_with_the_wrong_number_of_values_names_the_parameters :: proc(t: ^testing.T) {
	got := check_text("learn move_by dx dy [ move dx dy ]\nmove_by 5")
	d := got.checked.diagnostics[0]
	testing.expect_value(t, d.id, Message_Id.Wrong_Argument_Count)
	testing.expect_value(t, d.args[3], "move_by 5 dy")
}

@(test)
test_the_ir_of_a_call_points_at_its_version_and_the_body_has_its_gives :: proc(t: ^testing.T) {
	got := check_text("learn double n [ give n * 2 ]\nx = double 4")
	assign := got.checked.program.stmts[1].kind.(IR_Assign)
	call := assign.value.kind.(IR_Call)
	if testing.expect(t, call.instance != nil) {
		testing.expect_value(t, call.instance.name, "double")
		testing.expect(t, call.instance.gives)
		testing.expect_value(t, len(call.instance.params), 1)
		_, is_give := call.instance.body.stmts[0].kind.(IR_Give)
		testing.expect(t, is_give)
	}
}

@(test)
test_a_verb_taught_in_another_file_is_counted_but_not_checked :: proc(t: ^testing.T) {
	src := make_source("sketch.roci", "flock 1 2", 0, context.temp_allocator)
	extra := []Taught_Verb{{name = "flock", params = {"a", "b"}}}
	got := check(src, test_verbs(), extra, context.temp_allocator)
	testing.expect_value(t, len(got.diagnostics), 0)
	src2 := make_source("sketch.roci", "flock 1", 0, context.temp_allocator)
	got2 := check(src2, test_verbs(), extra, context.temp_allocator)
	testing.expect_value(t, got2.diagnostics[0].id, Message_Id.Wrong_Argument_Count)
}

// ---- messages between windows (step 3c) ----

@(test)
test_a_handler_gets_the_type_of_what_is_sent_to_its_window :: proc(t: ^testing.T) {
	expect_types(t, "w = window size 400 300\nsend w 5\non w receive m [ total = m + 1 ]\ntotal = 0", "w: a window\ntotal: a number")
	// The handler is above its sender: the first pass still finds the type.
	expect_types(t, "w = window size 400 300\non w receive m [ total = m + 1 ]\ntotal = 0\nsend w 5", "w: a window\ntotal: a number")
	expect_errors(t, "w = window size 400 300\nsend w \"calm\"\non w receive m [ total = m + 1 ]\ntotal = 0", {.Kind_Conflict})
}

@(test)
test_a_record_that_is_sent_reaches_the_handler_with_its_shape :: proc(t: ^testing.T) {
	expect_errors(t, "w = window size 400 300\nsend w { wind: 0.7 }\non w receive m [ speed = m.wind ]\nspeed = 0", {})
	expect_errors(t, "w = window size 400 300\nsend w { wind: 0.7 }\non w receive m [ speed = m.gust ]\nspeed = 0", {.Unknown_Field})
}

@(test)
test_different_kinds_sent_to_one_window_make_a_mixed_message :: proc(t: ^testing.T) {
	expect_errors(t, "w = window size 400 300\nsend w 1\nsend w \"calm\"\non w receive m [ x = m ]\nx = 0", {})
	expect_errors(t, "w = window size 400 300\nsend w [ \"palette\" 2 ]\non w receive m [ x = item 1 of m ]\nx = 0", {})
}

@(test)
test_two_windows_have_their_own_message_types :: proc(t: ^testing.T) {
	expect_errors(t, "a = window size 100 100\nb = window size 100 100\nsend a 1\nsend b \"x\"\non a receive m [ n = m + 1 ]\non b receive m [ s = m + \"!\" ]\nn = 0\ns = \"\"", {})
	expect_errors(t, "a = window size 100 100\nb = window size 100 100\nsend a 1\nsend b \"x\"\non b receive m [ n = m + 1 ]\nn = 0", {.Kind_Conflict})
}

@(test)
test_a_send_to_something_that_is_not_a_window_is_an_error :: proc(t: ^testing.T) {
	expect_errors(t, "send nowhere 5", {.Unknown_Name})
	expect_errors(t, "x = 3\nsend x 5", {.Wrong_Argument_Kind})
	expect_errors(t, "w = window size 100 100\nsend w", {.Wrong_Argument_Count})
}

@(test)
test_a_send_to_a_window_in_a_list_reaches_every_handler :: proc(t: ^testing.T) {
	expect_errors(t, "w = window size 100 100\nv = window size 100 100\nsend (pick [ v w ]) 5\non w receive m [ n = m + 1 ]\nn = 0", {})
}

// ---- hints (step 3c) ----

@(test)
test_changing_a_shared_list_or_record_gets_a_hint :: proc(t: ^testing.T) {
	got := check_text("ball = { x: 1 }\nother = ball\nother.x = 5")
	if testing.expect_value(t, len(got.checked.diagnostics), 1) {
		d := got.checked.diagnostics[0]
		testing.expect_value(t, d.id, Message_Id.Shared_Change)
		testing.expect_value(t, d.args[0], "other")
		testing.expect_value(t, d.args[1], "ball")
		testing.expect_value(t, d.args[3], "other = copy ball")
		testing.expect(t, !has_errors(got.checked.diagnostics), "a hint does not stop a sketch")
	}
	// Through the other name too, and for a list changed with `add`.
	expect_errors(t, "ball = { x: 1 }\nother = ball\nball.x = 5", {.Shared_Change})
	expect_errors(t, "xs = [ 1 ]\nys = xs\nadd 2 to ys", {.Shared_Change})
}

@(test)
test_a_plain_assignment_that_is_never_changed_or_is_copied_stays_quiet :: proc(t: ^testing.T) {
	expect_errors(t, "ball = { x: 1 }\nother = ball\ny = other.x", {})
	expect_errors(t, "ball = { x: 1 }\nother = copy ball\nother.x = 5", {})
	expect_errors(t, "a = 1\nb = a\nb = 5", {})
	// Numbers are copied, so changing one does not change the other.
	expect_errors(t, "v = { 1, 2 }\nw = v\nw.x = 5", {})
}

@(test)
test_a_name_that_hides_a_top_level_name_gets_a_warning :: proc(t: ^testing.T) {
	got := check_text("size = 10\nlearn star size [ circle at 1 2 radius size ]\nstar 5")
	if testing.expect_value(t, len(got.checked.diagnostics), 1) {
		d := got.checked.diagnostics[0]
		testing.expect_value(t, d.id, Message_Id.Name_Hides)
		testing.expect_value(t, d.args[3], "learn star size2 [ circle at 1 2 radius size ]")
		testing.expect(t, !has_errors(got.checked.diagnostics))
	}
	expect_errors(t, "i = 3\nfor i from 1 to 3 [ ]", {.Name_Hides})
	expect_errors(t, "p = 1\nfor each p in [ 1 2 ] [ ]", {.Name_Hides})
	expect_errors(t, "points = 3\nlearn star size with points 5 [ circle at 1 2 radius size ]\nstar 1", {.Name_Hides})
	expect_errors(t, "learn star n [ circle at 1 2 radius n ]\nstar 1", {})
	expect_errors(t, "for i from 1 to 3 [ ]\nfor i from 1 to 3 [ ]", {})
}

// ---- geometry written with labels ----

@(test)
test_a_labelled_call_builds_the_arguments_in_input_order :: proc(t: ^testing.T) {
	got := check_text("circle radius 5 at 1 2")
	call := got.checked.program.stmts[0].kind.(IR_Expr_Stmt).expr.kind.(IR_Call)
	testing.expect_value(t, len(got.checked.diagnostics), 0)
	testing.expect_value(t, call.shape, 0)
	if testing.expect_value(t, len(call.args), 3) {
		testing.expect_value(t, call.args[0].kind.(IR_Number).value, 1)
		testing.expect_value(t, call.args[1].kind.(IR_Number).value, 2)
		testing.expect_value(t, call.args[2].kind.(IR_Number).value, 5)
	}
	vector := check_text("circle at mouse radius 5")
	testing.expect_value(t, vector.checked.program.stmts[0].kind.(IR_Expr_Stmt).expr.kind.(IR_Call).shape, 1)
}

@(test)
test_every_geometry_verb_has_a_labelled_form_that_checks :: proc(t: ^testing.T) {
	expect_errors(t, `
circle at 1 2 radius 3
circle at mouse radius 3
ellipse at 1 2 size 3 4
ellipse at mouse size { 3, 4 }
rect at 1 2 size 3 4
rect at mouse size { 3, 4 } fill red
square at 1 2 size 3
square at mouse size 3
line from 1 2 to 3 4
line from mouse to pmouse
point at 1 2
point at mouse
arc at 1 2 size 3 4 from 5 to 6
triangle { 0, 0 } { 5, 0 } { 2, 4 }
quad { 0, 0 } { 5, 0 } { 5, 5 } { 0, 5 }
w = window size 800 600 at 10 10 title "x"
`, {})
}

@(test)
test_a_positional_geometry_call_says_how_to_write_it_with_labels :: proc(t: ^testing.T) {
	cases := [][2]string{
		{"circle 100 100 50 fill red", "circle at 100 100 radius 50 fill red"},
		{"circle mouse 5", "circle at mouse radius 5"},
		{"rect 1 2 3 4", "rect at 1 2 size 3 4"},
		{"line 0 0 10 10", "line from 0 0 to 10 10"},
		{"point 3 4", "point at 3 4"},
		{"square 1 2 3", "square at 1 2 size 3"},
		{"arc 1 2 3 4 5 6", "arc at 1 2 size 3 4 from 5 to 6"},
		{"w = window 800 600", "w = window size 800 600"},
	}
	for c in cases {
		got := check_text(c[0])
		if testing.expectf(t, len(got.checked.diagnostics) >= 1, "`%s` gave no message", c[0]) {
			d := got.checked.diagnostics[0]
			testing.expectf(t, d.id == .Labels_Needed, "`%s`: %v", c[0], d.id)
			testing.expect_value(t, d.args[3], c[1])
		}
	}
}

@(test)
test_a_missing_or_wrong_label_names_what_is_needed :: proc(t: ^testing.T) {
	expect_errors(t, "circle at 1 2", {.Missing_Required_Word})
	expect_errors(t, "circle radius 3", {.Missing_Required_Word})
	expect_errors(t, "circle", {.Missing_Required_Word})
	expect_errors(t, "rect at 1 2", {.Missing_Required_Word})
	expect_errors(t, "circle at 1 2 radius \"a\"", {.Wrong_Argument_Kind})
	expect_errors(t, "circle at 1 radius 5", {.Wrong_Argument_Kind})
	expect_errors(t, "rect at 1 2 size 3", {.Wrong_Argument_Kind})
	expect_errors(t, "circle at 1 2 radius 3 at 4 5", {.Word_Twice})
	expect_errors(t, "x = circle at 1 2 radius 3", {.Value_Of_Nothing})
	// What else the call says is still read.
	expect_errors(t, "circle at yy 1 radius 2 fill zz", {.Unknown_Name, .Unknown_Name})
	got := check_text("circle at 1 2")
	testing.expect_value(t, got.checked.diagnostics[0].args[3], "circle at 1 2 radius 0")
	bare := check_text("circle")
	testing.expect_value(t, bare.checked.diagnostics[0].args[3], "circle at 0 0 radius 0")
}

@(test)
test_a_triangle_or_quad_is_written_with_vectors_only :: proc(t: ^testing.T) {
	got := check_text("quad 0 0 5 0 5 5 0 5")
	if testing.expect(t, len(got.checked.diagnostics) > 0) {
		d := got.checked.diagnostics[0]
		testing.expect_value(t, d.id, Message_Id.Wrong_Argument_Kind)
		testing.expect_value(t, d.args[3], "quad { 0, 0 } { 5, 0 } { 5, 5 } { 0, 5 }")
	}
	expect_errors(t, "triangle 0 0 5 0 2 4", {.Wrong_Argument_Kind})
}

@(test)
test_a_window_takes_its_title_in_the_call_and_a_verb_names_the_window_later :: proc(t: ^testing.T) {
	expect_types(t, "w = window size 800 600 title \"garden\"\ntitle w \"new\"\ntitle \"current\"", "w: a window")
	expect_errors(t, "title 5 \"x\"", {.Wrong_Argument_Kind})
	expect_errors(t, "window size 800 600 title 5", {.Wrong_Argument_Kind})
}

@(test)
test_commas_between_the_values_of_a_label_are_one_error_with_the_fix :: proc(t: ^testing.T) {
	got := check_text("circle at 100, 100 radius 50")
	d := got.checked.diagnostics[0]
	testing.expect_value(t, d.id, Message_Id.Comma_In_Call)
	testing.expect_value(t, d.args[1], "circle at 100 100 radius 50")
}

@(test)
test_the_call_parentheses_example_uses_labels_for_geometry :: proc(t: ^testing.T) {
	got := check_text("circle(100, 100, 50)")
	testing.expect_value(t, got.checked.diagnostics[0].id, Message_Id.Call_Parentheses)
	testing.expect_value(t, got.checked.diagnostics[0].args[0], "circle at 100 100 radius 50")
}

@(test)
test_an_event_can_name_its_window_first :: proc(t: ^testing.T) {
	expect_errors(t, "w = window size 400 300\non w key \"a\" [ circle at mouse radius 5 ]\non w mouse down [ ]", {})
	expect_errors(t, "x = 3\non x mouse down [ ]", {.Wrong_Kind_Here})
	expect_errors(t, "w = window size 400 300\non w key 5 [ ]", {.Wrong_Kind_Here})
	expect_errors(t, "w = window size 400 300\non w nothing [ ]", {.Unknown_Event})
}

@(test)
test_a_field_that_starts_from_its_own_zero_has_a_kind :: proc(t: ^testing.T) {
	expect_types(t, "ball = { a: 7 }\ndraw [\n  ball.b = ball.b + 2\n  print ball.b\n]", "ball: a record with a and b")
}

@(test)
test_random_given_a_list_suggests_pick_built_from_the_line :: proc(t: ^testing.T) {
	parsed := check_text("colors = [ red teal ]\nbackground (random colors)\n")
	found := false
	for d in parsed.checked.diagnostics {
		if d.id == .Wrong_Argument_Kind {
			found = true
			testing.expect_value(t, d.args[3], "background (pick colors)")
		}
	}
	testing.expect(t, found)
}

@(test)
test_a_window_has_properties_that_can_be_read :: proc(t: ^testing.T) {
	expect_types(t, "w = window size 800 600\nsize_now = w.width + w.height\nname = w.title\nplace = w.at\nm = w.mouse\nfull = w.fullscreen", "w: a window\nsize_now: a number\nname: text\nplace: a vector of 2 numbers\nm: a vector of 2 numbers\nfull: true or false")
	expect_errors(t, "w = window size 800 600\ncircle at w.mouse radius w.width", {})
}

@(test)
test_a_property_a_window_does_not_have_names_the_ones_it_has :: proc(t: ^testing.T) {
	expect_errors(t, "w = window size 800 600\nx = w.widht", {.Bad_Field})
	parsed := check_text("w = window size 800 600\nx = w.widht\n")
	for d in parsed.checked.diagnostics {
		if d.id == .Bad_Field {
			testing.expect(t, strings.contains(d.args[2], "width, height, title, at, mouse, fullscreen and resizable"))
			testing.expect_value(t, d.args[3], "x = w.width")
		}
	}
}

@(test)
test_a_windows_properties_cannot_be_assigned :: proc(t: ^testing.T) {
	expect_errors(t, "w = window size 800 600\nw.width = 100", {.Bad_Field})
}

@(test)
test_shuffle_gives_a_list_of_the_same_kind_and_needs_a_list :: proc(t: ^testing.T) {
	expect_types(t, "xs = [ red teal ]\nys = shuffle xs", "xs: a list of colours\nys: a list of colours")
	expect_errors(t, "x = shuffle 3", {.Wrong_Argument_Kind})
}

@(test)
test_a_window_can_be_made_fixed_and_asked_whether_it_is :: proc(t: ^testing.T) {
	expect_errors(t, "w = window size 300 200 resizable false\nr = w.resizable\nresizable w true\nif r [ quit ]", {})
	expect_errors(t, "w = window size 300 200 resizable 3", {.Wrong_Argument_Kind})
	expect_errors(t, "w = window size 300 200\nresizable w 3", {.Wrong_Argument_Kind})
	expect_types(t, "w = window size 300 200 resizable false\nr = w.resizable", "w: a window\nr: true or false")
}
