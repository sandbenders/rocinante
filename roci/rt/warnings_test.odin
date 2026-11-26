// SPDX-License-Identifier: 0BSD
package rt

import "../lang"
import "core:fmt"
import "core:testing"

@(private = "file")
Pair :: struct {
	unset__: u64,
	a:       f64,
	b:       f64,
}

@(test)
test_a_field_a_record_was_made_without_is_said_once_when_it_is_read :: proc(t: ^testing.T) {
	forget_said()
	defer forget_said()
	defer forget_source()
	parts := make([]Part, 1, context.temp_allocator)
	parts[0] = Part{name = "t.roci", start = 0, first_line = 1}
	use_source("print r.b\nprint r.b\n", "t.roci", parts)
	site := Site{start = 6, end = 9, name = "b", fields = "a,b"}
	other := Site{start = 16, end = 19, name = "b", fields = "a,b"}
	whole := Pair{a = 1, b = 2}
	left_out := Pair{unset__ = 2, a = 1}
	// a record with the field is read and says nothing; one without it is read, said once at a place, and read again
	testing.expect_value(t, checked(&whole, 2, &site).b, 2)
	testing.expect(t, !(said != nil && said[fmt.tprintf("warning %d at %d", int(lang.Message_Id.Field_Missing), 6)]))
	testing.expect_value(t, checked(&left_out, 2, &site).b, 0)
	testing.expect_value(t, checked(&left_out, 2, &site).b, 0)
	testing.expect(t, said[fmt.tprintf("warning %d at %d", int(lang.Message_Id.Field_Missing), 6)], "said at the first place")
	testing.expect(t, !said[fmt.tprintf("warning %d at %d", int(lang.Message_Id.Field_Missing), 16)], "not yet at the other")
	checked(&left_out, 2, &other)
	testing.expect(t, said[fmt.tprintf("warning %d at %d", int(lang.Message_Id.Field_Missing), 16)], "each place says it once")
	// the field that was given is read with no word
	left_out.unset__ = 0
	testing.expect_value(t, checked(&left_out, 2, &site).a, 1)
}

@(test)
test_a_constant_not_yet_made_is_said_once_and_still_read :: proc(t: ^testing.T) {
	forget_said()
	defer forget_said()
	defer forget_source()
	parts := make([]Part, 1, context.temp_allocator)
	parts[0] = Part{name = "t.roci", start = 0, first_line = 1}
	use_source("learn v [ give HELLO ]\n", "t.roci", parts)
	site := Site{start = 16, end = 21, name = "HELLO"}
	testing.expect(t, constant_made(true, &site))
	testing.expect(t, said == nil || !said[fmt.tprintf("warning %d at %d", int(lang.Message_Id.Constant_Not_Made), 16)])
	testing.expect(t, constant_made(false, &site)) // it is read all the same
	testing.expect(t, said[fmt.tprintf("warning %d at %d", int(lang.Message_Id.Constant_Not_Made), 16)])
	// a program that has no text of its sketch says nothing
	forget_source()
	forget_said()
	testing.expect(t, constant_made(false, &site))
	testing.expect(t, said == nil || !said[fmt.tprintf("warning %d at %d", int(lang.Message_Id.Constant_Not_Made), 16)])
}

@(test)
test_a_constant_read_gives_its_value_with_its_own_type :: proc(t: ^testing.T) {
	forget_said()
	defer forget_said()
	site := Site{start = 0, end = 1, name = "WIDE"}
	wide := 12.5
	testing.expect_value(t, constant_read(wide, false, &site), 12.5)
	width: Maybe(f64) = constant_read(wide, true, &site) * 2 // a number where the place takes an optional one
	testing.expect_value(t, width, 25.0)
}

@(test)
test_a_division_by_zero_is_said_once_for_a_place_and_gives_0 :: proc(t: ^testing.T) {
	forget_said()
	defer forget_said()
	defer forget_source()
	parts := make([]Part, 1, context.temp_allocator)
	parts[0] = Part{name = "t.roci", start = 0, first_line = 1}
	text := "w = 600 / n\n"
	use_source(text, "t.roci", parts)
	site := Site{start = 4, end = 11, name = "n"}
	key := fmt.tprintf("warning %d at %d", int(lang.Message_Id.Division_By_Zero), 4)
	testing.expect_value(t, divide_at(6, 3, &site), 2.0)
	testing.expect(t, said == nil || !said[key]) // a divisor that is not 0 says nothing
	testing.expect_value(t, divide_at(6, 0, &site), 0.0)
	testing.expect(t, said[key])
	testing.expect_value(t, modulo_at(7, 0, &site), 0.0)
	testing.expect_value(t, modulo_at(7, 4, &site), 3.0)
	// vectors and boxes say it for a part of the divisor
	forget_said()
	testing.expect_value(t, divide_vector_at([2]f64{4, 4}, [2]f64{2, 0}, &site), [2]f64{2, 0})
	testing.expect(t, said[key])
	forget_said()
	testing.expect_value(t, divide_vector_by_at([2]f64{4, 4}, 0, &site), [2]f64{0, 0})
	testing.expect(t, said[key])
	forget_said()
	testing.expect_value(t, box_arith(.Divide, Box(f64(8)), Box(f64(0)), &site).(f64), 0.0)
	testing.expect(t, said[key])
	forget_said()
	box_arith(.Divide, Box([2]f64{1, 1}), Box(f64(2)), &site)
	box_arith(.Divide, Box(f64(8)), Box(f64(2)), &site)
	box_arith(.Multiply, Box(f64(8)), Box(f64(0)), &site)
	testing.expect(t, said == nil || !said[key]) // a divisor of 0 is only a fault for a division
	// a program that has no text of its sketch says nothing
	forget_source()
	forget_said()
	testing.expect_value(t, divide_at(6, 0, &site), 0.0)
	testing.expect(t, said == nil || !said[key])
}
