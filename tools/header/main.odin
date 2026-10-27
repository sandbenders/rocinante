// SPDX-License-Identifier: 0BSD
//
// Writes rocinante's C header from the verb registry:
//
//     odin run tools/header -- include/roci.h
//
// With no argument it prints the header. A test in package roci fails when the
// committed include/roci.h differs from what this writes, so run it after changing
// the registry or ABI_TABLE.
package header_tool

import "core:fmt"
import "core:os"
import "../../roci"

main :: proc() {
	text := roci.abi_header()
	defer delete(text)
	if len(os.args) < 2 {
		fmt.print(text)
		return
	}
	if err := os.write_entire_file(os.args[1], transmute([]u8)text); err != nil {
		fmt.eprintfln("header: cannot write %s: %v", os.args[1], err)
		os.exit(1)
	}
	fmt.printfln("header: wrote %s", os.args[1])
}
