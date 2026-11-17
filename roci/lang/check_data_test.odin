// SPDX-License-Identifier: 0BSD
#+feature dynamic-literals
package lang

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

// A reader of data files for tests: the files held in a table, or a folder's `assets/data`.
@(thread_local) @(private = "file") test_files: map[string]string
@(thread_local) @(private = "file") test_root: string

@(private = "file")
reader :: proc(name: string) -> (text: string, found: bool, why: string) {
	if content, there := test_files[name]; there {
		return content, true, ""
	}
	if test_root != "" {
		for place in ([]string{"assets/data", "assets"}) {
			bytes, err := os.read_entire_file(fmt.tprintf("%s/%s/%s", test_root, place, name), context.temp_allocator)
			if err == nil {
				return string(bytes), true, ""
			}
		}
	}
	return "", false, "there is no file of that name in it"
}

// Reads data files from the `assets` of this folder from now on (a program's checks in the corpus tests).
use_folder_for_data :: proc(root: string) {
	test_root = strings.clone(root, context.temp_allocator)
	set_data_reader(reader)
}

@(private = "file")
with_files :: proc(files: map[string]string) {
	test_files = files
	test_root = ""
	set_data_reader(reader)
}

@(private = "file")
done :: proc() {
	set_data_reader(nil)
	delete(test_files)
	test_files = nil
	test_root = ""
}

@(test)
test_a_json_file_gives_its_shape_to_what_load_gives :: proc(t: ^testing.T) {
	with_files({"birds.json" = `{ "title": "Birds", "count": 2, "items": [ { "name": "owl", "wings": 2, "tall": true }, { "name": "emu", "wings": 2, "pos": [1, 2] } ] }`})
	defer done()
	got := check_text("birds = load \"birds.json\"\nn = birds.count\nfirst = birds.items\nw = 0\nfor each b in birds.items [ w = w + b.wings ]\ncircle at 100 100 radius w")
	testing.expect_value(t, len(got.checked.diagnostics), 0)
	names := describe_names(got.checked, context.temp_allocator)
	testing.expect(t, strings.contains(names, "birds: a record with title, count and items"), names)
	testing.expect(t, strings.contains(names, "n: a number"), names)
	testing.expect(t, strings.contains(names, "first: a list of records with name, wings, tall and pos"), names)
}

@(test)
test_a_field_the_file_does_not_have_is_found_out_before_the_sketch_runs :: proc(t: ^testing.T) {
	with_files({"birds.json" = `[ { "name": "owl" } ]`})
	defer done()
	got := check_text("birds = load \"birds.json\"\nfor each b in birds [ print b.wings ]")
	testing.expect(t, len(got.checked.diagnostics) == 1 && got.checked.diagnostics[0].id == .Unknown_Field, "an unknown field")
}

@(test)
test_a_csv_is_a_list_of_records_and_its_number_columns_are_numbers :: proc(t: ^testing.T) {
	with_files({"scores.csv" = "Player Name,Score\nAna,10\nBo,12.5\n"})
	defer done()
	got := check_text("rows = load \"scores.csv\"\ntop = 0\nfor each r in rows [ top = top + r.score ]\nfirst = rows")
	testing.expectf(t, len(got.checked.diagnostics) == 0, "%s", render_all(got.src, got.checked.diagnostics, context.temp_allocator))
	names := describe_names(got.checked, context.temp_allocator)
	testing.expect(t, strings.contains(names, "rows: a list of records with player_name and score"), names)
	testing.expect(t, strings.contains(names, "top: a number"), names)
}

@(test)
test_a_text_file_is_text_and_no_reader_means_a_mixed_value :: proc(t: ^testing.T) {
	got := check_text("poem = load \"poem.txt\"\nother = load \"birds.json\"")
	testing.expect_value(t, len(got.checked.diagnostics), 0)
	names := describe_names(got.checked, context.temp_allocator)
	testing.expect(t, strings.contains(names, "poem: text"), names)
	testing.expect(t, strings.contains(names, "other: a mixed value") || strings.contains(names, "other: not known") || strings.contains(names, "other:"), names)
}

