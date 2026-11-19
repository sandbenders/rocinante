package rt

import "core:math"
import "core:os"
import "core:strings"
import "core:time"
import "../"
import "../data"
import "../folder"
import "../maths"
import "../osc"
import "core:testing"

@(test)
test_numbers_read_as_people_write_them :: proc(t: ^testing.T) {
	testing.expect_value(t, format_number(3), "3")
	testing.expect_value(t, format_number(0.5), "0.5")
	testing.expect_value(t, format_number(-2.25), "-2.25")
	testing.expect_value(t, format_number(100000), "100000")
	testing.expect_value(t, format_number(1000000), "1e+06") // as the interpreter has always printed it
	tenth, fifth := 0.1, 0.2
	testing.expect_value(t, format_number(tenth + fifth), "0.30000000000000004") // not Odin's exact 0.3 of constants
	testing.expect_value(t, format_number(math.inf_f64(1)), "inf")
	testing.expect_value(t, format_number(math.inf_f64(-1)), "-inf")
	testing.expect_value(t, format_number(math.nan_f64()), "nan")
}

@(test)
test_values_join_to_text_as_they_print :: proc(t: ^testing.T) {
	testing.expect_value(t, show(7.0), "7")
	testing.expect_value(t, show(true), "true")
	testing.expect_value(t, show("hi"), "hi")
	testing.expect_value(t, show([2]f64{1, 2.5}), "{ 1, 2.5 }")
	testing.expect_value(t, show([3]f64{1, 2, 3}), "{ 1, 2, 3 }")
	testing.expect_value(t, join("a", "b"), "ab")
	defer gc_reset()
	kept := keep(join("x", "y"))
	testing.expect_value(t, kept, "xy")
}

@(test)
test_a_division_by_zero_is_zero_and_a_remainder_takes_the_divisors_sign :: proc(t: ^testing.T) {
	testing.expect_value(t, divide(7, 2), 3.5)
	testing.expect_value(t, divide(7, 0), 0)
	testing.expect_value(t, divide_vector([2]f64{8, 4}, [2]f64{2, 0}), [2]f64{4, 0})
	testing.expect_value(t, divide_vector_by([2]f64{8, 4}, 2), [2]f64{4, 2})
	testing.expect_value(t, divide_vector_by([2]f64{8, 4}, 0), [2]f64{0, 0})
	testing.expect_value(t, modulo(7, 3), 1)
	testing.expect_value(t, modulo(-1, 5), 4)
	testing.expect_value(t, modulo(7, -3), -2)
	testing.expect_value(t, modulo(5, 0), 0)
}

@(test)
test_a_power_that_is_not_a_number_is_zero :: proc(t: ^testing.T) {
	testing.expect_value(t, power(2, 10), 1024)
	testing.expect_value(t, power(-8, 1.0 / 3), 0)
	testing.expect_value(t, power(0, -1), 0)
	testing.expect_value(t, power(10, 1000), 0)
}

@(test)
test_alpha_is_a_percentage_the_api_keeps_as_a_byte :: proc(t: ^testing.T) {
	testing.expect_value(t, alpha_to_byte(0), 0)
	testing.expect_value(t, alpha_to_byte(100), 255)
	testing.expect_value(t, alpha_to_byte(50), 127.5)
	testing.expect_value(t, alpha_to_byte(-5), 0)
	testing.expect_value(t, alpha_to_byte(500), 255)
}

@(test)
test_lists_are_shared_and_read_by_place_from_one :: proc(t: ^testing.T) {
	defer gc_reset()
	list := list_of(f64, nil, 10, 20, 30)
	testing.expect_value(t, count(list), 3)
	testing.expect_value(t, item(list, 1), 10)
	testing.expect_value(t, item(list, 3), 30)
	testing.expect_value(t, item(list, 3.9), 30)
	testing.expect_value(t, item(list, 0), 0)
	testing.expect_value(t, item(list, 4), 0)
	alias := list // another name for the same list
	add(40, alias)
	testing.expect_value(t, count(list), 4)
	testing.expect_value(t, item(list, 4), 40)
	empty := new_list(f64)
	testing.expect_value(t, count(empty), 0)
	testing.expect_value(t, item(empty, 1), 0)
	// nothing is nothing, not a crash
	none: ^List(f64)
	testing.expect_value(t, count(none), 0)
	testing.expect_value(t, item(none, 1), 0)
	add(1, none)
}

