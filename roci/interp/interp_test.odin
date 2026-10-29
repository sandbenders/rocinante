// SPDX-License-Identifier: 0BSD
//
// Tests of the interpreter, run headless: a sketch is read, checked and run with
// no window, then its printed output and the commands it recorded are looked at.
// Every test starts its own sketch (the sketch state is thread-local, so tests that
// run in parallel never meet).
package interp

import "../"
import "../gfx"
import "../folder"
import "../lang"
import "../platform"
import "../registry"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"
import sdl "vendor:sdl3"

// Runs `text` for `frames` frames. The caller frees it with `finish`.
run_text :: proc(t: ^testing.T, text: string, frames := 0, loc := #caller_location) -> ^Interp {
	roci.start_headless(1)
	p, ok := load("test.roci", text)
	if !ok {
		testing.expectf(t, false, "the sketch has errors:\n%s", lang.render_all(p.src, p.checked.diagnostics, context.temp_allocator), loc = loc)
		return p
	}
	start(p)
	for _ in 0 ..< frames {
		roci.step()
	}
	return p
}

finish :: proc(p: ^Interp) {
	destroy(p)
	roci.shutdown()
}

// Everything the sketch printed, one line each.
printed :: proc(p: ^Interp) -> string {
	return strings.join(p.printed[:], "\n", context.temp_allocator)
}

expect_printed :: proc(t: ^testing.T, text: string, want: string, frames := 0, loc := #caller_location) {
	p := run_text(t, text, frames, loc)
	defer finish(p)
	testing.expect_value(t, printed(p), want, loc = loc)
}

first_window :: proc() -> roci.Window {
	return roci.open_windows()[0]
}

// ---- the smallest programs ----

@(test)
test_the_smallest_program_draws_one_circle :: proc(t: ^testing.T) {
	p := run_text(t, "circle at 100 100 radius 50")
	defer finish(p)
	commands := roci.recorded(first_window())
	testing.expect_value(t, len(commands), 1)
	testing.expect_value(t, commands[0].kind, gfx.Kind.Circle)
	testing.expect_value(t, [3]f32{commands[0].args[0], commands[0].args[1], commands[0].args[2]}, [3]f32{100, 100, 50})
}

@(test)
test_a_sketch_with_check_errors_does_not_run :: proc(t: ^testing.T) {
	roci.start_headless(1)
	p, ok := load("test.roci", "circel at 1 1 radius 5")
	defer finish(p)
	testing.expect(t, !ok)
	start(p)
	testing.expect_value(t, len(roci.open_windows()), 0)
}

@(test)
test_a_draw_block_runs_every_frame :: proc(t: ^testing.T) {
	p := run_text(t, "n = 0\ndraw [\n  n = n + 1\n  print n\n]", 3)
	defer finish(p)
	testing.expect_value(t, printed(p), "1\n2\n3")
}

@(test)
test_drawing_in_a_draw_block_starts_each_frame_empty :: proc(t: ^testing.T) {
	p := run_text(t, "draw [\n  circle at 10 10 radius 5\n]", 4)
	defer finish(p)
	testing.expect_value(t, len(roci.recorded(first_window())), 1)
}

// ---- numbers, text and operators ----

@(test)
test_arithmetic_follows_the_usual_order :: proc(t: ^testing.T) {
	expect_printed(t, "print (2 + 3 * 4)\nprint ((2 + 3) * 4)\nprint (10 - 4 - 3)\nprint (7 / 2)\nprint (7 % 3)\nprint (-7 % 3)", "14\n20\n3\n3.5\n1\n2")
}

@(test)
test_comparisons_and_logic :: proc(t: ^testing.T) {
	expect_printed(t, "print (1 < 2)\nprint (2 <= 1)\nprint (3 is 3)\nprint (3 is not 3)\nprint (true and false)\nprint (true or false)\nprint (not true)", "true\nfalse\ntrue\nfalse\nfalse\ntrue\nfalse")
}

@(test)
test_and_and_or_leave_the_right_side_alone_when_the_left_decides :: proc(t: ^testing.T) {
	expect_printed(t, "n = 0\nlearn bump [\n  n = n + 1\n  give true\n]\nok = false and bump\nok = true or bump\nprint n", "0")
}

@(test)
test_text_joins_with_plus_and_shows_numbers_plainly :: proc(t: ^testing.T) {
	expect_printed(t, "print (\"fps: \" + 60)\nprint (1.5 + \" cats\")\nprint (\"a\" + \"b\")", "fps: 60\n1.5 cats\nab")
}

@(test)
test_vectors_do_array_arithmetic_and_swizzles :: proc(t: ^testing.T) {
	text := "v = { 1, 2 }\nprint (v + { 10, 20 })\nprint (v * 3)\nprint (2 * v)\nprint v.x\nprint v.yx\nw = { 1, 2, 3 }\nprint w.zy"
	expect_printed(t, text, "{ 11, 22 }\n{ 3, 6 }\n{ 2, 4 }\n1\n{ 2, 1 }\n{ 3, 2 }")
}

@(test)
test_colours_do_arithmetic_and_keep_to_0_through_255 :: proc(t: ^testing.T) {
	text := "c = rgb 100 200 250\nd = c * 2\nprint d.r\nprint d.g\nprint d.b\nprint c.a"
	expect_printed(t, text, "200\n255\n255\n100")
}

@(test)
test_a_part_of_a_vector_can_be_set :: proc(t: ^testing.T) {
	expect_printed(t, "v = { 1, 2 }\nv.x = 9\nprint v\nv.yx = { 5, 6 }\nprint v", "{ 9, 2 }\n{ 6, 5 }")
}

@(test)
test_dividing_by_zero_gives_0_and_a_runtime_error_and_the_sketch_goes_on :: proc(t: ^testing.T) {
	p := run_text(t, "x = 0\nprint (5 / x)\nprint (5 % x)\nprint 1")
	defer finish(p)
	testing.expect_value(t, printed(p), "0\n0\n1")
	testing.expect_value(t, len(p.errors), 2)
	testing.expect_value(t, p.errors[0].id, lang.Message_Id.Division_By_Zero)
}

@(test)
test_built_in_values :: proc(t: ^testing.T) {
	expect_printed(t, "print width\nprint height\nprint (pi > 3.14)\nprint (tau > 6.28)\nprint frame", "800\n600\ntrue\ntrue\n0")
}

// ---- statements ----

@(test)
test_if_and_else :: proc(t: ^testing.T) {
	expect_printed(t, "if 1 < 2 [ print \"yes\" ] else [ print \"no\" ]\nif 2 < 1 [ print \"yes\" ] else [ print \"no\" ]\nif 2 < 1 [ print \"never\" ]", "yes\nno")
}

@(test)
test_repeat_counts_and_ignores_a_count_below_one :: proc(t: ^testing.T) {
	expect_printed(t, "n = 0\nrepeat 3 [ n = n + 1 ]\nrepeat 0 [ n = n + 100 ]\nrepeat -2 [ n = n + 100 ]\nrepeat 2.9 [ n = n + 10 ]\nprint n", "23")
}

@(test)
test_for_counts_up_down_and_by_a_step :: proc(t: ^testing.T) {
	text := "for i from 1 to 3 [ print i ]\nfor i from 3 to 1 [ print i ]\nfor i from 0 to 1 by 0.25 [ print i ]\nfor i from 1 to 0 by 1 [ print i ]"
	expect_printed(t, text, "1\n2\n3\n3\n2\n1\n0\n0.25\n0.5\n0.75\n1")
}

