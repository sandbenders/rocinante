// SPDX-License-Identifier: 0BSD
package lang

import "core:encoding/json"
import "core:strings"
import "core:testing"

@(test)
test_json_escapes_what_json_needs_escaped :: proc(t: ^testing.T) {
	testing.expect_value(t, json_escape("a\"b\\c\nd\te\x01"), "a\\\"b\\\\c\\nd\\te\\u0001")
	testing.expect_value(t, json_escape("héllo"), "héllo")
}

@(test)
test_a_diagnostic_is_one_line_of_valid_json_with_its_place_and_id :: proc(t: ^testing.T) {
	parsed := check_text("circel at 1 1 radius 5\n")
	text := diagnostics_json(parsed.src, parsed.checked.diagnostics)
	testing.expect(t, strings.count(text, "\n") == len(parsed.checked.diagnostics))
	line := strings.split_lines(text, context.temp_allocator)[0]
	value, err := json.parse(transmute([]byte)line, parse_integers = true, allocator = context.temp_allocator)
	testing.expect_value(t, err, json.Error.None)
	object := value.(json.Object)
	testing.expect_value(t, object["id"].(json.String), "unknown_word")
	testing.expect_value(t, object["line"].(json.Integer), 1)
	testing.expect_value(t, object["column"].(json.Integer), 1)
	testing.expect_value(t, object["severity"].(json.String), "error")
	testing.expect_value(t, object["runtime"].(json.Boolean), false)
	testing.expect(t, strings.contains(object["example"].(json.String), "circle"))
}

@(test)
test_a_sketch_with_no_diagnostics_gives_no_lines :: proc(t: ^testing.T) {
	parsed := check_text("circle at 1 1 radius 5\n")
	testing.expect_value(t, diagnostics_json(parsed.src, parsed.checked.diagnostics), "")
}

@(test)
test_the_plain_message_has_the_place_the_source_line_and_the_example :: proc(t: ^testing.T) {
	parsed := check_text("circel at 1 1 radius 5\n")
	title, lines := plain_message(parsed.src, parsed.checked.diagnostics[0])
	testing.expect(t, strings.contains(title, "circel"))
	testing.expect_value(t, lines[0], "sketch.roci:1:1")
	testing.expect_value(t, lines[1], "1 | circel at 1 1 radius 5")
	for l in lines {
		for r in l {
			testing.expectf(t, r < 0x80, "non-ASCII character in %q", l)
		}
	}
}