@(test)
test_a_phrase_of_args_is_checked_in_the_roci_run_words :: proc(t: ^testing.T) {
	// the defaults a program starts with when it is given nothing
	run := Run{sketch = "x", odin = "y", seed = 1, mode = "compiled"}
	testing.expect_value(t, run.frames, 0)
	testing.expect(t, !run.stats && !run.no_vsync)
	testing.expect_value(t, run.mode, "compiled")
}

// A record of the tests': a header first, a number, a text and a list of records of its own kind.
Node :: struct {
	using gc__: Header,
	value:      f64,
	name:       string,
	children:   ^List(^Node),
}

trace_node :: proc(h: ^Header) {
	n := (^Node)(h)
	mark_text(n.name)
	if n.children != nil {
		mark(&n.children.gc__)
	}
}

mark_node :: proc(item: ^Node) {
	if item != nil {
		mark(&item.gc__)
	}
}

@(test)
test_the_collector_frees_what_nothing_holds_and_keeps_what_a_name_holds :: proc(t: ^testing.T) {
	defer gc_reset()
	kept: ^Node
	kept_list: ^List(^Node)
	roots :: proc() {
		// the names of the test, set below, are the roots
	}
	_ = roots
	root_proc :: proc() {
		test_kept_node, test_kept_list = test_kept_node, test_kept_list
	}
	_ = root_proc
	// garbage: records and lists nothing points to, and a text nothing holds
	for i in 0 ..< 100 {
		node := new_record(Node{value = f64(i), name = keep("garbage")}, trace_node)
		node.children = new_list(^Node, mark_node)
		add(node, node.children)
	}
	// what a name holds: a list of two records, each with a text and one a child
	kept_list = new_list(^Node, mark_node)
	first := new_record(Node{value = 1, name = keep("first")}, trace_node)
	second := new_record(Node{value = 2, name = keep("second")}, trace_node)
	first.children = new_list(^Node, mark_node)
	add(second, first.children)
	add(first, kept_list)
	kept = new_record(Node{value = 3, name = keep("alone")}, trace_node)
	test_kept_node, test_kept_list = kept, kept_list
	before := gc_stats()
	testing.expect_value(t, before.objects, 100 * 3 + 8) // records, lists and texts: 100 each of the three kinds, then what is kept
	collect(proc() {
		mark(&test_kept_node.gc__)
		mark(&test_kept_list.gc__)
	})
	after := gc_stats()
	testing.expect_value(t, after.collections, 1)
	// kept: the list (1), first, second, first's children (1), `alone`, and the texts of the three
	testing.expect_value(t, after.objects, 1 + 2 + 1 + 1 + 3)
	testing.expect(t, after.freed > 0)
	testing.expect_value(t, first.name, "first")
	testing.expect_value(t, second.name, "second")
	testing.expect_value(t, kept.name, "alone")
	testing.expect_value(t, count(first.children), 1)
	// a second collection with nothing held frees the rest
	collect(proc() {})
	testing.expect_value(t, gc_stats().objects, 0)
}

@(thread_local) test_kept_node: ^Node
@(thread_local) test_kept_list: ^List(^Node)

@(test)
test_a_collection_starts_when_enough_was_made :: proc(t: ^testing.T) {
	defer gc_reset()
	roots :: proc() {}
	maybe_collect(roots)
	testing.expect_value(t, gc_stats().collections, 0) // nothing made, nothing to do
	big := new_list(f64)
	for _ in 0 ..< COLLECT_FLOOR / size_of(f64) + 1000 {
		add(1, big)
	}
	maybe_collect(roots)
	testing.expect_value(t, gc_stats().collections, 1)
	testing.expect_value(t, gc_stats().objects, 0) // the list was held by nothing
	// what survives raises the bar: a sketch holding 20 MB is not collected again until it has made 20 MB more
	held := new_list(f64)
	test_kept_list2 = held
	for _ in 0 ..< 20 * 1024 * 1024 / size_of(f64) {
		add(1, held)
	}
	collect(proc() { mark(&test_kept_list2.gc__) })
	live := gc_stats().live
	testing.expect(t, live > 19 * 1024 * 1024)
	maybe_collect(proc() { mark(&test_kept_list2.gc__) })
	testing.expect_value(t, gc_stats().collections, 2)
}

@(thread_local) test_kept_list2: ^List(f64)

