// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "../gfx"
import "../folder"
import "../lang"
import "core:os"
import "core:testing"

typeset_commands :: proc() -> [dynamic]gfx.Command {
	found: [dynamic]gfx.Command
	for c in roci.recorded(first_window()) {
		if c.kind == .Typeset {
			append(&found, c)
		}
	}
	return found
}

@(test)
test_text_draws_real_text_at_its_point :: proc(t: ^testing.T) {
	p := run_text(t, "text \"hello\" at 20 30")
	defer finish(p)
	found := typeset_commands()
	defer delete(found)
	if testing.expect_value(t, len(found), 1) {
		testing.expect_value(t, [2]f32{found[0].args[0], found[0].args[1]}, [2]f32{20, 30})
		testing.expect(t, found[0].args[3] > 0, "it has a width")
	}
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_text_words_style_one_text_and_font_and_align_stick :: proc(t: ^testing.T) {
	p := run_text(t, "text \"a\" at 1 1 size 50 font \"Inter Bold\" align right fill red\nfont \"Inter Bold\" size 33\nalign center\ntext \"b\" at 2 2")
	defer finish(p)
	found := typeset_commands()
	defer delete(found)
	if testing.expect_value(t, len(found), 2) {
		testing.expect_value(t, found[0].style.font_size, f32(50))
		testing.expect_value(t, found[0].style.align, gfx.Align.Right)
		testing.expect_value(t, found[0].style.font, gfx.FACE_BOLD)
		testing.expect_value(t, found[1].style.font_size, f32(33))
		testing.expect_value(t, found[1].style.align, gfx.Align.Center)
	}
}

@(test)
test_a_width_wraps_the_text :: proc(t: ^testing.T) {
	p := run_text(t, "text \"a long line that has to wrap\" at 0 0 width 70")
	defer finish(p)
	found := typeset_commands()
	defer delete(found)
	if testing.expect_value(t, len(found), 1) {
		testing.expect_value(t, found[0].args[2], f32(70))
	}
}

@(test)
test_text_at_a_vector_and_text_made_from_a_calculation :: proc(t: ^testing.T) {
	p := run_text(t, "p = { 5, 6 }\nn = 3\ntext (\"n is \" + n) at p")
	defer finish(p)
	found := typeset_commands()
	defer delete(found)
	if testing.expect_value(t, len(found), 1) {
		testing.expect_value(t, [2]f32{found[0].args[0], found[0].args[1]}, [2]f32{5, 6})
	}
}

@(test)
test_measure_gives_a_vector_that_follows_the_font_size :: proc(t: ^testing.T) {
	expect_printed(t, "a = measure \"hello\"\nfont \"Inter\" size 80\nb = measure \"hello\"\nprint (a.x > 0)\nprint (b.x > a.x * 2)\nprint (b.y > a.y)", "true\ntrue\ntrue")
}

@(test)
test_leading_is_a_verb_and_a_word_of_text_and_measure_follows_it :: proc(t: ^testing.T) {
	expect_printed(t, "a = measure \"a\\nb\\nc\"\nleading 2\nb = measure \"a\\nb\\nc\"\nleading 0\nc = measure \"a\\nb\\nc\"\nprint (b.y > a.y)\nprint (c.y is a.y)", "true\ntrue")
	p := run_text(t, "text \"x\" at 1 1 leading 1.5\ntext \"y\" at 2 2")
	defer finish(p)
	found := typeset_commands()
	defer delete(found)
	if testing.expect_value(t, len(found), 2) {
		testing.expect_value(t, found[0].style.leading, f32(1.5))
		testing.expect_value(t, found[1].style.leading, f32(0))
	}
}

@(test)
test_an_unknown_font_is_said_once_and_the_text_still_draws :: proc(t: ^testing.T) {
	p := run_text(t, "font \"No Such Font\"\ntext \"x\" at 1 1 font \"Nor This\"\ntext \"y\" at 2 2 font \"Nor This\"")
	defer finish(p)
	testing.expect_value(t, len(p.errors), 3)
	for e in p.errors {
		testing.expect_value(t, e.id, lang.Message_Id.Font_Missing)
	}
	found := typeset_commands()
	defer delete(found)
	testing.expect_value(t, len(found), 2)
}

@(test)
test_a_font_file_in_the_sketchs_assets_is_found_by_name :: proc(t: ^testing.T) {
	root := "output/tests/font_sketch"
	_ = os.make_directory_all("output/tests/font_sketch/assets/fonts")
	testing.expect(t, os.write_entire_file("output/tests/font_sketch/assets/fonts/Mine.ttf", gfx.INTER_REGULAR) == nil)
	testing.expect(t, os.write_entire_file("output/tests/font_sketch/assets/fonts/Other.otf", gfx.INTER_BOLD) == nil)
	testing.expect(t, os.write_entire_file("output/tests/font_sketch/assets/fonts/Broken.ttf", transmute([]byte)string("not a font")) == nil)
	path := "output/tests/font_sketch/sketch.roci"
	text := "font \"Mine\"\ntext \"a\" at 1 1\nfont \"Other.otf\" size 22\ntext \"b\" at 2 2\nfont \"Broken\"\n"
	testing.expect(t, os.write_entire_file(path, transmute([]byte)text) == nil)
	_ = root
	p, ok := load(path, text)
	testing.expect(t, ok)
	roci.start_headless(1)
	watch(p, path)
	start(p)
	defer finish_all()
	testing.expect(t, roci.has_font("Mine"))
	testing.expect(t, roci.has_font("Other.otf"))
	testing.expect(t, !roci.has_font("Broken"), "bytes that are not a font are not a font")
	testing.expect_value(t, len(p.errors), 1)
	testing.expect_value(t, p.errors[0].id, lang.Message_Id.Font_Missing)
}

// A folder of installed fonts for a test: Inter under `free`, and under `locked` the
// same font with the embedding bits saying it may not be shared. Gives the folder.
make_installed_fonts :: proc(t: ^testing.T, root: string, free, locked: string) -> string {
	_ = os.remove_all(root)
	testing.expect(t, folder.ensure_directory(root))
	testing.expect(t, os.write_entire_file(concat(root, "/", free, ".ttf"), gfx.INTER_REGULAR) == nil)
	copied := make([]u8, len(gfx.INTER_REGULAR), context.temp_allocator)
	copy(copied, gfx.INTER_REGULAR)
	for i in 0 ..< int(u16(copied[4]) << 8 | u16(copied[5])) {
		record := 12 + i * 16
		if string(copied[record:][:4]) == "OS/2" {
			at := int(u32(copied[record + 8]) << 24 | u32(copied[record + 9]) << 16 | u32(copied[record + 10]) << 8 | u32(copied[record + 11])) + 8
			copied[at], copied[at + 1] = 0, 2
		}
	}
	testing.expect(t, os.write_entire_file(concat(root, "/", locked, ".ttf"), copied) == nil)
	return root
}

@(test)
test_a_free_installed_font_is_copied_into_the_sketch_and_said :: proc(t: ^testing.T) {
	installed := make_installed_fonts(t, "output/tests/installed_a", "Copy Me", "Keep Me")
	sketch := "output/tests/font_copy_sketch"
	_ = os.remove_all(sketch)
	testing.expect(t, folder.ensure_directory(sketch))
	folder.system_font_dirs = {installed}
	defer folder.system_font_dirs = nil
	path := "output/tests/font_copy_sketch/sketch.roci"
	text := "font \"Copy Me\"\ntext \"a\" at 1 1\nfont \"Copy Me\"\ntext \"b\" at 2 2\n"
	testing.expect(t, os.write_entire_file(path, transmute([]byte)text) == nil)
	roci.start_headless(1)
	p, ok := load(path, text)
	testing.expect(t, ok)
	watch(p, path)
	start(p)
	defer finish_all()
	testing.expect(t, roci.has_font("Copy Me"))
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, len(p.notices), 1)
	if len(p.notices) == 1 {
		testing.expect_value(t, p.notices[0], "copied the font Copy Me into assets/fonts, under the SIL Open Font License, so your sketch travels with it")
	}
	copied, err := os.read_entire_file("output/tests/font_copy_sketch/assets/fonts/Copy Me.ttf", context.temp_allocator)
	testing.expect(t, err == nil)
	testing.expect_value(t, len(copied), len(gfx.INTER_REGULAR))
}

