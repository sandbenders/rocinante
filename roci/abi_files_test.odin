// SPDX-License-Identifier: 0BSD
package roci

import "core:os"
import "platform"
import "core:testing"

@(test)
test_c_reads_and_writes_files_whole :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	defer abi_text_stop()
	_ = os.remove_all("output/tests/abi_files")
	testing.expect_value(t, abi_write_file("output/tests/abi_files/deep/a.txt", "one\ntwo"), 1)
	testing.expect_value(t, abi_write_file("output/tests/abi_files/b.txt", "x"), 1)
	testing.expect_value(t, string(abi_read_file("output/tests/abi_files/deep/a.txt")), "one\ntwo")
	testing.expect(t, abi_read_file("output/tests/abi_files/nothing.txt") == nil)
	// writing again replaces the file, and no half-written file is left beside it
	testing.expect_value(t, abi_write_file("output/tests/abi_files/b.txt", "yy"), 1)
	testing.expect_value(t, string(abi_read_file("output/tests/abi_files/b.txt")), "yy")
	testing.expect_value(t, abi_file_count("output/tests/abi_files"), 1) // the folder inside is not a file
	testing.expect_value(t, string(abi_file_name("output/tests/abi_files", 0)), "b.txt")
	testing.expect(t, abi_file_name("output/tests/abi_files", 1) == nil)
	testing.expect(t, abi_file_name("output/tests/abi_files", -1) == nil)
	testing.expect_value(t, abi_file_count("output/tests/abi_nothing"), 0)
	testing.expect_value(t, abi_write_file("output/tests/abi_files/b.txt/x", "no"), 0) // a file is not a folder
}

@(test)
test_c_asks_for_a_file_and_is_answered_later :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	defer abi_text_stop()
	testing.expect_value(t, abi_ask("nonsense", "", ""), 0)
	request := abi_ask("file", "png jpg", "")
	testing.expect(t, request != 0)
	// still open
	testing.expect(t, abi_answer(request) == nil)
	platform.dialog_deliver(int(request), "/home/player/photo.png")
	testing.expect_value(t, string(abi_answer(request)), "/home/player/photo.png")
	// answered once
	testing.expect_value(t, string(abi_answer(request)), "")
	closed := abi_ask("save", "json", "scores.json")
	platform.dialog_deliver(int(closed), "")
	testing.expect_value(t, string(abi_answer(closed)), "")
	testing.expect(t, abi_ask("folder", "", "") != 0)
}

@(test)
test_c_puts_text_on_the_clipboard_and_reads_it_back :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	defer abi_text_stop()
	testing.expect_value(t, abi_set_clipboard("#ff8800"), 1)
	testing.expect_value(t, string(abi_clipboard()), "#ff8800")
	// a headless sketch has no program to open anything with
	testing.expect_value(t, abi_open("https://example.org"), 0)
}