@(test)
test_a_value_that_goes_too_deep_to_save_is_a_loop_and_writes_nothing :: proc(t: ^testing.T) {
	for _ in 0 ..< DATUM_DEPTH {
		testing.expect(t, datum_enter())
	}
	testing.expect(t, !datum_enter())
	testing.expect(t, datum_looped)
	for _ in 0 ..< DATUM_DEPTH {
		datum_leave()
	}
	testing.expect_value(t, datum_depth, 0)
	defer forget_said()
	save_data(data.Null{}, "loop.json") // says the value holds itself and forgets the loop
	testing.expect(t, !datum_looped)
	testing.expect(t, datum_enter()) // the next save starts again from the top
	datum_leave()
}

@(test)
test_a_data_file_is_read_again_when_it_changes :: proc(t: ^testing.T) {
	roci.start_headless(1)
	defer roci.shutdown()
	defer gc_reset()
	testing.expect(t, folder.ensure_directory("output/tests/rt-data"))
	path := "output/tests/rt-data/count.json"
	defer forget_data()
	defer forget_said()
	defer {
		for key in allowed {
			delete(key)
		}
		delete(allowed)
		allowed = nil
	}
	read_number :: proc(d: data.Datum) -> f64 {
		return datum_number(datum_member(d, "n"))
	}
	testing.expect(t, roci.write_text_file(path, `{"n": 1}`))
	if allowed == nil {
		allowed = make(map[string]bool)
	}
	allowed[strings.clone(path)] = true
	testing.expect_value(t, load_data(path, "", read_number), 1)
	roci.step()
	testing.expect_value(t, load_data(path, "", read_number), 1) // unchanged: kept
	testing.expect(t, roci.write_text_file(path, `{"n": 2}`))
	info, err := os.stat(path, context.temp_allocator)
	testing.expect(t, err == nil)
	testing.expect(t, os.change_times(path, time.now(), time.time_add(info.modification_time, 10 * time.Second)) == nil)
	testing.expect_value(t, load_data(path, "", read_number), 1) // still the same frame: not looked at again
	roci.step()
	testing.expect_value(t, load_data(path, "", read_number), 2)
}

@(test)
test_a_box_gives_back_what_was_put_in_it_and_zero_for_another_kind :: proc(t: ^testing.T) {
	testing.expect_value(t, unbox_number(box_number(3)), 3)
	testing.expect_value(t, unbox_number(box_bool(true)), 1)
	testing.expect_value(t, unbox_number(box_text("x")), 0)
	testing.expect_value(t, unbox_number(nil), 0)
	testing.expect_value(t, unbox_bool(box_bool(true)), true)
	testing.expect_value(t, unbox_bool(box_number(2)), true)
	testing.expect_value(t, unbox_bool(box_number(0)), false)
	testing.expect_value(t, unbox_bool(box_text("true")), false)
	testing.expect_value(t, unbox_text(box_text("hi")), "hi")
	testing.expect_value(t, unbox_text(box_number(1)), "")
	testing.expect_value(t, unbox_vector(box_vector2({1, 2}), 2), [2]f64{1, 2})
	testing.expect_value(t, unbox_vector(box_vector2({1, 2}), 3), [3]f64{1, 2, 0})
	testing.expect_value(t, unbox_vector(box_vector3({1, 2, 3}), 2), [2]f64{1, 2})
	testing.expect_value(t, unbox_vector(box_number(1), 2), [2]f64{0, 0})
	testing.expect_value(t, unbox_colour(box_colour({1, 2, 3, 4})), maths.Colour{1, 2, 3, 4})
	testing.expect_value(t, unbox_colour(nil), maths.Colour{})
	testing.expect_value(t, unbox_image(box_image(4)), roci.Image(4))
	testing.expect_value(t, unbox_sound(box_text("")), roci.Sound(0))
	testing.expect_value(t, unbox_window(box_window(2)), roci.Window(2))
}

@(test)
test_a_box_holds_a_list_only_for_the_type_it_was_made_as :: proc(t: ^testing.T) {
	defer gc_reset()
	numbers := list_of(f64, nil, 1, 2)
	boxed := box_heap(numbers)
	testing.expect(t, unbox_heap(boxed, ^List(f64)) == numbers)
	testing.expect(t, unbox_heap(boxed, ^List(string)) == nil)
	testing.expect(t, unbox_heap(box_number(1), ^List(f64)) == nil)
	nothing: ^List(f64)
	testing.expect_value(t, box_heap(nothing), nil)
	testing.expect(t, box_equal(boxed, box_heap(numbers)))
	testing.expect(t, !box_equal(boxed, box_heap(list_of(f64, nil, 1, 2))))
	// with nothing written for the type it is shared and reads plainly
	testing.expect(t, copy_box(boxed).(Heap_Ref).object == &numbers.gc__)
	testing.expect_value(t, show_box(boxed), "a record or a list")
	// with what the generator writes for it, copied and read as a list
	with_ops := box_heap(numbers, &number_list_ops)
	copied := copy_box(with_ops)
	testing.expect(t, copied.(Heap_Ref).object != &numbers.gc__)
	testing.expect_value(t, show_box(copied), "[ 1 2 ]")
}

