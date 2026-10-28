// SPDX-License-Identifier: 0BSD
//
// The spike's stand-in for the core's verbs. The
// interpreter and the generated Odin both call these same procedures, which is
// what keeps their behaviour identical. The real core draws;
// this one writes a line per call, so two runs can be compared exactly.
package verbs

import "core:fmt"
import "core:strings"

// When set, output goes here instead of stdout. The spike's test sets it for
// the interpreter run; generated programs never touch it.
@(thread_local)
sink: ^strings.Builder

circle :: proc(x, y, radius: f64) {
	if sink != nil {
		fmt.sbprintfln(sink, "circle %v %v %v", x, y, radius)
	} else {
		fmt.printfln("circle %v %v %v", x, y, radius)
	}
}
