package codegen

import "../lang"
import "../registry"
import "core:strings"
import "core:testing"

// Checks a sketch and generates its program, in the temporary memory.
@(private = "file")
compile :: proc(text: string) -> Result {
	src := lang.make_source("test.roci", text, 0, context.temp_allocator)
	checked := lang.check(src, registry.ALL_VERBS, nil, context.temp_allocator)
	lang.optimise(&checked.program, lang.ALL_PASSES, context.temp_allocator)
	return generate(&checked.program, src, Options{sketch = "test", source = "test.roci"}, context.temp_allocator)
}

@(private = "file")
refused_for :: proc(t: ^testing.T, text, what: string) {
	result := compile(text)
	testing.expectf(t, len(result.problems) > 0, "`%s` should be refused", text)
	said := false
	for p in result.problems {
		said ||= strings.contains(p.what, what)
	}
	testing.expectf(t, said, "`%s`: no problem mentions `%s`: %v", text, what, result.problems)
	testing.expect_value(t, result.source, "")
}

@(test)
test_the_smallest_sketch_is_a_program_that_draws_a_circle :: proc(t: ^testing.T) {
	result := compile("circle at 100 100 radius 50\n")
	testing.expect_value(t, len(result.problems), 0)
	source := result.source
	testing.expect(t, strings.contains(source, "package sketch"))
	testing.expect(t, strings.contains(source, "roci.circle_xyr(100.0, 100.0, 50.0)"))
	testing.expect(t, strings.contains(source, "// line 1: circle at 100 100 radius 50"), "each statement says its line")
	testing.expect(t, strings.contains(source, "rt.execute(run, setup, roots)"))
	testing.expect(t, !strings.contains(source, "hook"), "no handlers, no hook")
}

@(test)
test_names_keep_the_sketchs_own_and_are_declared_once_at_the_top :: proc(t: ^testing.T) {
	result := compile("speed = 3\nsize = { 1, 2 }\nname = \"x\"\nlist = [ 1 2 ]\n")
	testing.expect_value(t, len(result.problems), 0)
	testing.expect(t, strings.contains(result.source, "speed: f64\n"))
	testing.expect(t, strings.contains(result.source, "size: [2]f64\n"))
	testing.expect(t, strings.contains(result.source, "name: string\n"))
	testing.expect(t, strings.contains(result.source, "list: ^rt.List(f64)\n"))
}

@(test)
test_a_name_odin_uses_gets_an_underscore :: proc(t: ^testing.T) {
	result := compile("context = 1\nproc = 2\nmap = 3\nprint (context + proc + map)\n")
	testing.expect_value(t, len(result.problems), 0)
	testing.expect(t, strings.contains(result.source, "context_: f64"))
	testing.expect(t, strings.contains(result.source, "proc_: f64"))
	testing.expect(t, strings.contains(result.source, "map_: f64"))
}

@(test)
test_a_sum_of_number_literals_is_worked_out_as_the_interpreter_does :: proc(t: ^testing.T) {
	result := compile("print (0.1 + 0.2)\nprint (7 / 0)\nprint (-7 % 5)\n")
	testing.expect_value(t, len(result.problems), 0)
	testing.expect(t, strings.contains(result.source, "0.30000000000000004"), "not Odin's exact 0.3")
	testing.expect(t, strings.contains(result.source, "rt.show(0.0"), "a division by zero is 0")
	testing.expect(t, strings.contains(result.source, "rt.show(3.0"), "the sign of the divisor: -7 % 5 is 3")
}

@(test)
test_division_and_remainders_that_can_meet_zero_go_through_the_runtime :: proc(t: ^testing.T) {
	result := compile("a = 3\nb = 0\nprint (a / b)\nprint (a % b)\nprint (a / 2)\nprint (a ^ 2)\n")
	testing.expect_value(t, len(result.problems), 0)
	testing.expect(t, strings.contains(result.source, "rt.divide(a, b)"))
	testing.expect(t, strings.contains(result.source, "rt.modulo(a, b)"))
	testing.expect(t, strings.contains(result.source, "(a / 2.0)"), "a divisor that is not zero is a plain division")
	testing.expect(t, strings.contains(result.source, "rt.power(a, 2.0)"))
}

