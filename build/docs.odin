// SPDX-License-Identifier: 0BSD
//
// `docs`: the documentation site. tools/site writes Hugo's source into output/site
// (the reference and the messages from the registry and the catalogue, every
// example's picture, the guides with their code coloured), then Hugo builds it into
// output/site/public. Hugo is a build tool only, pinned in HUGO_VERSION like Odin.
package build

import "core:fmt"
import "core:os"
import "core:strings"

import "../tools/term"

SITE_SOURCE :: "output/site"

docs :: proc() -> bool {
	ok := check_hugo()
	if !ok {
		return false
	}
	// The pictures are drawn by the real renderer, so the tool runs optimised.
	ok = step("write the site's source", {"odin", "run", "tools/site", "-o:speed", fmt.tprintf("-out:%s/site-tool%s", TEST_OUT_DIR, EXE), "--", SITE_SOURCE})
	if !ok {
		return false
	}
	ok = step("build the site with Hugo", {"hugo", "--source", SITE_SOURCE, "--destination", "public", "--minify", "--cleanDestinationDir"})
	if ok {
		fmt.printfln("%s%s", term.out_icon(.Ok), term.out(fmt.tprintf("docs: built %s/public; preview it with: hugo server --source %s", SITE_SOURCE, SITE_SOURCE), .Bold_Green))
	}
	return ok
}

// The pinned Hugo lives in HUGO_VERSION. As with Odin, another version is a warning
// on a developer's machine and an error in the pipelines, which set CI.
check_hugo :: proc() -> bool {
	data, read_err := os.read_entire_file("HUGO_VERSION", context.allocator)
	if read_err != nil {
		fmt.eprintfln("%s", term.err(fmt.tprintf("cannot read HUGO_VERSION: %v", read_err), .Bold_Red))
		return false
	}
	pinned := strings.trim_space(string(data))
	state, stdout, _, err := os.process_exec({command = {"hugo", "version"}}, context.allocator)
	if err != nil || state.exit_code != 0 {
		fmt.eprintfln("%s Hugo is needed to build the documentation, and it is not installed. Get version %s from https://github.com/gohugoio/hugo/releases/tag/v%s (Arch: pacman -S hugo; macOS: brew install hugo; FreeBSD: pkg install gohugo).", term.err("hugo:", .Bold_Red), pinned, pinned)
		return false
	}
	have := strings.trim_space(string(stdout))
	if hugo_version_matches(have, pinned) {
		fmt.printfln("%s %s", term.out("hugo:", .Bold), term.out(fmt.tprintf("ok (%s)", pinned), .Green))
		return true
	}
	fmt.eprintfln("%s the documentation is pinned to Hugo %s, but you have '%s'.", term.err("hugo:", .Bold_Red), pinned, have)
	if os.get_env("CI", context.temp_allocator) != "" {
		return false
	}
	fmt.eprintfln("%s continuing, because this is not a pipeline.", term.err("hugo:", .Yellow))
	return true
}

// `hugo v0.169.0-6ba4366+extended linux/amd64 ...` is version 0.169.0.
hugo_version_matches :: proc(output, pinned: string) -> bool {
	return strings.contains(output, fmt.tprintf("v%s-", pinned)) || strings.contains(output, fmt.tprintf("v%s ", pinned))
}