@(test)
test_while_loops_until_its_condition_is_false :: proc(t: ^testing.T) {
	expect_printed(t, "n = 1\nwhile n < 100 [ n = n * 2 ]\nprint n", "128")
}

@(test)
test_for_each_walks_a_list_and_changes_records_in_it :: proc(t: ^testing.T) {
	text := "ps = [ { x: 1 } { x: 2 } ]\nfor each p in ps [ p.x = p.x * 10 ]\nfor each p in ps [ print p.x ]"
	expect_printed(t, text, "10\n20")
}

@(test)
test_for_each_writes_a_changed_vector_back_to_the_list :: proc(t: ^testing.T) {
	text := "vs = [ { 1, 2 } { 3, 4 } ]\nfor each v in vs [ v.x = 0 ]\nprint vs"
	expect_printed(t, text, "[ { 0, 2 } { 0, 4 } ]")
}

@(test)
test_with_styles_a_block_and_puts_the_style_back :: proc(t: ^testing.T) {
	p := run_text(t, "with fill red thickness 4 [\n  circle at 10 10 radius 5\n]\ncircle at 20 20 radius 5")
	defer finish(p)
	commands := roci.recorded(first_window())
	testing.expect_value(t, len(commands), 2)
	testing.expect_value(t, commands[0].style.fill, [4]f32{255, 0, 0, 255})
	testing.expect(t, commands[1].style.fill != commands[0].style.fill)
}

@(test)
test_push_puts_the_transform_back :: proc(t: ^testing.T) {
	p := run_text(t, "push [\n  move 100 0\n  circle at 0 0 radius 5\n]\ncircle at 0 0 radius 5")
	defer finish(p)
	commands := roci.recorded(first_window())
	testing.expect(t, commands[0].transform != commands[1].transform)
}

// ---- taught verbs ----

@(test)
test_a_taught_verb_gives_a_value :: proc(t: ^testing.T) {
	expect_printed(t, "learn double n [ give n * 2 ]\nprint (double 21)\nprint (double (double 1))", "42\n4")
}

@(test)
test_stop_ends_a_verb_early_and_give_ends_it_from_inside_a_loop :: proc(t: ^testing.T) {
	text := "learn first_big list [\n  for each x in list [\n    if x > 10 [ give x ]\n  ]\n  give 0\n]\nlearn greet name [\n  if name is \"\" [ stop ]\n  print (\"hi \" + name)\n]\nprint (first_big [ 1 20 30 ])\nprint (first_big [ 1 2 ])\ngreet \"\"\ngreet \"ada\""
	expect_printed(t, text, "20\n0\nhi ada")
}

@(test)
test_optional_words_take_their_defaults_and_can_be_given :: proc(t: ^testing.T) {
	text := "learn show n with times 2 [ print (n * times) ]\nshow 5\nshow 5 times 3"
	expect_printed(t, text, "10\n15")
}

@(test)
test_verbs_can_call_themselves :: proc(t: ^testing.T) {
	text := "learn factorial n [\n  if n <= 1 [ give 1 ]\n  give n * (factorial (n - 1))\n]\nprint (factorial 5)"
	expect_printed(t, text, "120")
}

@(test)
test_a_verb_never_ending_in_calls_is_stopped_and_the_sketch_goes_on :: proc(t: ^testing.T) {
	p := run_text(t, "learn forever n [ give 1 + (forever (n + 1)) ]\nprint (forever 1)\nprint \"after\"")
	defer finish(p)
	testing.expect_value(t, printed(p), "100\nafter")
	testing.expect_value(t, len(p.errors), 1)
	testing.expect_value(t, p.errors[0].id, lang.Message_Id.Recursion_Too_Deep)
}

@(test)
test_a_name_made_inside_a_verb_is_its_own :: proc(t: ^testing.T) {
	text := "learn work n [\n  inner = n + 1\n  give inner\n]\nprint (work 1)\nprint (work 5)"
	expect_printed(t, text, "2\n6")
}

@(test)
test_a_verb_changes_the_callers_record :: proc(t: ^testing.T) {
	text := "learn step p [ p.pos = p.pos + p.vel ]\nball = { pos: { 0, 0 }, vel: { 1, 2 } }\nstep ball\nstep ball\nprint ball.pos"
	expect_printed(t, text, "{ 2, 4 }")
}

@(test)
test_one_verb_works_for_records_of_different_shapes :: proc(t: ^testing.T) {
	text := "learn nudge p [ p.x = p.x + 1 ]\na = { x: 1, y: 5 }\nb = { x: 10, name: \"b\" }\nnudge a\nnudge b\nprint a.x\nprint b.x"
	expect_printed(t, text, "2\n11")
}

// ---- lists and records ----

@(test)
test_add_remove_count_and_item :: proc(t: ^testing.T) {
	text := "l = [ 1 2 3 ]\nadd 4 to l\nremove 2 from l\nprint l\nprint (count l)\nprint (item 2 of l)"
	expect_printed(t, text, "[ 1 3 4 ]\n3\n3")
}

@(test)
test_remove_takes_the_very_item_before_an_equal_one :: proc(t: ^testing.T) {
	text := "a = { v: 1 }\nb = { v: 1 }\nl = [ a b ]\nremove b from l\nb.v = 7\nprint a.v\nprint (count l)"
	expect_printed(t, text, "1\n1")
}

@(test)
test_records_and_lists_are_shared_and_copy_makes_one_of_its_own :: proc(t: ^testing.T) {
	text := "a = [ 1 2 ]\nb = a\nadd 3 to b\nprint (count a)\nc = copy a\nadd 4 to c\nprint (count a)\nprint (count c)"
	expect_printed(t, text, "3\n3\n4")
}

@(test)
test_a_record_field_never_set_reads_as_zero :: proc(t: ^testing.T) {
	text := "p = { a: 1 }\nif p.a > 5 [ p.b = \"x\" ]\nprint p.a\nprint (p.b + \"|\")"
	expect_printed(t, text, "1\n|")
}

@(test)
test_a_record_in_a_record_changes_through_the_path :: proc(t: ^testing.T) {
	text := "ball = { pos: { 1, 2 }, tag: { n: 1 } }\nball.pos.x = 9\nball.tag.n = 5\nprint ball.pos\nprint ball.tag.n"
	expect_printed(t, text, "{ 9, 2 }\n5")
}

@(test)
test_keep_skip_collect_find_and_combine :: proc(t: ^testing.T) {
	text := "xs = [ 1 2 3 4 5 ]\nprint (keep xs [ it > 2 ])\nprint (skip xs [ it > 2 ])\nprint (collect xs [ it * it ])\nprint (find xs [ it > 3 ])\nprint (combine xs from 0 [ result + it ])\nprint (combine xs from 1 [ result * it ])"
	expect_printed(t, text, "[ 3 4 5 ]\n[ 1 2 ]\n[ 1 4 9 16 25 ]\n4\n15\n120")
}