@(test)
test_a_record_shape_is_a_struct_and_records_are_pointers :: proc(t: ^testing.T) {
	result := compile("p = { x: 1, y: 2 }\np.x = p.x + 1\nprint p.x\n")
	testing.expect_value(t, len(result.problems), 0)
	testing.expect(t, strings.contains(result.source, "Record_1 :: struct {"))
	testing.expect(t, strings.contains(result.source, "x: f64,"))
	testing.expect(t, strings.contains(result.source, "p: ^Record_1"))
	testing.expect(t, strings.contains(result.source, "rt.new_record(Record_1{x = 1.0, y = 2.0})"), "a record with no heap objects in it has nothing to trace")
	testing.expect(t, strings.contains(result.source, "using gc__: rt.Header"))
}

@(test)
test_a_taught_verb_is_a_procedure_with_a_result_when_it_gives :: proc(t: ^testing.T) {
	result := compile("learn twice n [ give n * 2 ]\nprint (twice 4)\nlearn shout with word \"hey\" [ print word ]\nshout\nshout word \"ho\"\n")
	testing.expect_value(t, len(result.problems), 0)
	testing.expect(t, strings.contains(result.source, "twice :: proc(n: f64) -> (result__: f64) {"))
	testing.expect(t, strings.contains(result.source, "return\n}"), "a verb that gives ends by handing back its result")
	testing.expect(t, strings.contains(result.source, "shout :: proc(word: string = \"hey\")"))
	testing.expect(t, strings.contains(result.source, "shout(word = \"ho\")"))
}

@(test)
test_draw_every_and_on_are_procedures_the_program_registers :: proc(t: ^testing.T) {
	result := compile("n = 0\ndraw [\n  n = n + 1\n  circle at n 5 radius 3\n]\nevery 2 seconds [ print n ]\non key \"space\" [ n = 0 ]\n")
	testing.expect_value(t, len(result.problems), 0)
	source := result.source
	testing.expect(t, strings.contains(source, "draw_0 :: proc() {"))
	testing.expect(t, strings.contains(source, "roci.draw(draw_0)"))
	testing.expect(t, strings.contains(source, "every_1 :: proc() {"))
	testing.expect(t, strings.contains(source, "on_2 :: proc() {"))
	testing.expect(t, strings.contains(source, "hook :: proc(w: roci.Window) {"))
	testing.expect(t, strings.contains(source, "happening.kind == .Key_Down && happening.name == \"space\""))
	testing.expect(t, strings.contains(source, "rt.execute(run, setup, roots, hook)"))
}

@(test)
test_a_style_word_after_a_shape_makes_a_look :: proc(t: ^testing.T) {
	result := compile("circle at 1 2 radius 3 fill red thickness 2 alpha 50\ntext \"hi\" at 5 5 size 20 align center\nrect at 1 1 size 2 2 as center\n")
	testing.expect_value(t, len(result.problems), 0)
	testing.expect(t, strings.contains(result.source, "roci.circle_xyr(1.0, 2.0, 3.0, roci.Look{fill = maths.Colour{"))
	testing.expect(t, strings.contains(result.source, "thickness = 2.0, alpha = rt.alpha_to_byte(50.0)}"))
	testing.expect(t, strings.contains(result.source, "size = 20.0, align = roci.Align.Center}"))
	testing.expect(t, strings.contains(result.source, "roci.rect_xywh(1.0, 1.0, 2.0, 2.0, roci.Look{}, roci.Origin.Center)"))
}

@(test)
test_list_blocks_become_procedures_with_plain_loops :: proc(t: ^testing.T) {
	result := compile("xs = [ 1 2 3 ]\nbig = keep xs [ it > 1 ]\nsmall = skip xs [ it > 1 ]\ndouble = collect xs [ it * 2 ]\n")
	testing.expect_value(t, len(result.problems), 0)
	testing.expect(t, strings.contains(result.source, "keep_0 :: proc(list: ^rt.List(f64)) -> ^rt.List(f64) {"))
	testing.expect(t, strings.contains(result.source, "if (it_ > 1.0) { rt.add(it_, out) }"))
	testing.expect(t, strings.contains(result.source, "if !(it_ > 1.0) { rt.add(it_, out) }"))
	testing.expect(t, strings.contains(result.source, "rt.add((it_ * 2.0), out)"))
}

