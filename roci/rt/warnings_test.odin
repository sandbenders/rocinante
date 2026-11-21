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
	use_source("print r.b\nprint r.b\n", "t.roci", []Part{{name = "t.roci", start = 0, first_line = 1}})
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
	use_source("learn v [ give HELLO ]\n", "t.roci", []Part{{name = "t.roci", start = 0, first_line = 1}})
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
