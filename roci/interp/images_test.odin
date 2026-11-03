// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "../folder"
import "../gfx"
import "../lang"
import "../maths"
import "core:os"
import "core:testing"
import "core:time"

image_commands :: proc() -> [dynamic]gfx.Command {
	found: [dynamic]gfx.Command
	for c in roci.recorded(first_window()) {
		if c.kind == .Image {
			append(&found, c)
		}
	}
	return found
}

// A picture file of `w` by `h` for a test sketch.
write_test_picture :: proc(t: ^testing.T, path: string, w, h: int) {
	pixels := make([]u8, w * h * 4, context.temp_allocator)
	for i in 0 ..< len(pixels) {
		pixels[i] = u8(i * 9 + 1)
	}
	png, ok := gfx.png_encode(gfx.Image{w, h, pixels})
	testing.expect(t, ok)
	defer delete(png)
	testing.expect(t, os.write_entire_file(path, png) == nil)
}

// Makes a sketch folder with a 3 by 2 `cat.png` in `assets/images`, writes the sketch
// into it, and runs it. `folder_name` is under output/tests.
run_picture_sketch :: proc(t: ^testing.T, folder_name, text: string) -> ^Interp {
	root := concat("output/tests/", folder_name)
	_ = os.remove_all(root)
	testing.expect(t, folder.ensure_directory(concat(root, "/assets/images")))
	write_test_picture(t, concat(root, "/assets/images/cat.png"), 3, 2)
	path := concat(root, "/sketch.roci")
	testing.expect(t, os.write_entire_file(path, transmute([]byte)text) == nil)
	roci.start_headless(1)
	p, ok := load(path, text)
	if !testing.expectf(t, ok, "the sketch has errors:\n%s", lang.render_all(p.src, p.checked.diagnostics, context.temp_allocator)) {
		return p
	}
	watch(p, path)
	start(p)
	return p
}

@(test)
test_a_picture_is_loaded_by_name_drawn_and_has_a_width_and_a_height :: proc(t: ^testing.T) {
	p := run_picture_sketch(t, "pictures_basic", "photo = load \"cat.png\"\nimage photo at 10 20\nprint photo.width\nprint photo.height")
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, printed(p), "3\n2")
	found := image_commands()
	defer delete(found)
	if testing.expect_value(t, len(found), 1) {
		testing.expect_value(t, [4]f32{found[0].args[0], found[0].args[1], found[0].args[2], found[0].args[3]}, [4]f32{10, 20, 3, 2})
	}
}

@(test)
test_every_form_of_image_draws_what_its_words_say :: proc(t: ^testing.T) {
	p := run_picture_sketch(t, "pictures_forms", `photo = load "cat.png"
image photo at 1 2
image photo at { 3, 4 }
image photo at 5 6 size 30 40
image photo at { 7, 8 } size { 50, 60 }
image photo at { 9, 10 } size 70 80
image photo at 11 12 width 12
image photo at 13 14 height 8
image photo at 15 16 width 9 height 9
image photo at 17 18 as center
image photo at 19 20 tint teal alpha 50`)
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	found := image_commands()
	defer delete(found)
	if !testing.expect_value(t, len(found), 10) {
		return
	}
	want := [?][4]f32{{1, 2, 3, 2}, {3, 4, 3, 2}, {5, 6, 30, 40}, {7, 8, 50, 60}, {9, 10, 70, 80}, {11, 12, 12, 8}, {13, 14, 12, 8}, {15, 16, 9, 9}, {17, 18, 3, 2}, {19, 20, 3, 2}}
	for w, i in want {
		testing.expect_value(t, [4]f32{found[i].args[0], found[i].args[1], found[i].args[2], found[i].args[3]}, w)
	}
	testing.expect_value(t, found[8].origin, gfx.Origin.Center)
	teal, _ := maths.name_lookup("teal")
	testing.expect_value(t, found[9].style.tint, teal)
	testing.expect(t, abs(found[9].style.alpha - 127.5) < 0.5)
	testing.expect_value(t, found[0].style.tint, gfx.DEFAULT_STYLE.tint) // a word of one image leaves the style alone
}

@(test)
test_tint_is_a_verb_that_lasts_and_pictures_are_values_that_can_be_kept :: proc(t: ^testing.T) {
	p := run_picture_sketch(t, "pictures_tint", `photo = load "cat.png"
others = [ photo photo ]
tint red
for each one in others [ image one at 0 0 ]
print (photo is photo)`)
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	found := image_commands()
	defer delete(found)
	testing.expect_value(t, len(found), 2)
	red, _ := maths.name_lookup("red")
	for c in found {
		testing.expect_value(t, c.style.tint, red)
	}
	testing.expect_value(t, printed(p), "true")
}