@(test)
test_what_cannot_be_compiled_yet_is_refused_with_its_name_and_never_half_done :: proc(t: ^testing.T) {
	refused_for(t, "xs = [ 1 \"a\" ]\nys = xs\nzs = [ 1 2 ]\nys = zs\nprint (collect ys [ it ])\n", "shared between")
	refused_for(t, "scene \"a\" [ draw [ scene \"b\" [ ] ] ]\n", "another block")
	refused_for(t, "x = table\n", "table")
	refused_for(t, "draw [ push [ circle at 1 1 radius 1 ] ]\nevery 1 second [ draw [ circle at 1 1 radius 1 ] ]\n", "inside another block")
}

@(test)
test_every_problem_is_said_not_just_the_first :: proc(t: ^testing.T) {
	result := compile("scene \"a\" [ draw [ scene \"b\" [ ] ] ]\nx = table\ndraw [ push [ circle at 1 1 radius 1 ] ]\nevery 1 second [ draw [ circle at 1 1 radius 1 ] ]\n")
	testing.expect(t, len(result.problems) >= 3, "three things to say")
}

@(test)
test_a_repeat_takes_its_count_once :: proc(t: ^testing.T) {
	result := compile("xs = []\nrepeat 5 - (count xs) [ add 1 to xs ]\n")
	testing.expect_value(t, len(result.problems), 0)
	testing.expect(t, strings.contains(result.source, "times_0 := int("), "Odin works out the end of a range again each turn")
	testing.expect(t, strings.contains(result.source, "for _ in 0 ..< times_0 {"))
}

@(test)
test_the_verbs_in_space_and_the_window_words_are_written_as_calls :: proc(t: ^testing.T) {
	result := compile("window size 400 300 title \"x\" resizable false at 10 20\nlight sun from 0 -1 1 fill white\nmaterial metallic 50\nbox at 0 0 0 size 5\nsphere at { 1, 2, 3 } radius 4\nmove 1 2 3\nturn 30 around y\ncamera at 0 5 10 fov 60\nwith fill red [ circle at 1 1 radius 1 ]\n")
	testing.expect_value(t, len(result.problems), 0)
	source := result.source
	testing.expect(t, strings.contains(source, "roci.set_resizable(window_0, false)"))
	testing.expect(t, strings.contains(source, "roci.title_window(window_0, \"x\")"))
	testing.expect(t, strings.contains(source, "_ = roci.light(.Sun, [3]f64{0.0, -1.0, 1.0}, nil, maths.Colour{"))
	testing.expect(t, strings.contains(source, "roci.material(metallic = 50.0, roughness = nil, emissive = nil)"))
	testing.expect(t, strings.contains(source, "roci.box_xyz_side(0.0, 0.0, 0.0, 5.0)"))
	testing.expect(t, strings.contains(source, "roci.sphere_vr([3]f64{1.0, 2.0, 3.0}, 4.0)"))
	testing.expect(t, strings.contains(source, "roci.move_xyz(1.0, 2.0, 3.0)"))
	testing.expect(t, strings.contains(source, "roci.turn_about(30.0, .Y)"))
	testing.expect(t, strings.contains(source, "roci.camera_xyz(0.0, 5.0, 10.0, 60.0)"))
	testing.expect(t, strings.contains(source, "roci.push(.Style)"))
	testing.expect(t, strings.contains(source, "roci.pop()"))
}

@(test)
test_records_and_lists_that_hold_heap_objects_are_traced_and_the_names_are_the_roots :: proc(t: ^testing.T) {
	result := compile(`sparks = []
names = [ "a" ]
thing = { label: "x", kids: [ 1 2 ], n: 1 }
count_of = 5
add thing to sparks
`)
	testing.expect_value(t, len(result.problems), 0)
	source := result.source
	// the record marks its text and its list; a number needs nothing
	testing.expect(t, strings.contains(source, "trace_Record_1 :: proc(h: ^rt.Header) {"))
	testing.expect(t, strings.contains(source, "rt.mark_text(r.label)"))
	testing.expect(t, strings.contains(source, "if r.kids != nil { rt.mark(&r.kids.gc__) }"))
	// a list of records marks each record, a list of texts each text, a list of numbers nothing
	testing.expect(t, strings.contains(source, "mark_item_"))
	testing.expect(t, strings.contains(source, "rt.mark_text(item)"))
	// the roots are the names that can hold something on the heap, and only those
	roots_at := strings.index(source, "roots :: proc() {")
	testing.expect(t, roots_at >= 0)
	roots := source[roots_at:]
	testing.expect(t, strings.contains(roots, "if sparks != nil { rt.mark(&sparks.gc__) }"))
	testing.expect(t, strings.contains(roots, "if thing != nil { rt.mark(&thing.gc__) }"))
	testing.expect(t, !strings.contains(roots[:strings.index(roots, "}\n")], "count_of"), "a number holds nothing")
}