@(test)
test_members_of_a_file_that_differ_in_kind_keep_the_first_and_null_takes_the_kind_of_the_rest :: proc(t: ^testing.T) {
	with_files({"a.json" = `[ { "x": null, "y": 1 }, { "x": "text", "y": "no" } ]`, "b.json" = `[ null, 1 ]`, "c.json" = `[ 1, "a" ]`, "d.json" = `[]`})
	defer done()
	got := check_text("a = load \"a.json\"\nb = load \"b.json\"\nc = load \"c.json\"\nd = load \"d.json\"")
	testing.expect_value(t, len(got.checked.diagnostics), 0)
	names := describe_names(got.checked, context.temp_allocator)
	testing.expect(t, strings.contains(names, "b: a list of numbers"), names)
	testing.expect(t, strings.contains(names, "c: a list of mixed values") || strings.contains(names, "c: a list"), names)
}

@(test)
test_the_same_place_in_a_file_is_one_shape_in_both_passes :: proc(t: ^testing.T) {
	with_files({"a.json" = `{ "p": { "x": 1 } }`})
	defer done()
	got := check_text("a = load \"a.json\"\nb = load \"a.json\"\nq = a.p.x + b.p.x")
	testing.expect_value(t, len(got.checked.diagnostics), 0)
}

@(test)
test_a_missing_or_unreadable_data_file_is_said_in_words :: proc(t: ^testing.T) {
	with_files({"bad.json" = "{ \"a\": 1,\n \"b\" }"})
	defer done()
	expect_ids(t, "x = load \"nothing.json\"", {.Data_File_Missing})
	expect_ids(t, "x = load \"bad.json\"", {.Data_File_Unreadable})
	// one mistake, one message: what is done with the value afterwards is not another
	expect_ids(t, "x = load \"bad.json\"\ny = x.a + 1", {.Data_File_Unreadable})
}

@(test)
test_a_data_file_named_by_a_computed_text_is_not_one_the_checker_reads :: proc(t: ^testing.T) {
	with_files({})
	defer done()
	// the name is worked out while the sketch runs: it stays a picture, as it always was
	expect_ids(t, "name = \"a\" + \".json\"\nx = load name", {})
}

@(private = "file")
expect_ids :: proc(t: ^testing.T, text: string, want: []Message_Id, loc := #caller_location) {
	got := check_text(text)
	ids := make([dynamic]Message_Id, context.temp_allocator)
	for d in got.checked.diagnostics {
		append(&ids, d.id)
	}
	if !testing.expectf(t, len(ids) == len(want), "`%s`: got %v, want %v", text, ids, want, loc = loc) {
		return
	}
	for id, i in want {
		testing.expectf(t, ids[i] == id, "`%s` message %d: got %v, want %v", text, i, ids[i], id, loc = loc)
	}
}

@(test)
test_a_spreadsheet_gives_its_columns_as_fields_and_a_sheet_can_be_named :: proc(t: ^testing.T) {
	bytes, err := os.read_entire_file("tests/office/book.xlsx", context.temp_allocator)
	testing.expect(t, err == nil)
	with_files({"book.xlsx" = string(bytes)})
	defer done()
	got := check_text("stock = load \"book.xlsx\"\nnotes = load \"book.xlsx\" sheet \"Notes\"\nn = 0\nfor each r in stock [ n = n + r.count ]\nm = 0\nfor each r in notes [ m = m + r.day ]")
	testing.expectf(t, len(got.checked.diagnostics) == 0, "%s", render_all(got.src, got.checked.diagnostics, context.temp_allocator))
	names := describe_names(got.checked, context.temp_allocator)
	testing.expect(t, strings.contains(names, "stock: a list of records with item_name, count, price and in_stock"), names)
	testing.expect(t, strings.contains(names, "notes: a list of records with day and note"), names)
	// a sheet that is not there says which are, and a sheet that is worked out is not read before the sketch runs
	expect_ids(t, "x = load \"book.xlsx\" sheet \"Nope\"", {.Data_File_Unreadable})
	expect_ids(t, "name = \"Notes\"\nx = load \"book.xlsx\" sheet name", {})
	// a document is its text
	letter := check_text("x = load \"letter.odt\"")
	testing.expect(t, strings.contains(describe_names(letter.checked, context.temp_allocator), "x: text"))
}
