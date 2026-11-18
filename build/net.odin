// SPDX-License-Identifier: 0BSD
//
// libcurl and the TLS it uses, built as static libraries by tools/net-libs.sh into .cache/net. Every program
// that can fetch an address links them, and `roci` is one.
package build

import "core:fmt"
import "core:os"
import "core:time"

import "../tools/term"

NET_LIBRARY :: ".cache/net/lib/libcurl.a" when ODIN_OS != .Windows else ".cache/net/lib/libcurl.lib"

// Builds the libraries (`net-libs`).
net_libs :: proc() -> bool {
	state, stdout, stderr, err := os.process_exec({command = {"sh", "tools/net-libs.sh"}}, context.allocator)
	fmt.print(string(stdout))
	if err != nil || state.exit_code != 0 {
		fmt.eprint(string(stderr))
		fmt.eprintfln("%s", term.err("net-libs failed", .Bold_Red))
		return false
	}
	return true
}

// Builds the libraries before the packages are checked when they are missing or older than the scripts that
// make them (a clone that has built them since the scripts last changed skips this).
check_net :: proc() -> bool {
	if os.exists(NET_LIBRARY) {
		library, library_err := os.stat(NET_LIBRARY, context.temp_allocator)
		fresh := library_err == nil
		for name in ([]string{"tools/net-libs.sh", "tools/fetch-net.sh"}) {
			source, source_err := os.stat(name, context.temp_allocator)
			if source_err == nil && time.diff(source.modification_time, library.modification_time) < 0 {
				fresh = false
			}
		}
		if fresh {
			return true
		}
	}
	fmt.printfln("%s", term.out("== building libcurl and its TLS (tools/net-libs.sh)", .Bold_Cyan))
	return net_libs()
}
