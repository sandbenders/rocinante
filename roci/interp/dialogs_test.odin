// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "../folder"
import "../lang"
import "../platform"
import "core:os"
import "core:strings"
import "core:testing"

// A path as a sketch writes it: a backslash in text starts an escape (the `\U` of `C:\Users`), so a Windows
// path is written with forward slashes, which Windows takes too.
sketch_path :: proc(path: string) -> string {
	out, _ := strings.replace_all(path, "\\", "/", context.temp_allocator)
	return out
}

// Runs a sketch in a folder of its own, with the files given (name below the folder, text) written first.
@(private = "file")
run_with_files :: proc(t: ^testing.T, folder_name, text: string, files: [][2]string, frames := 1) -> ^Interp {
	root := strings.concatenate({"output/tests/", folder_name}, context.temp_allocator)
	_ = os.remove_all(root)
	testing.expect(t, folder.ensure_directory(root))
	for f in files {
		path := strings.concatenate({root, "/", f[0]}, context.temp_allocator)
		if slash := strings.last_index_byte(path, '/'); slash > 0 {
			testing.expect(t, folder.ensure_directory(path[:slash]))
		}
		testing.expect(t, os.write_entire_file(path, transmute([]byte)f[1]) == nil)
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

// Plays the player: answers the one dialog the sketch has open.
@(private = "file")
answer :: proc(p: ^Interp, path: string) {
	if len(p.asks) > 0 {
		platform.dialog_deliver(p.asks[0].id, path)
	}
}

@(test)
test_the_block_of_ask_file_runs_when_the_player_chooses :: proc(t: ^testing.T) {
	p := run_with_files(t, "dialogs_file", `w = window size 10 10
got = ""
count_runs = 0
ask file "png jpg" [
  got = chosen
  count_runs = count_runs + 1
]
`, {})
	defer finish(p)
	// nothing runs while the dialog is open, and the sketch goes on
	roci.step()
	testing.expect_value(t, as_text(global_named(p, "got")), "")
	testing.expect_value(t, len(p.asks), 1)
	answer(p, "/home/player/photo.png")
	roci.step()
	testing.expect_value(t, as_text(global_named(p, "got")), "/home/player/photo.png")
	testing.expect_value(t, as_number(global_named(p, "count_runs")), 1)
	testing.expect_value(t, len(p.asks), 0)
	// and it runs once
	roci.step()
	testing.expect_value(t, as_number(global_named(p, "count_runs")), 1)
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_a_dialog_closed_without_a_choice_runs_nothing :: proc(t: ^testing.T) {
	p := run_with_files(t, "dialogs_closed", `w = window size 10 10
ran = false
ask folder [ ran = true ]
`, {})
	defer finish(p)
	answer(p, "")
	roci.step()
	roci.step()
	testing.expect_value(t, as_bool(global_named(p, "ran")), false)
	testing.expect_value(t, len(p.asks), 0)
}

@(test)
test_ask_save_runs_its_block_with_the_path_and_save_writes_there :: proc(t: ^testing.T) {
	p := run_with_files(t, "dialogs_save", `w = window size 10 10
where = ""
ask save "notes.json" [
  where = chosen
  save { a: 1 } chosen
]
`, {})
	defer finish(p)
	target := "output/tests/dialogs_save/out/chosen.json"
	testing.expect(t, folder.ensure_directory("output/tests/dialogs_save/out"))
	absolute, _ := os.get_absolute_path("output/tests/dialogs_save/out", context.temp_allocator)
	absolute = strings.concatenate({absolute, "/chosen.json"}, context.temp_allocator)
	answer(p, absolute)
	roci.step()
	roci.step()
	testing.expect_value(t, as_text(global_named(p, "where")), absolute)
	for e in p.errors {
		testing.expectf(t, false, "error %v %v", e.id, e.args)
	}
	data, err := os.read_entire_file(target, context.temp_allocator)
	testing.expect(t, err == nil)
	testing.expect(t, strings.contains(string(data), "\"a\""))
}

@(test)
test_read_takes_a_file_of_assets_or_one_the_player_chose :: proc(t: ^testing.T) {
	p := run_with_files(t, "dialogs_read", `w = window size 10 10
from_assets = read "notes.txt"
outside = ""
ask file [ outside = read chosen ]
`, {{"assets/data/notes.txt", "from assets"}, {"elsewhere/other.txt", "from the player"}})
	defer finish(p)
	testing.expect_value(t, as_text(global_named(p, "from_assets")), "from assets")
	absolute, _ := os.get_absolute_path("output/tests/dialogs_read/elsewhere/other.txt", context.temp_allocator)
	answer(p, absolute)
	roci.step()
	roci.step()
	testing.expect_value(t, as_text(global_named(p, "outside")), "from the player")
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_read_refuses_a_file_nobody_chose :: proc(t: ^testing.T) {
	absolute, _ := os.get_absolute_path("output/tests/dialogs_refuse/elsewhere/secret.txt", context.temp_allocator)
	p := run_with_files(t, "dialogs_refuse", strings.concatenate({`x = read "`, sketch_path(absolute), `"
y = read "nothing.txt"
`}, context.temp_allocator), {{"elsewhere/secret.txt", "private"}})
	defer finish(p)
	testing.expect_value(t, as_text(global_named(p, "x")), "")
	testing.expect_value(t, as_text(global_named(p, "y")), "")
	if testing.expect_value(t, len(p.errors), 2) {
		testing.expect_value(t, p.errors[0].id, lang.Message_Id.File_Not_Read)
	}
}

@(test)
test_load_takes_a_picture_the_player_chose :: proc(t: ^testing.T) {
	png, err := os.read_entire_file("examples/outline/assets/images/ship.png", context.temp_allocator)
	testing.expect(t, err == nil)
	p := run_with_files(t, "dialogs_picture", `w = window size 10 10
photo = load "ship.png"
size = 0
ask file "png" [
  photo = load chosen
  size = 1
]
`, {{"elsewhere/ship.png", string(png)}, {"assets/images/ship.png", string(png)}})
	defer finish(p)
	absolute, _ := os.get_absolute_path("output/tests/dialogs_picture/elsewhere/ship.png", context.temp_allocator)
	answer(p, absolute)
	roci.step()
	roci.step()
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, as_number(global_named(p, "size")), 1)
}

@(test)
test_the_clipboard_is_written_and_read_back :: proc(t: ^testing.T) {
	p := run_with_files(t, "dialogs_clipboard", `before = clipboard
copy to clipboard "#ff8800"
after = clipboard
`, {})
	defer finish(p)
	testing.expect_value(t, as_text(global_named(p, "before")), "")
	testing.expect_value(t, as_text(global_named(p, "after")), "#ff8800")
}

@(test)
test_open_says_when_it_cannot :: proc(t: ^testing.T) {
	p := run_with_files(t, "dialogs_open", `open "nothing.png"
open "https://example.org"
`, {})
	defer finish(p)
	// a name that is not in assets, and a web address with no system to open it (headless)
	testing.expect_value(t, len(p.errors), 2)
	testing.expect_value(t, p.errors[0].id, lang.Message_Id.Open_Failed)
	testing.expect_value(t, p.errors[1].id, lang.Message_Id.Open_Failed)
}

@(test)
test_a_sketch_that_asks_every_frame_has_a_few_dialogs_open_at_most :: proc(t: ^testing.T) {
	p := run_with_files(t, "dialogs_many", `w = window size 10 10
draw [ ask file [ print chosen ] ]
`, {}, 12)
	defer finish(p)
	testing.expect_value(t, len(p.asks), MAX_OPEN_DIALOGS)
}

@(test)
test_the_dialogs_example_loads_a_picture_saves_a_path_and_copies_and_pastes :: proc(t: ^testing.T) {
	png, err := os.read_entire_file("examples/dialogs/assets/images/ship.png", context.temp_allocator)
	testing.expect(t, err == nil)
	p := run_with_files(t, "dialogs_example", example_text("dialogs"), {{"assets/images/ship.png", string(png)}, {"elsewhere/other.png", string(png)}}, 3)
	defer finish_all()
	w := first_window()
	testing.expect_value(t, len(p.errors), 0)
	// choose a picture
	testing.expect(t, ask_node(w, "choose a picture", .Click))
	steps(2)
	testing.expect_value(t, len(p.asks), 1)
	other, _ := os.get_absolute_path("output/tests/dialogs_example/elsewhere/other.png", context.temp_allocator)
	answer(p, other)
	steps(2)
	testing.expect_value(t, as_text(global_named(p, "path")), other)
	testing.expect_value(t, as_text(global_named(p, "note")), "chosen")
	// copy it, then paste it
	testing.expect(t, ask_node(w, "copy its path", .Click))
	steps(2)
	testing.expect(t, ask_node(w, "paste", .Click))
	steps(2)
	testing.expect_value(t, as_text(global_named(p, "pasted")), other)
	// save it where the player says
	testing.expect(t, ask_node(w, "save its path", .Click))
	steps(2)
	target, _ := os.get_absolute_path("output/tests/dialogs_example", context.temp_allocator)
	target = strings.concatenate({target, "/path.txt"}, context.temp_allocator)
	answer(p, target)
	steps(3)
	text, read_err := os.read_entire_file(target, context.temp_allocator)
	testing.expect(t, read_err == nil)
	testing.expect_value(t, string(text), other)
	testing.expect_value(t, len(p.errors), 0)
}