@(test)
test_a_copied_font_is_found_in_assets_next_time_without_the_computers_copy :: proc(t: ^testing.T) {
	sketch :: "output/tests/font_again_sketch"
	_ = os.remove_all(sketch)
	testing.expect(t, folder.ensure_directory(sketch + "/assets/fonts"))
	testing.expect(t, os.write_entire_file("output/tests/font_again_sketch/assets/fonts/Travelled.ttf", gfx.INTER_REGULAR) == nil)
	folder.system_font_dirs = {"output/tests/no_fonts_here"}
	defer folder.system_font_dirs = nil
	path := "output/tests/font_again_sketch/sketch.roci"
	text := "font \"Travelled\"\ntext \"a\" at 1 1\n"
	testing.expect(t, os.write_entire_file(path, transmute([]byte)text) == nil)
	roci.start_headless(1)
	p, ok := load(path, text)
	testing.expect(t, ok)
	watch(p, path)
	start(p)
	defer finish_all()
	testing.expect(t, roci.has_font("Travelled"))
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, len(p.notices), 0)
}

@(test)
test_a_font_with_no_free_licence_is_copied_too_and_the_writer_is_warned :: proc(t: ^testing.T) {
	installed := make_installed_fonts(t, "output/tests/installed_b", "Other Free", "Keep Me")
	sketch :: "output/tests/font_locked_sketch"
	_ = os.remove_all(sketch)
	testing.expect(t, folder.ensure_directory(sketch))
	folder.system_font_dirs = {installed}
	defer folder.system_font_dirs = nil
	path := "output/tests/font_locked_sketch/sketch.roci"
	text := "font \"Keep Me\"\ntext \"a\" at 1 1\ntext \"b\" at 1 30\n"
	testing.expect(t, os.write_entire_file(path, transmute([]byte)text) == nil)
	roci.start_headless(1)
	p, ok := load(path, text)
	testing.expect(t, ok)
	watch(p, path)
	start(p)
	defer finish_all()
	testing.expect(t, roci.has_font("Keep Me"))
	testing.expect_value(t, len(p.errors), 1)
	testing.expect_value(t, p.errors[0].id, lang.Message_Id.Font_Licence)
	testing.expect_value(t, p.errors[0].args[1], "its licence says it may not be shared.")
	testing.expect(t, os.exists(sketch + "/assets/fonts/Keep Me.ttf"), "copied all the same")
	testing.expect_value(t, len(p.notices), 1)
	testing.expect_value(t, p.notices[0], "copied the font Keep Me into assets/fonts, so your sketch looks the same everywhere")
}

