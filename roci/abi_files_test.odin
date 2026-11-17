// SPDX-License-Identifier: 0BSD
package roci

import "core:os"
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
