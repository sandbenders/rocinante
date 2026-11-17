// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "../folder"
import "../lang"
import "core:os"
import "core:strings"
import "core:testing"
import sdl "vendor:sdl3"

// Runs a sketch in a folder of its own whose `assets/data` holds the files, each as (name, text).
@(private = "file")
run_with_data :: proc(t: ^testing.T, folder_name, text: string, files: [][2]string, frames := 2) -> ^Interp {
	root := strings.concatenate({"output/tests/", folder_name}, context.temp_allocator)
	_ = os.remove_all(root)
	testing.expect(t, folder.ensure_directory(strings.concatenate({root, "/assets/data"}, context.temp_allocator)))
	for f in files {
		testing.expect(t, os.write_entire_file(strings.concatenate({root, "/assets/data/", f[0]}, context.temp_allocator), transmute([]byte)f[1]) == nil)
	}
	path := strings.concatenate({root, "/sketch.roci"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(path, transmute([]byte)text) == nil)
	roci.start_headless(1)
	p, ok := load(path, text)
	if !testing.expectf(t, ok, "the sketch has errors:\n%s", lang.render_all(p.src, p.checked.diagnostics, context.temp_allocator)) {
		return p
	}
	watch(p, path)
	start(p)
	for _ in 0 ..< frames {
		roci.step()
	}
	return p
}

@(test)
test_a_json_file_is_a_record_and_a_list_with_its_members_as_fields :: proc(t: ^testing.T) {
	p := run_with_data(t, "data_json", `birds = load "birds.json"
wings = 0
names = ""
for each b in birds.items [
  wings = wings + b.wings
  names = names + b.name + " "
]
heading = birds.title
first = item 1 of birds.items
second = item 2 of birds.items
tall = first.tall
missing = second.pos
`, {{"birds.json", `{ "title": "Birds", "items": [ { "name": "owl", "wings": 2, "tall": true }, { "name": "emu", "wings": 2, "pos": [3, 4] } ] }`}})
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, as_number(global_named(p, "wings")), 4)
	testing.expect_value(t, as_text(global_named(p, "names")), "owl emu ")
	testing.expect_value(t, as_text(global_named(p, "heading")), "Birds")
	testing.expect_value(t, as_bool(global_named(p, "tall")), true)
	// the first bird has no `pos`, and a member a record lacks starts as the zero of its place
	testing.expect(t, global_named(p, "missing") != nil)
}

@(test)
test_a_csv_file_is_a_list_of_records_and_numbers_are_numbers :: proc(t: ^testing.T) {
	p := run_with_data(t, "data_csv", `rows = load "scores.csv"
total = 0
best = ""
for each r in rows [
  total = total + r.score
  if r.score > 11 [ best = r.player_name ]
]
n = count rows
`, {{"scores.csv", "Player Name,Score\nAna,10\nBo,12.5\n\"Cy, Jr\",3\n"}})
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, as_number(global_named(p, "total")), 25.5)
	testing.expect_value(t, as_text(global_named(p, "best")), "Bo")
	testing.expect_value(t, as_number(global_named(p, "n")), 3)
}

@(test)
test_a_text_file_and_a_toml_file_load :: proc(t: ^testing.T) {
	p := run_with_data(t, "data_text", `poem = load "poem.txt"
settings = load "game.toml"
lives = settings.lives
`, {{"poem.txt", "roses\nare red\n"}, {"game.toml", "lives = 3\nname = \"Ana\"\n"}})
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, as_text(global_named(p, "poem")), "roses\nare red\n")
	testing.expect_value(t, as_number(global_named(p, "lives")), 3)
}

@(test)
test_loading_a_file_again_gives_the_same_list :: proc(t: ^testing.T) {
	p := run_with_data(t, "data_same", `a = load "n.json"
b = load "n.json"
add 4 to a
size = count b
`, {{"n.json", "[1, 2, 3]"}})
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, as_number(global_named(p, "size")), 4)
}

