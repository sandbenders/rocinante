// SPDX-License-Identifier: 0BSD
package interp

import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

import "../"
import "../folder"
import "../gfx"

BADGE :: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 50"><rect width="100" height="50" fill="red"/><circle cx="50" cy="25" r="10" fill="blue"/></svg>`

// A sketch folder with two drawings, one with a part that cannot be drawn, a file that is not a drawing and two of one name.
make_svg_folder :: proc(t: ^testing.T, name: string) -> string {
	root := strings.concatenate({"output/tests/", name}, context.temp_allocator)
	_ = os.remove_all(root)
	dir := strings.concatenate({root, "/assets/images"}, context.temp_allocator)
	testing.expect(t, folder.ensure_directory(strings.concatenate({dir, "/a"}, context.temp_allocator)))
	testing.expect(t, folder.ensure_directory(strings.concatenate({dir, "/b"}, context.temp_allocator)))
	write :: proc(t: ^testing.T, path, text: string) {
		testing.expect(t, os.write_entire_file(path, transmute([]byte)text) == nil)
	}
	write(t, strings.concatenate({dir, "/badge.svg"}, context.temp_allocator), BADGE)
	write(t, strings.concatenate({dir, "/broken.svg"}, context.temp_allocator), "not a drawing")
	write(t, strings.concatenate({dir, "/words.svg"}, context.temp_allocator), `<svg viewBox="0 0 10 10"><rect width="5" height="5"/><text>hi</text></svg>`)
	write(t, strings.concatenate({dir, "/a/twin.svg"}, context.temp_allocator), BADGE)
	write(t, strings.concatenate({dir, "/b/twin.svg"}, context.temp_allocator), BADGE)
	write(t, strings.concatenate({root, "/sketch.roci"}, context.temp_allocator), "circle at 1 1 radius 1\n")
	return root
}

paths_drawn :: proc() -> [dynamic]gfx.Command {
	out := make([dynamic]gfx.Command, context.temp_allocator)
	for c in roci.commands_whole(first_window()) {
		if c.kind == .Path {
			append(&out, c)
		}
	}
	return out
}

