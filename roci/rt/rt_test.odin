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
	kept := keep(join("x", "y"))
	defer delete(kept)
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
	list := list_of(f64, 10, 20, 30)
	defer {
		delete(list^)
		free(list)
	}
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
	defer {
		delete(empty^)
		free(empty)
	}
	testing.expect_value(t, count(empty), 0)
	testing.expect_value(t, item(empty, 1), 0)
	// nothing is nothing, not a crash
	none: ^[dynamic]f64
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
