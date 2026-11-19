package rt

import "core:math"
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