@(test)
test_a_data_file_is_found_in_a_folder_of_assets_by_its_name :: proc(t: ^testing.T) {
	root := "output/tests/data_where"
	_ = os.remove_all(root)
	testing.expect(t, folder.ensure_directory("output/tests/data_where/assets/data/levels"))
	testing.expect(t, os.write_entire_file("output/tests/data_where/assets/data/levels/one.json", transmute([]byte)string("{ \"w\": 5 }")) == nil)
	text := "level_one = load \"one.json\"\nwide = level_one.w\n"
	testing.expect(t, os.write_entire_file("output/tests/data_where/sketch.roci", transmute([]byte)text) == nil)
	roci.start_headless(1)
	p, ok := load("output/tests/data_where/sketch.roci", text)
	testing.expect(t, ok)
	watch(p, "output/tests/data_where/sketch.roci")
	start(p)
	roci.step()
	defer finish(p)
	testing.expect_value(t, as_number(global_named(p, "wide")), 5)
}

@(test)
test_lines_are_split_and_the_files_of_a_folder_are_listed :: proc(t: ^testing.T) {
	root := "output/tests/data_lines"
	_ = os.remove_all(root)
	testing.expect(t, folder.ensure_directory("output/tests/data_lines/assets/images"))
	testing.expect(t, folder.ensure_directory("output/tests/data_lines/assets/data"))
	for name in ([]string{"b.png", "a.png"}) {
		testing.expect(t, os.write_entire_file(strings.concatenate({root, "/assets/images/", name}, context.temp_allocator), transmute([]byte)string("x")) == nil)
	}
	testing.expect(t, os.write_entire_file("output/tests/data_lines/assets/data/poem.txt", transmute([]byte)string("one\r\ntwo\n\nfour")) == nil)
	text := "a = lines (load \"poem.txt\")\nb = lines \"\"\nc = lines \"x\\n\"\nnames = files in \"images\"\nnone = files in \"nothing\"\nn = count a\nfirst = item 1 of names\nm = count none\nlast_line = item 4 of a\n"
	testing.expect(t, os.write_entire_file("output/tests/data_lines/sketch.roci", transmute([]byte)text) == nil)
	roci.start_headless(1)
	p, ok := load("output/tests/data_lines/sketch.roci", text)
	if !testing.expectf(t, ok, "%s", lang.render_all(p.src, p.checked.diagnostics, context.temp_allocator)) {
		destroy(p)
		roci.shutdown()
		return
	}
	watch(p, "output/tests/data_lines/sketch.roci")
	start(p)
	roci.step()
	defer finish(p)
	testing.expect_value(t, as_number(global_named(p, "n")), 4) // one, two, an empty line, four
	testing.expect_value(t, as_text(global_named(p, "last_line")), "four")
	testing.expect_value(t, len(as_list(global_named(p, "b")).items), 0)
	testing.expect_value(t, len(as_list(global_named(p, "c")).items), 1)
	testing.expect_value(t, as_text(global_named(p, "first")), "a.png")
	testing.expect_value(t, as_number(global_named(p, "m")), 0)
	testing.expect_value(t, as_list(global_named(p, "a")).items[0].(string), "one") // no \r left on it
}

