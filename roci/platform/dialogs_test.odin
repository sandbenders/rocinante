// SPDX-License-Identifier: 0BSD
package platform

import "core:testing"

@(test)
test_a_pattern_is_the_extensions_joined_by_semicolons :: proc(t: ^testing.T) {
	testing.expect_value(t, dialog_pattern("png jpg"), "png;jpg")
	testing.expect_value(t, dialog_pattern(".png, *.JPG"), "png;JPG")
	testing.expect_value(t, dialog_pattern("  "), "")
	testing.expect_value(t, dialog_pattern(""), "")
	testing.expect_value(t, dialog_pattern("tar.gz"), "tar;gz")
	testing.expect_value(t, dialog_pattern("a-b_c"), "a-b_c")
}

@(test)
test_a_request_waits_until_it_is_answered :: proc(t: ^testing.T) {
	id := dialog_new()
	testing.expect_value(t, dialog_take(id).state, Dialog_State.Waiting)
	dialog_deliver(id, "/tmp/photo.png")
	got := dialog_take(id)
	defer delete(got.path)
	testing.expect_value(t, got.state, Dialog_State.Chosen)
	testing.expect_value(t, got.path, "/tmp/photo.png")
	// taken once: it is gone
	testing.expect_value(t, dialog_take(id).state, Dialog_State.Closed)
}

@(test)
test_a_dialog_closed_without_a_choice_says_so :: proc(t: ^testing.T) {
	id := dialog_new()
	dialog_deliver(id, "")
	got := dialog_take(id)
	testing.expect_value(t, got.state, Dialog_State.Closed)
	testing.expect_value(t, got.path, "")
}

@(test)
test_the_first_answer_stands_and_numbers_are_not_shared :: proc(t: ^testing.T) {
	a, b := dialog_new(), dialog_new()
	testing.expect(t, a != b)
	dialog_deliver(a, "one")
	dialog_deliver(a, "two")
	dialog_deliver(9999999, "nobody")
	testing.expect_value(t, dialog_take(b).state, Dialog_State.Waiting)
	got := dialog_take(a)
	defer delete(got.path)
	testing.expect_value(t, got.path, "one")
	dialog_deliver(b, "")
	dialog_take(b)
}
