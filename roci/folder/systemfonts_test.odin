// SPDX-License-Identifier: 0BSD
package folder

import "core:fmt"
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

INTER_BOLD :: "roci/gfx/fonts/Inter-Bold.ttf"

@(test)
a_fonts_names_are_read_without_reading_the_whole_file :: proc(t: ^testing.T) {
	info, ok := read_font_names(INTER)
	testing.expect(t, ok)
	testing.expect_value(t, info.family, "Inter")
	testing.expect_value(t, info.style, "Regular")
	whole, whole_ok := read_font_info(inter_bytes(t), context.temp_allocator)
	testing.expect(t, whole_ok)
	testing.expect_value(t, whole.family, info.family)
	testing.expect_value(t, whole.style, info.style)
	testing.expect_value(t, whole.licence, info.licence)

	bold, bold_ok := read_font_names(INTER_BOLD)
	testing.expect(t, bold_ok)
	testing.expect_value(t, simple_name(bold.style), "bold")

	root :: "output/tests/system_fonts_names"
	_ = os.remove_all(root)
	testing.expect(t, ensure_directory(root))
	// a collection: Inter's table directory copied to the end, and a header that points at it
	bytes := inter_bytes(t)
	directory := 12 + int(be16(bytes, 4)) * 16
	collection := make([]u8, len(bytes) + directory, context.temp_allocator)
	copy(collection, bytes)
	copy(collection[len(bytes):], bytes[:directory])
	copy(collection[:16], "ttcf\x00\x01\x00\x00\x00\x00\x00\x01")
	at := u32(len(bytes))
	collection[12], collection[13], collection[14], collection[15] = u8(at >> 24), u8(at >> 16), u8(at >> 8), u8(at)
	testing.expect(t, os.write_entire_file(concat_path(root, "inter.ttc"), collection) == nil)
	in_collection, collection_ok := read_font_names(concat_path(root, "inter.ttc"))
	testing.expect(t, collection_ok)
	testing.expect_value(t, in_collection.family, "Inter")

	// not fonts: missing, too short, another kind of file, a directory cut short, no name table
	_, ok = read_font_names(concat_path(root, "missing.ttf"))
	testing.expect(t, !ok)
	cases := [][]u8{
		transmute([]u8)string("short"),
		transmute([]u8)string("not a font, but long enough"),
		bytes[:40],
		transmute([]u8)string("\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"),
		transmute([]u8)string("ttcf\x00\x01\x00\x00\x00\x00\x00\x01\x00\x00\xff\xff"),
	}
	for c, i in cases {
		path := concat_path(root, fmt.tprintf("bad%d.ttf", i))
		testing.expect(t, os.write_entire_file(path, c) == nil)
		_, bad_ok := read_font_names(path)
		testing.expectf(t, !bad_ok, "case %d is not a font", i)
	}
}

@(test)
an_installed_font_is_found_by_its_family_when_its_file_is_named_otherwise :: proc(t: ^testing.T) {
	root :: "output/tests/system_fonts_family"
	_ = os.remove_all(root)
	testing.expect(t, ensure_directory(root + "/sub"))
	regular, _ := os.read_entire_file(INTER, context.temp_allocator)
	bold, _ := os.read_entire_file(INTER_BOLD, context.temp_allocator)
	// the bold comes first by name, and a file that only looks like a font is passed over
	testing.expect(t, os.write_entire_file(root + "/a.ttf", bold) == nil)
	testing.expect(t, os.write_entire_file(root + "/b.ttf", transmute([]u8)string("x")) == nil)
	testing.expect(t, os.write_entire_file(root + "/sub/c.otf", regular) == nil)
	system_font_dirs = {root}
	defer system_font_dirs = nil

	path, found := find_system_font("Inter")
	testing.expect(t, found)
	testing.expect_value(t, path, root + "/sub/c.otf")
	_, found = find_system_font("Intern")
	testing.expect(t, !found)

	// with no regular, any style of the family answers
	testing.expect(t, os.remove(root + "/sub/c.otf") == nil)
	path, found = find_system_font("inter")
	testing.expect(t, found)
	testing.expect_value(t, path, root + "/a.ttf")

	// a file named for the font still wins over a family found inside another
	testing.expect(t, os.write_entire_file(root + "/Inter.ttf", regular) == nil)
	path, found = find_system_font("Inter")
	testing.expect(t, found)
	testing.expect_value(t, path, root + "/Inter.ttf")
}

// A collection of Inter Bold, then Inter Regular, so Regular is the second face.
bold_then_regular :: proc(t: ^testing.T) -> []u8 {
	bold, err := os.read_entire_file(INTER_BOLD, context.temp_allocator)
	testing.expect(t, err == nil)
	collection := join_fonts({bold, inter_bytes(t)}, context.temp_allocator)
	testing.expect(t, collection != nil)
	return collection
}

