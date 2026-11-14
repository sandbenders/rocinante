// SPDX-License-Identifier: 0BSD
package soundfont_tool

import "core:os"
import "core:testing"

import "../../roci/audio"

// tests/sounds/tiny.sf2 is what this tool writes, byte for byte, so a change to the writer or the
// font shows here: `odin run tools/soundfont -- tiny` writes it again.
@(test)
test_tiny_font_is_up_to_date :: proc(t: ^testing.T) {
	made := tiny_font()
	defer delete(made)
	stored, err := os.read_entire_file(TINY_PATH, context.temp_allocator)
	testing.expect_value(t, err, nil)
	testing.expect(t, string(made) == string(stored), "tests/sounds/tiny.sf2 is out of date: odin run tools/soundfont -- tiny")
	free_all(context.temp_allocator)
}

// What the writer writes, the reader reads back as it was written.
@(test)
test_written_font_reads_back :: proc(t: ^testing.T) {
	made := tiny_font()
	defer delete(made)
	font, ok := audio.font_read(made)
	defer audio.font_destroy(font)
	testing.expect(t, ok)
	testing.expect_value(t, len(font.presets), 3)
	testing.expect_value(t, len(font.samples), 1000 + 46 + 4400 + 46)
	testing.expect_value(t, font.presets[0].regions[0].loop_end - font.presets[0].regions[0].loop_start, 1000)
	free_all(context.temp_allocator)
}