@(test)
test_boxes_are_equal_by_kind_and_contents :: proc(t: ^testing.T) {
	testing.expect(t, box_equal(box_number(1), box_number(1)))
	testing.expect(t, !box_equal(box_number(1), box_number(2)))
	testing.expect(t, !box_equal(box_number(1), box_bool(true)))
	testing.expect(t, box_equal(box_bool(true), box_bool(true)))
	testing.expect(t, box_equal(box_text("a"), box_text("a")))
	testing.expect(t, !box_equal(box_text("a"), box_text("b")))
	testing.expect(t, !box_equal(box_text("1"), box_number(1)))
	testing.expect(t, box_equal(box_vector2({1, 2}), box_vector2({1, 2})))
	testing.expect(t, !box_equal(box_vector2({1, 2}), box_vector3({1, 2, 0})))
	testing.expect(t, box_equal(box_vector3({1, 2, 3}), box_vector3({1, 2, 3})))
	testing.expect(t, box_equal(box_vector4({1, 2, 3, 4}), box_vector4({1, 2, 3, 4})))
	testing.expect(t, box_equal(box_colour({1, 2, 3, 4}), box_colour({1, 2, 3, 4})))
	testing.expect(t, !box_equal(box_colour({1, 2, 3, 4}), box_colour({1, 2, 3, 5})))
	testing.expect(t, box_equal(box_image(2), box_image(2)))
	testing.expect(t, box_equal(box_sound(2), box_sound(2)))
	testing.expect(t, box_equal(box_window(2), box_window(2)))
	testing.expect(t, box_equal(nil, nil))
	testing.expect(t, !box_equal(nil, box_number(0)))
	testing.expect(t, !box_equal(box_number(0), nil))
}

@(test)
test_a_box_is_worked_out_as_the_interpreter_works_values_out :: proc(t: ^testing.T) {
	defer gc_reset()
	testing.expect_value(t, box_arith(.Add, box_number(1), box_number(2)).(f64), 3)
	testing.expect_value(t, box_arith(.Subtract, box_number(1), box_number(2)).(f64), -1)
	testing.expect_value(t, box_arith(.Multiply, box_number(3), box_number(2)).(f64), 6)
	testing.expect_value(t, box_arith(.Divide, box_number(1), box_number(0)).(f64), 0)
	testing.expect_value(t, box_arith(.Divide, box_number(3), box_number(2)).(f64), 1.5)
	testing.expect_value(t, box_arith(.Add, box_text("a"), box_number(2)).(string), "a2")
	testing.expect_value(t, box_arith(.Add, box_bool(true), box_text("!")).(string), "true!")
	testing.expect_value(t, box_arith(.Add, box_text("a"), box_vector2({1, 2})).(string), "a{ 1, 2 }")
	testing.expect_value(t, box_arith(.Add, box_bool(true), box_number(1)).(f64), 2)
	testing.expect_value(t, box_arith(.Add, box_text(""), nil).(string), "")
	testing.expect_value(t, box_arith(.Multiply, box_vector2({1, 2}), box_number(3)).([2]f64), [2]f64{3, 6})
	testing.expect_value(t, box_arith(.Add, box_vector2({1, 2}), box_vector3({10, 20, 30})).([2]f64), [2]f64{11, 22})
	testing.expect_value(t, box_arith(.Divide, box_vector3({1, 2, 3}), box_number(0)).([3]f64), [3]f64{0, 0, 0})
	testing.expect_value(t, box_arith(.Multiply, box_number(2), box_vector4({1, 2, 3, 4})).([4]f64), [4]f64{2, 4, 6, 8})
	testing.expect_value(t, box_arith(.Subtract, box_number(10), box_vector2({1, 2})).([2]f64), [2]f64{9, 8})
	testing.expect_value(t, box_arith(.Add, box_colour({10, 20, 30, 40}), box_colour({250, 0, 0, 0})).(maths.Colour), maths.Colour{255, 20, 30, 40})
	testing.expect_value(t, box_arith(.Multiply, box_colour({10, 20, 30, 40}), box_number(2)).(maths.Colour), maths.Colour{20, 40, 60, 80})
	testing.expect_value(t, box_arith(.Multiply, box_number(100), box_colour({10, 20, 30, 40})).(maths.Colour), maths.Colour{255, 255, 255, 255})
	testing.expect_value(t, box_negate(box_number(2)).(f64), -2)
	testing.expect_value(t, box_negate(box_vector2({1, -2})).([2]f64), [2]f64{-1, 2})
	testing.expect_value(t, box_negate(box_colour({1, 2, 3, 4})).(maths.Colour), maths.Colour{0, 0, 0, 0})
	testing.expect_value(t, box_not(box_bool(true)).(bool), false)
	testing.expect_value(t, box_not(nil).(bool), true)
	testing.expect_value(t, box_part(box_vector2({1, 2}), "y").(f64), 2)
	testing.expect_value(t, box_part(box_vector3({1, 2, 3}), "z").(f64), 3)
	testing.expect_value(t, box_part(box_vector2({1, 2}), "z").(f64), 0)
	testing.expect_value(t, box_part(box_colour({1, 2, 3, 255}), "b").(f64), 3)
	testing.expect_value(t, box_part(box_colour({1, 2, 3, 255}), "a").(f64), 100)
	testing.expect_value(t, box_part(box_number(1), "x").(f64), 0)
	testing.expect_value(t, box_part(box_vector2({1, 2}), "xy").(f64), 0)
}