@(test)
test_pictures_sounds_fonts_and_paints_are_written_as_calls_of_the_runtime :: proc(t: ^testing.T) {
	result := compile(`photo = load "cat.png"
rain = load "rain.wav"
image photo at 1 2 width 30
fill photo as cover
fill [ red blue ] as radial
font "Mono" size 18
play rain volume 50
set rain speed 2
pale = crop photo at 0 0 size 5 5
w = window size 100 100 title "x" at 1 2
`)
	testing.expect_value(t, len(result.problems), 0)
	source := result.source
	testing.expect(t, strings.contains(source, "photo: roci.Image"))
	testing.expect(t, strings.contains(source, "rain: roci.Sound"))
	testing.expect(t, strings.contains(source, "rt.load_image(\"cat.png\")"))
	testing.expect(t, strings.contains(source, "rt.load_sound(\"rain.wav\", 0.0)"))
	testing.expect(t, strings.contains(source, "roci.image_xy(photo, 1.0, 2.0, roci.Look{}, roci.Origin.Default, 30.0, nil)"))
	testing.expect(t, strings.contains(source, "rt.picture_fill(photo, 0, 0.0, [2]f64{})"))
	testing.expect(t, strings.contains(source, "rt.gradient_paint([]maths.Colour{"))
	testing.expect(t, strings.contains(source, "rt.font(\"Mono\", 18.0)"))
	testing.expect(t, strings.contains(source, "roci.play(rain, volume = 50.0, pan = nil"))
	testing.expect(t, strings.contains(source, "roci.set_sound(rain, at = nil, volume = nil, pan = nil, speed = 2.0"))
	testing.expect(t, strings.contains(source, "rt.crop(photo, [2]f64{0.0, 0.0}, [2]f64{5.0, 5.0})"))
	testing.expect(t, strings.contains(source, "window_0 := roci.window(int(100.0), int(100.0), [2]int{int(1.0), int(2.0)}, {})"), "a window used as a value is made on lines before the statement")
	testing.expect(t, strings.contains(source, "roci.title_window(window_0, \"x\")"))
	testing.expect(t, strings.contains(source, "w = window_0"))
}

@(test)
test_tables_tweens_effects_and_canvases_are_written_with_what_the_collector_needs :: proc(t: ^testing.T) {
	result := compile(`counts = table
put counts "cat" 3
labels = table
put labels "a" "alpha"
p = { pos: { 1, 2 } }
tween p.pos to { 5, 5 } over 2 as out
level = 1
tween level to 10 over 1
effect "glow" by { amount: 0.5 }
c = canvas 10 10
draw into c [ circle at 5 5 radius 2 ]
`)
	testing.expect_value(t, len(result.problems), 0)
	source := result.source
	testing.expect(t, strings.contains(source, "counts: ^rt.Table(f64)"))
	testing.expect(t, strings.contains(source, "labels: ^rt.Table(string)"))
	testing.expect(t, strings.contains(source, "rt.put(counts, \"cat\", 3.0)"))
	testing.expect(t, strings.contains(source, "rt.put(labels, \"a\", \"alpha\")"))
	testing.expect(t, strings.contains(source, "rt.tween_vector(&rt.live(p).pos, [2]f64{5.0, 5.0}, 2.0, \"out\", &p.gc__)"), "the record a tween moves is kept while it does")
	testing.expect(t, strings.contains(source, "rt.tween_number(&level, 10.0, 1.0, \"\", nil)"))
	testing.expect(t, strings.contains(source, "rt.step_tweens()"), "the frame hook steps the tweens")
	testing.expect(t, strings.contains(source, "rt.effect(\"glow\", []roci.Effect_Value{rt.effect_number(\"amount\", 0.5)})"))
	testing.expect(t, strings.contains(source, "if rt.begin_into(c_) {"))
	testing.expect(t, strings.contains(source, "if counts != nil { rt.mark(&counts.gc__) }"), "a table held by a name is a root")
}

