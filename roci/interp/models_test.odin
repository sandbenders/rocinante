// SPDX-License-Identifier: 0BSD
package interp

import "core:os"
import "core:strings"
import "core:testing"

import "../"
import "../folder"
import "../gfx"
import "../lang"

// A sketch folder holding the example's ship, for tests of what `model` finds.
make_model_folder :: proc(t: ^testing.T, name: string) -> string {
	root := strings.concatenate({"output/tests/", name}, context.temp_allocator)
	_ = os.remove_all(root)
	testing.expect(t, folder.ensure_directory(strings.concatenate({root, "/assets/3d-models"}, context.temp_allocator)))
	ship, err := os.read_entire_file("examples/model/assets/3d-models/ship.glb", context.temp_allocator)
	testing.expect(t, err == nil)
	testing.expect(t, os.write_entire_file(strings.concatenate({root, "/assets/3d-models/ship.glb"}, context.temp_allocator), ship) == nil)
	testing.expect(t, os.write_entire_file(strings.concatenate({root, "/sketch.roci"}, context.temp_allocator), transmute([]byte)string("circle at 1 1 radius 1\n")) == nil)
	return root
}

run_in_folder :: proc(t: ^testing.T, root, text: string, frames: int) -> ^Interp {
	roci.start_headless(1)
	p, ok := load(strings.concatenate({root, "/sketch.roci"}, context.temp_allocator), text)
	if !ok {
		testing.expectf(t, false, "the sketch has errors:\n%s", lang.render_all(p.src, p.checked.diagnostics, context.temp_allocator))
		return p
	}
	p.home = strings.concatenate({root, "/sketch.roci"}, context.temp_allocator)
	start(p)
	for _ in 0 ..< frames {
		roci.step()
	}
	return p
}

@(test)
test_a_model_is_found_by_name_and_drawn_a_part_at_a_time :: proc(t: ^testing.T) {
	root := make_model_folder(t, "model_found")
	p := run_in_folder(t, root, "draw [ model \"ship.glb\" at 0 0 0 size 100 ]\n", 2)
	defer finish(p)
	items := roci.scene_items(first_window())
	// the ship is eight pieces, each with a mesh and a material of its own
	if !testing.expect_value(t, len(items), 8) {
		return
	}
	for item in items {
		testing.expect_value(t, item.shape, gfx.Shape3.Model)
	}
	testing.expect(t, items[0].material[0] > 0.6 && items[0].material[0] < 0.8, "the hull's metal came with the model")
	testing.expect(t, items[7].material[3] > 0.9, "the engines glow, from their emissive color")
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, len(roci.scene_items(first_window())), 8)
}

@(test)
test_a_model_is_fitted_to_its_size_and_put_at_its_place :: proc(t: ^testing.T) {
	root := make_model_folder(t, "model_fit")
	p := run_in_folder(t, root, "draw [ model \"ship.glb\" at 10 20 30 size 200 ]\n", 1)
	defer finish(p)
	// the middle of the box the model holds, taken through each item, is the place, and the longest side is the size
	low, high := [3]f32{1e9, 1e9, 1e9}, [3]f32{-1e9, -1e9, -1e9}
	data := gfx.model_data(roci.scene_items(first_window())[0].model_id)
	if !testing.expect(t, data != nil, "the model is kept") {
		return
	}
	for item in roci.scene_items(first_window()) {
		for corner in 0 ..< 8 {
			p := [3]f32{data.low.x if corner & 1 == 0 else data.high.x, data.low.y if corner & 2 == 0 else data.high.y, data.low.z if corner & 4 == 0 else data.high.z}
			w: [3]f32
			for row in 0 ..< 3 {
				w[row] = item.model[row][0] * p.x + item.model[row][1] * p.y + item.model[row][2] * p.z + item.model[row][3]
			}
			for axis in 0 ..< 3 {
				low[axis], high[axis] = min(low[axis], w[axis]), max(high[axis], w[axis])
			}
		}
	}
	middle := (low + high) / 2
	size := high - low
	testing.expect(t, abs(middle.x - 10) < 1e-3 && abs(middle.y - 20) < 1e-3 && abs(middle.z - 30) < 1e-3, "the middle is where it was put")
	testing.expect(t, abs(max(size.x, size.y, size.z) - 200) < 1e-2, "the longest side is the size")
}

