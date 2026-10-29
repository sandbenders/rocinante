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
	value, _ := global_value(p, p.checked.program.symbols[0])
	list := as_list(value)
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

click_event :: proc(w: roci.Window, x, y: f32, down := true, button := platform.Mouse_Button.Left) -> platform.Event {
	return platform.Mouse_Button_Changed{window = platform.Window_Id(w), button = button, down = down, clicks = 1, x = x, y = y}
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

// ---- rounding, and what is held down ----

@(test)
test_floor_round_and_ceil_give_whole_numbers_and_round_is_still_a_word_for_caps :: proc(t: ^testing.T) {
	text := "print (floor 2.7)\nprint (floor -2.1)\nprint (round 2.5)\nprint (round -2.5)\nprint (ceil 2.1)\nprint (ceil -0.5)\nx = round 2.4 + 1\nprint x\nn = 7\nprint (floor n / 2)\ncaps round\njoins round\ncircle at 1 1 radius 2 fill red"
	expect_printed(t, text, "2\n-3\n3\n-3\n3\n0\n3\n3.5")
}

@(test)
test_pressed_is_true_while_a_button_is_held_in_the_window_the_code_runs_in :: proc(t: ^testing.T) {
	p := run_text(t, "a = window size 100 100\nb = window size 100 100\ndraw a [ print pressed ]\ndraw b [ print (not pressed) ]")
	defer finish(p)
	windows := roci.open_windows()
	roci.step({click_event(windows[0], 5, 5)})
	roci.step()
	roci.step({click_event(windows[0], 5, 5, false)})
	testing.expect_value(t, printed(p), "true\ntrue\ntrue\ntrue\nfalse\ntrue")
}

@(test)
test_held_is_true_while_the_key_is_down :: proc(t: ^testing.T) {
	p := run_text(t, "draw [ print (held \"a\") ]")
	defer finish(p)
	w := first_window()
	roci.step({key_event(w, .A)})
	roci.step()
	roci.step({key_event(w, .A, false)})
	testing.expect_value(t, printed(p), "true\ntrue\nfalse")
}

// ---- the turtle ----

@(test)
test_the_turtle_walks_a_square_back_to_where_it_began :: proc(t: ^testing.T) {
	p := run_text(t, "repeat 4 [ forward 100  right 90 ]")
	defer finish(p)
	commands := roci.recorded(first_window())
	testing.expect_value(t, len(commands), 4)
	ends := [4][2]f32{{400, 200}, {500, 200}, {500, 300}, {400, 300}}
	for end, i in ends {
		testing.expect_value(t, commands[i].kind, gfx.Kind.Line)
		testing.expect_value(t, [2]f32{commands[i].args[2], commands[i].args[3]}, end)
	}
}

@(test)
test_the_pen_lifts_and_push_brings_the_turtle_back :: proc(t: ^testing.T) {
	text := "pen up\nback 100\npen down\nlearn branch size [\n  if size < 20 [ stop ]\n  forward size\n  push [ left 30  branch (size / 2) ]\n  push [ right 30  branch (size / 2) ]\n]\nbranch 80\nforward 10\nhome\nleft 90\nforward 5"
	p := run_text(t, text)
	defer finish(p)
	commands := roci.recorded(first_window())
	// Trunk 80, two branches of 40, four of 20, then the walk on from the trunk's top and from home.
	testing.expect_value(t, len(commands), 1 + 2 + 4 + 2)
	testing.expect_value(t, commands[0].args, [8]f32{400, 400, 400, 320, 0, 0, 0, 0})
	testing.expect_value(t, commands[7].args, [8]f32{400, 320, 400, 310, 0, 0, 0, 0})
	testing.expect_value(t, commands[8].args, [8]f32{400, 300, 395, 300, 0, 0, 0, 0})
}

// ---- collision ----

@(test)
test_touching_and_inside_answer_for_every_kind_of_shape :: proc(t: ^testing.T) {
	text := `ball = { pos: { 200, 100 }, radius: 10 }
paddle = { pos: { 180, 380 }, size: { 80, 12 } }
turned = { pos: { 0, 0 }, size: { 20, 10 }, angle: 90 }
wall = { from: { 0, 50 }, to: { 400, 50 } }
roof = { points: [ { 0, 0 } { 100, 0 } { 50, 40 } ] }
print (touching ball paddle)
ball.pos = { 200, 375 }
print (touching ball paddle)
print (touching { 210, 385 } paddle)
print (inside { 10, -4 } turned)
print (inside { 1, 5 } turned)
print (touching wall { 99, 50 })
print (inside { 50, 10 } roof)
print (inside { 90, 30 } roof)`
	expect_printed(t, text, "false\ntrue\ntrue\ntrue\nfalse\ntrue\ntrue\nfalse")
}

@(test)
test_contact_gives_a_record_or_an_empty_one :: proc(t: ^testing.T) {
	text := `ball = { pos: { 50, 98 }, radius: 5 }
paddle = { pos: { 0, 95 }, size: { 100, 10 } }
c = contact ball paddle
print c.normal
print c.depth
ball.pos = { 50, 0 }
d = contact ball paddle
print d.depth
print d.normal`
	expect_printed(t, text, "{ 0, -1 }\n8\n0\n{ 0, 0 }")
}

@(test)
test_hits_keeps_the_items_that_touch_in_list_order :: proc(t: ^testing.T) {
	text := `bricks = []
for i from 0 to 4 [ add { pos: { i * 50, 0 }, size: { 40, 20 } } to bricks ]
ball = { pos: { 95, 10 }, radius: 12 }
for each b in (hits ball bricks) [ print b.pos.x ]
print (count (hits { 500, 500 } bricks))`
	expect_printed(t, text, "50\n100\n0")
}

@(test)
test_cast_finds_the_first_item_along_a_line_in_a_mixed_list :: proc(t: ^testing.T) {
	text := `things = [ { from: { 0, 300 }, to: { 400, 300 } } { pos: { 100, 200 }, radius: 20 } { pos: { 80, 100 }, size: { 40, 10 } } ]
h = cast { from: { 100, 0 }, to: { 100, 400 } } things
print h.point
print h.normal
print h.distance
print h.item.size
miss = cast { from: { 300, 0 }, to: { 300, 100 } } things
print miss.distance`
	expect_printed(t, text, "{ 100, 100 }\n{ 0, -1 }\n100\n{ 40, 10 }\n0")
}

@(test)
test_a_copied_record_stays_the_same_shape :: proc(t: ^testing.T) {
	text := `wall = { from: { 0, 0 }, to: { 10, 0 } }
other = copy wall
other.to = { 0, 10 }
print (touching other { 0, 5 })
keep_it = []
add other to keep_it
print (touching (item 1 of keep_it) { 0, 5 })`
	expect_printed(t, text, "true\ntrue")
}

@(test)
test_shapes_in_a_draw_block_are_tested_every_frame :: proc(t: ^testing.T) {
	text := `ball = { pos: { 0, 100 }, radius: 5 }
wall = { from: { 20, 0 }, to: { 20, 200 } }
draw [
  ball.pos = ball.pos + { 10, 0 }
  if touching ball wall [ print "hit" ]
]`
	// x is 10, 20, 30: only in the second frame does it reach the wall (its left
	// edge is at 25 in the third).
	expect_printed(t, text, "hit", 3)
}

@(test)
test_a_list_asked_again_answers_the_same_and_sees_every_change :: proc(t: ^testing.T) {
	// The second question builds a tree; the answers must not change because of it,
	// and a moved wall, an added one, a removed one and a changed outline must all be seen.
	text := `walls = []
for i from 0 to 9 [ add { pos: { i * 30, 0 }, size: { 20, 20 } } to walls ]
add { points: [ { 0, 100 } { 50, 100 } { 25, 140 } ] } to walls
probe = { pos: { 35, 10 }, radius: 6 }
repeat 3 [ print (count (hits probe walls)) ]
w = item 2 of walls
w.pos = { 500, 500 }
print (count (hits probe walls))
add { pos: { 30, 0 }, size: { 5, 5 } } to walls
print (count (hits probe walls))
remove w from walls
print (count (hits probe walls))
print (count (hits { 25, 120 } walls))
o = item 10 of walls
add { 25, 170 } to o.points
print (count (hits { 25, 150 } walls))
print (count (hits { 25, 150 } walls))
h = cast { from: { 35, -50 }, to: { 35, 50 } } walls
h = cast { from: { 35, -50 }, to: { 35, 50 } } walls
print h.item.size`
	expect_printed(t, text, "1\n1\n1\n0\n1\n1\n1\n1\n1\n{ 5, 5 }")
}

@(test)
test_moving_one_list_keeps_the_tree_of_another :: proc(t: ^testing.T) {
	// Balls move every frame; the walls do not, so their tree stays (and the answers are right).
	text := `walls = []
for i from 0 to 9 [ add { from: { i * 40, 0 }, to: { i * 40, 100 } } to walls ]
balls = []
for i from 0 to 4 [ add { pos: { i * 40 + 30, 50 }, radius: 5 } to balls ]
draw [
  n = 0
  for each b in balls [
    b.pos = b.pos + { 2, 0 }
    n = n + count (hits b walls)
  ]
  print n
]`
	// Each ball starts 10 left of a wall and moves 2 a frame; it touches the wall
	// while its centre is within 5 of it, in frames 3 to 7.
	expect_printed(t, text, "0\n0\n5\n5\n5\n5\n5\n0", 8)
}

@(test)
test_a_window_hides_its_cursor_with_window_or_set :: proc(t: ^testing.T) {
	// `cursor` stays free as a name.
	text := "w = window size 300 200 cursor none\nprint w.cursor\nset w cursor arrow\nprint w.cursor\ncursor = 5\nprint cursor"
	expect_printed(t, text, "none\narrow\n5")
}

// ---- ease and tween ----

@(test)
test_ease_maps_an_amount_onto_a_curve :: proc(t: ^testing.T) {
	expect_printed(t, "print (ease 0.5)\nprint (ease 0.5 as in)\nprint (ease 0.25 as linear)\nprint (ease 2 as out)", "0.5\n0.125\n0.25\n1")
}

@(test)
test_a_tween_moves_its_place_each_frame_and_lands_on_the_value :: proc(t: ^testing.T) {
	// Frames are 1/60 of a second apart; the tween starts while the sketch sets up.
	text := "x = 0\ntween x to 60 over 1 as linear\ndraw [ print (round x) ]"
	p := run_text(t, text, 70)
	defer finish(p)
	lines := strings.split(printed(p), "\n", context.temp_allocator)
	testing.expect_value(t, lines[0], "1")
	testing.expect_value(t, lines[29], "30")
	testing.expect_value(t, lines[59], "60")
	testing.expect_value(t, lines[69], "60")
}

@(test)
test_tweens_move_fields_vectors_parts_and_colours :: proc(t: ^testing.T) {
	text := `balls = [ { pos: { 0, 0 } } { pos: { 0, 0 } } ]
for each b in balls [ tween b.pos to { 10, 20 } over 0.1 ]
c = black
tween c to white over 0.1 as linear
p = { 5, 5 }
tween p.x to 50 over 0.1
draw [ ]
every 1 seconds [
  second = item 2 of balls
  print second.pos
  print c.r
  print p
]`
	expect_printed(t, text, "{ 10, 20 }\n255\n{ 50, 5 }", 61)
}

@(test)
test_a_new_tween_of_the_same_place_replaces_the_old :: proc(t: ^testing.T) {
	text := "x = 0\ntween x to 1000 over 10\ntween x to 5 over 0.1\ndraw [ ]\nevery 1 seconds [ print x ]"
	expect_printed(t, text, "5", 61)
}

// ---- tables ----

@(test)
test_a_table_counts_words_in_the_order_they_came :: proc(t: ^testing.T) {
	text := `counts = table
for each word in [ "cat" "dog" "cat" "owl" "cat" ] [ put counts word ((get counts word) + 1) ]
print counts
print (get counts "cat")
print (get counts "emu")
print (count counts)
print (keys counts)
remove "dog" from counts
remove "emu" from counts
print counts
print (keys counts)`
	expect_printed(t, text, "{ \"cat\": 3, \"dog\": 1, \"owl\": 1 }\n3\n0\n3\n[ cat dog owl ]\n{ \"cat\": 3, \"owl\": 1 }\n[ cat owl ]")
}

@(test)
test_a_table_is_shared_and_copy_makes_another :: proc(t: ^testing.T) {
	text := `a = table
put a "x" 1
b = a
put b "y" 2
c = copy a
put c "z" 3
print (count a)
print (count c)
print (a is b)
print (a is c)
put c "z" 0
remove "z" from c
print (a is c)`
	expect_printed(t, text, "2\n3\ntrue\nfalse\ntrue")
}

@(test)
test_a_table_made_while_drawing_lasts_when_kept :: proc(t: ^testing.T) {
	// The table and its names are made in the frame's memory, then kept by a
	// sketch-wide name, so they have to be copied out before the frame ends.
	text := "seen = table\ndraw [\n  t = table\n  put t \"frame\" frame\n  seen = t\n]\nevery 3 frames [ print seen ]"
	expect_printed(t, text, "{ \"frame\": 2 }\n{ \"frame\": 5 }", 7)
}

@(test)
test_a_table_keeps_its_values_across_a_reload :: proc(t: ^testing.T) {
	before := "counts = table\nput counts \"a\" 1\ndraw [ put counts \"b\" frame ]"
	after := "counts = table\nput counts \"a\" 1\ndraw [ print counts ]"
	n, outcome := reloaded(t, before, after, 3)
	defer finish_all()
	testing.expect_value(t, outcome, Outcome.Reloaded)
	roci.step()
	testing.expect(t, strings.has_prefix(printed(n), "{ \"a\": 1, \"b\": "), printed(n))
}

// ---- mouse buttons and the wheel ----

@(test)
test_on_mouse_down_can_wait_for_one_button :: proc(t: ^testing.T) {
	text := `on mouse down [ print "any" ]
on mouse down right [ print "right" ]
on mouse up left [ print "left up" ]
on mouse down back [ print "back" ]
circle at 1 1 radius 1`
	p := run_text(t, text)
	defer finish(p)
	w := first_window()
	roci.step({click_event(w, 5, 5, button = .Right)})
	roci.step({click_event(w, 5, 5, false, .Right), click_event(w, 5, 5, button = .Left)})
	roci.step({click_event(w, 5, 5, false, .Left)})
	roci.step({click_event(w, 5, 5, button = .Back)})
	testing.expect_value(t, printed(p), "any\nright\nany\nleft up\nany\nback")
}

@(test)
test_held_reads_mouse_buttons_by_name :: proc(t: ^testing.T) {
	text := "draw [ print (held \"mouse right\")  print (held \"mouse left\")  print pressed ]"
	p := run_text(t, text)
	defer finish(p)
	w := first_window()
	clear(&p.printed)
	roci.step({click_event(w, 5, 5, button = .Right)})
	testing.expect_value(t, printed(p), "true\nfalse\ntrue")
	clear(&p.printed)
	roci.step({click_event(w, 5, 5, false, .Right)})
	testing.expect_value(t, printed(p), "false\nfalse\nfalse")
}

@(test)
test_the_wheel_is_how_far_it_turned_since_the_last_frame :: proc(t: ^testing.T) {
	p := run_text(t, "zoom = 1\ndraw [\n  zoom = zoom + wheel.y\n  print zoom\n  print wheel\n]")
	defer finish(p)
	w := platform.Window_Id(first_window())
	clear(&p.printed)
	roci.step({platform.Wheel{window = w, dx = 0, dy = 2}, platform.Wheel{window = w, dx = -1, dy = 1}})
	roci.step()
	testing.expect_value(t, printed(p), "4\n{ -1, 3 }\n4\n{ 0, 0 }")
}

// The value of a sketch-wide name, for tests that drive a sketch and look inside.
global_named :: proc(p: ^Interp, name: string) -> Value {
	for symbol in p.checked.program.symbols {
		if symbol.name == name {
			value, _ := global_value(p, symbol)
			return value
		}
	}
	return nil
}

@(test)
test_the_mouse_example_draws_undoes_zooms_and_pans :: proc(t: ^testing.T) {
	data, err := os.read_entire_file("examples/mouse/sketch.roci", context.temp_allocator)
	if !testing.expect(t, err == nil, "tests run from the repository root") {
		return
	}
	p := run_text(t, string(data), 1)
	defer finish(p)
	w := first_window()
	id := platform.Window_Id(w)
	dots := proc(p: ^Interp) -> int {return len(as_list(global_named(p, "dots")).items)}
	at :: proc(id: platform.Window_Id, x, y: f32) -> platform.Event {return platform.Mouse_Moved{window = id, x = x, y = y}}
	testing.expect_value(t, dots(p), 12)

	// Left puts a dot, back takes it away, forward brings it back, right takes it away.
	roci.step({at(id, 100, 100), click_event(w, 100, 100)})
	roci.step({click_event(w, 100, 100, false)})
	testing.expect_value(t, dots(p), 13)
	roci.step({click_event(w, 100, 100, button = .Back)})
	testing.expect_value(t, dots(p), 12)
	roci.step({click_event(w, 100, 100, button = .Forward)})
	testing.expect_value(t, dots(p), 13)
	roci.step({click_event(w, 100, 100, button = .Right)})
	testing.expect_value(t, dots(p), 12)

	// The wheel zooms around the mouse: the canvas point under it stays under it.
	roci.step({platform.Wheel{window = id, dy = 1, x = 100, y = 100}})
	testing.expect(t, abs(as_number(global_named(p, "zoom")) - 1.15) < 1e-12)
	offset := as_pair(global_named(p, "offset"))
	testing.expect(t, abs(offset.x + 15) < 1e-9 && abs(offset.y + 15) < 1e-9, "offset")

	// Dragging with the middle button moves the canvas with the mouse.
	roci.step({click_event(w, 100, 100, button = .Middle)})
	roci.step({at(id, 130, 90)})
	roci.step({click_event(w, 130, 90, false, .Middle)})
	offset = as_pair(global_named(p, "offset"))
	testing.expect(t, abs(offset.x - 15) < 1e-9 && abs(offset.y + 25) < 1e-9, "offset after the drag")
}

// The examples that only draw: each runs for a while without a runtime error.
@(test)
test_the_drawing_examples_run_without_a_runtime_error :: proc(t: ^testing.T) {
	for name in ([]string{"rays", "style", "landscape", "shapes"}) {
		p := run_text(t, example_text(name), 120)
		testing.expectf(t, len(p.errors) == 0, "%s hit a runtime error", name)
		testing.expectf(t, len(roci.recorded(first_window())) > 20, "%s drew too little", name)
		finish(p)
	}
}

@(test)
test_the_tally_example_counts_a_click_and_forgets_a_name :: proc(t: ^testing.T) {
	p := run_text(t, example_text("tally"), 1)
	defer finish(p)
	w := first_window()
	counts := proc(p: ^Interp) -> ^Table {return as_table(global_named(p, "counts"))}
	total := proc(table: ^Table) -> (sum: f64) {
		for v in table.values {
			sum += as_number(v)
		}
		return
	}
	testing.expect_value(t, total(counts(p)), 36)

	// A click on the first tile moves one count from its colour to the next.
	before := len(counts(p).keys)
	roci.step({platform.Mouse_Moved{window = platform.Window_Id(w), x = 30, y = 30}, click_event(w, 30, 30)})
	roci.step({click_event(w, 30, 30, false)})
	testing.expect_value(t, total(counts(p)), 36)
	testing.expect(t, len(counts(p).keys) >= before)

	// A right click on the first bar takes its name out, with the tiles it counted.
	first := counts(p).keys[0]
	gone := as_number(counts(p).values[0])
	roci.step({platform.Mouse_Moved{window = platform.Window_Id(w), x = 370, y = 30}, click_event(w, 370, 30, button = .Right)})
	_, still := table_get(counts(p), first)
	testing.expect(t, !still, "the first name is taken out")
	testing.expect_value(t, total(counts(p)), 36 - gone)
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_the_sorting_example_keeps_and_skips_the_tall_bars :: proc(t: ^testing.T) {
	p := run_text(t, example_text("sorting"), 1)
	defer finish(p)
	w := first_window()
	shown := proc(p: ^Interp) -> int {return len(as_list(global_named(p, "shown")).items)}
	testing.expect_value(t, shown(p), 24)
	roci.step({key_event(w, .K)})
	tall := shown(p)
	testing.expect(t, tall > 0 && tall < 24, "some bars are tall and some are not")
	roci.step({key_event(w, .K, false), key_event(w, .S)})
	testing.expect_value(t, shown(p), 24 - tall)
	roci.step({key_event(w, .S, false), key_event(w, .SPACE)})
	testing.expect_value(t, shown(p), 24)
	for _ in 0 ..< 200 {
		roci.step()
	}
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_the_windows_example_changes_its_settings_from_keys :: proc(t: ^testing.T) {
	p := run_text(t, example_text("windows"), 1)
	defer finish(p)
	windows := roci.open_windows()
	if !testing.expect_value(t, len(windows), 2) {
		return
	}
	big, pad := windows[0], windows[1]
	testing.expect_value(t, roci.window_parent(pad), big)
	testing.expect(t, roci.window_flag(pad, "topmost"))

	roci.step({key_event(big, ._2)})
	testing.expect_value(t, roci.window_size(big), [2]f64{640, 400})
	roci.step({key_event(big, ._2, false), key_event(big, .T)})
	testing.expect(t, !roci.window_flag(pad, "topmost"), "t takes the pad off the top")
	roci.step({key_event(big, .T, false), key_event(big, .DOWN)})
	testing.expect_value(t, roci.window_alpha(pad), 229.5) // 90 in the language; the Odin API counts to 255

	// Holding the mouse in the pad grows the dot, and letting go drops it.
	roci.step({click_event(pad, 100, 100)})
	for _ in 0 ..< 30 {
		roci.step()
	}
	roci.step({click_event(pad, 100, 100, false)})
	testing.expect(t, as_number(global_named(p, "drop")) > 5, "the dot dropped")
	testing.expect_value(t, as_number(global_named(p, "dot")), 0)
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_a_vector_and_two_numbers_draw_what_four_numbers_draw :: proc(t: ^testing.T) {
	p := run_text(t, "p = { 5, 6 }\nrect at p size 80 40\nrect at 5 6 size { 80, 40 }\nrect at 5 6 size 80 40")
	defer finish(p)
	commands := roci.recorded(first_window())
	if !testing.expect_value(t, len(commands), 3) {
		return
	}
	for c in commands {
		testing.expect_value(t, c.kind, gfx.Kind.Rect)
		testing.expect_value(t, [4]f32{c.args[0], c.args[1], c.args[2], c.args[3]}, [4]f32{5, 6, 80, 40})
	}
}

finger_event :: proc(w: roci.Window, key: u64, phase: platform.Finger_Phase, x, y: f32) -> platform.Event {
	return platform.Finger_Changed{window = platform.Window_Id(w), finger = {1, key}, phase = phase, x = x, y = y, pressure = 0.5}
}

@(test)
test_touch_blocks_see_their_finger_and_draw_sees_every_finger :: proc(t: ^testing.T) {
	text := `on touch down [ print finger.id  print finger.pos ]
on touch up [ print (finger.pos - finger.start) ]
on mouse down [ print "mouse" ]
draw [ print (count touches) ]`
	p := run_text(t, text)
	defer finish(p)
	w := first_window()
	clear(&p.printed)
	roci.step({finger_event(w, 5, .Down, 0.5, 0.5)})
	roci.step({finger_event(w, 6, .Down, 0, 0), finger_event(w, 5, .Moved, 0.75, 0.5)})
	roci.step({finger_event(w, 5, .Up, 0.75, 0.5)})
	roci.step()
	testing.expect_value(t, printed(p), "1\n{ 400, 300 }\n1\n2\n{ 0, 0 }\n2\n{ 200, 0 }\n1\n1")
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_a_list_of_fingers_keeps_their_fields :: proc(t: ^testing.T) {
	text := `marks = []
on touch down [ add finger to marks ]
draw [ for each f in touches [ print f.pressure ] ]`
	p := run_text(t, text)
	defer finish(p)
	w := first_window()
	clear(&p.printed)
	roci.step({finger_event(w, 1, .Down, 0.25, 0.5)})
	for _ in 0 ..< 3 {
		roci.step() // the frame's memory is freed; the mark kept in the sketch's stays
	}
	marks := as_list(global_named(p, "marks"))
	if testing.expect_value(t, len(marks.items), 1) {
		testing.expect_value(t, as_pair(read_field(p, marks.items[0], "pos")), [2]f64{200, 300})
		testing.expect_value(t, as_number(read_field(p, marks.items[0], "id")), 1)
	}
	testing.expect_value(t, printed(p), "0.5\n0.5\n0.5\n0.5")
}

@(test)
test_the_touch_example_rings_holds_and_throws :: proc(t: ^testing.T) {
	p := run_text(t, example_text("touch"), 1)
	defer finish(p)
	w := first_window()
	count_of := proc(p: ^Interp, name: string) -> int {return len(as_list(global_named(p, name)).items)}
	testing.expect_value(t, count_of(p, "rings"), 2)
	roci.step({finger_event(w, 1, .Down, 0.25, 0.5), finger_event(w, 2, .Down, 0.75, 0.5)})
	testing.expect_value(t, count_of(p, "rings"), 4)
	testing.expect_value(t, len(roci.touches()), 2)
	roci.step({finger_event(w, 1, .Moved, 0.5, 0.5)})
	roci.step({finger_event(w, 1, .Up, 0.5, 0.5)})
	testing.expect_value(t, count_of(p, "thrown"), 1)
	thrown := as_list(global_named(p, "thrown")).items[0]
	testing.expect_value(t, as_pair(read_field(p, thrown, "vel")), [2]f64{16, 0}) // moved 160 to the right, a tenth a frame
	for _ in 0 ..< 100 {
		roci.step()
	}
	testing.expect_value(t, count_of(p, "thrown"), 0)
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_the_benchmark_example_draws_its_hundred_thousand_circles :: proc(t: ^testing.T) {
	p := run_text(t, example_text("benchmark"), 1)
	defer finish(p)
	circles := 0
	for c in roci.recorded(first_window()) {
		if c.kind == gfx.Kind.Circle {
			circles += 1
		}
	}
	testing.expect_value(t, circles, 100_000)
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_every_registry_verb_has_its_own_code :: proc(t: ^testing.T) {
	seen: [Verb_Code]bool
	for &verb in registry.ALL_VERBS {
		code := verb_code(&verb)
		testing.expectf(t, code != .None, "`%s` has no code", verb.name)
		testing.expectf(t, VERB_CODE_NAMES[code] == verb.name, "`%s` has the code of `%s`", verb.name, VERB_CODE_NAMES[code])
		testing.expectf(t, !seen[code], "`%s` shares a code", verb.name)
		seen[code] = true
		// The language's own verbs are the ones the Odin API does not have.
		_, in_api := registry.find_in(registry.VERBS, verb.name)
		testing.expectf(t, is_language_code(code) == !in_api, "`%s` is on the wrong side", verb.name)
	}
	testing.expect_value(t, verb_code(nil), Verb_Code.None)
	outside := registry.Verb{name = "circle"}
	testing.expect_value(t, verb_code(&outside), Verb_Code.None) // only the registry's own verbs have codes
	testing.expect_value(t, code_for_name("no fill"), Verb_Code.No_Fill)
	testing.expect_value(t, code_for_name("nothing"), Verb_Code.None)
	testing.expect_value(t, code_for_name(""), Verb_Code.None)
}

// ---- the sketch's memory ----

@(test)
test_replacing_a_list_every_frame_keeps_memory_bounded :: proc(t: ^testing.T) {
	p := run_text(t, "dots = []\nrepeat 1000 [ add { pos: { random 800, random 600 }, life: 1 } to dots ]\nlabel = \"\"\ndraw [\n  dots = keep dots [ it.life > 0 ]\n  label = \"frame \" + frame\n]")
	defer finish(p)
	for _ in 0 ..< 10 {
		roci.step()
	}
	for _ in 0 ..< 990 {
		roci.step()
		used := p.values[p.values_now].total_used
		testing.expectf(t, used < 2 * p.live + COLLECT_SLACK + 1 << 20, "the values arena grew to %d bytes", used)
	}
	testing.expect(t, p.collections > 0, "the arena was copied")
	testing.expect_value(t, len(as_list(global_named(p, "dots")).items), 1000)
	testing.expect_value(t, as_text(global_named(p, "label")), "frame 999") // `frame` counts from 0
}

@(test)
test_a_copy_of_the_memory_keeps_values_and_what_is_shared :: proc(t: ^testing.T) {
	text := `a = [ { x: 1 } ]
b = a
r = { x: 7 }
first = [ r ]
second = [ r ]
counts = table
put counts "cat" 3
name = "hello"
`
	p := run_text(t, text, 1)
	defer finish(p)
	collect(p)
	collect(p) // twice, so the arena the values started in is the one in use again
	testing.expect_value(t, p.collections, 2)
	a, b := as_list(global_named(p, "a")), as_list(global_named(p, "b"))
	testing.expect(t, a == b, "b and a are still one list")
	first := as_list(global_named(p, "first"))
	second := as_list(global_named(p, "second"))
	testing.expect(t, first.items[0] == second.items[0], "a record in two lists is still one record")
	testing.expect_value(t, as_number(read_field(p, first.items[0], "x")), 7)
	value, _ := table_get(as_table(global_named(p, "counts")), "cat")
	testing.expect_value(t, as_number(value), 3)
	testing.expect_value(t, as_text(global_named(p, "name")), "hello")
	testing.expect_value(t, len(a.items), 1)
}

@(test)
test_a_tween_and_a_cached_tree_follow_their_values_across_a_copy :: proc(t: ^testing.T) {
	text := `balls = [ { pos: { 0, 0 }, radius: 5 } ]
walls = []
for i from 0 to 9 [ add { pos: { i * 50, 100 }, size: { 40, 10 } } to walls ]
on key "a" [ for each b in balls [ tween b.pos to { 100, 0 } over 0.5 ] ]
draw [ print (count (hits { 210, 105 } walls)) ]`
	p := run_text(t, text, 3) // asked about unchanged: the list has a tree by now
	defer finish(p)
	w := first_window()
	roci.step({key_event(w, .A)})
	collect(p)
	for _ in 0 ..< 60 {
		roci.step()
	}
	ball := as_list(global_named(p, "balls")).items[0]
	testing.expect_value(t, as_pair(read_field(p, ball, "pos")), [2]f64{100, 0})
	testing.expect_value(t, p.printed[len(p.printed) - 1], "1")
	walls := as_list(global_named(p, "walls"))
	cached := false
	for e in p.shape_cache {
		cached ||= e.list == walls
	}
	testing.expect(t, cached, "the cached tree follows the list it belongs to")
	testing.expect_value(t, len(p.errors), 0)
}

// ---- the optimisation passes against the reference ----

// One run of a sketch: a hash of every window's commands each frame, what it
// printed and how many runtime errors it hit.
@(private = "file")
Trace :: struct {
	frames:  [dynamic]u64,
	printed: string,
	errors:  int,
}

// Runs an example for `frames` frames with a fixed seed, sending the same mouse
// moves, clicks, keys, wheel turns and fingers to every window each time.
@(private = "file")
trace_example :: proc(t: ^testing.T, name: string, frames: int, chosen: lang.Passes) -> (trace: Trace, ok: bool) {
	program, problem := folder.read_program(fmt.tprintf("examples/%s/sketch.roci", name))
	if problem != "" {
		return
	}
	set_passes(chosen)
	defer set_passes(lang.ALL_PASSES)
	roci.start_headless(3)
	defer roci.shutdown()
	p, loaded := load_files(program.files)
	defer destroy(p)
	if !testing.expectf(t, loaded, "%s does not load", name) {
		return
	}
	start(p)
	trace.frames = make([dynamic]u64, context.temp_allocator)
	for f in 0 ..< frames {
		events := make([dynamic]platform.Event, context.temp_allocator)
		for w in roci.open_windows() {
			id := platform.Window_Id(w)
			x := f32(120 + (f * 37) % 300)
			y := f32(90 + (f * 53) % 220)
			append(&events, platform.Mouse_Moved{window = id, x = x, y = y})
			switch f % 20 {
			case 3:  append(&events, click_event(w, x, y))
			case 5:  append(&events, click_event(w, x, y, false))
			case 7:  append(&events, click_event(w, x, y, button = .Right))
			case 8:  append(&events, click_event(w, x, y, false, .Right))
			case 9:  append(&events, platform.Wheel{window = id, dy = 1, x = x, y = y})
			case 11: append(&events, finger_event(w, 1, .Down, 0.3, 0.4))
			case 13: append(&events, finger_event(w, 1, .Up, 0.6, 0.5))
			case 15: append(&events, key_event(w, sdl.Scancode(int(sdl.Scancode.A) + f % 26)))
			case 16: append(&events, key_event(w, sdl.Scancode(int(sdl.Scancode.A) + (f - 1) % 26), false))
			case 17: append(&events, key_event(w, .SPACE), key_event(w, ._1))
			case 18: append(&events, key_event(w, .SPACE, false), key_event(w, ._1, false))
			}
		}
		roci.step(events[:])
		h: u64 = 14695981039346656037
		for w in roci.open_windows() {
			for c in roci.recorded(w) {
				h = (h ~ gfx.command_hash(c)) * 1099511628211
			}
		}
		append(&trace.frames, h)
	}
	trace.printed = strings.join(p.printed[:], "\n", context.temp_allocator)
	trace.errors = len(p.errors)
	return trace, true
}

@(test)
test_every_example_draws_the_same_with_the_passes_on_and_off :: proc(t: ^testing.T) {
	dir, err := os.open("examples")
	if !testing.expect(t, err == nil, "tests run from the repository root") {
		return
	}
	defer os.close(dir)
	entries, _ := os.read_dir(dir, -1, context.temp_allocator)
	compared := 0
	for entry in entries {
		if !os.exists(fmt.tprintf("examples/%s/sketch.roci", entry.name)) {
			continue
		}
		frames := 2 if entry.name == "benchmark" else 80
		reference, ok := trace_example(t, entry.name, frames, {})
		if !ok {
			continue
		}
		optimised, _ := trace_example(t, entry.name, frames, lang.ALL_PASSES)
		compared += 1
		testing.expectf(t, optimised.errors == reference.errors, "%s: %d runtime errors with the passes, %d without", entry.name, optimised.errors, reference.errors)
		testing.expectf(t, optimised.printed == reference.printed, "%s prints something else with the passes", entry.name)
		for h, f in reference.frames {
			if !testing.expectf(t, f < len(optimised.frames) && optimised.frames[f] == h, "%s draws frame %d differently with the passes", entry.name, f) {
				break
			}
		}
	}
	testing.expect(t, compared >= 15, "the examples were found")
}

@(test)
test_the_interpreter_never_fuses_a_multiply_and_an_add :: proc(t: ^testing.T) {
	// 1 + 2^-30 and 1 + 2^-29, written out: rounded twice the sum is exactly 0.
	text := "a = 1 + 1 / 1073741824\nc = 0 - (1 + 1 / 536870912)\ndraw [ print (a * a + c) ]"
	for chosen in ([]lang.Passes{{}, lang.ALL_PASSES}) {
		set_passes(chosen)
		expect_printed(t, text, "0", 1)
	}
	set_passes(lang.ALL_PASSES)
}