@(test)
test_an_installed_font_of_a_lone_file_is_used_with_nowhere_to_copy_it :: proc(t: ^testing.T) {
	installed := make_installed_fonts(t, "output/tests/installed_c", "Lone Free", "Lone Locked")
	folder.system_font_dirs = {installed}
	defer folder.system_font_dirs = nil
	p := run_text(t, "font \"Lone Free\"\ntext \"a\" at 1 1\nfont \"Lone Locked\"")
	defer finish(p)
	testing.expect(t, roci.has_font("Lone Free"))
	testing.expect(t, roci.has_font("Lone Locked"))
	testing.expect_value(t, len(p.errors), 1) // only the one with no free licence is said
	testing.expect_value(t, p.errors[0].id, lang.Message_Id.Font_Licence)
	testing.expect_value(t, len(p.notices), 0)
}

@(test)
test_a_name_nothing_has_is_looked_for_once :: proc(t: ^testing.T) {
	folder.system_font_dirs = {"output/tests/no_fonts_here"}
	defer folder.system_font_dirs = nil
	p := run_text(t, "draw [ font \"Not Anywhere\"\n text \"a\" at 1 1 ]", 3)
	defer finish(p)
	testing.expect_value(t, len(p.fonts_missed), 1)
	testing.expect_value(t, len(p.errors), 1)
	testing.expect_value(t, p.errors[0].id, lang.Message_Id.Font_Missing)
}