@(test)
test_sort_orders_by_the_block_and_leaves_the_original_alone :: proc(t: ^testing.T) {
	text := "xs = [ { n: 3 } { n: 1 } { n: 2 } ]\nsorted = sort xs by [ it.n ]\nfor each s in sorted [ print s.n ]\nfor each x in xs [ print x.n ]"
	expect_printed(t, text, "1\n2\n3\n3\n1\n2")
}

@(test)
test_find_with_no_match_gives_an_empty_value :: proc(t: ^testing.T) {
	expect_printed(t, "found = find [ 1 2 3 ] [ it > 5 ]\nprint (found is 0)", "false")
}

@(test)
test_sort_by_text_and_a_list_that_is_a_block_of_a_list_verb_in_a_list_verb :: proc(t: ^testing.T) {
	text := "names = [ \"bo\" \"al\" \"cy\" ]\nprint (sort names by [ it ])\nbig = keep [ 1 2 3 ] [ it > (count (keep [ 5 6 ] [ it > 5 ])) ]\nprint big"
	expect_printed(t, text, "[ al bo cy ]\n[ 2 3 ]")
}

@(test)
test_an_item_that_is_not_there_is_empty_and_says_so_once :: proc(t: ^testing.T) {
	p := run_text(t, "l = [ 1 2 ]\nrepeat 3 [ print (item 5 of l) ]\nprint (item 0 of l)")
	defer finish(p)
	testing.expect_value(t, printed(p), "0\n0\n0\n0")
	testing.expect_value(t, len(p.errors), 2)
	testing.expect_value(t, p.errors[0].id, lang.Message_Id.Index_Out_Of_Range)
}

@(test)
test_a_list_made_in_a_frame_is_kept_when_stored_in_the_sketch :: proc(t: ^testing.T) {
	text := "flowers = []\ndraw [\n  add { n: frame } to flowers\n  stash = collect flowers [ it.n ]\n]\non mouse down [ ]\n"
	p := run_text(t, text, 5)
	defer finish(p)
	list := as_list(p.globals[p.checked.program.symbols[0]])
	testing.expect(t, list != nil)
	testing.expect_value(t, len(list.items), 5)
	testing.expect(t, as_record(list.items[4]).long)
}

// ---- drawing through the verbs ----

@(test)
test_a_labelled_shape_draws_what_the_odin_call_draws :: proc(t: ^testing.T) {
	p := run_text(t, "rect at 10 20 size 30 40 fill red\nellipse at { 1, 2 } size { 3, 4 }\nline from 0 0 to 5 5\npoint at 1 2\nsquare at 5 5 size 9\ntriangle { 0, 0 } { 5, 0 } { 0, 5 }\nquad { 0, 0 } { 5, 0 } { 5, 5 } { 0, 5 }\narc at 50 50 size 20 20 from 0 to 90")
	defer finish(p)
	commands := roci.recorded(first_window())
	kinds := make([dynamic]gfx.Kind, context.temp_allocator)
	for c in commands {
		append(&kinds, c.kind)
	}
	testing.expect_value(t, len(commands), 8)
	testing.expect_value(t, kinds[0], gfx.Kind.Rect)
	testing.expect_value(t, kinds[1], gfx.Kind.Ellipse)
	testing.expect_value(t, kinds[2], gfx.Kind.Line)
	testing.expect_value(t, kinds[3], gfx.Kind.Point)
	testing.expect_value(t, kinds[7], gfx.Kind.Arc)
	testing.expect_value(t, [4]f32{commands[0].args[0], commands[0].args[1], commands[0].args[2], commands[0].args[3]}, [4]f32{10, 20, 30, 40})
}

@(test)
test_style_verbs_set_the_style_for_what_follows :: proc(t: ^testing.T) {
	p := run_text(t, "fill orange\nstroke white\nthickness 3\ncircle at 1 1 radius 1\nno fill\nno stroke\ncircle at 2 2 radius 1")
	defer finish(p)
	commands := roci.recorded(first_window())
	testing.expect_value(t, commands[0].style.fill, [4]f32{255, 165, 0, 255})
	testing.expect_value(t, commands[0].style.thickness, f32(3))
	testing.expect(t, !commands[1].style.fill_on)
	testing.expect(t, !commands[1].style.stroke_on)
}

@(test)
test_a_gradient_from_a_list_and_from_the_gradient_verb :: proc(t: ^testing.T) {
	p := run_text(t, "background [ red blue ] angle 90\nfill (gradient [ red blue ] as radial)\ncircle at 1 1 radius 5\nfill [ red teal ]\ncircle at 1 1 radius 5\nfill red angle 3\ncircle at 1 1 radius 5")
	defer finish(p)
	commands := roci.recorded(first_window())
	testing.expect_value(t, len(commands), 3) // the background is not a command of its own
	testing.expect(t, commands[0].style.fill_paint != commands[1].style.fill_paint)
	testing.expect(t, commands[1].style.fill_paint != commands[2].style.fill_paint)
}

@(test)
test_a_named_style_is_a_record_of_style_words :: proc(t: ^testing.T) {
	p := run_text(t, "glow = { fill: cyan, thickness: 6 }\ncircle at 1 1 radius 5 style glow\nwith glow [ circle at 2 2 radius 5 ]")
	defer finish(p)
	commands := roci.recorded(first_window())
	testing.expect_value(t, commands[0].style.thickness, f32(6))
	testing.expect_value(t, commands[1].style.thickness, f32(6))
	testing.expect_value(t, commands[0].style.fill, [4]f32{0, 255, 255, 255})
}

@(test)
test_colour_verbs_and_mix :: proc(t: ^testing.T) {
	text := "c = rgb 10 20 30 alpha 40\nprint c.a\nprint (mix 0 10 0.5)\nm = mix red blue 0\nprint m.r\nh = hsb 0 255 255\nprint h.r"
	expect_printed(t, text, "40\n5\n255\n255")
}

@(test)
test_maths_verbs :: proc(t: ^testing.T) {
	text := "print (map 5 0 10 0 100)\nprint (clamp 15 0 10)\nprint (dist { 0, 0 } { 3, 4 })\nprint (dist 0 0 3 4)\nprint (abs -3)\nprint (sqrt 16)\nprint (sin 90)\nprint (cos 0)"
	expect_printed(t, text, "50\n10\n5\n5\n3\n4\n1\n1")
}

@(test)
test_random_follows_the_seed_and_stays_in_range :: proc(t: ^testing.T) {
	text := "seed 5\na = random 100\nseed 5\nb = random 100\nprint (a is b)\nr = random from 10 to 20\nprint (r >= 10 and r <= 20)\nprint (pick [ 7 7 7 ])\nprint ((noise 1.5) >= 0)"
	expect_printed(t, text, "true\ntrue\n7\ntrue")
}

@(test)
test_windows_open_with_a_size_a_position_and_a_title :: proc(t: ^testing.T) {
	p := run_text(t, "w = window size 320 220 at 60 120 title \"palette\"\ncircle at 10 10 radius 5\nset w title \"renamed\"\nv = window size 200 100\ndraw v [ circle at 1 1 radius 1 ]", 1)
	defer finish(p)
	testing.expect_value(t, len(roci.open_windows()), 2)
	testing.expect_value(t, len(roci.recorded(roci.open_windows()[0])), 1)
	testing.expect_value(t, len(roci.recorded(roci.open_windows()[1])), 1)
}

// ---- runtime failures never stop the sketch ----