@(test)
test_a_list_block_that_reads_a_verbs_own_names_gets_them_as_arguments :: proc(t: ^testing.T) {
	result := compile("nums = [ 1 2 3 ]\nlearn above limit [ give keep nums [ it > limit ] ]\nprint (count (above 1))\nbyname = sort nums by [ 0 - it ]\n")
	testing.expect_value(t, len(result.problems), 0)
	testing.expect(t, strings.contains(result.source, "keep_0 :: proc(list: ^rt.List(f64), limit: f64) -> ^rt.List(f64) {"))
	testing.expect(t, strings.contains(result.source, "keep_0(nums, limit)"))
	testing.expect(t, strings.contains(result.source, "sort_1 :: proc(list: ^rt.List(f64)) -> ^rt.List(f64) {"))
	testing.expect(t, strings.contains(result.source, "rt.sorted(list, keys, nil)"))
}

@(test)
test_a_give_ends_the_verb_and_what_follows_is_not_written :: proc(t: ^testing.T) {
	result := compile("learn sign n [\n  if n < 0 [ give \"minus\" ]\n  give \"plus\"\n  print \"never\"\n]\nprint (sign 1)\n")
	testing.expect_value(t, len(result.problems), 0)
	testing.expect(t, strings.contains(result.source, "result__ = \"minus\"\n\t\treturn\n"), "a give sets the result and returns")
	testing.expect(t, !strings.contains(result.source, "never"), "a statement after a give is never reached")
}

@(test)
test_two_calls_that_work_something_out_are_worked_out_in_the_order_written :: proc(t: ^testing.T) {
	result := compile("c = hsb (random 255) 255 (random from 40 to 255)\nx = random 5 + random 5\nlearn pair [ give { random 3, random 3 } ]\n")
	testing.expect_value(t, len(result.problems), 0)
	source := result.source
	testing.expect(t, strings.contains(source, "order_1 := roci.random(255.0)\n"))
	testing.expect(t, strings.contains(source, "order_2 := roci.random_between(40.0, 255.0)\n"))
	testing.expect(t, strings.contains(source, "roci.hsb(order_1, 255.0, order_2)"))
	testing.expect(t, strings.contains(source, "(order_3 + order_4)"), "the two sides of a sum too")
}

@(test)
test_an_expression_asked_for_twice_is_written_once :: proc(t: ^testing.T) {
	// `add` works out its item once, even though two parts of the generator look at it
	result := compile("things = []\nadd { a: random 2, b: random 2 } to things\n")
	testing.expect_value(t, len(result.problems), 0)
	testing.expect_value(t, strings.count(result.source, "roci.random(2.0)"), 2)
}

@(test)
test_scenes_are_run_by_one_draw_procedure_that_picks_the_ones_that_take_part :: proc(t: ^testing.T) {
	result := compile("scene \"a\" [\n  on enter [ print \"in\" ]\n  draw [ if frame is 3 [ go \"b\" ] ]\n]\nscene \"b\" [\n  draw [ circle at 1 1 radius 1 ]\n]\n")
	testing.expect_value(t, len(result.problems), 0)
	testing.expect(t, strings.contains(result.source, "roci.draw(scene_draw)"))
	testing.expect(t, strings.contains(result.source, "rt.go(\"b\")"))
	testing.expect(t, strings.contains(result.source, "rt.scene_hooks"))
	testing.expect(t, strings.contains(result.source, "if name == \"enter\" && scene == 1"))
}

@(test)
test_a_message_is_copied_into_the_inbox_of_the_window_that_receives_it :: proc(t: ^testing.T) {
	result := compile("w = window size 10 10\nxs = [ 1 2 ]\non w receive m [ print count m ]\nsend w xs\n")
	testing.expect_value(t, len(result.problems), 0)
	testing.expect(t, strings.contains(result.source, "append(&inbox_1_next, copy_1(xs))"))
	testing.expect(t, strings.contains(result.source, "inbox_1_now, inbox_1_next = inbox_1_next, inbox_1_now"))
}

