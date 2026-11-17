// SPDX-License-Identifier: 0BSD
package roci

import "core:os"
import "core:testing"

@(test)
test_memory_keeps_every_kind_through_the_c_functions :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	abi_remember_number("n", 1280)
	abi_remember_number("half", 2.5)
	abi_remember_text("word", "hi")
	abi_remember_bool("flag", 1)
	numbers := [3]f64{1, 2.5, 3}
	abi_remember_numbers("list", cast([^]f64)rawptr(raw_data(numbers[:])), 3)
	testing.expect_value(t, abi_recall_number("n", -1), 1280)
	testing.expect_value(t, abi_recall_number("half", -1), 2.5)
	testing.expect_value(t, string(abi_recall_text("word", "none")), "hi")
	testing.expect_value(t, abi_recall_bool("flag", 0), 1)
	out: [2]f64
	testing.expect_value(t, abi_recall_numbers("list", raw_data(out[:]), 2), 3) // how many are kept, though two fit
	testing.expect_value(t, out, [2]f64{1, 2.5})
	// another kind, or nothing, gives the start
	testing.expect_value(t, abi_recall_number("word", 7), 7)
	testing.expect_value(t, abi_recall_bool("n", 1), 1)
	testing.expect_value(t, string(abi_recall_text("n", "start")), "start")
	testing.expect_value(t, abi_recall_numbers("n", nil, 0), 0)
	testing.expect_value(t, abi_recall_number("missing", 9), 9)
	testing.expect_value(t, string(abi_recall_text("missing", nil)), "")
	abi_forget("n")
	testing.expect_value(t, abi_recall_number("n", 5), 5)
	abi_forget_memory()
	testing.expect_value(t, abi_recall_number("half", 5), 5)
	abi_remember_numbers("list", nil, -1) // nonsense is left out
	abi_remember_numbers("list", nil, 2)
	testing.expect_value(t, abi_recall_numbers("list", nil, 0), 0)
}

@(test)
test_memory_is_written_after_a_pause_and_when_the_sketch_ends_and_never_by_a_read_only_run :: proc(t: ^testing.T) {
	os.make_directory("output")
	os.make_directory("output/tests")
	path := "output/tests/memory_store.toml"
	os.remove(path)
	defer os.remove(path)
	start_headless(1)
	memory_persist(path)
	abi_remember_number("visits", 3)
	testing.expect(t, !os.exists(path), "not written at once")
	memory_autosave()
	testing.expect(t, !os.exists(path), "not written before the pause is over")
	shutdown() // flushes
	data, err := os.read_entire_file(path, context.temp_allocator)
	testing.expect(t, err == nil)
	testing.expect_value(t, string(data), "# What sketch.roci remembers. Edit it freely while the sketch isn't running.\n\nvisits = 3\n")
	// a file edited by hand is read, a line that is not one is said and left out
	_ = os.write_entire_file(path, transmute([]byte)string("visits = 8\nbroken\n"))
	start_headless(1)
	memory_persist(path, false)
	testing.expect_value(t, abi_recall_number("visits", 0), 8)
	abi_remember_number("visits", 9)
	memory_save()
	shutdown()
	data2, _ := os.read_entire_file(path, context.temp_allocator)
	testing.expect_value(t, string(data2), "visits = 8\nbroken\n")
}

@(test)
test_a_sketch_that_remembers_nothing_makes_no_file :: proc(t: ^testing.T) {
	os.make_directory("output")
	os.make_directory("output/tests")
	path := "output/tests/memory_none.toml"
	os.remove(path)
	start_headless(1)
	memory_persist(path)
	abi_remember_number("x", 1)
	abi_forget_memory()
	shutdown()
	testing.expect(t, !os.exists(path), "a sketch with nothing remembered makes no file")
	os.remove(path)
}