@(test)
test_a_block_that_runs_far_too_long_is_stopped_and_the_frame_is_kept :: proc(t: ^testing.T) {
	roci.start_headless(1)
	p, ok := load("test.roci", "circle at 5 5 radius 5\nwhile true [ n = 1 ]\ncircle at 9 9 radius 5")
	defer finish(p)
	testing.expect(t, ok)
	// A short limit for the test: the same check, a smaller budget.
	p.budget = 0.05
	start(p)
	testing.expect_value(t, len(roci.recorded(first_window())), 1)
	testing.expect_value(t, len(p.errors), 1)
	testing.expect_value(t, p.errors[0].id, lang.Message_Id.Runs_Too_Long)
}

@(test)
test_the_report_names_each_runtime_error_in_the_error_format :: proc(t: ^testing.T) {
	p := run_text(t, "x = 0\nprint (5 / x)")
	defer finish(p)
	text := report(p, context.temp_allocator)
	testing.expect(t, strings.contains(text, "divides by zero"))
	testing.expect(t, strings.contains(text, "2 │ print (5 / x)"))
	testing.expect(t, strings.contains(text, "if x is not 0 [ print (5 / x) ]"))
}

@(test)
test_a_name_not_given_a_value_yet_reads_as_the_zero_of_its_kind :: proc(t: ^testing.T) {
	text := "draw [\n  print later\n]\nlater = 5\n"
	expect_printed(t, text, "5", 1)
}

@(test)
test_every_registry_verb_that_is_a_statement_or_a_value_has_a_way_to_run :: proc(t: ^testing.T) {
	// Each core verb is handled by the interpreter or by its language verbs, so a
	// verb added to the registry cannot be silently ignored.
	for verb in registry.ALL_VERBS {
		testing.expectf(t, handled(verb.name), "the interpreter does not run `%s`", verb.name)
	}
}

// ---- the examples ----

example_text :: proc(name: string) -> string {
	data, err := os.read_entire_file(fmt.tprintf("examples/%s/sketch.roci", name), context.temp_allocator)
	if err != nil {
		return ""
	}
	return string(data)
}