@(test)
test_a_model_can_be_given_a_vector_and_follows_the_transform :: proc(t: ^testing.T) {
	root := make_model_folder(t, "model_vector")
	p := run_in_folder(t, root, "draw [\n  push [\n    move 100 0 0\n    model \"ship.glb\" at { 0, 0, 0 } size 50\n  ]\n]\n", 1)
	defer finish(p)
	items := roci.scene_items(first_window())
	if testing.expect_value(t, len(items), 8) {
		testing.expect(t, items[0].model[0][3] > 90, "moved by the transform of the moment")
	}
}

@(test)
test_a_model_that_is_not_there_is_said_once_and_draws_nothing :: proc(t: ^testing.T) {
	root := make_model_folder(t, "model_missing")
	p := run_in_folder(t, root, "draw [ model \"nothing.glb\" at 0 0 0 size 100 ]\n", 5)
	defer finish(p)
	testing.expect_value(t, len(roci.scene_items(first_window())), 0)
	said := 0
	for e in p.errors {
		if e.id == .Model_Missing {said += 1}
	}
	testing.expect_value(t, said, 1)
}

@(test)
test_a_file_that_is_not_a_model_is_unreadable :: proc(t: ^testing.T) {
	root := make_model_folder(t, "model_broken")
	testing.expect(t, os.write_entire_file(strings.concatenate({root, "/assets/3d-models/broken.glb"}, context.temp_allocator), transmute([]byte)string("not a model")) == nil)
	p := run_in_folder(t, root, "draw [ model \"broken.glb\" at 0 0 0 size 100 ]\n", 2)
	defer finish(p)
	testing.expect_value(t, len(roci.scene_items(first_window())), 0)
	found := false
	for e in p.errors {
		found ||= e.id == .Model_Unreadable
	}
	testing.expect(t, found, "the file is said not to be a model")
}

@(test)
test_a_model_edited_while_the_sketch_runs_is_read_again :: proc(t: ^testing.T) {
	root := make_model_folder(t, "model_edited")
	p := run_in_folder(t, root, "draw [ model \"ship.glb\" at 0 0 0 size 100 ]\n", 2)
	defer finish(p)
	first := roci.scene_items(first_window())[0].model_id
	testing.expect_value(t, gfx.model_version(first), 1)
	// the same file with another time is the same model, in a new version
	path := strings.concatenate({root, "/assets/3d-models/ship.glb"}, context.temp_allocator)
	data, _ := os.read_entire_file(path, context.temp_allocator)
	again, error := roci.add_model(strings.concatenate({root, "/assets/3d-models/ship.glb"}, context.temp_allocator), 12345, data)
	testing.expect_value(t, error, gfx.Gltf_Error.None)
	testing.expect_value(t, again, first)
	testing.expect_value(t, gfx.model_version(first), 2)
	// a stamp that is already known gives the number without reading
	found, ok := roci.find_model(strings.concatenate({root, "/assets/3d-models/ship.glb"}, context.temp_allocator), 12345)
	testing.expect(t, ok && found == first, "found by its path and stamp")
	_, ok = roci.find_model("elsewhere.glb", 1)
	testing.expect(t, !ok, "an unknown path is not found")
}

@(test)
test_a_gltf_file_reads_only_the_files_beside_it :: proc(t: ^testing.T) {
	model_directory = "output/tests/neighbours"
	_ = os.remove_all(model_directory)
	testing.expect(t, folder.ensure_directory(model_directory))
	testing.expect(t, os.write_entire_file("output/tests/neighbours/data.bin", transmute([]byte)string("abcd")) == nil)
	bytes, ok := model_neighbour("data.bin")
	testing.expect(t, ok && string(bytes) == "abcd", "a file beside it")
	for bad in ([?]string{"", "../x.bin", "/etc/passwd", "a/../b", "C:\\x", "http://x/y.bin", "a\\b"}) {
		_, found := model_neighbour(bad)
		testing.expectf(t, !found, "`%s` is not read", bad)
	}
	_, found := model_neighbour("nothing.bin")
	testing.expect(t, !found, "a file that is not there")
}

@(test)
test_the_model_example_runs_with_its_ship :: proc(t: ^testing.T) {
	// the example's own folder, which is where its model is
	roci.start_headless(1)
	p, ok := load("examples/model/sketch.roci", example_text("model"))
	if !testing.expect(t, ok, "the example checks") {
		return
	}
	start(p)
	for _ in 0 ..< 3 {
		roci.step()
	}
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, len(roci.scene_items(first_window())), 9) // eight parts of the ship and the floor
	testing.expect(t, roci.shadows_of(first_window()), "it asks for shadows")
}