@(test)
test_a_drawing_is_found_by_name_and_drawn_as_a_path_for_each_shape :: proc(t: ^testing.T) {
	root := make_svg_folder(t, "svg_found")
	p := run_in_folder(t, root, "draw [ svg \"badge.svg\" at 20 10 ]\n", 2)
	defer finish(p)
	paths := paths_drawn()
	if !testing.expect_value(t, len(paths), 2) {
		return
	}
	testing.expect_value(t, paths[0].style.fill, [4]f32{255, 0, 0, 255})
	testing.expect_value(t, paths[1].style.fill, [4]f32{0, 0, 255, 255})
	// at its own size, 100 by 50, from (20, 10)
	x, y := gfx.transform_apply(paths[0].transform, 100, 50)
	testing.expect_value(t, [2]f32{x, y}, [2]f32{120, 60})
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_every_form_of_svg_places_and_stretches_the_drawing :: proc(t: ^testing.T) {
	root := make_svg_folder(t, "svg_forms")
	p := run_in_folder(t, root, "draw [\n  svg \"badge.svg\" at { 5, 6 }\n  svg \"badge.svg\" at 10 20 size 200 100\n  svg \"badge.svg\" at { 30, 40 } size { 50, 25 }\n]\n", 2)
	defer finish(p)
	paths := paths_drawn()
	if !testing.expect_value(t, len(paths), 6) {
		return
	}
	ends := [3][2]f32{}
	for i in 0 ..< 3 {
		ends[i].x, ends[i].y = gfx.transform_apply(paths[i * 2].transform, 100, 50)
	}
	testing.expect_value(t, ends[0], [2]f32{105, 56})
	testing.expect_value(t, ends[1], [2]f32{210, 120})
	testing.expect_value(t, ends[2], [2]f32{80, 65})
}

@(test)
test_a_drawing_follows_the_transform_of_the_moment_and_leaves_the_style_alone :: proc(t: ^testing.T) {
	root := make_svg_folder(t, "svg_transform")
	p := run_in_folder(t, root, "draw [\n  fill green\n  push [\n    move 100 100\n    grow 2\n    svg \"badge.svg\" at 0 0\n  ]\n  circle at 5 5 radius 3\n]\n", 2)
	defer finish(p)
	paths := paths_drawn()
	if !testing.expect_value(t, len(paths), 2) {
		return
	}
	x, y := gfx.transform_apply(paths[0].transform, 100, 50)
	testing.expect_value(t, [2]f32{x, y}, [2]f32{300, 200})
	for c in roci.commands_whole(first_window()) {
		if c.kind == .Circle {
			testing.expect_value(t, c.style.fill, [4]f32{0, 128, 0, 255}) // the sketch's green, not the drawing's colors
		}
	}
}

@(test)
test_a_drawing_that_is_not_there_is_said_once_and_draws_nothing :: proc(t: ^testing.T) {
	root := make_svg_folder(t, "svg_missing")
	p := run_in_folder(t, root, "draw [ svg \"nothing.svg\" at 0 0 ]\n", 5)
	defer finish(p)
	testing.expect_value(t, len(paths_drawn()), 0)
	said := 0
	for e in p.errors {
		if e.id == .Svg_Missing {said += 1}
	}
	testing.expect_value(t, said, 1)
}

@(test)
test_two_drawings_of_one_name_are_asked_to_be_told_apart :: proc(t: ^testing.T) {
	root := make_svg_folder(t, "svg_twin")
	p := run_in_folder(t, root, "draw [ svg \"twin.svg\" at 0 0 ]\n", 2)
	defer finish(p)
	testing.expect_value(t, len(paths_drawn()), 0)
	found := false
	for e in p.errors {
		found ||= e.id == .Svg_Missing
	}
	testing.expect(t, found, "the clash is said")
	q := run_in_folder(t, root, "draw [ svg \"a/twin.svg\" at 0 0 ]\n", 2)
	defer finish(q)
	testing.expect_value(t, len(paths_drawn()), 2)
}

@(test)
test_a_file_that_is_not_svg_is_unreadable :: proc(t: ^testing.T) {
	root := make_svg_folder(t, "svg_broken")
	p := run_in_folder(t, root, "draw [ svg \"broken.svg\" at 0 0 ]\n", 2)
	defer finish(p)
	testing.expect_value(t, len(paths_drawn()), 0)
	found := false
	for e in p.errors {
		found ||= e.id == .Svg_Unreadable
	}
	testing.expect(t, found, "the file is said not to be a drawing")
}

@(test)
test_what_a_drawing_cannot_show_is_said_once_and_the_rest_is_drawn :: proc(t: ^testing.T) {
	root := make_svg_folder(t, "svg_lost")
	p := run_in_folder(t, root, "draw [ svg \"words.svg\" at 0 0 ]\n", 6)
	defer finish(p)
	testing.expect_value(t, len(paths_drawn()), 1)
	said := 0
	for e in p.errors {
		if e.id == .Svg_Lost {said += 1}
	}
	testing.expect_value(t, said, 1)
}

@(test)
test_a_drawing_edited_while_the_sketch_runs_is_read_again :: proc(t: ^testing.T) {
	root := make_svg_folder(t, "svg_edited")
	testing.expect(t, os.write_entire_file(strings.concatenate({root, "/sketch.roci"}, context.temp_allocator), transmute([]byte)string("draw [ svg \"badge.svg\" at 0 0 ]\n")) == nil) // a watched sketch reads its own file again
	p := run_in_folder(t, root, "draw [ svg \"badge.svg\" at 0 0 ]\n", 2)
	defer finish(p)
	p.path = p.home // a watched sketch looks at its files
	testing.expect_value(t, len(paths_drawn()), 2)
	smaller := `<svg viewBox="0 0 10 10"><rect width="10" height="10" fill="lime"/></svg>`
	path := strings.concatenate({root, "/assets/images/badge.svg"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(path, transmute([]byte)smaller) == nil)
	// the file's time must move on for the sketch to notice, on a system that counts it in seconds
	later := time.time_add(time.now(), 10 * time.Second)
	testing.expect(t, os.change_times(path, later, later) == nil)
	for _ in 0 ..< 3 {
		roci.step()
	}
	paths := paths_drawn()
	if testing.expect_value(t, len(paths), 1) {
		testing.expect_value(t, paths[0].style.fill, [4]f32{0, 255, 0, 255})
	}
}
