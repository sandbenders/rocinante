// SPDX-License-Identifier: 0BSD
package folder

import "core:os"
import "core:testing"

INTER :: "roci/gfx/fonts/Inter-Regular.ttf"

inter_bytes :: proc(t: ^testing.T) -> []u8 {
	bytes, err := os.read_entire_file(INTER, context.temp_allocator)
	testing.expect(t, err == nil)
	return bytes
}

// A copy of a font with the `OS/2` embedding bits set to `value`.
with_embedding :: proc(t: ^testing.T, bytes: []u8, value: u16) -> []u8 {
	copied := make([]u8, len(bytes), context.temp_allocator)
	copy(copied, bytes)
	for i in 0 ..< int(be16(copied, 4)) {
		record := 12 + i * 16
		if string(copied[record:][:4]) == "OS/2" {
			at := int(be32(copied, record + 8)) + 8
			copied[at], copied[at + 1] = u8(value >> 8), u8(value)
			return copied
		}
	}
	testing.expect(t, false, "no OS/2 table")
	return copied
}

@(test)
inters_own_fields_name_the_open_font_licence :: proc(t: ^testing.T) {
	info, ok := read_font_info(inter_bytes(t), context.temp_allocator)
	testing.expect(t, ok)
	testing.expect_value(t, info.family, "Inter")
	testing.expect(t, info.has_os2)
	testing.expect_value(t, font_licence(info), Font_Licence.Open)
	testing.expect_value(t, font_licence_name(info), "SIL Open Font License")
}

@(test)
the_restricted_embedding_bit_wins_over_a_free_licence :: proc(t: ^testing.T) {
	bytes := with_embedding(t, inter_bytes(t), 0x0002)
	info, ok := read_font_info(bytes, context.temp_allocator)
	testing.expect(t, ok)
	testing.expect_value(t, info.embedding, u16(2))
	testing.expect_value(t, font_licence(info), Font_Licence.Restricted)
}

@(test)
a_font_that_says_nothing_is_not_assumed_free :: proc(t: ^testing.T) {
	testing.expect_value(t, font_licence({copyright = "(c) Acme Type 2020. All rights reserved."}), Font_Licence.Unknown)
	testing.expect_value(t, font_licence({}), Font_Licence.Unknown)
	testing.expect_value(t, font_licence({licence = "Licensed under the Apache License, Version 2.0"}), Font_Licence.Open)
	testing.expect_value(t, font_licence({url = "https://www.apache.org/licenses/LICENSE-2.0"}), Font_Licence.Open)
	testing.expect_value(t, font_licence({licence = "Ubuntu Font Licence 1.0"}), Font_Licence.Open)
	testing.expect_value(t, font_licence({copyright = "Released into the public domain"}), Font_Licence.Open)
	testing.expect_value(t, font_licence({licence = "MIT License", embedding = 2, has_os2 = true}), Font_Licence.Restricted)
	testing.expect_value(t, font_licence({licence = "MIT License", embedding = 8, has_os2 = true}), Font_Licence.Open)
}

@(test)
words_that_forbid_sharing_win_over_a_free_licence_named_beside_them :: proc(t: ^testing.T) {
	// Windows' Segoe UI and Arial, shortened: their MIT text covers only the Hebrew layout code.
	segoe := Font_Info {
		copyright = "© 2025 Microsoft Corporation. All Rights Reserved. Hebrew OpenType Layout logic copyright © 2003 & 2007, Ralph Hancock & John Hudson. This layout logic for Biblical Hebrew is open source software under the MIT License.",
		licence   = "Microsoft supplied font. You may use this font to create, display, and print content. Any other use is prohibited.\r\n\r\nThe following license, based on the MIT license (http://en.wikipedia.org/wiki/MIT_License), applies to the OpenType Layout logic for Biblical Hebrew.",
		embedding = 8,
		has_os2   = true,
	}
	testing.expect_value(t, font_licence(segoe), Font_Licence.Restricted)
	for words in ([]string{"This font may not be redistributed.", "You MAY NOT REDISTRIBUTE it.", "Redistribution is prohibited.", "Redistribution is not permitted."}) {
		testing.expectf(t, font_licence({licence = words, url = "https://opensource.org/licenses/MIT"}) == .Restricted, "`%s` forbids sharing", words)
	}
	// a free licence that speaks of redistribution in its own words stays free
	testing.expect_value(t, font_licence({licence = "This Font Software is licensed under the SIL Open Font License, Version 1.1. Redistribution and use in source and binary forms are permitted."}), Font_Licence.Open)
}

