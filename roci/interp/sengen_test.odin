// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "core:os"
import "core:testing"

@(test)
test_the_sengen_example_writes_a_new_poem_on_space_and_saves_it_on_s_and_p :: proc(t: ^testing.T) {
	p := run_text(t, example_text("sengen"), 2)
	defer finish(p)
	// Helvetica Neue Condensed Black is a Mac's font: where it is not, it is said (the words are set
	// in Inter); where it is, it is a font that is not known to be free to share. Nothing else.
	for e in p.errors {
		testing.expect(t, e.id == .Font_Missing || e.id == .Font_Licence, "an unexpected message")
	}
	sentence := proc(p: ^Interp) -> int {return len(as_list(global_named(p, "sentence")).items)}
	testing.expect_value(t, sentence(p), 5)
	testing.expect_value(t, len(as_list(global_named(p, "colors")).items), 5)
	// the size makes the widest word fit the window across, or five lines fit down
	big := as_number(global_named(p, "big"))
	testing.expect(t, big > 0 && big <= 600 / (5 * 0.71) + 1e-9, "five lines fit down the window")
	// space chooses again: five words and a size, whatever they are
	w := first_window()
	for _ in 0 ..< 3 {
		roci.step({key_event(w, .SPACE)})
		roci.step({key_event(w, .SPACE, false)})
		testing.expect_value(t, sentence(p), 5)
		testing.expect(t, as_number(global_named(p, "big")) > 0)
	}
	// s and p save the shapes, which needs no graphics
	roci.step({key_event(w, .S)})
	roci.step({key_event(w, .S, false)})
	roci.step({key_event(w, .P)})
	roci.step({key_event(w, .P, false)})
	roci.step()
	roci.step()
	testing.expect(t, os.exists("output/sengen.svg"))
	testing.expect(t, os.exists("output/sengen.pdf"))
}