@(test)
test_a_value_is_saved_in_the_kind_of_file_its_name_ends_in :: proc(t: ^testing.T) {
	root := "output/tests/data_save"
	_ = os.remove_all(root)
	testing.expect(t, folder.ensure_directory(root))
	text := `scores = [ { name: "Ana", points: 10 } { name: "Bo, Jr", points: 12.5 } ]
settings = { lives: 3, name: "Ana", tint: red, spot: { 1, 2 } }
save scores "scores.json"
save scores "scores.csv"
save settings "settings.toml"
save "plain\nlines" "notes.txt"
save settings "settings.json"
`
	testing.expect(t, os.write_entire_file("output/tests/data_save/sketch.roci", transmute([]byte)text) == nil)
	roci.start_headless(1)
	p, ok := load("output/tests/data_save/sketch.roci", text)
	testing.expectf(t, ok, "%s", lang.render_all(p.src, p.checked.diagnostics, context.temp_allocator))
	watch(p, "output/tests/data_save/sketch.roci")
	start(p)
	roci.step()
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	read :: proc(name: string) -> string {
		bytes, _ := os.read_entire_file(strings.concatenate({"output/tests/data_save/output/", name}, context.temp_allocator), context.temp_allocator)
		return string(bytes)
	}
	testing.expect(t, strings.contains(read("scores.json"), "\"points\": 12.5"), read("scores.json"))
	testing.expect_value(t, read("scores.csv"), "name,points\nAna,10\n\"Bo, Jr\",12.5\n")
	testing.expect(t, strings.contains(read("settings.toml"), "lives = 3"), read("settings.toml"))
	testing.expect_value(t, read("notes.txt"), "plain\nlines")
	testing.expect(t, strings.contains(read("settings.json"), "\"tint\": \"#ff0000ff\""), read("settings.json"))
	testing.expect(t, strings.contains(read("settings.json"), "\"spot\": [ 1, 2 ]"), read("settings.json"))
}

@(test)
test_a_save_that_cannot_be_written_is_said_and_the_sketch_goes_on :: proc(t: ^testing.T) {
	p := run_text(t, "save 5 \"x.xyz\"\nsave 5 \"table.csv\"\nsave { 1, 2 } \"v.toml\"\nok = 1\n", 2)
	defer finish(p)
	testing.expect_value(t, as_number(global_named(p, "ok")), 1)
	testing.expect_value(t, len(p.errors), 3)
	for e in p.errors {
		testing.expect_value(t, e.id, lang.Message_Id.Save_Failed)
	}
}

@(test)
test_a_record_that_holds_itself_has_no_end_to_write :: proc(t: ^testing.T) {
	p := run_text(t, "a = { name: \"x\", next: { name: \"y\" } }\na.next = a\nsave a \"loop.json\"\nok = 1\n", 2)
	defer finish(p)
	testing.expect_value(t, as_number(global_named(p, "ok")), 1)
	found := false
	for e in p.errors {
		found ||= e.id == .Save_Failed && strings.contains(e.args[1], "holds itself")
	}
	testing.expect(t, found, "the loop is said")
}

@(test)
test_the_data_example_reads_its_files_and_saves_a_summary :: proc(t: ^testing.T) {
	root := "output/tests/data_example"
	_ = os.remove_all(root)
	testing.expect(t, folder.ensure_directory("output/tests/data_example/assets/data"))
	for name in ([]string{"birds.json", "scores.csv", "poem.txt"}) {
		bytes, err := os.read_entire_file(strings.concatenate({"examples/data/assets/data/", name}, context.temp_allocator), context.temp_allocator)
		testing.expect(t, err == nil)
		testing.expect(t, os.write_entire_file(strings.concatenate({root, "/assets/data/", name}, context.temp_allocator), bytes) == nil)
	}
	text := example_text("data")
	testing.expect(t, os.write_entire_file("output/tests/data_example/sketch.roci", transmute([]byte)text) == nil)
	roci.start_headless(1)
	p, ok := load("output/tests/data_example/sketch.roci", text)
	if !testing.expectf(t, ok, "%s", lang.render_all(p.src, p.checked.diagnostics, context.temp_allocator)) {
		destroy(p)
		roci.shutdown()
		return
	}
	watch(p, "output/tests/data_example/sketch.roci")
	start(p)
	roci.step()
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, as_number(global_named(p, "total")), 172)
	testing.expect_value(t, as_number(global_named(p, "best")), 50)
	w := first_window()
	roci.step({key_event(w, sdl.Scancode.S)})
	roci.step()
	bytes, err := os.read_entire_file("output/tests/data_example/output/summary.json", context.temp_allocator)
	testing.expect(t, err == nil)
	testing.expect(t, strings.contains(string(bytes), "\"total\": 172") && strings.contains(string(bytes), "\"birds\": 4"), string(bytes))
}