@(test)
the_licence_name_comes_from_the_fields :: proc(t: ^testing.T) {
	testing.expect_value(t, font_licence_name({licence = "Apache License 2.0"}), "Apache License")
	testing.expect_value(t, font_licence_name({licence = "Ubuntu Font Licence 1.0"}), "Ubuntu Font Licence")
	testing.expect_value(t, font_licence_name({licence = "MIT License"}), "MIT License")
	testing.expect_value(t, font_licence_name({licence = "public domain"}), "a free licence")
}

@(test)
bytes_that_are_not_a_font_are_not_read :: proc(t: ^testing.T) {
	_, ok := read_font_info(transmute([]u8)string("not a font at all"), context.temp_allocator)
	testing.expect(t, !ok)
	_, ok = read_font_info({}, context.temp_allocator)
	testing.expect(t, !ok)
	// a collection whose first font is beyond the end of the file
	_, ok = read_font_info(transmute([]u8)string("ttcf\x00\x01\x00\x00\x00\x00\x00\x01\x00\x00\xff\xff"), context.temp_allocator)
	testing.expect(t, !ok)
	// a font cut short in its table directory, and one with no name table
	bytes := inter_bytes(t)
	_, ok = read_font_info(bytes[:40], context.temp_allocator)
	testing.expect(t, !ok)
	_, ok = read_font_info(transmute([]u8)string("\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"), context.temp_allocator)
	testing.expect(t, !ok)
}

@(test)
installed_fonts_are_found_by_a_name_spelled_loosely :: proc(t: ^testing.T) {
	root :: "output/tests/system_fonts_find"
	_ = os.remove_all(root)
	testing.expect(t, ensure_directory(root + "/nested/deeper"))
	for file in ([]string{"Helvetica Neue.ttc", "Mono-Regular.otf", "Mono-Bold.otf", "nested/deeper/Deep Font.TTF", "Notes.txt", "Other.woff"}) {
		testing.expect(t, os.write_entire_file(concat_path(root, file), transmute([]u8)string("x")) == nil)
	}
	system_font_dirs = {"output/tests/no_such_dir", root}
	defer system_font_dirs = nil

	path, found := find_system_font("helvetica-neue")
	testing.expect(t, found)
	testing.expect_value(t, path, root + "/Helvetica Neue.ttc")
	path, found = find_system_font("Mono")
	testing.expect(t, found, "the name and Regular")
	testing.expect_value(t, path, root + "/Mono-Regular.otf")
	path, found = find_system_font("Deep Font")
	testing.expect(t, found, "folders are searched down, and a capital extension counts")
	testing.expect_value(t, path, root + "/nested/deeper/Deep Font.TTF")
	path, found = find_system_font("Mono Bold")
	testing.expect(t, found, "a style asked for by its own file name")
	testing.expect_value(t, path, root + "/Mono-Bold.otf")
	_, found = find_system_font("Mon")
	testing.expect(t, !found, "a part of a name is not a name")
	_, found = find_system_font("Notes")
	testing.expect(t, !found, "not a font file")
	_, found = find_system_font("Other")
	testing.expect(t, !found, "a type that is not read")
	_, found = find_system_font("Missing")
	testing.expect(t, !found)
	_, found = find_system_font("")
	testing.expect(t, !found)
	_, found = find_system_font("  --  ")
	testing.expect(t, !found)
}

@(test)
an_exact_name_wins_over_name_and_regular_even_in_a_later_folder :: proc(t: ^testing.T) {
	root :: "output/tests/system_fonts_exact"
	_ = os.remove_all(root)
	testing.expect(t, ensure_directory(root + "/a"))
	testing.expect(t, ensure_directory(root + "/b"))
	testing.expect(t, os.write_entire_file(root + "/a/Face-Regular.ttf", transmute([]u8)string("x")) == nil)
	testing.expect(t, os.write_entire_file(root + "/b/Face.otf", transmute([]u8)string("x")) == nil)
	system_font_dirs = {root + "/a", root + "/b"}
	defer system_font_dirs = nil
	path, found := find_system_font("Face")
	testing.expect(t, found)
	testing.expect_value(t, path, root + "/b/Face.otf")
}

@(test)
the_default_places_are_named_for_this_system :: proc(t: ^testing.T) {
	testing.expect(t, len(default_font_dirs()) >= 1)
	testing.expect_value(t, font_extension("a/b/Font.TTC"), ".ttc")
	testing.expect_value(t, font_extension("nodot"), "")
}

concat_path :: proc(root, file: string) -> string {
	return os.join_path({root, file}, context.temp_allocator) or_else ""
}