@(test)
test_midi_osc_and_tcp_events_read_what_happened_through_the_runtime :: proc(t: ^testing.T) {
	result := compile("on midi down [ print midi.note ]\non osc \"/a\" [ print osc.value ]\non tcp \"chat\" [ print received.text ]\n")
	testing.expect_value(t, len(result.problems), 0)
	testing.expect(t, strings.contains(result.source, "roci.start_midi()"))
	testing.expect(t, strings.contains(result.source, "rt.osc_match("))
	testing.expect(t, strings.contains(result.source, "rt.happening.midi"))
	testing.expect(t, strings.contains(result.source, "rt.happening.tcp"))
}

@(test)
test_saving_a_record_that_holds_itself_stops_at_a_depth :: proc(t: ^testing.T) {
	result := compile(`node = { name: "a", next: 0 }
node.next = node
save node "node.json"
`)
	testing.expect_value(t, len(result.problems), 0)
	testing.expect(t, strings.contains(result.source, "rt.datum_enter()"))
}

@(test)
test_a_list_of_mixed_kinds_is_a_list_of_boxes_and_each_use_takes_out_the_kind_it_wants :: proc(t: ^testing.T) {
	result := compile("m = [ 1 \"two\" true ]\nn = item 1 of m\ntotal = 0\nif n is 1 [ total = total + 1 ]\nprint (n + 1)\nadd 4 to m\nprint m\n")
	testing.expect_value(t, len(result.problems), 0)
	source := result.source
	testing.expect(t, strings.contains(source, "rt.list_of(rt.Box, mark_item_"), "the list holds boxes")
	testing.expect(t, strings.contains(source, "rt.box_number(1.0)"), "a number goes in a box")
	testing.expect(t, strings.contains(source, "rt.box_text(\"two\")"), "text goes in a box")
	testing.expect(t, strings.contains(source, "rt.box_bool(true)"), "true goes in a box")
	testing.expect(t, strings.contains(source, "rt.box_equal("), "a comparison of boxes compares kind and contents")
	testing.expect(t, strings.contains(source, "rt.box_arith(.Add, "), "a sum of boxes is worked out from what they hold")
	testing.expect(t, strings.contains(source, "rt.mark_box("), "the collector keeps what a box holds")
}

@(test)
test_the_arguments_of_an_osc_message_are_read_from_the_message :: proc(t: ^testing.T) {
	result := compile("on osc \"/a\" [ print osc.args ]\n")
	testing.expect_value(t, len(result.problems), 0)
	testing.expect(t, strings.contains(result.source, "args = rt.osc_args(m)"))
}

@(test)
test_a_part_of_a_box_is_read_while_the_sketch_runs :: proc(t: ^testing.T) {
	result := compile("m = [ { 1, 2 } \"a\" ]\nfor each p in m [ print p.x ]\n")
	testing.expect_value(t, len(result.problems), 0)
	testing.expect(t, strings.contains(result.source, "rt.box_part("))
}

@(test)
test_the_blocks_of_a_window_of_its_own_in_a_sketch_with_scenes_run_only_while_their_scene_takes_part :: proc(t: ^testing.T) {
	result := compile("other = window size 100 100\nscene \"a\" [\n  draw other [ circle at 1 1 radius 1 ]\n  draw other [ ui [ ] ]\n]\ndraw other [ circle at 2 2 radius 2 ]\n")
	testing.expect_value(t, len(result.problems), 0)
	source := result.source
	testing.expect(t, strings.contains(source, "if rt.takes_part(1) { draw_"), "a scene's block is gated")
	testing.expect(t, strings.contains(source, "roci.draw_window(other, draw_"), "the block outside every scene is registered as it is")
	testing.expect(t, strings.contains(source, "_in_scene)"), "the gated procedure is the one registered")
}

@(test)
test_files_in_a_folder_and_osc_lists_made_elsewhere_are_written_as_calls :: proc(t: ^testing.T) {
	result := compile("names = files in \"images\"\nall = files\nlist = [ 1 \"a\" true ]\nosc send \"/x\" list\nnums = [ 1 2 ]\nosc send \"/y\" nums\nosc send [ [ \"/a\" 1 ] [ \"/b\" ] ] to \"localhost\" port 9000\nosc send \"/z\" [ 1 \"a\" true ]\n")
	testing.expect_value(t, len(result.problems), 0)
	source := result.source
	testing.expect(t, strings.contains(source, "rt.files_in(\"images\")"))
	testing.expect(t, strings.contains(source, "rt.files_in(\"\")"))
	testing.expect(t, strings.contains(source, "rt.osc_args_of_boxes("))
	testing.expect(t, strings.contains(source, "rt.osc_args_of_values("))
	testing.expect(t, strings.contains(source, "rt.osc_bundle("))
	testing.expect(t, strings.contains(source, "[]rt.Osc_Arg{rt.Osc_Arg(1.0), rt.Osc_Arg(\"a\"), rt.Osc_Arg(true)}"))
}