@(test)
a_collection_made_of_fonts_has_a_face_for_each_and_works_as_a_font :: proc(t: ^testing.T) {
	collection := bold_then_regular(t)
	offsets := face_offsets(collection)
	testing.expect_value(t, len(offsets), 2)
	testing.expect_value(t, len(face_offsets(inter_bytes(t))), 1)
	first, first_ok := face_info_at(collection, offsets[0], context.temp_allocator)
	second, second_ok := face_info_at(collection, offsets[1], context.temp_allocator)
	testing.expect(t, first_ok && second_ok)
	testing.expect_value(t, simple_name(first.style), "bold")
	testing.expect_value(t, simple_name(second.style), "regular")
	// the first font is what read_font_info reads, and the face number says which
	info, ok := read_font_info(collection, context.temp_allocator)
	testing.expect(t, ok)
	testing.expect_value(t, simple_name(info.style), "bold")
	info, ok = read_font_info(collection, context.temp_allocator, 1)
	testing.expect(t, ok)
	testing.expect_value(t, simple_name(info.style), "regular")
	testing.expect(t, join_fonts(nil) == nil)
	testing.expect(t, join_fonts({[]u8{1, 2}}) == nil)
}

@(test)
a_face_is_found_by_its_full_postscript_or_family_and_style_name :: proc(t: ^testing.T) {
	collection := bold_then_regular(t)
	for name in ([?]string{"Inter Bold", "Inter-Bold", "inter bold", "InterBold"}) {
		index, found := face_named(collection, name)
		testing.expectf(t, found && index == 0, "%s: %d %v", name, index, found)
	}
	for name in ([?]string{"Inter Regular", "Inter-Regular", "Inter"}) {
		index, found := face_named(collection, name)
		testing.expectf(t, found && index == 1, "%s: %d %v", name, index, found)
	}
	_, found := face_named(collection, "Inter Black")
	testing.expect(t, !found)
	_, found = face_named(collection, "")
	testing.expect(t, !found)
	// a plain font is one face
	index, plain := face_named(inter_bytes(t), "Inter Regular")
	testing.expect(t, plain && index == 0)
}

@(test)
a_face_goes_by_the_names_a_font_gives_it :: proc(t: ^testing.T) {
	info := Font_Info{family = "Helvetica Neue", style = "Bold", full = "Helvetica Neue Bold", postscript = "HelveticaNeue-Bold"}
	for name in ([?]string{"Helvetica Neue Bold", "helveticaneuebold", "HelveticaNeue-Bold"}) {
		testing.expectf(t, face_goes_by(info, simple_name(name)), "%s", name)
	}
	testing.expect(t, !face_goes_by(info, simple_name("Helvetica Neue")), "a bold face is not the plain family")
	testing.expect(t, !face_goes_by(info, ""))
	// the family alone names its regular face, or a face with no style
	regular := Font_Info{family = "Helvetica Neue", style = "Regular"}
	testing.expect(t, face_goes_by(regular, "helveticaneue"))
	testing.expect(t, face_goes_by(Font_Info{family = "Mono"}, "mono"))
	// a family that groups styles (id 1) and the typographic one (id 16 and 17)
	condensed := Font_Info{family = "Helvetica Neue Condensed", style = "Black", typo_family = "Helvetica Neue", typo_style = "Condensed Black"}
	testing.expect(t, face_goes_by(condensed, "helveticaneuecondensedblack"))
	testing.expect(t, !face_goes_by(condensed, "helveticaneue"))
}

@(test)
an_installed_collection_is_found_by_the_name_of_one_of_its_faces :: proc(t: ^testing.T) {
	root :: "output/tests/system_fonts_faces"
	_ = os.remove_all(root)
	testing.expect(t, ensure_directory(root))
	testing.expect(t, os.write_entire_file(concat_path(root, "Pair.ttc"), bold_then_regular(t)) == nil)
	system_font_dirs = {root}
	defer system_font_dirs = nil
	// Inter Regular is no file name, and no first face of anything: the second face of Pair.ttc
	path, found := find_system_font("Inter Regular")
	testing.expect(t, found)
	// The search joins with a forward slash on every system, Windows too.
	testing.expect_value(t, path, root + "/Pair.ttc")
	_, found = find_system_font("Inter Black")
	testing.expect(t, !found)
	testing.expect(t, is_collection_name("a/b/Pair.TTC") && is_collection_name("x.otc"))
	testing.expect(t, !is_collection_name("x.ttf") && !is_collection_name("ttc"))
}

@(test)
the_names_of_every_face_of_a_collection_are_read_without_reading_the_whole_file :: proc(t: ^testing.T) {
	root :: "output/tests/system_fonts_all_faces"
	_ = os.remove_all(root)
	testing.expect(t, ensure_directory(root))
	testing.expect(t, os.write_entire_file(concat_path(root, "pair.ttc"), bold_then_regular(t)) == nil)
	faces := read_collection_names(concat_path(root, "pair.ttc"))
	if testing.expect_value(t, len(faces), 2) {
		testing.expect_value(t, simple_name(faces[0].style), "bold")
		testing.expect_value(t, simple_name(faces[1].style), "regular")
		testing.expect_value(t, faces[1].full, "Inter Regular")
	}
	// a plain font is one face; something that is not a font, or not there, none
	testing.expect_value(t, len(read_collection_names(INTER)), 1)
	testing.expect_value(t, len(read_collection_names("output/tests/there-is-no-font.ttc")), 0)
	testing.expect(t, os.write_entire_file(concat_path(root, "text.ttc"), transmute([]u8)string("not a font at all, only text")) == nil)
	testing.expect_value(t, len(read_collection_names(concat_path(root, "text.ttc"))), 0)
}
