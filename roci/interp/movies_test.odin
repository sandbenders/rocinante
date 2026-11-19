// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "../folder"
import "../lang"
import "core:os"
import "core:testing"
import sdl "vendor:sdl3"

// Makes a sketch folder with `clip.mpg` in `assets/videos`, writes the sketch into it and runs it.
run_movie_sketch :: proc(t: ^testing.T, folder_name, text: string) -> ^Interp {
	root := concat("output/tests/", folder_name)
	_ = os.remove_all(root)
	testing.expect(t, folder.ensure_directory(concat(root, "/assets/videos")))
	bytes, err := os.read_entire_file("tests/movies/tiny.mpg", context.temp_allocator)
	testing.expect(t, err == nil)
	testing.expect(t, os.write_entire_file(concat(root, "/assets/videos/clip.mpg"), bytes) == nil)
	return run_movie_folder(t, root, text)
}

// Writes a sketch into a folder that is already made and runs it.
run_movie_folder :: proc(t: ^testing.T, root, text: string) -> ^Interp {
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
test_a_movie_is_loaded_by_name_plays_and_is_drawn_as_the_picture_of_the_moment :: proc(t: ^testing.T) {
	p := run_movie_sketch(t, "movies_basic", `
clip = load "clip.mpg"
wide = clip.width
high = clip.height
length = clip.length
before = clip.playing
play clip
draw [
  image clip at 10 20
  now = clip.at
  going = clip.playing
]
`)
	defer finish(p)
	testing.expect_value(t, as_number(global_named(p, "wide")), 160)
	testing.expect_value(t, as_number(global_named(p, "high")), 96)
	testing.expect(t, as_number(global_named(p, "length")) > 1.9)
	testing.expect_value(t, as_bool(global_named(p, "before")), false)
	roci.step()
	first := image_commands()
	testing.expect_value(t, len(first), 1)
	for _ in 0 ..< 29 {
		roci.step()
	}
	testing.expect(t, as_number(global_named(p, "now")) > 0.4 && as_number(global_named(p, "now")) < 0.55)
	testing.expect_value(t, as_bool(global_named(p, "going")), true)
	later := image_commands()
	testing.expect_value(t, len(later), 1)
	testing.expect(t, later[0].args[4] != first[0].args[4], "the picture drawn changes as the movie plays")
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_the_movie_verbs_pause_rewind_forward_set_and_loop :: proc(t: ^testing.T) {
	p := run_movie_sketch(t, "movies_verbs", `
clip = load "clip.mpg"
draw [
  image clip at 0 0
  place = clip.at
  going = clip.playing
  loops = clip.loop
  fast = clip.speed
]
on key "a" [ play clip speed 2 ]
on key "b" [ pause clip ]
on key "c" [ rewind clip ]
on key "d" [ forward clip by 1 ]
on key "e" [ rewind clip by 0.5 ]
on key "f" [ set clip at 0.25 speed 3 loop true ]
on key "g" [ loop clip ]
`)
	defer finish(p)
	w := first_window()
	press :: proc(w: roci.Window, code: sdl.Scancode) {
		roci.step({key_event(w, code)})
		roci.step({key_event(w, code, false)})
	}
	roci.step()
	press(w, .A)
	testing.expect_value(t, as_bool(global_named(p, "going")), true)
	testing.expect_value(t, as_number(global_named(p, "fast")), 2)
	for _ in 0 ..< 10 {
		roci.step()
	}
	moved := as_number(global_named(p, "place"))
	testing.expect(t, moved > 0.3, "twice the speed: a third of a second in 10 frames and the presses")
	press(w, .B)
	held := as_number(global_named(p, "place"))
	for _ in 0 ..< 5 {
		roci.step()
	}
	testing.expect_value(t, as_number(global_named(p, "place")), held)
	testing.expect_value(t, as_bool(global_named(p, "going")), false)
	press(w, .C)
	testing.expect(t, as_number(global_named(p, "place")) < 0.1)
	press(w, .D)
	testing.expect(t, as_number(global_named(p, "place")) > 0.9)
	press(w, .E)
	testing.expect(t, as_number(global_named(p, "place")) > 0.4 && as_number(global_named(p, "place")) < 0.6)
	press(w, .F)
	testing.expect(t, as_number(global_named(p, "place")) > 0.2 && as_number(global_named(p, "place")) < 0.4)
	testing.expect_value(t, as_number(global_named(p, "fast")), 3)
	testing.expect_value(t, as_bool(global_named(p, "loops")), true)
	press(w, .G)
	testing.expect_value(t, as_bool(global_named(p, "going")), true)
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_a_movie_fills_a_shape_and_goes_through_the_picture_verbs :: proc(t: ^testing.T) {
	p := run_movie_sketch(t, "movies_fill", `
clip = load "clip.mpg"
loop clip
draw [
  fill clip
  circle at 100 100 radius 50
  small = resize clip size 80 0
  image small at 200 0
  flipped = flip clip
  image flipped at 0 200
]
`)
	defer finish(p)
	for _ in 0 ..< 20 {
		roci.step()
	}
	testing.expect_value(t, len(p.errors), 0)
	testing.expect(t, len(image_commands()) >= 2)
}

@(test)
test_a_picture_that_is_no_movie_has_the_movie_fields_at_rest_and_a_file_that_is_no_movie_is_said :: proc(t: ^testing.T) {
	p := run_picture_sketch(t, "movies_not", `
photo = load "cat.png"
play photo
pause photo
place = photo.at
length = photo.length
going = photo.playing
`)
	testing.expect_value(t, as_number(global_named(p, "place")), 0)
	testing.expect_value(t, as_number(global_named(p, "length")), 0)
	testing.expect_value(t, as_bool(global_named(p, "going")), false)
	testing.expect_value(t, len(p.errors), 0)
	// a file called .mpg that is not a movie is an unreadable picture, said once
	finish(p)
	root := "output/tests/movies_junk"
	_ = os.remove_all(root)
	testing.expect(t, folder.ensure_directory(concat(root, "/assets/videos")))
	testing.expect(t, os.write_entire_file(concat(root, "/assets/videos/junk.mpg"), transmute([]byte)string("not a movie")) == nil)
	q := run_movie_folder(t, root, `
junk = load "junk.mpg"
play junk
`)
	defer finish(q)
	testing.expect_value(t, len(q.errors), 1)
}