@(test)
test_a_program_for_a_phone_ends_in_the_entry_its_app_runs :: proc(t: ^testing.T) {
	text := "c = 1\ncircle at 100 100 radius 50\n"
	src := lang.make_source("test.roci", text, 0, context.temp_allocator)
	checked := lang.check(src, registry.ALL_VERBS, nil, context.temp_allocator)
	lang.optimise(&checked.program, lang.ALL_PASSES, context.temp_allocator)
	desktop := generate(&checked.program, src, Options{sketch = "test", source = "test.roci"}, context.temp_allocator)
	testing.expect(t, strings.contains(desktop.source, "main :: proc() {\n\trun := rt.read_run(\"test\""))
	testing.expect(t, !strings.contains(desktop.source, "sdl_main"))
	testing.expect(t, !strings.contains(desktop.source, "vendor:sdl3"))

	ios := generate(&checked.program, src, Options{sketch = "test", source = "test.roci", target = "ios"}, context.temp_allocator)
	testing.expect_value(t, len(ios.problems), 0)
	testing.expect(t, strings.contains(ios.source, "import sdl \"vendor:sdl3\""))
	testing.expect(t, strings.contains(ios.source, "sdl_main :: proc \"c\" (argc: c.int, argv: [^]cstring) -> c.int {"))
	testing.expect(t, strings.contains(ios.source, "rt.use_home(string(sdl.GetBasePath()), string(cstring(sdl.GetPrefPath(\"rocinante\", \"test\"))))"))
	testing.expect(t, strings.contains(ios.source, "main :: proc() {\n\tsdl.RunApp(0, nil, sdl_main, nil)\n}"))
	testing.expect(t, strings.contains(ios.source, "sketch_main :: proc() {"))
	testing.expect(t, strings.contains(ios.source, "c_ = "), "a name of the sketch that is also an import of the program is renamed")

	android := generate(&checked.program, src, Options{sketch = "test", source = "test.roci", target = "android"}, context.temp_allocator)
	testing.expect_value(t, len(android.problems), 0)
	testing.expect(t, strings.contains(android.source, "@(export, link_name = \"rocinante_main\")"))
	testing.expect(t, strings.contains(android.source, "sdl.GetAndroidInternalStoragePath()"))
	testing.expect(t, strings.contains(android.source, "@(export, link_name = \"android_main\")"))
	testing.expect(t, !strings.contains(android.source, "\nmain :: proc() {"), "a library has no main")

	// a packaged Mac app: an ordinary main that first points the program at its bundle and its own folder
	mac := generate(&checked.program, src, Options{sketch = "test", source = "test.roci", target = "macos", app_id = "org.example.test"}, context.temp_allocator)
	testing.expect_value(t, len(mac.problems), 0)
	testing.expect(t, strings.contains(mac.source, "import sdl \"vendor:sdl3\""))
	testing.expect(t, !strings.contains(mac.source, "import \"base:runtime\""), "only what a Mac app uses is imported")
	testing.expect(t, strings.contains(mac.source, "main :: proc() {\n\trt.enter_app(string(sdl.GetBasePath()), string(cstring(sdl.GetPrefPath(\"\", \"org.example.test\"))))\n\trun := rt.read_run("))
	testing.expect(t, !strings.contains(mac.source, "sdl_main"), "the system starts a Mac app the ordinary way")

	// a packaged Linux app starts the same way: its assets beside the program, what it writes in the app's folder under the user's data
	linux := generate(&checked.program, src, Options{sketch = "test", source = "test.roci", target = "linux", app_id = "org.example.test"}, context.temp_allocator)
	testing.expect_value(t, len(linux.problems), 0)
	testing.expect_value(t, linux.source, strings.clone(mac.source, context.temp_allocator))
}

