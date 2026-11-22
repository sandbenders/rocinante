// SPDX-License-Identifier: 0BSD
package main

import "../roci/gfx"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

// A square drawing with a gradient and a stroke, the picture the tests make icons from.
@(private = "file")
TEST_SVG :: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
	<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#205"/><stop offset="1" stop-color="#f80"/></linearGradient></defs>
	<rect width="100" height="100" fill="url(#g)"/>
	<circle cx="50" cy="50" r="30" fill="#fff" stroke="#000" stroke-width="4"/>
</svg>`

// A PNG of one color, `side` pixels square (or `width` by `height`).
@(private = "file")
png_of :: proc(width, height: int, colour: [4]u8) -> []byte {
	pixels := make([]u8, width * height * 4, context.temp_allocator)
	for i in 0 ..< width * height {
		pixels[i * 4], pixels[i * 4 + 1], pixels[i * 4 + 2], pixels[i * 4 + 3] = colour[0], colour[1], colour[2], colour[3]
	}
	png, _ := gfx.png_encode(gfx.Image{width = width, height = height, pixels = pixels}, context.temp_allocator, .None)
	return png
}

@(private = "file")
fresh_sketch :: proc(name: string) -> string {
	root := strings.concatenate({"output/tests/", name}, context.temp_allocator)
	_ = os.remove_all(root)
	_ = os.make_directory_all(strings.concatenate({root, "/icons"}, context.temp_allocator))
	return root
}

@(private = "file")
pixel :: proc(img: gfx.Image, x, y: int) -> [4]u8 {
	at := (y * img.width + x) * 4
	return {img.pixels[at], img.pixels[at + 1], img.pixels[at + 2], img.pixels[at + 3]}
}

@(test)
test_every_system_has_its_icon_files_named_as_it_wants_them :: proc(t: ^testing.T) {
	files := icon_files("wild")
	testing.expect_value(t, len(files), 10 + 1 + 10 + 11 + 1 + 5 * 4 + 2 + 2)
	testing.expect_value(t, files[0], Icon_File{path = "macos/wild.iconset/icon_16x16.png", size = 16, kind = .Mac})
	testing.expect_value(t, files[9].path, "macos/wild.iconset/icon_512x512@2x.png")
	testing.expect_value(t, files[9].size, 1024)
	testing.expect_value(t, files[10], Icon_File{path = "ios/AppIcon-1024.png", size = 1024, kind = .Opaque})
	paths := make(map[string]Icon_File, len(files), context.temp_allocator)
	for f in files {
		paths[f.path] = f
	}
	testing.expect_value(t, paths["windows/wild-256.png"].size, 256)
	testing.expect_value(t, paths["freedesktop/hicolor/512x512/apps/wild.png"].kind, Icon_Kind.Full)
	testing.expect_value(t, paths["android/res/mipmap-xxxhdpi/ic_launcher_background.png"].size, 432)
	testing.expect_value(t, paths["android/res/mipmap-hdpi/ic_launcher_round.png"], Icon_File{path = "android/res/mipmap-hdpi/ic_launcher_round.png", size = 72, kind = .Round})
	testing.expect_value(t, paths["android/res/mipmap-mdpi/ic_launcher.png"].kind, Icon_Kind.Rounded)
	testing.expect_value(t, paths["android/res/mipmap-mdpi/ic_launcher_foreground.png"].kind, Icon_Kind.Adaptive_Front)
	testing.expect(t, strings.contains(paths["android/res/mipmap-anydpi-v26/ic_launcher.xml"].text, "@mipmap/ic_launcher_background"))
	// the .ico is made after the PNGs it holds, and the drawing last
	ico_at, last_png := -1, -1
	for f, i in files {
		if f.kind == .Ico {
			ico_at = i
		}
		if strings.has_prefix(f.path, "windows/") && f.kind == .Full {
			last_png = i
		}
	}
	testing.expect(t, ico_at > last_png && files[len(files) - 1].kind == .Scalable)
}

@(test)
test_the_record_of_what_roci_made_is_read_and_written_back :: proc(t: ^testing.T) {
	record := Icon_Record{source = "abc", files = make(map[string]string, 4, context.temp_allocator)}
	record.files["windows/x-16.png"] = "111"
	record.files["ios/AppIcon-1024.png"] = "222"
	text := write_icon_record(record, "icons/icon.svg")
	testing.expect(t, strings.has_prefix(text, "# The icons roci package made from icons/icon.svg"), text)
	testing.expect(t, strings.index(text, "ios/") < strings.index(text, "windows/"), "the paths are sorted")
	back := read_icon_record(strings.concatenate({text, "\nnonsense\n# a comment\n"}, context.temp_allocator))
	testing.expect_value(t, back.source, "abc")
	testing.expect_value(t, len(back.files), 2)
	testing.expect_value(t, back.files["windows/x-16.png"], "111")
	testing.expect_value(t, read_icon_record("").source, "")
}

@(test)
test_a_file_is_made_kept_or_left_as_the_persons_own :: proc(t: ^testing.T) {
	record := Icon_Record{source = "new", files = make(map[string]string, 4, context.temp_allocator)}
	record.files["a.png"] = "sum-a"
	testing.expect_value(t, plan_icon(false, "", record, "a.png", "new"), Icon_Action.Make) // missing
	testing.expect_value(t, plan_icon(true, "sum-a", record, "a.png", "new"), Icon_Action.Keep) // ours, from this picture
	testing.expect_value(t, plan_icon(true, "sum-a", record, "a.png", "newer"), Icon_Action.Make) // ours, from another picture
	testing.expect_value(t, plan_icon(true, "changed", record, "a.png", "newer"), Icon_Action.Yours) // changed by hand
	testing.expect_value(t, plan_icon(true, "x", record, "b.png", "new"), Icon_Action.Yours) // never ours
	testing.expect_value(t, len(sum_of(transmute([]byte)string("x"))), 64)
	testing.expect_value(t, parent_of("a/b/c.png"), "a/b")
	testing.expect_value(t, parent_of("c.png"), ".")
}

@(test)
test_a_picture_that_is_not_square_or_too_small_or_unreadable_is_refused_in_words :: proc(t: ^testing.T) {
	_, wide, _ := read_icon_source("icons/icon.png", png_of(64, 32, {0, 0, 0, 255}), false)
	testing.expect(t, strings.contains(wide, "64 by 32 pixels") && strings.contains(wide, "must be square"), wide)
	_, small, _ := read_icon_source("icons/icon.png", png_of(512, 512, {0, 0, 0, 255}), false)
	testing.expect(t, strings.contains(small, "512 by 512") && strings.contains(small, "at least 1024 by 1024"), small)
	_, junk, _ := read_icon_source("icons/icon.png", transmute([]byte)string("not a picture"), false)
	testing.expect(t, strings.contains(junk, "not a picture I can read"), junk)
	good, none, _ := read_icon_source("icons/icon.png", png_of(1024, 1024, {10, 20, 30, 255}), false)
	testing.expect_value(t, none, "")
	testing.expect_value(t, good.picture.width, 1024)
	icon_source_destroy(&good)
	// a drawing must be square by its view box, be SVG, and hold something
	_, oblong, _ := read_icon_source("icons/icon.svg", transmute([]byte)string(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100"><rect width="10" height="10"/></svg>`), true)
	testing.expect(t, strings.contains(oblong, "200 by 100") && strings.contains(oblong, "viewBox"), oblong)
	_, not_svg, _ := read_icon_source("icons/icon.svg", transmute([]byte)string("<html/>"), true)
	testing.expect(t, strings.contains(not_svg, "not an SVG file"), not_svg)
	_, empty, _ := read_icon_source("icons/icon.svg", transmute([]byte)string(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"/>`), true)
	testing.expect(t, strings.contains(empty, "nothing in it"), empty)
	// what an icon cannot show is said, but does not refuse the drawing
	with_text, ok_text, left := read_icon_source("icons/icon.svg", transmute([]byte)string(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="10" height="10"/><text>hi</text></svg>`), true)
	testing.expect_value(t, ok_text, "")
	testing.expect_value(t, len(left), 1)
	testing.expect(t, len(left) == 1 && strings.contains(left[0], "text"))
	icon_source_destroy(&with_text)
	testing.expect_value(t, len(left_out_words(~bit_set[gfx.Svg_Lost]{})), 7)
	testing.expect_value(t, len(left_out_words({})), 0)
}

@(test)
test_each_kind_of_icon_has_its_systems_shape :: proc(t: ^testing.T) {
	source, problem, _ := read_icon_source("icons/icon.svg", transmute([]byte)string(TEST_SVG), true)
	defer icon_source_destroy(&source)
	testing.expect_value(t, problem, "")
	full := render_icon(&source, .Full, 64, context.temp_allocator)
	testing.expect_value(t, pixel(full, 0, 0).a, 255) // edge to edge
	testing.expect_value(t, pixel(full, 32, 32), [4]u8{255, 255, 255, 255}) // the circle
	mac := render_icon(&source, .Mac, 64, context.temp_allocator)
	testing.expect_value(t, pixel(mac, 3, 32).a, 0) // the Mac's margin
	testing.expect_value(t, pixel(mac, 8, 8).a, 0) // its rounded corner
	testing.expect_value(t, pixel(mac, 32, 10).a, 255)
	rounded := render_icon(&source, .Rounded, 64, context.temp_allocator)
	testing.expect_value(t, pixel(rounded, 0, 0).a, 0)
	testing.expect_value(t, pixel(rounded, 32, 0).a, 255)
	round := render_icon(&source, .Round, 64, context.temp_allocator)
	testing.expect_value(t, pixel(round, 5, 5).a, 0)
	testing.expect_value(t, pixel(round, 32, 1).a, 255)
	// the background of Android's adaptive icon goes on past the picture to its border; the foreground is empty
	back := render_icon(&source, .Adaptive_Back, 108, context.temp_allocator)
	testing.expect_value(t, pixel(back, 0, 0), pixel(back, 18, 18))
	testing.expect_value(t, pixel(back, 54, 54), [4]u8{255, 255, 255, 255})
	front := render_icon(&source, .Adaptive_Front, 108, context.temp_allocator)
	testing.expect_value(t, pixel(front, 54, 54).a, 0)
	// the iPhone's has nothing see-through, even where the picture has
	clear_picture, _, _ := read_icon_source("x.svg", transmute([]byte)string(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="5" height="5" fill="#000"/></svg>`), true)
	defer icon_source_destroy(&clear_picture)
	opaque := render_icon(&clear_picture, .Opaque, 16, context.temp_allocator)
	testing.expect_value(t, pixel(opaque, 15, 15), [4]u8{255, 255, 255, 255})
	testing.expect_value(t, pixel(opaque, 0, 0), [4]u8{0, 0, 0, 255})
	// a PNG is scaled down into the icon
	png_source, _, _ := read_icon_source("icons/icon.png", png_of(1024, 1024, {200, 100, 50, 255}), false)
	defer icon_source_destroy(&png_source)
	small := render_icon(&png_source, .Full, 16, context.temp_allocator)
	testing.expect_value(t, pixel(small, 8, 8), [4]u8{200, 100, 50, 255})
}

@(test)
test_an_ico_holds_its_pngs_after_a_header_and_an_entry_each :: proc(t: ^testing.T) {
	ico := ico_encode({transmute([]byte)string("AAAA"), transmute([]byte)string("BB")}, {16, 256})
	testing.expect_value(t, len(ico), 6 + 32 + 6)
	testing.expect(t, ico[0] == 0 && ico[2] == 1 && ico[4] == 2, "a header of two icons")
	testing.expect(t, ico[6] == 16 && ico[7] == 16, "the first is 16 pixels")
	testing.expect(t, ico[22] == 0 && ico[23] == 0, "256 is written as 0")
	testing.expect_value(t, int(ico[6 + 8]), 4) // the first PNG's length
	testing.expect_value(t, int(ico[6 + 12]), 38) // and where it starts
	testing.expect_value(t, string(ico[38:42]), "AAAA")
	testing.expect_value(t, string(ico[42:44]), "BB")
}

@(test)
test_icons_are_made_once_remade_from_a_new_picture_and_a_changed_one_is_kept :: proc(t: ^testing.T) {
	root := fresh_sketch("icons_made")
	work := strings.concatenate({root, "/output/package/linux"}, context.temp_allocator)
	_ = os.make_directory_all(work)
	testing.expect(t, os.write_entire_file(strings.concatenate({root, "/icons/icon.svg"}, context.temp_allocator), transmute([]byte)string(TEST_SVG)) == nil)
	err := strings.builder_make(context.temp_allocator)
	icons, ok := prepare_icons(root, ".", "wild", work, "", &err)
	testing.expect(t, ok, strings.to_string(err))
	testing.expect_value(t, icons.source, "icons/icon.svg")
	testing.expect(t, !icons.logo && icons.folder == strings.concatenate({root, "/icons"}, context.temp_allocator))
	testing.expect_value(t, icons.made, len(icon_files("wild")))
	testing.expect(t, os.is_file(strings.concatenate({root, "/icons/macos/wild.iconset/icon_512x512@2x.png"}, context.temp_allocator)))
	testing.expect(t, os.is_file(strings.concatenate({root, "/icons/freedesktop/scalable/apps/wild.svg"}, context.temp_allocator)))
	testing.expect(t, os.is_file(strings.concatenate({root, "/icons/.made"}, context.temp_allocator)))
	ico, _ := os.read_entire_file(strings.concatenate({root, "/icons/windows/wild.ico"}, context.temp_allocator), context.temp_allocator)
	testing.expect(t, len(ico) > 6 && ico[4] == 10, "the .ico holds the ten Windows sizes")
	// a second package makes nothing
	again, _ := prepare_icons(root, ".", "wild", work, "", &err)
	testing.expect_value(t, again.made, 0)
	testing.expect_value(t, len(again.kept), 0)
	// a file changed by hand is the person's own; a new picture remakes the rest and not it
	mine := strings.concatenate({root, "/icons/windows/wild-16.png"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(mine, png_of(16, 16, {1, 2, 3, 255})) == nil)
	newer := strings.concatenate({TEST_SVG, "\n"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(strings.concatenate({root, "/icons/icon.svg"}, context.temp_allocator), transmute([]byte)newer) == nil)
	third, _ := prepare_icons(root, ".", "wild", work, "", &err)
	testing.expect_value(t, third.made, len(icon_files("wild")) - 1)
	testing.expect_value(t, len(third.kept), 1)
	kept, _ := os.read_entire_file(mine, context.temp_allocator)
	testing.expect_value(t, string(kept), string(png_of(16, 16, {1, 2, 3, 255})))
	// a deleted file is made again
	_ = os.remove(strings.concatenate({root, "/icons/ios/AppIcon-1024.png"}, context.temp_allocator))
	fourth, _ := prepare_icons(root, ".", "wild", work, "", &err)
	testing.expect_value(t, fourth.made, 1)
	// the Linux icons are found by size, the largest PNG first
	hicolor := strings.concatenate({root, "/icons/freedesktop"}, context.temp_allocator)
	testing.expect_value(t, len(linux_icon_files(hicolor, "wild")), len(ICON_LINUX_SIZES) + 1)
	largest, found := largest_linux_icon(hicolor, "wild")
	testing.expect(t, found && strings.contains(largest, "512x512"), largest)
	_, none := largest_linux_icon(hicolor, "other")
	testing.expect(t, !none)
}

@(test)
test_a_picture_given_with_icon_is_put_in_the_icons_folder_after_it_is_checked :: proc(t: ^testing.T) {
	root := fresh_sketch("icons_flag")
	work := strings.concatenate({root, "/output/package/linux"}, context.temp_allocator)
	_ = os.make_directory_all(work)
	testing.expect(t, os.write_entire_file(strings.concatenate({root, "/art.png"}, context.temp_allocator), png_of(1024, 1024, {0, 128, 255, 255})) == nil)
	testing.expect(t, os.write_entire_file(strings.concatenate({root, "/icons/icon.svg"}, context.temp_allocator), transmute([]byte)string(TEST_SVG)) == nil)
	err := strings.builder_make(context.temp_allocator)
	icons, ok := prepare_icons(root, ".", "wild", work, "art.png", &err)
	testing.expect(t, ok, strings.to_string(err))
	testing.expect_value(t, icons.source, "icons/icon.png")
	testing.expect(t, !os.exists(strings.concatenate({root, "/icons/icon.svg"}, context.temp_allocator)), "the other picture goes")
	testing.expect(t, !os.exists(strings.concatenate({root, "/icons/freedesktop/scalable/apps/wild.svg"}, context.temp_allocator)), "a PNG has no drawing for Linux")
	// what cannot be used is refused before anything is written
	testing.expect(t, os.write_entire_file(strings.concatenate({root, "/wide.png"}, context.temp_allocator), png_of(30, 20, {0, 0, 0, 255})) == nil)
	bad := strings.builder_make(context.temp_allocator)
	_, refused := prepare_icons(root, ".", "wild", work, "wide.png", &bad)
	testing.expect(t, !refused && strings.contains(strings.to_string(bad), "must be square"), strings.to_string(bad))
	testing.expect(t, os.is_file(strings.concatenate({root, "/icons/icon.png"}, context.temp_allocator)), "the picture there stays")
	for flag in ([]string{"art.jpg", "missing.svg"}) {
		why := strings.builder_make(context.temp_allocator)
		_, no := prepare_icons(root, ".", "wild", work, flag, &why)
		testing.expectf(t, !no && strings.to_string(why) != "", "%s should be refused", flag)
	}
	// a picture in the icons folder that cannot be used stops the packaging
	testing.expect(t, os.write_entire_file(strings.concatenate({root, "/icons/icon.png"}, context.temp_allocator), png_of(100, 100, {0, 0, 0, 255})) == nil)
	stopped := strings.builder_make(context.temp_allocator)
	_, used := prepare_icons(root, ".", "wild", work, "", &stopped)
	testing.expect(t, !used && strings.contains(strings.to_string(stopped), "at least 1024"), strings.to_string(stopped))
}

@(test)
test_with_no_picture_the_logo_stands_in_where_the_package_is_made_and_the_sketchs_own_icons_are_kept :: proc(t: ^testing.T) {
	root := fresh_sketch("icons_logo")
	work := strings.concatenate({root, "/output/package/macos"}, context.temp_allocator)
	_ = os.make_directory_all(work)
	// one icon of the sketch's own, drawn by hand
	mine := strings.concatenate({root, "/icons/macos/wild.iconset"}, context.temp_allocator)
	_ = os.make_directory_all(mine)
	testing.expect(t, os.write_entire_file(strings.concatenate({mine, "/icon_16x16.png"}, context.temp_allocator), png_of(16, 16, {9, 9, 9, 255})) == nil)
	err := strings.builder_make(context.temp_allocator)
	icons, ok := prepare_icons(root, ".", "wild", work, "", &err)
	testing.expect(t, ok, strings.to_string(err))
	testing.expect(t, icons.logo)
	testing.expect_value(t, icons.folder, strings.concatenate({work, "/icons"}, context.temp_allocator))
	testing.expect_value(t, icons.made, len(icon_files("wild")) - 2) // all but the hand-made one and the drawing
	testing.expect_value(t, len(icons.kept), 1)
	copied, _ := os.read_entire_file(strings.concatenate({work, "/icons/macos/wild.iconset/icon_16x16.png"}, context.temp_allocator), context.temp_allocator)
	testing.expect_value(t, string(copied), string(png_of(16, 16, {9, 9, 9, 255})))
	// nothing was written into the sketch's own folder
	entries, _ := os.read_all_directory_by_path(strings.concatenate({root, "/icons"}, context.temp_allocator), context.temp_allocator)
	testing.expect_value(t, len(entries), 1)
	// with rocinante's source nowhere to be found, it says so
	lost := strings.builder_make(context.temp_allocator)
	_, found := prepare_icons(root, "/no/such/rocinante", "wild", work, "", &lost)
	testing.expect(t, !found && strings.contains(strings.to_string(lost), "logo"), strings.to_string(lost))
	// a folder that cannot be copied
	testing.expect(t, !copy_files("output/tests/no-such-folder", fmt.tprintf("%s/x", work)))
}