@(test)
test_a_picture_is_read_once_and_again_when_its_file_changes :: proc(t: ^testing.T) {
	p := run_picture_sketch(t, "pictures_cache", "photo = load \"cat.png\"\nsecond = load \"cat.png\"\nprint (photo is second)")
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	count := len(p.pictures)
	testing.expect_value(t, count, 1)
	entry := p.pictures["cat.png"]
	testing.expect_value(t, entry.state, Picture_State.Loaded)
	stored := len(gfx.image_store)
	// the same name again: the same picture, nothing decoded
	again := load_picture(p, "cat.png", {})
	testing.expect_value(t, as_image(again), entry.id)
	testing.expect_value(t, len(gfx.image_store), stored)
	// a changed file, a later time: read again, a different picture
	write_test_picture(t, entry.path, 5, 4)
	testing.expect(t, os.change_times(entry.path, time.now(), time.time_add(entry.mtime, 10 * time.Second)) == nil)
	changed := load_picture(p, "cat.png", {})
	testing.expect(t, as_image(changed) != entry.id)
	testing.expect_value(t, roci.image_size(as_image(changed)), [2]f64{5, 4})
	testing.expect_value(t, len(gfx.image_store), stored + 1)
}

@(test)
test_a_reload_does_not_decode_the_pictures_again :: proc(t: ^testing.T) {
	p := run_picture_sketch(t, "pictures_reload", "photo = load \"cat.png\"\nimage photo at 0 0")
	defer finish(p)
	stored := len(gfx.image_store)
	first := p.pictures["cat.png"]
	testing.expect_value(t, first.state, Picture_State.Loaded)
	// another interpreter over the same folder, as a reload makes, finds the picture
	// the first one decoded
	text := "photo = load \"cat.png\"\n"
	other, ok := load(p.path, text)
	testing.expect(t, ok)
	other.path = p.path
	defer destroy(other)
	entry := read_picture(other, "cat.png")
	testing.expect_value(t, entry.state, Picture_State.Loaded)
	testing.expect_value(t, entry.id, first.id)
	testing.expect_value(t, len(gfx.image_store), stored)
	delete(entry.path)
}

@(test)
test_a_picture_that_is_not_there_draws_nothing_and_is_found_when_it_appears :: proc(t: ^testing.T) {
	p := run_picture_sketch(t, "pictures_late", "photo = load \"late.png\"\nimage photo at 0 0\nprint photo.width")
	defer finish(p)
	testing.expect_value(t, len(p.errors), 1)
	testing.expect_value(t, p.errors[0].id, lang.Message_Id.Image_Missing)
	testing.expect_value(t, printed(p), "") // the width of no picture is the empty value
	found := image_commands()
	testing.expect_value(t, len(found), 0)
	delete(found)
	// the file arrives; the name is looked for again after a second
	write_test_picture(t, "output/tests/pictures_late/assets/images/late.png", 6, 6)
	value := load_picture(p, "late.png", {})
	testing.expect(t, value == nil, "not looked for again yet")
	entry := p.pictures["late.png"]
	entry.tried = {}
	p.pictures["late.png"] = entry
	value = load_picture(p, "late.png", {})
	testing.expect_value(t, roci.image_size(as_image(value)), [2]f64{6, 6})
}

@(test)
test_a_file_that_is_not_a_picture_and_a_name_two_files_share_are_said :: proc(t: ^testing.T) {
	p := run_picture_sketch(t, "pictures_bad", "a = load \"broken.png\"\nb = load \"twin.png\"\nimage a at 0 0\nimage b at 0 0")
	defer finish(p)
	ids: [dynamic]lang.Message_Id
	defer delete(ids)
	for e in p.errors {
		append(&ids, e.id)
	}
	testing.expect_value(t, len(ids), 2) // neither file is there yet
	for id in ids {
		testing.expect_value(t, id, lang.Message_Id.Image_Missing)
	}
	root := "output/tests/pictures_bad/assets/images"
	testing.expect(t, folder.ensure_directory(concat(root, "/x")))
	testing.expect(t, folder.ensure_directory(concat(root, "/y")))
	testing.expect(t, os.write_entire_file(concat(root, "/broken.png"), transmute([]byte)string("nope")) == nil)
	testing.expect(t, os.write_entire_file(concat(root, "/x/twin.png"), transmute([]byte)string("1")) == nil)
	testing.expect(t, os.write_entire_file(concat(root, "/y/twin.png"), transmute([]byte)string("2")) == nil)
	for name in ([]string{"broken.png", "twin.png"}) {
		entry := p.pictures[name]
		entry.tried = {}
		p.pictures[name] = entry
	}
	testing.expect(t, load_picture(p, "broken.png", lang.Span{start = 100, end = 110}) == nil)
	testing.expect(t, load_picture(p, "twin.png", lang.Span{start = 200, end = 210}) == nil)
	testing.expect_value(t, p.pictures["broken.png"].state, Picture_State.Unreadable)
	testing.expect_value(t, p.pictures["twin.png"].state, Picture_State.Ambiguous)
	testing.expect_value(t, p.errors[len(p.errors) - 2].id, lang.Message_Id.Image_Unreadable)
	testing.expect_value(t, p.errors[len(p.errors) - 1].id, lang.Message_Id.Image_Missing)
}