@(test)
test_a_box_reads_in_text_as_the_interpreter_writes_values :: proc(t: ^testing.T) {
	defer gc_reset()
	testing.expect_value(t, show_box(box_number(2.5)), "2.5")
	testing.expect_value(t, show_box(box_bool(false)), "false")
	testing.expect_value(t, show_box(box_text("hi")), "hi")
	testing.expect_value(t, show_box(box_vector2({1, 2})), "{ 1, 2 }")
	testing.expect_value(t, show_box(box_vector3({1, 2, 3})), "{ 1, 2, 3 }")
	testing.expect_value(t, show_box(box_vector4({1, 2, 3, 4})), "{ 1, 2, 3, 4 }")
	testing.expect_value(t, show_box(box_colour({1, 2, 3, 255})), "rgb 1 2 3 alpha 100")
	testing.expect_value(t, show_box(box_window(2)), "window 2")
	testing.expect_value(t, show_box(nil), "")
	testing.expect_value(t, show(list_of(Box, mark_box, box_number(1), box_text("a"))), "[ 1 a ]")
}

@(test)
test_lists_of_boxes_and_of_one_kind_are_copied_into_each_other :: proc(t: ^testing.T) {
	defer gc_reset()
	boxes := list_of(Box, mark_box, box_number(1), box_text("x"), box_number(3))
	numbers := list_unboxed(boxes, unbox_number, nil)
	testing.expect_value(t, len(numbers.items), 3)
	testing.expect_value(t, numbers.items[0], 1)
	testing.expect_value(t, numbers.items[1], 0)
	testing.expect_value(t, numbers.items[2], 3)
	back := list_boxed(numbers, box_number)
	testing.expect_value(t, len(back.items), 3)
	testing.expect(t, box_equal(back.items[2], box_number(3)))
	nothing: ^List(Box)
	testing.expect_value(t, len(list_unboxed(nothing, unbox_number, nil).items), 0)
	nobody: ^List(f64)
	testing.expect_value(t, len(list_boxed(nobody, box_number).items), 0)
}

@(test)
test_a_text_in_a_box_is_kept_and_marked_by_the_collector :: proc(t: ^testing.T) {
	defer gc_reset()
	made := keep_box(box_text(join("a", "b")))
	testing.expect_value(t, made.(string), "ab")
	testing.expect(t, keep_box(box_number(1)).(f64) == 1)
	mark_box(made) // a text of the heap, an object, a number: each is marked without trouble
	mark_box(box_number(1))
	mark_box(box_heap(list_of(f64, nil, 1)))
	mark_box(nil)
}

@(test)
test_the_arguments_of_an_osc_message_are_boxes :: proc(t: ^testing.T) {
	defer gc_reset()
	args := []osc.Arg{f64(1), true, "hi", osc.Blob{1, 2}}
	list := osc_args(roci.Osc_Message{args = args})
	testing.expect_value(t, len(list.items), 4)
	testing.expect_value(t, list.items[0].(f64), 1)
	testing.expect_value(t, list.items[1].(bool), true)
	testing.expect_value(t, list.items[2].(string), "hi")
	testing.expect_value(t, show_box(list.items[3]), "[ 1 2 ]")
	testing.expect_value(t, len(osc_args(roci.Osc_Message{}).items), 0)
}