// A collection of Inter Bold and then Inter Regular, written as `file` in `root`.
make_font_pair :: proc(t: ^testing.T, root, file: string) {
	_ = os.remove_all(root)
	testing.expect(t, folder.ensure_directory(root))
	collection := folder.join_fonts({gfx.INTER_BOLD, gfx.INTER_REGULAR}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(concat(root, "/", file), collection) == nil)
}

@(test)
test_a_face_of_a_collection_in_assets_is_found_by_its_own_name_and_not_copied :: proc(t: ^testing.T) {
	sketch :: "output/tests/font_face_sketch"
	make_font_pair(t, sketch + "/assets/fonts", "Pair.ttc")
	folder.system_font_dirs = {"output/tests/no_fonts_here"}
	defer folder.system_font_dirs = nil
	path := "output/tests/font_face_sketch/sketch.roci"
	text := "font \"Inter Regular\" size 40\ntext \"Hamburgefonstiv\" at 1 1\n"
	testing.expect(t, os.write_entire_file(path, transmute([]byte)text) == nil)
	roci.start_headless(1)
	p, ok := load(path, text)
	testing.expect(t, ok)
	watch(p, path)
	start(p)
	defer finish_all()
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, len(p.notices), 0)
	face, found := gfx.find_face("Inter Regular")
	testing.expect(t, found)
	// the second face of Pair.ttc is Regular: as wide as the built-in Inter, and narrower than Bold
	width, _ := gfx.measure_typeset(face, 40, .Left, "Hamburgefonstiv")
	regular, _ := gfx.measure_typeset(gfx.FACE_DEFAULT, 40, .Left, "Hamburgefonstiv")
	bold, _ := gfx.measure_typeset(gfx.FACE_BOLD, 40, .Left, "Hamburgefonstiv")
	testing.expect_value(t, width, regular)
	testing.expect(t, width < bold)
	// nothing was copied: the collection in assets answered
	entries, _ := os.read_all_directory_by_path("output/tests/font_face_sketch/assets/fonts", context.temp_allocator)
	testing.expect_value(t, len(entries), 1)
}

@(test)
test_an_installed_collection_is_copied_under_the_name_of_the_face_asked_for :: proc(t: ^testing.T) {
	make_font_pair(t, "output/tests/installed_pair", "Pair.ttc")
	sketch :: "output/tests/font_face_copy_sketch"
	_ = os.remove_all(sketch)
	testing.expect(t, folder.ensure_directory(sketch))
	folder.system_font_dirs = {"output/tests/installed_pair"}
	defer folder.system_font_dirs = nil
	path := "output/tests/font_face_copy_sketch/sketch.roci"
	// The face by its PostScript name, which no other test asks for: a thread keeps the fonts it has
	// added for as long as it lives, so a name another test added would be found, and not copied.
	text := "font \"Inter-Regular\"\ntext \"a\" at 1 1\n"
	testing.expect(t, os.write_entire_file(path, transmute([]byte)text) == nil)
	roci.start_headless(1)
	p, ok := load(path, text)
	testing.expect(t, ok)
	watch(p, path)
	start(p)
	defer finish_all()
	testing.expect(t, roci.has_font("Inter-Regular"))
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, len(p.notices), 1)
	// the whole collection is copied (its other faces may be wanted next), under the name asked
	copied, err := os.read_entire_file("output/tests/font_face_copy_sketch/assets/fonts/Inter-Regular.ttc", context.temp_allocator)
	testing.expect(t, err == nil)
	testing.expect_value(t, len(copied), len(folder.join_fonts({gfx.INTER_BOLD, gfx.INTER_REGULAR}, context.temp_allocator)))
	// the copy is found by that name next time, by the face the name goes by
	face, _ := gfx.find_face("Inter-Regular")
	width, _ := gfx.measure_typeset(face, 40, .Left, "Hamburgefonstiv")
	regular, _ := gfx.measure_typeset(gfx.FACE_DEFAULT, 40, .Left, "Hamburgefonstiv")
	testing.expect_value(t, width, regular)
}