@(test)
test_a_lone_file_has_no_assets_to_load_from_and_a_picture_field_that_is_misspelt_is_a_message :: proc(t: ^testing.T) {
	p := run_text(t, "photo = load \"cat.png\"\nimage photo at 0 0")
	defer finish(p)
	testing.expect_value(t, len(p.errors), 1)
	testing.expect_value(t, p.errors[0].id, lang.Message_Id.Image_Missing)
	roci.start_headless(1)
	_, ok := load("test.roci", "photo = load \"cat.png\"\nprint photo.depth")
	testing.expect(t, !ok, "a picture has a width and a height and nothing else")
	_, ok = load("test.roci", "photo = load \"cat.png\"\nphoto.width = 5")
	testing.expect(t, !ok, "a picture's size can be read but not changed")
}

@(test)
test_fill_takes_a_picture_and_its_words_say_how_it_sits :: proc(t: ^testing.T) {
	p := run_picture_sketch(t, "pictures_fill", `photo = load "cat.png"
fill photo
circle at 10 10 radius 5
fill photo as fit
rect at 0 0 size 10 10
fill photo as stretch
rect at 0 0 size 10 10
fill photo as tile size 40 at 3 4
rect at 0 0 size 10 10
fill photo as center at { 1, 2 }
rect at 0 0 size 10 10
fill red
rect at 0 0 size 10 10
rect at 0 0 size 10 10 fill photo
`)
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	commands := roci.recorded(first_window())
	if !testing.expect_value(t, len(commands), 7) {
		return
	}
	fills: [7]gfx.Image_Fill
	for c, i in commands {
		fills[i] = c.style.fill_image
	}
	testing.expect(t, fills[0].image != 0)
	testing.expect_value(t, fills[0].fit, gfx.Image_Fit.Cover) // the start
	testing.expect_value(t, fills[1].fit, gfx.Image_Fit.Fit)
	testing.expect_value(t, fills[2].fit, gfx.Image_Fit.Stretch)
	testing.expect_value(t, fills[3].fit, gfx.Image_Fit.Tile)
	testing.expect_value(t, fills[3].tile, f32(40))
	testing.expect_value(t, fills[3].at, [2]f32{3, 4})
	testing.expect_value(t, fills[4].fit, gfx.Image_Fit.Center)
	testing.expect_value(t, fills[4].at, [2]f32{1, 2})
	testing.expect_value(t, fills[5].image, gfx.Image_Id(0)) // a color puts the picture away
	testing.expect_value(t, fills[6].image, fills[0].image)  // one element, with the fill word
	testing.expect_value(t, commands[6].style.fill, [4]f32{255, 0, 0, 255}) // the color before it is kept underneath
}

@(test)
test_a_picture_that_is_not_there_fills_with_nothing_new :: proc(t: ^testing.T) {
	p := run_picture_sketch(t, "pictures_fill_missing", "fill teal\nphoto = load \"nope.png\"\nfill photo\nrect at 0 0 size 5 5")
	defer finish(p)
	commands := roci.recorded(first_window())
	if testing.expect_value(t, len(commands), 1) {
		testing.expect_value(t, commands[0].style.fill_image.image, gfx.Image_Id(0))
		testing.expect_value(t, commands[0].style.fill, [4]f32{0, 128, 128, 255})
	}
}

@(test)
test_a_with_group_can_fill_with_a_picture :: proc(t: ^testing.T) {
	p := run_picture_sketch(t, "pictures_fill_with", "photo = load \"cat.png\"\nwith fill photo [ rect at 0 0 size 5 5 ]\nrect at 0 0 size 5 5")
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	commands := roci.recorded(first_window())
	if testing.expect_value(t, len(commands), 2) {
		testing.expect(t, commands[0].style.fill_image.image != 0)
		testing.expect_value(t, commands[1].style.fill_image.image, gfx.Image_Id(0)) // the group ended
	}
}