@(test)
test_lists_and_tables_are_equal_by_what_they_hold_and_a_loop_does_not_end_the_comparison :: proc(t: ^testing.T) {
	defer gc_reset()
	same_number :: proc(x, y: f64) -> bool { return x == y }
	a := list_of(f64, nil, 1, 2)
	b := list_of(f64, nil, 1, 2)
	c := list_of(f64, nil, 1, 3)
	short := list_of(f64, nil, 1)
	compare_begin()
	testing.expect(t, lists_equal(a, a, same_number))
	testing.expect(t, lists_equal(a, b, same_number))
	testing.expect(t, !lists_equal(a, c, same_number))
	testing.expect(t, !lists_equal(a, short, same_number))
	testing.expect(t, !lists_equal(a, nil, same_number))
	testing.expect(t, lists_equal(a, b, same_number), "a pair met again is taken as equal")
	compare_end()
	ta, tb, tc := new_table(f64), new_table(f64), new_table(f64)
	put(ta, "k", 1)
	put(ta, "j", 2)
	put(tb, "j", 2)
	put(tb, "k", 1)
	put(tc, "k", 1)
	put(tc, "j", 3)
	compare_begin()
	testing.expect(t, tables_equal(ta, tb, same_number))
	testing.expect(t, !tables_equal(ta, tc, same_number))
	testing.expect(t, !tables_equal(ta, nil, same_number))
	compare_end()
	testing.expect_value(t, met_depth, 0)
}

@(test)
test_a_record_that_is_not_there_reads_as_an_empty_one :: proc(t: ^testing.T) {
	Thing :: struct {
		using gc__: Header,
		n:          f64,
	}
	none: ^Thing
	testing.expect_value(t, live(none).n, 0)
	defer gc_reset()
	there := new_record(Thing{n = 4})
	testing.expect_value(t, live(there).n, 4)
}

@(test)
test_osc_messages_are_made_from_boxes_and_sent_alone_or_in_a_bundle :: proc(t: ^testing.T) {
	roci.start_headless(1)
	defer roci.shutdown()
	defer gc_reset()
	defer forget_said()
	numbers := list_of(f64, nil, 1, 300, -5)
	items := list_of(Box, mark_box, box_number(60), box_text("hi"), box_bool(true), box_heap(numbers), box_vector2({1, 2}))
	args := osc_args_of_boxes(items)
	testing.expect_value(t, len(args), 4) // the vector is left out
	testing.expect_value(t, args[0].(f64), 60)
	testing.expect_value(t, args[1].(string), "hi")
	testing.expect_value(t, args[2].(bool), true)
	blob, is_blob := args[3].(osc.Blob)
	testing.expect(t, is_blob)
	testing.expect_value(t, len(blob), 3)
	testing.expect_value(t, blob[1], 255)
	testing.expect_value(t, blob[2], 0)
	testing.expect_value(t, len(osc_args_of_boxes(items, 3)), 1)
	testing.expect_value(t, len(osc_args_of_boxes(nil)), 0)
	testing.expect_value(t, len(osc_args_of_values(list_of(string, nil, "a", "b"))), 2)
	testing.expect_value(t, len(osc_args_of_values((^List(f64))(nil))), 0)

	first := list_of(Box, mark_box, box_text("/a"), box_number(1))
	second := list_of(Box, mark_box, box_text("/b"))
	messages := list_of(^List(Box), nil, first, second)
	osc_bundle(messages, "localhost", 9000)
	sent := roci.osc_sent_messages()
	testing.expect_value(t, len(sent), 2)
	testing.expect(t, sent[0].bundled && sent[1].bundled)
	testing.expect_value(t, sent[0].address, "/a")
	testing.expect_value(t, sent[1].address, "/b")
	testing.expect_value(t, sent[0].port, 9000)
	// an address without a slash sends nothing
	bad := list_of(^List(Box), nil, list_of(Box, mark_box, box_text("a")))
	osc_bundle(bad, "localhost", 9000)
	testing.expect_value(t, len(roci.osc_sent_messages()), 2)
	osc_send("/one", osc_args_of_boxes(items), "localhost", 1)
	testing.expect_value(t, len(roci.osc_sent_messages()), 3)
}
