// SPDX-License-Identifier: 0BSD
//
// libcurl and the TLS it uses, built as static libraries by tools/net-libs.sh into .cache/net. Every program
// that can fetch an address links them, and `roci` is one.
package build

import "core:fmt"
import "core:os"

import "../tools/term"

NET_LIBRARY :: ".cache/net/lib/libcurl.a" when ODIN_OS != .Windows else ".cache/net/lib/libcurl.lib"
NET_STAMP :: ".cache/net/" + STAMP_FILE

// The stamp of what the libraries are made from: the scripts that fetch (with their checksums) and build them.
net_sources_stamp :: proc() -> string {
	return sources_stamp({"tools/net-libs.sh", "tools/fetch-net.sh"}, nil)
}

// Builds the libraries (`net-libs`).
net_libs :: proc() -> bool {
	state, stdout, stderr, err := os.process_exec({command = {"sh", "tools/net-libs.sh"}}, context.allocator)
	fmt.print(string(stdout))
	if err != nil || state.exit_code != 0 {
		fmt.eprint(string(stderr))
		fmt.eprintfln("%s", term.err("net-libs failed", .Bold_Red))
		return false
	}
	stamp_write(NET_STAMP, net_sources_stamp())
	return true
}

// Builds the libraries before the packages are checked when they are missing or what they are made from has
// changed (a clone or a cache that has them for the scripts as they are now skips this).
check_net :: proc() -> bool {
	if os.exists(NET_LIBRARY) && stamp_matches(NET_STAMP, net_sources_stamp()) {
		return true
	}
	fmt.printfln("%s", term.out("== building libcurl and its TLS (tools/net-libs.sh)", .Bold_Cyan))
	return net_libs()
}