@(test)
test_saving_a_picture_writes_a_png_and_saving_data_still_writes_data :: proc(t: ^testing.T) {
	result := compile("swatch = picture from [ red blue ] size 2 1\nsave (resize swatch size 8 4) \"swatch.png\"\nsave swatch \"again.png\"\nsave [ 1 2 ] \"numbers.json\"\n")
	testing.expect_value(t, len(result.problems), 0)
	testing.expect_value(t, strings.count(result.source, "rt.save_picture_file("), 2)
	testing.expect(t, strings.contains(result.source, "rt.save_data("), "a list is still data")
}

@(test)
test_round_after_a_rect_or_a_square_is_a_look_field :: proc(t: ^testing.T) {
	result := compile("rect at 1 1 size 20 10 round 4\nsquare at 0 0 size 8 round 2 as center\n")
	testing.expect_value(t, len(result.problems), 0)
	testing.expect(t, strings.contains(result.source, "roci.rect_xywh(1.0, 1.0, 20.0, 10.0, roci.Look{round = 4.0})"))
	testing.expect(t, strings.contains(result.source, "roci.square_xys(0.0, 0.0, 8.0, roci.Look{round = 2.0}, roci.Origin.Center)"))
}

@(test)
test_a_clip_to_a_shape_is_a_call_with_the_same_words :: proc(t: ^testing.T) {
	result := compile("clip circle at 50 50 radius 20\nclip ellipse at 5 5 size 6 4 as corner\nclip rect at 0 0 size 10 10 round 3\nclip square at 0 0 size 8\nclip polygon [ { 0, 0 } { 10, 0 } { 5, 8 } ]\nclip polygon [ [ { 0, 0 } { 9, 0 } { 5, 8 } ] [ { 2, 1 } { 6, 1 } { 4, 4 } ] ]\n")
	testing.expect_value(t, len(result.problems), 0)
	testing.expect(t, strings.contains(result.source, "rt.clip_circle_xyr(50.0, 50.0, 20.0)"), result.source)
	testing.expect(t, strings.contains(result.source, "rt.clip_ellipse_xywh(5.0, 5.0, 6.0, 4.0, roci.Look{}, roci.Origin.Corner)"), result.source)
	testing.expect(t, strings.contains(result.source, "roci.clip_rect_xywh(0.0, 0.0, 10.0, 10.0, roci.Look{round = 3.0})"), result.source)
	testing.expect(t, strings.contains(result.source, "roci.clip_square_xys(0.0, 0.0, 8.0)"), result.source)
	testing.expect(t, strings.contains(result.source, "rt.clip_polygon("), result.source)
	testing.expect(t, strings.contains(result.source, "rt.clip_polygons("), result.source)
}

@(test)
test_reverse_join_items_and_plus_on_lists_call_the_runtime :: proc(t: ^testing.T) {
	result := compile("a = [ 1 2 3 ]\nb = reverse a\nc = join a b\nd = items 2 to 3 of c\ne = a + b\nprint (count e)\nprint (count d)\n")
	testing.expect_value(t, len(result.problems), 0)
	testing.expect(t, strings.contains(result.source, "rt.reverse("), result.source)
	testing.expect(t, strings.contains(result.source, "rt.join_lists("), result.source)
	testing.expect(t, strings.contains(result.source, "rt.items_between("), result.source)
}

@(test)
test_language_is_read_from_the_system :: proc(t: ^testing.T) {
	result := compile("said = language\nprint said\n")
	testing.expect_value(t, len(result.problems), 0)
	testing.expect(t, strings.contains(result.source, "roci.language_name("), result.source)
}

@(test)
test_save_in_sketch_says_so_to_the_runtime :: proc(t: ^testing.T) {
	result := compile("swatch = picture from [ red blue ] size 2 1\nsave swatch \"a.png\" in sketch\nsave swatch \"b.png\"\nsave [ 1 2 ] \"c.json\" in sketch\ncircle at 1 1 radius 1\nsave \"s.png\" in sketch\n")
	testing.expect_value(t, len(result.problems), 0)
	testing.expect(t, strings.contains(result.source, "rt.save_picture_file(swatch, \"a.png\", true)"), result.source)
	testing.expect(t, strings.contains(result.source, "rt.save_picture_file(swatch, \"b.png\", false)"), result.source)
	testing.expect(t, strings.contains(result.source, "\"c.json\", true)"), result.source)
	testing.expect(t, strings.contains(result.source, "rt.save(\"s.png\", true)"), result.source)
}
