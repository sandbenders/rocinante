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
	expect_types(t, "circle 100 100 50", "")
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
	expect_errors(t, "draw [ circle x 100 50 ]\nx = 10", {})
	expect_errors(t, "on key \"a\" [ y = x ]\nx = 1\ny = 2", {})
	expect_errors(t, "every 1 second [ circle x 1 2 ]\nx = 1", {})
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
	far := check_text("circle zzz 100 50")
	testing.expect_value(t, far.checked.diagnostics[0].args[3], "zzz = 0\ncircle zzz 100 50")
}

@(test)
test_colour_names_and_built_in_values_are_names :: proc(t: ^testing.T) {
	expect_errors(t, "fill red\ncircle mouse.x mouse.y 5\nx = pi + tau + fps + frame + time + width + height\nk = key\nflag = true", {})
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
	// `size` is both a value and a connecting word and stays free (section 5.15).
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
	expect_errors(t, "circle yy 1 2 fill zz", {.Unknown_Name, .Unknown_Name})
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
	expect_errors(t, "for i from 1 to 3 [ circle i i 5 ]", {})
	expect_errors(t, "for i from 1 to 3 [ ]\ncircle i 1 2", {.Unknown_Name})
	// The same name may be used again by another loop.
	expect_errors(t, "for i from 1 to 3 [ ]\nfor i from 1 to 3 [ circle i 1 2 ]", {})
}

@(test)
test_for_each_gives_its_name_the_type_of_the_items :: proc(t: ^testing.T) {
	expect_errors(t, "ps = [ { 1, 2 } { 3, 4 } ]\nfor each p in ps [ circle p 5 ]", {})
	expect_errors(t, "ps = [ { 1, 2 } { 3, 4 } ]\nfor each p in ps [ circle p \"a\" ]", {.Wrong_Argument_Kind})
	expect_errors(t, "for each p in 5 [ ]", {.Wrong_Kind_Here})
}

@(test)
test_draw_every_and_on_blocks_are_checked :: proc(t: ^testing.T) {
	expect_errors(t, "draw [ background 0\n  circle mouse 20 ]", {})
	expect_errors(t, "draw 3 [ ]", {.Wrong_Kind_Here})
	expect_errors(t, "w = window 400 300\ndraw w [ ]\non w receive m [ x = m ]\nx = 1", {})
	expect_errors(t, "on key 5 [ ]", {.Wrong_Kind_Here})
	expect_errors(t, "on mouse down [ circle mouse 5 ]", {})
	expect_errors(t, "x = 3\non x receive m [ ]", {.Wrong_Kind_Here})
}

@(test)
test_with_checks_its_style_words :: proc(t: ^testing.T) {
	expect_errors(t, "with fill cyan thickness 2 [ circle 1 2 3 ]", {})
	expect_errors(t, "with fill \"a\" [ ]", {.Wrong_Argument_Kind})
	expect_errors(t, "glow = { fill: cyan }\nwith glow [ ]", {})
}

// ---- calls ----

@(test)
test_a_verb_group_picks_its_shape_by_count_then_kinds :: proc(t: ^testing.T) {
	expect_errors(t, "circle 1 2 3\ncircle mouse 5\nx = mix 1 2 0.5\nc = mix red blue 0.5", {})
	expect_types(t, "x = mix 1 2 0.5\nc = mix red blue 0.5", "x: a number\nc: a colour")
}

@(test)
test_the_wrong_number_of_arguments_names_what_the_verb_takes :: proc(t: ^testing.T) {
	got := check_text("circle 100")
	d := got.checked.diagnostics[0]
	testing.expect_value(t, d.id, Message_Id.Wrong_Argument_Count)
	testing.expect_value(t, d.args[1], "3 values (x, y and radius) or 2 values (position and radius)")
	testing.expect_value(t, d.args[2], "1 value")
	testing.expect_value(t, d.args[3], "circle 100 radius")
	expect_errors(t, "background", {.Wrong_Argument_Count})
	expect_errors(t, "x = random", {.Missing_Required_Word, .Missing_Required_Word})
}

@(test)
test_the_wrong_kind_of_argument_names_the_parameter :: proc(t: ^testing.T) {
	got := check_text("circle 100 \"two\" 50")
	d := got.checked.diagnostics[0]
	testing.expect_value(t, d.id, Message_Id.Wrong_Argument_Kind)
	testing.expect_value(t, d.args[1], "a number for `y`")
	testing.expect_value(t, d.args[2], "text")
	testing.expect_value(t, d.args[3], "circle 100 0 50")
	// A grey number, a gradient list and a colour all fit a colour parameter.
	expect_errors(t, "fill 128\nfill [ red teal ]\nfill red\nbackground (gradient [ red teal ])", {})
	expect_errors(t, "fill \"red\"", {.Wrong_Argument_Kind})
}

@(test)
test_a_call_that_gives_nothing_cannot_be_a_value :: proc(t: ^testing.T) {
	expect_errors(t, "x = clear", {.Value_Of_Nothing})
	expect_errors(t, "x = circle 1 2 3", {.Value_Of_Nothing})
	expect_errors(t, "circle (clear) 2 3", {.Value_Of_Nothing})
}

@(test)
test_connecting_words_are_checked_for_kind_repeats_and_required_ones :: proc(t: ^testing.T) {
	expect_errors(t, "window 800 600 at 100 100", {})
	expect_errors(t, "window 800 600 at \"a\" 100", {.Wrong_Argument_Kind})
	expect_errors(t, "circle 1 2 3 fill red fill blue", {.Word_Twice})
	expect_errors(t, "x = random from 1", {.Missing_Required_Word})
	expect_errors(t, "x = random from 1 to 3", {})
	expect_errors(t, "circle 1 2 3 as center fill red", {})
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
	expect_types(t, "w = window 800 600", "w: a window")
}

@(test)
test_a_verb_taught_with_learn_is_not_checked_yet_but_its_calls_are_counted :: proc(t: ^testing.T) {
	expect_errors(t, "learn star size [ circle 1 2 size ]\nstar 100", {})
	expect_errors(t, "learn star size [ ]\nstar 100 200", {.Unexpected_Token})
	got := check_text("learn star size [ ]\nstar")
	testing.expect_value(t, got.checked.diagnostics[0].id, Message_Id.Wrong_Argument_Count)
	testing.expect_value(t, got.checked.diagnostics[0].args[3], "star size")
}

// ---- parse errors do not cascade ----

@(test)
test_a_sketch_with_parse_errors_is_still_checked_without_extra_noise :: proc(t: ^testing.T) {
	expect_errors(t, "circel 1 2 3\ncircle 4 5 6", {.Unknown_Word})
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
	got := check_text("circle mouse 5")
	call := got.checked.program.stmts[0].kind.(IR_Expr_Stmt).expr.kind.(IR_Call)
	testing.expect_value(t, call.shape, 1)
	testing.expect_value(t, call.verb.name, "circle")
	testing.expect_value(t, len(call.args), 2)
}

@(test)
test_checking_the_same_sketch_twice_gives_the_same_answer :: proc(t: ^testing.T) {
	text := "x = 10\ndraw [ circle x x 5 ]\nfor i from 1 to 3 [ x = x + i ]\n"
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