@(test)
test_the_circle_example_draws_what_the_odin_example_draws :: proc(t: ^testing.T) {
	p := run_text(t, example_text("circle"), 2)
	defer finish(p)
	commands := roci.recorded(first_window())
	testing.expect_value(t, len(commands), 1)
	testing.expect_value(t, commands[0].kind, gfx.Kind.Circle)
	testing.expect_value(t, [3]f32{commands[0].args[0], commands[0].args[1], commands[0].args[2]}, [3]f32{100, 100, 50})
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_the_garden_example_runs_without_a_runtime_error :: proc(t: ^testing.T) {
	p := run_text(t, example_text("garden"), 30)
	defer finish(p)
	windows := roci.open_windows()
	testing.expect_value(t, len(windows), 2)
	testing.expect_value(t, len(p.errors), 0)
	testing.expect(t, len(roci.recorded(windows[0])) >= 5)  // the palette: three swatches, a bar, a knob
	testing.expect(t, len(roci.recorded(windows[1])) > 300) // stars, moon, grass, flowers, firefly
}

@(test)
test_the_two_windows_example_runs_without_a_runtime_error :: proc(t: ^testing.T) {
	p := run_text(t, example_text("two_windows"), 10)
	defer finish(p)
	testing.expect_value(t, len(roci.open_windows()), 2)
	testing.expect_value(t, len(p.errors), 0)
}

// ---- the runtime messages ----

RUNTIME_ERRORS_DIR :: "tests/errors/runtime"

// A sketch in tests/errors/runtime/<id>/ must set off that message, and the message
// it renders must be the text beside it (ROCI_UPDATE_ERRORS=1 writes the files again).
@(test)
test_every_runtime_message_has_a_sketch_and_its_text_matches :: proc(t: ^testing.T) {
	update := os.get_env("ROCI_UPDATE_ERRORS", context.temp_allocator) != ""
	for id in lang.Message_Id {
		if !lang.is_runtime(id) {
			continue
		}
		folder := fmt.tprintf("%s/%s", RUNTIME_ERRORS_DIR, strings.to_lower(fmt.tprintf("%v", id), context.temp_allocator))
		entries, read_err := os.read_all_directory_by_path(folder, context.temp_allocator)
		if !testing.expectf(t, read_err == nil, "message %v has no folder %s", id, folder) {
			continue
		}
		found := 0
		for entry in entries {
			if !strings.has_suffix(entry.name, ".roci") {
				continue
			}
			found += 1
			path := fmt.tprintf("%s/%s", folder, strings.trim_suffix(entry.name, ".roci"))
			data, err := os.read_entire_file(fmt.tprintf("%s.roci", path), context.temp_allocator)
			if !testing.expectf(t, err == nil, "cannot read %s.roci", path) {
				continue
			}
			roci.start_headless(1)
			p, ok := load("sketch.roci", string(data))
			testing.expectf(t, ok, "%s.roci has check errors", path)
			p.budget = 0.05 // the same check as a real run, with a smaller budget
			start(p)
			triggered := false
			for e in p.errors {
				triggered ||= e.id == id
			}
			testing.expectf(t, triggered, "%s.roci does not set off %v", path, id)
			got := report(p, context.temp_allocator)
			finish(p)
			txt := fmt.tprintf("%s.txt", path)
			if update {
				testing.expectf(t, os.write_entire_file(txt, transmute([]byte)got) == nil, "cannot write %s", txt)
				continue
			}
			want, want_err := os.read_entire_file(txt, context.temp_allocator)
			if !testing.expectf(t, want_err == nil, "%s is missing: run with ROCI_UPDATE_ERRORS=1 to write it", txt) {
				continue
			}
			testing.expectf(t, string(want) == got, "%s differs.\n--- expected\n%s\n--- got\n%s", txt, string(want), got)
		}
		testing.expectf(t, found > 0, "message %v has no sketch in %s", id, folder)
	}
}

// ---- events, timers and messages ----

key_event :: proc(w: roci.Window, code: sdl.Scancode, down := true) -> platform.Event {
	return platform.Key_Changed{window = platform.Window_Id(w), scancode = code, down = down}
}

click_event :: proc(w: roci.Window, x, y: f32, down := true) -> platform.Event {
	return platform.Mouse_Button_Changed{window = platform.Window_Id(w), button = .Left, down = down, clicks = 1, x = x, y = y}
}

@(test)
test_on_key_runs_for_that_key_only_and_once_a_press :: proc(t: ^testing.T) {
	p := run_text(t, "on key \"a\" [ print \"a\" ]\non key \"b\" [ print \"b\" ]\ncircle at 1 1 radius 1")
	defer finish(p)
	w := first_window()
	roci.step({key_event(w, .A), key_event(w, .C)})
	roci.step({key_event(w, .A, false)})
	roci.step({key_event(w, .B), key_event(w, .A)})
	testing.expect_value(t, printed(p), "a\nb\na")
}

@(test)
test_a_key_repeat_is_not_a_press :: proc(t: ^testing.T) {
	p := run_text(t, "on key \"a\" [ print \"a\" ]\ncircle at 1 1 radius 1")
	defer finish(p)
	roci.step({platform.Key_Changed{window = platform.Window_Id(first_window()), scancode = .A, down = true, repeat = true}})
	testing.expect_value(t, len(p.printed), 0)
}

@(test)
test_an_event_that_names_a_window_runs_only_for_that_window :: proc(t: ^testing.T) {
	text := "a = window size 100 100\nb = window size 100 100\non a mouse down [ print \"a\" ]\non b mouse down [ print \"b\" ]\non mouse down [ print \"any\" ]"
	p := run_text(t, text)
	defer finish(p)
	windows := roci.open_windows()
	roci.step({click_event(windows[1], 5, 5)})
	testing.expect_value(t, printed(p), "b\nany")
}

@(test)
test_the_mouse_in_an_event_is_the_mouse_of_the_window_it_happened_in :: proc(t: ^testing.T) {
	text := "a = window size 100 100\nb = window size 100 100\non b mouse down [ print mouse ]"
	p := run_text(t, text)
	defer finish(p)
	windows := roci.open_windows()
	roci.step({click_event(windows[1], 40, 60)})
	testing.expect_value(t, printed(p), "{ 40, 60 }")
}

@(test)
test_the_key_value_is_the_key_pressed_last :: proc(t: ^testing.T) {
	p := run_text(t, "on key \"x\" [ print key ]\non key \"y\" [ print key ]\ncircle at 1 1 radius 1")
	defer finish(p)
	roci.step({key_event(first_window(), .Y)})
	roci.step({key_event(first_window(), .X)})
	testing.expect_value(t, printed(p), "y\nx")
}

@(test)
test_drawing_in_an_event_lands_in_that_frame_before_the_draw_block :: proc(t: ^testing.T) {
	p := run_text(t, "draw [\n  circle at 2 2 radius 2\n]\non mouse down [ circle at 1 1 radius 1 ]")
	defer finish(p)
	roci.step({click_event(first_window(), 0, 0)})
	commands := roci.recorded(first_window())
	testing.expect_value(t, len(commands), 2)
	testing.expect_value(t, commands[0].args[2], f32(1)) // the event's circle came first
}

@(test)
test_drawing_in_an_event_with_no_draw_block_stays :: proc(t: ^testing.T) {
	p := run_text(t, "on mouse down [ circle at 1 1 radius 1 ]\nbackground 0")
	defer finish(p)
	roci.step({click_event(first_window(), 0, 0)})
	roci.step({click_event(first_window(), 0, 0)})
	roci.step()
	testing.expect_value(t, len(roci.recorded(first_window())), 2)
}

@(test)
test_every_runs_after_its_interval_in_frames_and_in_seconds :: proc(t: ^testing.T) {
	p := run_text(t, "every 3 frames [ print \"f\" ]\nevery 1 second [ print \"s\" ]\ncircle at 1 1 radius 1")
	defer finish(p)
	for _ in 0 ..< 7 {
		roci.step()
	}
	testing.expect_value(t, printed(p), "f\nf")
	for _ in 0 ..< 60 {
		roci.step()
	}
	count := 0
	for line in p.printed {
		if line == "s" {
			count += 1
		}
	}
	testing.expect_value(t, count, 1)
}

@(test)
test_a_message_arrives_on_the_next_frame_in_order_and_is_a_copy :: proc(t: ^testing.T) {
	text := "a = window size 100 100\nb = window size 100 100\nsent = { n: 1 }\ndraw a [\n  if frame is 0 [\n    send b sent\n    send b { n: 2 }\n    sent.n = 9\n  ]\n]\non b receive m [ print m.n ]"
	p := run_text(t, text)
	defer finish(p)
	roci.step()
	testing.expect_value(t, len(p.printed), 0)
	roci.step()
	roci.step()
	testing.expect_value(t, printed(p), "1\n2")
}

@(test)
test_a_message_sent_while_setting_up_arrives_on_the_first_frame :: proc(t: ^testing.T) {
	p := run_text(t, "w = window size 10 10\nsend w 5\non w receive m [ print m ]")
	defer finish(p)
	roci.step()
	testing.expect_value(t, printed(p), "5")
}

@(test)
test_a_receive_handler_can_keep_what_it_hears :: proc(t: ^testing.T) {
	text := "w = window size 10 10\nheard = { n: 0 }\nsend w { n: 7 }\non w receive m [ heard = m ]\nevery 1 frames [ print heard.n ]"
	p := run_text(t, text)
	defer finish(p)
	roci.step()
	roci.step()
	roci.step()
	roci.step()
	testing.expect_value(t, printed(p), "7\n7\n7")
}

@(test)
test_the_two_windows_example_passes_the_mouse_and_a_flash :: proc(t: ^testing.T) {
	p := run_text(t, example_text("two_windows"), 2)
	defer finish(p)
	windows := roci.open_windows()
	roci.step({click_event(windows[0], 30, 20)})
	roci.step()
	testing.expect_value(t, len(p.errors), 0)
	commands := roci.recorded(windows[1])
	testing.expect_value(t, len(commands), 1)
	testing.expect_value(t, [2]f32{commands[0].args[0], commands[0].args[1]}, [2]f32{52, 42}) // the mouse, scaled to the canvas
}

@(test)
test_the_garden_example_reacts_to_keys_and_clicks :: proc(t: ^testing.T) {
	p := run_text(t, example_text("garden"), 3)
	defer finish(p)
	windows := roci.open_windows()
	before := len(roci.recorded(windows[1]))
	roci.step({click_event(windows[1], 300, 520), key_event(windows[0], ._2)})
	roci.step()
	roci.step()
	testing.expect_value(t, len(p.errors), 0)
	testing.expect(t, len(roci.recorded(windows[1])) > before) // a flower was planted
}

// A running app frees the temporary memory after every frame, so nothing the
// sketch keeps may live there: the examples must run the same with it freed.
@(test)
test_the_examples_run_the_same_when_the_temporary_memory_is_freed_each_frame :: proc(t: ^testing.T) {
	for name in ([]string{"garden", "two_windows"}) {
		roci.start_headless(1)
		text := strings.clone(example_text(name), context.temp_allocator)
		p, ok := load("sketch.roci", text)
		testing.expect(t, ok)
		start(p)
		free_all(context.temp_allocator) // the source text goes with it
		for _ in 0 ..< 20 {
			roci.step()
			free_all(context.temp_allocator)
		}
		testing.expectf(t, len(p.errors) == 0, "%s: %s", name, report(p, context.temp_allocator))
		finish(p)
	}
}

// ---- reload, restart and the overlay ----

finish_all :: proc() {
	shutdown()
	roci.shutdown()
}

// Runs a sketch, reloads it with `after`, and gives the interpreter that runs now.
reloaded :: proc(t: ^testing.T, before, after: string, frames := 2, loc := #caller_location) -> (^Interp, Outcome) {
	p := run_text(t, before, frames, loc)
	return reload(p, after)
}

@(test)
test_a_line_that_did_not_change_keeps_its_value_across_a_reload :: proc(t: ^testing.T) {
	n, outcome := reloaded(t, "n = 0\ndraw [\n  n = n + 1\n]", "n = 0\ndraw [\n  n = n + 1\n  print n\n]", 5)
	defer finish_all()
	testing.expect_value(t, outcome, Outcome.Reloaded)
	roci.step()
	testing.expect_value(t, printed(n), "6")
}

@(test)
test_a_changed_line_runs_again_and_a_constant_takes_the_new_text :: proc(t: ^testing.T) {
	n, outcome := reloaded(t, "x = 1\nSPEED = 4\nkept = 10\ndraw [ kept = kept + 1 ]", "x = 2\nSPEED = 8\nkept = 10\ndraw [ kept = kept + 1\n  print (x + SPEED + kept) ]", 3)
	defer finish_all()
	testing.expect_value(t, outcome, Outcome.Reloaded)
	roci.step()
	testing.expect_value(t, printed(n), "24") // x is 2, SPEED 8 and kept went on from 13 to 14
}

@(test)
test_a_record_that_gains_a_field_keeps_its_values :: proc(t: ^testing.T) {
	before := "ball = { a: 7 }\ndraw [ ball.a = ball.a + 1 ]"
	after := "ball = { a: 7 }\ndraw [\n  ball.b = ball.b + 2\n  print ball.a\n  print ball.b\n]"
	n, outcome := reloaded(t, before, after, 3)
	defer finish_all()
	testing.expect_value(t, outcome, Outcome.Reloaded)
	roci.step()
	testing.expect_value(t, printed(n), "10\n2") // a kept at 10, the new field starts at 0
}

@(test)
test_a_record_that_loses_a_field_starts_again_from_its_line :: proc(t: ^testing.T) {
	before := "ball = { a: 7, b: 1 }\ndraw [ ball.a = ball.a + 1 ]"
	after := "ball = { a: 7 }\ndraw [\n  print ball.a\n]"
	n, outcome := reloaded(t, before, after, 3)
	defer finish_all()
	testing.expect_value(t, outcome, Outcome.Reloaded)
	testing.expect(t, strings.contains(n.notices[0], "ball"))
	roci.step()
	testing.expect_value(t, printed(n), "7")
}

@(test)
test_a_name_that_changes_kind_is_not_carried_and_the_reload_says_so :: proc(t: ^testing.T) {
	n, outcome := reloaded(t, "draw [ y = 5 ]", "draw [ y = \"five\" ]\n", 2)
	defer finish_all()
	testing.expect_value(t, outcome, Outcome.Reloaded)
	testing.expect(t, strings.contains(n.notices[0], "lost: y"))
}

@(test)
test_the_reload_says_how_many_values_it_kept :: proc(t: ^testing.T) {
	n, _ := reloaded(t, "a = 1\nb = 2\ndraw [ ]", "a = 1\nb = 2\ndraw [ circle at 1 1 radius 1 ]")
	defer finish_all()
	testing.expect_value(t, n.notices[0], "reloaded: 2 values kept")
}

@(test)
test_text_with_errors_leaves_the_old_sketch_running_under_the_overlay :: proc(t: ^testing.T) {
	p := run_text(t, "n = 0\ndraw [\n  n = n + 1\n  print n\n]", 2)
	same, outcome := reload(p, "n = 0\ndraw [\n  circel at 1 1 radius 5\n]")
	defer finish_all()
	testing.expect_value(t, outcome, Outcome.Failed)
	testing.expect(t, same == p)
	title, lines := roci.overlay_text()
	testing.expect(t, strings.contains(title, "circel"))
	testing.expect(t, len(lines) > 3)
	roci.step()
	testing.expect_value(t, printed(p), "1\n2\n3")
	// Fixing it clears the overlay and carries the value over.
	fixed, ok := reload(p, "n = 0\ndraw [\n  n = n + 1\n  print (n * 10)\n]")
	testing.expect_value(t, ok, Outcome.Reloaded)
	title, _ = roci.overlay_text()
	testing.expect_value(t, title, "")
	roci.step()
	testing.expect_value(t, printed(fixed), "40")
}

@(test)
test_a_runtime_error_is_shown_over_the_sketch_and_the_sketch_goes_on :: proc(t: ^testing.T) {
	p := run_text(t, "zero = 0\ndraw [\n  circle at 5 5 radius (10 / zero)\n  print 1\n]", 3)
	defer finish_all()
	title, _ := roci.overlay_text()
	testing.expect(t, strings.contains(title, "divides by zero"), title)
	testing.expect_value(t, len(p.printed), 3)
}

@(test)
test_a_changed_line_that_opens_a_window_restarts_and_keeps_the_windows_open :: proc(t: ^testing.T) {
	before := "w = window size 200 100\nn = 5\ndraw w [ n = n + 1 ]"
	after := "w = window size 300 120\nn = 5\ndraw w [ n = n + 1\n  print n ]"
	p := run_text(t, before, 3)
	opened := roci.open_windows()
	n, outcome := reload(p, after)
	defer finish_all()
	testing.expect_value(t, outcome, Outcome.Restarted)
	testing.expect_value(t, len(roci.open_windows()), 1)
	testing.expect_value(t, roci.open_windows()[0], opened[0])
	roci.step()
	testing.expect_value(t, printed(n), "6") // started again from its first line
}

@(test)
test_a_changed_line_that_draws_restarts_without_drawing_twice :: proc(t: ^testing.T) {
	p := run_text(t, "circle at 1 1 radius 1\ncircle at 2 2 radius 2")
	n, outcome := reload(p, "circle at 1 1 radius 1\ncircle at 2 2 radius 9")
	defer finish_all()
	testing.expect_value(t, outcome, Outcome.Restarted)
	commands := roci.recorded(first_window())
	testing.expect_value(t, len(commands), 2)
	testing.expect_value(t, commands[1].args[2], f32(9))
	_ = n
}

@(test)
test_unchanged_set_up_lines_are_not_run_again :: proc(t: ^testing.T) {
	p := run_text(t, "circle at 1 1 radius 1\nx = 1")
	_, outcome := reload(p, "circle at 1 1 radius 1\nx = 2")
	defer finish_all()
	testing.expect_value(t, outcome, Outcome.Reloaded)
	testing.expect_value(t, len(roci.recorded(first_window())), 1)
}

@(test)
test_a_forced_restart_runs_everything_from_the_first_line_and_the_windows_stay :: proc(t: ^testing.T) {
	p := run_text(t, "n = 0\ndraw [\n  n = n + 1\n  print n\n]", 3)
	n := restart(p)
	defer finish_all()
	testing.expect(t, n != p)
	roci.step()
	testing.expect_value(t, printed(n), "1")
	testing.expect_value(t, len(roci.open_windows()), 1)
}

@(test)
test_ctrl_r_restarts_the_running_sketch :: proc(t: ^testing.T) {
	p := run_text(t, "n = 0\ndraw [\n  n = n + 1\n  print n\n]", 3)
	defer finish_all()
	roci.step({platform.Key_Changed{window = platform.Window_Id(first_window()), scancode = .R, down = true, mods = {.Ctrl}}})
	running := active()
	testing.expect(t, running != p)
	testing.expect_value(t, printed(running), "1") // the draw block ran once in the restarted sketch
}

@(test)
test_saving_the_watched_file_reloads_the_sketch :: proc(t: ^testing.T) {
	_ = os.make_directory_all("output/tests")
	path := "output/tests/watched_sketch.roci"
	testing.expect(t, os.write_entire_file(path, transmute([]byte)string("n = 0\ndraw [\n  n = n + 1\n]\n")) == nil)
	p, _ := load(path, "n = 0\ndraw [\n  n = n + 1\n]\n")
	roci.start_headless(1)
	watch(p, path)
	start(p)
	defer finish_all()
	roci.step()
	testing.expect(t, poll(p) == p) // nothing changed
	time.sleep(20 * time.Millisecond)
	testing.expect(t, os.write_entire_file(path, transmute([]byte)string("n = 0\ndraw [\n  n = n + 1\n  print n\n]\n")) == nil)
	next := poll(p)
	testing.expect(t, next != p)
	roci.step()
	testing.expect_value(t, printed(next), "2")
}

write_sketch :: proc(t: ^testing.T, path, text: string) {
	testing.expect(t, os.write_entire_file(path, transmute([]byte)text) == nil)
}

@(test)
test_saving_the_working_text_back_clears_the_errors_of_the_last_save :: proc(t: ^testing.T) {
	_ = os.make_directory_all("output/tests")
	path := "output/tests/recover_sketch.roci"
	good := "n = 0\ndraw [\n  n = n + 1\n]\n"
	write_sketch(t, path, good)
	p, _ := load(path, good)
	roci.start_headless(1)
	watch(p, path)
	start(p)
	defer finish_all()
	roci.step()
	time.sleep(20 * time.Millisecond)
	write_sketch(t, path, "n = 0\ndraw [\n  circel at 1 1 radius 1\n]\n")
	testing.expect(t, poll(p) == p)
	title, _ := roci.overlay_text()
	testing.expect(t, strings.contains(title, "circel"))
	time.sleep(20 * time.Millisecond)
	write_sketch(t, path, good) // the fix is to undo the change
	testing.expect(t, poll(p) == p)
	title, _ = roci.overlay_text()
	testing.expect_value(t, title, "")
	testing.expect_value(t, p.problem_title, "")
}

@(test)
test_a_sketch_opened_with_errors_waits_and_runs_when_the_file_is_fixed :: proc(t: ^testing.T) {
	_ = os.make_directory_all("output/tests")
	path := "output/tests/open_broken_sketch.roci"
	write_sketch(t, path, "circel at 1 1 radius 1\n")
	roci.start_headless(1)
	data, _ := os.read_entire_file(path, context.temp_allocator)
	p, ok := load(path, string(data))
	testing.expect(t, !ok)
	watch(p, path)
	start(p)
	defer finish_all()
	roci.step()
	title, _ := roci.overlay_text()
	testing.expect(t, strings.contains(title, "circel"))
	time.sleep(20 * time.Millisecond)
	write_sketch(t, path, "n = 0\ndraw [\n  n = n + 1\n  print n\n]\n")
	next := poll(p)
	testing.expect(t, next != p)
	testing.expect(t, !next.has_errors)
	roci.step()
	testing.expect_value(t, printed(next), "1")
	title, _ = roci.overlay_text()
	testing.expect_value(t, title, "")
	testing.expect(t, len(roci.open_windows()) >= 1)
}

// ---- window properties ----

@(test)
test_a_window_can_be_asked_for_its_size_title_position_and_mouse :: proc(t: ^testing.T) {
	text := "a = window size 320 200 at 40 60 title \"first\"\nb = window size 100 50 title \"second\"\nprint a.width\nprint a.height\nprint a.title\nprint a.at\nprint b.width\nprint a.fullscreen\nprint a.mouse"
	expect_printed(t, text, "320\n200\nfirst\n{ 40, 60 }\n100\nfalse\n{ 0, 0 }")
}

@(test)
test_one_windows_code_can_read_another_windows_mouse_and_size :: proc(t: ^testing.T) {
	text := "a = window size 300 200\nb = window size 500 400\ndraw a [\n  print b.mouse\n  print b.width\n]"
	p := run_text(t, text)
	defer finish(p)
	windows := roci.open_windows()
	roci.step({platform.Mouse_Moved{window = platform.Window_Id(windows[1]), x = 12, y = 34}})
	testing.expect_value(t, printed(p), "{ 12, 34 }\n500")
}

@(test)
test_a_windows_size_follows_it_when_it_is_resized :: proc(t: ^testing.T) {
	text := "w = window size 300 200\ndraw w [ print w.width ]"
	p := run_text(t, text)
	defer finish(p)
	roci.step({platform.Resized{window = platform.Window_Id(first_window()), width = 640, height = 480}})
	testing.expect_value(t, printed(p), "640")
}

@(test)
test_shuffle_gives_a_new_list_with_the_same_items_in_another_order :: proc(t: ^testing.T) {
	text := "xs = [ 1 2 3 4 5 6 7 8 ]\nys = shuffle xs\nprint xs\nprint (count ys)\nprint (combine ys from 0 [ result + it ])\nprint (ys is xs)"
	p := run_text(t, text)
	defer finish(p)
	testing.expect_value(t, printed(p), "[ 1 2 3 4 5 6 7 8 ]\n8\n36\nfalse")
}

@(test)
test_shuffle_repeats_with_the_same_seed_and_changes_with_another :: proc(t: ^testing.T) {
	text := "print (shuffle [ 1 2 3 4 5 6 7 8 9 10 ])"
	roci.start_headless(5)
	a, _ := load("a.roci", text)
	start(a)
	first := printed(a)
	destroy(a)
	roci.shutdown()
	roci.start_headless(5)
	b, _ := load("b.roci", text)
	start(b)
	testing.expect_value(t, printed(b), first)
	destroy(b)
	roci.shutdown()
	roci.start_headless(6)
	c, _ := load("c.roci", text)
	start(c)
	testing.expect(t, printed(c) != first)
	destroy(c)
	roci.shutdown()
}

@(test)
test_shuffling_an_empty_list_and_a_one_item_list_is_fine :: proc(t: ^testing.T) {
	expect_printed(t, "print (shuffle [])\nprint (shuffle [ 7 ])", "[ ]\n[ 7 ]")
}

@(test)
test_resizable_false_fixes_a_window_and_set_changes_it_later :: proc(t: ^testing.T) {
	text := "a = window size 300 200 resizable false\nb = window size 100 100\nprint a.resizable\nprint b.resizable\nset a resizable true\nset b resizable false\nprint a.resizable\nprint b.resizable"
	expect_printed(t, text, "false\ntrue\ntrue\nfalse")
}

@(test)
test_every_window_word_is_a_property_that_reads_back_what_was_asked :: proc(t: ^testing.T) {
	text := "p = window size 500 400\nw = window size 300 200 bordered false topmost true smallest 100 50 largest 800 600 ratio 1.5 alpha 80 focusable false visible false grab true parent p modal true\nprint w.bordered\nprint w.topmost\nprint w.smallest\nprint w.largest\nprint w.ratio\nprint w.alpha\nprint w.focusable\nprint w.visible\nprint w.grab\nprint w.modal\nprint (w.parent is p)"
	expect_printed(t, text, "false\ntrue\n{ 100, 50 }\n{ 800, 600 }\n1.5\n80\nfalse\nfalse\ntrue\ntrue\ntrue")
}

@(test)
test_set_changes_a_windows_size_title_and_position :: proc(t: ^testing.T) {
	text := "w = window size 300 200 at 10 20 title \"a\"\nset w width 640 title \"b\" at { 50, 60 }\nprint w.width\nprint w.height\nprint w.title\nprint w.at"
	expect_printed(t, text, "640\n200\nb\n{ 50, 60 }")
}

@(test)
test_set_can_name_a_window_through_another_window_property :: proc(t: ^testing.T) {
	text := "p = window size 500 400\nw = window size 300 200 parent p\nset w.parent width 700\nprint p.width"
	expect_printed(t, text, "700")
}

@(test)
test_window_states_the_system_knows_read_false_without_a_system_window :: proc(t: ^testing.T) {
	text := "w = window size 300 200\nprint w.focused\nprint w.hovered\nprint w.maximized\nprint w.minimized\nprint w.covered\nset w maximized true\nset w focused true"
	expect_printed(t, text, "false\nfalse\nfalse\nfalse\nfalse")
}

@(test)
test_alpha_is_a_percentage_in_the_language_and_a_byte_below_it :: proc(t: ^testing.T) {
	text := "c = rgb 10 20 30 alpha 50\nprint c.a\nc.a = 25\nprint c.a\nd = rgb 1 2 3 alpha 400\nprint d.a\ne = rgb 1 2 3\nprint e.a\nw = window size 100 100 alpha 40\nprint w.alpha\nset w alpha 100\nprint w.alpha"
	expect_printed(t, text, "50\n25\n100\n100\n40\n100")
}

@(test)
test_set_takes_a_pair_as_two_numbers_or_one_vector :: proc(t: ^testing.T) {
	text := "p = { 100, 50 }\nw = window size 300 200\nset w smallest p at 7 8\nprint w.smallest\nprint w.at\nset w at p largest 900 700\nprint w.at\nprint w.largest"
	expect_printed(t, text, "{ 100, 50 }\n{ 7, 8 }\n{ 100, 50 }\n{ 900, 700 }")
}

// ---- sketches of several files ----

@(private = "file")
expect_files_printed :: proc(t: ^testing.T, files: []lang.File_Text, want: string) {
	roci.start_headless(1)
	defer roci.shutdown()
	p, ok := load_files(files)
	defer destroy(p)
	if !ok {
		testing.expectf(t, false, "the program has errors: %s", lang.render_all(p.src, p.checked.diagnostics, context.temp_allocator))
		return
	}
	start(p)
	roci.step()
	testing.expect_value(t, printed(p), want)
}

@(test)
test_a_verb_and_a_constant_taught_in_another_file_run :: proc(t: ^testing.T) {
	expect_files_printed(t, {
		{name = "moves.roci", text = "SPEED = 3\nlearn double n [ give n * SPEED ]\n"},
		{name = "sketch.roci", text = "print (double 5)\nprint SPEED\n"},
	}, "15\n3")
}

@(test)
test_files_run_in_name_order_before_the_sketch_and_take_calls_in_any_order :: proc(t: ^testing.T) {
	expect_files_printed(t, {
		{name = "a.roci", text = "learn first [ print \"a\" ]\nlearn again [ second ]\n"},
		{name = "b.roci", text = "learn second [ print \"b\" ]\n"},
		{name = "sketch.roci", text = "again\nfirst\n"},
	}, "b\na")
}

@(test)
test_a_runtime_error_in_another_file_names_that_file :: proc(t: ^testing.T) {
	roci.start_headless(1)
	defer roci.shutdown()
	p, ok := load_files({
		{name = "maths.roci", text = "learn inverse n [ give 1 / n ]\n"},
		{name = "sketch.roci", text = "x = inverse 0\n"},
	})
	defer destroy(p)
	testing.expect(t, ok)
	start(p)
	testing.expect(t, len(p.errors) > 0)
	testing.expect(t, strings.contains(report(p, context.temp_allocator), "maths.roci:1:"))
}

@(test)
test_a_change_to_a_second_file_reloads_the_program_and_a_new_file_joins_it :: proc(t: ^testing.T) {
	root := "output/tests/interp_program"
	_ = os.remove_all(root)
	_ = os.make_directory_all(root)
	sketch, moves := "output/tests/interp_program/sketch.roci", "output/tests/interp_program/moves.roci"
	write_sketch(t, sketch, "n = 0\ndraw [\n  n = n + step_size\n  print n\n]\n")
	write_sketch(t, moves, "learn unused_verb [ print 0 ]\nSTEP = 1\n")
	// step_size is not defined yet: the program has an error and waits.
	write_sketch(t, moves, "STEP = 1\nlearn unused_verb [ print 0 ]\n")
	write_sketch(t, sketch, "n = 0\ndraw [\n  n = n + STEP\n  print n\n]\n")
	roci.start_headless(1)
	program, problem := folder.read_program(sketch)
	testing.expect_value(t, problem, "")
	p, ok := load_files(program.files)
	testing.expect(t, ok)
	watch(p, sketch)
	start(p)
	defer finish_all()
	roci.step()
	roci.step()
	testing.expect_value(t, printed(p), "1\n2")
	testing.expect(t, p.program)
	testing.expect_value(t, len(p.watched), 2)

	// The second file changes: the constant takes its new value at once, and n keeps running.
	time.sleep(20 * time.Millisecond)
	write_sketch(t, moves, "STEP = 10\nlearn unused_verb [ print 0 ]\n")
	next := poll(p)
	testing.expect(t, next != p)
	roci.step()
	testing.expect_value(t, printed(next), "12")

	// A third file appears with a verb the sketch then uses.
	time.sleep(600 * time.Millisecond)
	write_sketch(t, "output/tests/interp_program/extra.roci", "learn shout n [ print n ]\n")
	write_sketch(t, sketch, "n = 0\ndraw [\n  n = n + STEP\n  shout n\n]\n")
	after := poll(next)
	testing.expect(t, after != next)
	testing.expect(t, !after.has_errors)
	testing.expect_value(t, len(after.watched), 3)
}

@(test)
test_the_starfield_example_of_two_files_draws_its_stars :: proc(t: ^testing.T) {
	program, problem := folder.read_program("examples/starfield/sketch.roci")
	testing.expect_value(t, problem, "")
	testing.expect_value(t, len(program.files), 2)
	roci.start_headless(1)
	defer roci.shutdown()
	p, ok := load_files(program.files)
	defer destroy(p)
	testing.expect(t, ok)
	start(p)
	roci.step()
	testing.expect_value(t, len(p.errors), 0)
	windows := roci.open_windows()
	testing.expect_value(t, len(windows), 1)
	testing.expect(t, len(roci.recorded(windows[0])) >= 40)
}

@(test)
test_a_library_in_libs_runs_with_its_hidden_helper_and_the_sketch_wins_a_clash :: proc(t: ^testing.T) {
	root := "output/tests/interp_libs"
	_ = os.remove_all(root)
	_ = os.make_directory_all("output/tests/interp_libs/libs/stars")
	write_sketch(t, "output/tests/interp_libs/libs/stars/stars.roci", "learn twinkle n [ print (double_it n) ]\nhidden learn double_it n [ give n * 2 ]\nlearn glow [ print \"library glow\" ]\nlearn flash [ glow ]\n")
	write_sketch(t, "output/tests/interp_libs/sketch.roci", "use \"stars\"\nlearn glow [ print \"my glow\" ]\ntwinkle 4\nglow\nflash\nstars.glow\n")
	program, problem := folder.read_program("output/tests/interp_libs/sketch.roci")
	testing.expect_value(t, problem, "")
	expect_files_printed(t, program.files, "8\nmy glow\nlibrary glow\nlibrary glow")
}
