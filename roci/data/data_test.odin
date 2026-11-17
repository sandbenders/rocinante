// SPDX-License-Identifier: 0BSD
package data

import "core:strings"
import "core:testing"

@(private = "file")
json :: proc(t: ^testing.T, text: string) -> Datum {
	d, problem, ok := parse_json(text)
	testing.expectf(t, ok, "`%s` should be JSON: %s", text, problem.why)
	return d
}

@(private = "file")
refused :: proc(t: ^testing.T, text: string, line: int, why: string) {
	d, problem, ok := parse_json(text)
	testing.expectf(t, !ok, "`%s` is not JSON", text)
	if ok {
		destroy(d)
		return
	}
	testing.expectf(t, problem.line == line, "`%s`: line %d, got %d", text, line, problem.line)
	testing.expectf(t, strings.contains(problem.why, why), "`%s`: %s, got %s", text, why, problem.why)
}

@(test)
test_json_values_are_read :: proc(t: ^testing.T) {
	d := json(t, `{ "name": "Ana", "age": 31, "tall": true, "pet": null, "scores": [1, 2.5, -3e2], "home": { "city": "Roma" } }`)
	defer destroy(d)
	o := d.(Object)
	testing.expect_value(t, len(o), 6)
	testing.expect_value(t, o[0].key, "name")
	name, _ := member(o, "name")
	testing.expect_value(t, name.(string), "Ana")
	age, _ := member(o, "age")
	testing.expect_value(t, age.(f64), 31)
	tall, _ := member(o, "tall")
	testing.expect_value(t, tall.(bool), true)
	pet, _ := member(o, "pet")
	_, is_null := pet.(Null)
	testing.expect(t, is_null)
	scores, _ := member(o, "scores")
	testing.expect_value(t, len(scores.([]Datum)), 3)
	testing.expect_value(t, scores.([]Datum)[2].(f64), -300)
	home, _ := member(o, "home")
	city, _ := member(home.(Object), "city")
	testing.expect_value(t, city.(string), "Roma")
	_, found := member(o, "nothing")
	testing.expect(t, !found)
}

@(test)
test_json_scalars_empty_things_and_a_byte_order_mark :: proc(t: ^testing.T) {
	for text in ([]string{"1", "  \"a\"  ", "true", "false", "null", "[]", "{}", "[[]]", "\xef\xbb\xbf[1]"}) {
		destroy(json(t, text))
	}
	d := json(t, "{}")
	defer destroy(d)
	testing.expect_value(t, len(d.(Object)), 0)
}

@(test)
test_json_text_escapes_are_read :: proc(t: ^testing.T) {
	d := json(t, `"a\"b\\c\/d\b\f\n\r\t é 😀 \ud800"`)
	defer destroy(d)
	testing.expect_value(t, d.(string), "a\"b\\c/d\b\f\n\r\t é 😀 �")
}

@(test)
test_a_member_named_twice_keeps_its_last_value_in_its_first_place :: proc(t: ^testing.T) {
	d := json(t, `{ "a": 1, "b": 2, "a": 3 }`)
	defer destroy(d)
	o := d.(Object)
	testing.expect_value(t, len(o), 2)
	testing.expect_value(t, o[0].key, "a")
	testing.expect_value(t, o[0].value.(f64), 3)
}

@(test)
test_a_file_that_is_not_json_is_said_in_words_with_its_line :: proc(t: ^testing.T) {
	refused(t, "", 1, "file is empty")
	refused(t, "  \n ", 1, "file is empty")
	refused(t, "[1, 2", 1, "never closed")
	refused(t, "[1 2]", 1, "comma or a closing ]")
	refused(t, "{ \"a\": 1\n \"b\": 2 }", 2, "comma or a closing }")
	refused(t, "{ \"a\" 1 }", 1, "colon is missing")
	refused(t, "{ a: 1 }", 1, "name in double quotes")
	refused(t, "{ \"a\": 1", 1, "never closed with }")
	refused(t, "\n\n[1,]", 3, "not the start of a value")
	refused(t, "'a'", 1, "not the start of a value")
	refused(t, "nope", 1, "did you mean null")
	refused(t, "tru", 1, "did you mean true")
	refused(t, "-", 1, "minus sign")
	refused(t, "1.", 1, "digits after")
	refused(t, "1e", 1, "exponent")
	refused(t, "\"abc", 1, "never closed")
	refused(t, "\"ab\ncd\"", 1, "ends at the end of its line")
	refused(t, `"\q"`, 1, "is not a way to write a character")
	refused(t, `"\u12"`, 1, "four hexadecimal digits")
	refused(t, "1 2", 1, "more after the end")
	refused(t, "[1]\n[2]", 2, "more after the end")
	refused(t, "[", 1, "ends where a value should be")
	refused(t, `"a\`, 1, "never closed")
}

@(test)
test_json_that_goes_too_deep_is_a_problem_and_not_a_crash :: proc(t: ^testing.T) {
	deep := strings.concatenate({strings.repeat("[", 500, context.temp_allocator), strings.repeat("]", 500, context.temp_allocator)}, context.temp_allocator)
	refused(t, deep, 1, "too deeply")
	ok_depth := strings.concatenate({strings.repeat("[", 100, context.temp_allocator), strings.repeat("]", 100, context.temp_allocator)}, context.temp_allocator)
	destroy(json(t, ok_depth))
}

@(test)
test_json_is_written_and_read_back_the_same :: proc(t: ^testing.T) {
	source := `{ "name": "Ana \"A\"", "age": 31, "ratio": 0.25, "big": 1e20, "tall": true, "pet": null, "scores": [1, 2, 3], "empty": [], "none": {}, "rows": [ { "x": 1 }, { "x": 2 } ] }`
	d := json(t, source)
	defer destroy(d)
	written := write_json(d)
	defer delete(written)
	again := json(t, written)
	defer destroy(again)
	second := write_json(again)
	defer delete(second)
	testing.expect_value(t, second, written)
	testing.expect(t, strings.contains(written, "\"scores\": [ 1, 2, 3 ]"), written)
	testing.expect(t, strings.contains(written, "\"age\": 31,"), written)
	testing.expect(t, strings.contains(written, "\"ratio\": 0.25"), written)
	testing.expect(t, strings.contains(written, "\"empty\": []"), written)
	testing.expect(t, strings.contains(written, "\"none\": {}"), written)
	testing.expect(t, strings.has_suffix(written, "}\n"))
}

@(test)
test_what_json_cannot_say_is_written_as_null_and_text_is_escaped :: proc(t: ^testing.T) {
	zero := 0.0
	items := []Datum{zero / zero, 1.0 / zero, "tab\there\u0001", 12345678901.0, -0.5}
	text := write_json(items)
	defer delete(text)
	testing.expect_value(t, text, "[ null, null, \"tab\\there\\u0001\", 12345678901, -0.5 ]\n")
	long := make([]Datum, 20)
	defer delete(long)
	for &x in long {
		x = 1.0
	}
	wrapped := write_json(long)
	defer delete(wrapped)
	testing.expect(t, strings.has_prefix(wrapped, "[\n  1,\n"), wrapped)
}

@(test)
test_a_title_becomes_the_name_of_a_field :: proc(t: ^testing.T) {
	cases := [?][3]string{
		{"First Name", "first_name", ""},
		{"  Age ", "age", ""},
		{"2nd place", "_2nd_place", ""},
		{"price ($)", "price", ""},
		{"a--b", "a_b", ""},
		{"snake_case", "snake_case", ""},
		{"Größe", "größe", ""},
		{"", "column_3", ""},
		{"!!!", "column_3", ""},
	}
	for c in cases {
		got := field_name(c[0], 3)
		testing.expectf(t, got == c[1], "`%s` is `%s`, got `%s`", c[0], c[1], got)
		delete(got)
	}
}

@(private = "file")
table :: proc(t: ^testing.T, text: string, delimiter: byte = ',') -> []Datum {
	d, problem, ok := parse_table(text, delimiter)
	testing.expectf(t, ok, "`%s`: %s", text, problem.why)
	items, _ := d.([]Datum)
	return items
}

@(test)
test_a_csv_is_a_list_of_records_and_a_column_of_numbers_is_numbers :: proc(t: ^testing.T) {
	items := table(t, "Name,Age,Score\nAna,31,1.5\nBo,,2\n\nCy,7,-1e1\n")
	defer destroy(items)
	testing.expect_value(t, len(items), 3)
	first := items[0].(Object)
	testing.expect_value(t, first[0].key, "name")
	testing.expect_value(t, first[0].value.(string), "Ana")
	testing.expect_value(t, first[1].value.(f64), 31)
	testing.expect_value(t, first[2].value.(f64), 1.5)
	second := items[1].(Object)
	testing.expect_value(t, second[1].value.(f64), 0) // an empty cell of a number column
	testing.expect_value(t, items[2].(Object)[2].value.(f64), -10)
}

@(test)
test_a_column_with_a_word_in_it_is_text_all_the_way_down :: proc(t: ^testing.T) {
	items := table(t, "id,code\n1,007\n2,x9\n")
	defer destroy(items)
	testing.expect_value(t, items[0].(Object)[0].value.(f64), 1)
	testing.expect_value(t, items[0].(Object)[1].value.(string), "007")
	items2 := table(t, "n\n1\ninf\n")
	defer destroy(items2)
	testing.expect_value(t, items2[0].(Object)[0].value.(string), "1") // infinity is a word here
	items3 := table(t, "n\n-\n.\n")
	defer destroy(items3)
	testing.expect_value(t, items3[0].(Object)[0].value.(string), "-")
}

@(test)
test_csv_quotes_line_breaks_and_a_byte_order_mark :: proc(t: ^testing.T) {
	items := table(t, "\xef\xbb\xbfa,b\r\n\"x, y\",\"say \"\"hi\"\"\"\r\n\"two\nlines\",z\r\n")
	defer destroy(items)
	testing.expect_value(t, len(items), 2)
	testing.expect_value(t, items[0].(Object)[0].value.(string), "x, y")
	testing.expect_value(t, items[0].(Object)[1].value.(string), "say \"hi\"")
	testing.expect_value(t, items[1].(Object)[0].value.(string), "two\nlines")
}

@(test)
test_a_tsv_splits_on_tabs :: proc(t: ^testing.T) {
	items := table(t, "a\tb\n1, 2\t3\n", '\t')
	defer destroy(items)
	testing.expect_value(t, items[0].(Object)[0].value.(string), "1, 2")
	testing.expect_value(t, items[0].(Object)[1].value.(f64), 3)
}

@(test)
test_columns_with_one_name_are_numbered_and_short_rows_are_filled :: proc(t: ^testing.T) {
	items := table(t, "Size,size,\n1,2,3\n4\n")
	defer destroy(items)
	o := items[0].(Object)
	testing.expect_value(t, o[0].key, "size")
	testing.expect_value(t, o[1].key, "size_2")
	testing.expect_value(t, o[2].key, "column_3")
	testing.expect_value(t, items[1].(Object)[1].value.(f64), 0)
}

@(test)
test_a_table_that_cannot_be_read_says_why :: proc(t: ^testing.T) {
	_, problem, ok := parse_table("", ',')
	testing.expect(t, !ok && strings.contains(problem.why, "empty"))
	_, problem, ok = parse_table("\n  \n", ',')
	testing.expect(t, !ok && strings.contains(problem.why, "empty"))
	_, problem, ok = parse_table("a,b\n1,2\n3,4,5\n", ',')
	testing.expect(t, !ok)
	testing.expect_value(t, problem.line, 3)
	testing.expect(t, strings.contains(problem.why, "3 values") && strings.contains(problem.why, "2 columns"), problem.why)
	// a header alone is a table with no rows
	d, _, header_ok := parse_table("a,b\n", ',')
	defer destroy(d)
	testing.expect(t, header_ok)
	testing.expect_value(t, len(d.([]Datum)), 0)
}

@(test)
test_a_list_of_records_is_written_as_a_table :: proc(t: ^testing.T) {
	d := json(t, `[ { "name": "Ana, B", "age": 31 }, { "name": "say \"hi\"", "age": 2.5, "extra": true }, { "name": " pad", "age": null } ]`)
	defer destroy(d)
	text, why, ok := write_table(d, ',')
	defer delete(text)
	testing.expectf(t, ok, "%s", why)
	testing.expect_value(t, text, "name,age,extra\n\"Ana, B\",31,\n\"say \"\"hi\"\"\",2.5,true\n\" pad\",,\n")
	tabs, _, _ := write_table(d, '\t')
	defer delete(tabs)
	testing.expect(t, strings.has_prefix(tabs, "name\tage\textra\nAna, B\t31\t\n"), tabs)
	// and it reads back as it was
	back := table(t, text)
	defer destroy(back)
	testing.expect_value(t, back[0].(Object)[0].value.(string), "Ana, B")
}

@(test)
test_a_list_of_lists_is_written_without_names_and_other_things_are_refused :: proc(t: ^testing.T) {
	d := json(t, `[ [1, "a"], [2, "b"] ]`)
	defer destroy(d)
	text, _, ok := write_table(d, ',')
	defer delete(text)
	testing.expect(t, ok)
	testing.expect_value(t, text, "1,a\n2,b\n")
	for source in ([]string{`5`, `{ "a": 1 }`, `[ 1, 2 ]`, `[ [1], 2 ]`}) {
		bad := json(t, source)
		_, why, bad_ok := write_table(bad, ',')
		testing.expectf(t, !bad_ok && why != "", "%s is not a table", source)
		destroy(bad)
	}
	empty := json(t, `[]`)
	defer destroy(empty)
	nothing, _, empty_ok := write_table(empty, ',')
	defer delete(nothing)
	testing.expect(t, empty_ok && nothing == "")
	nested := json(t, `[ { "a": [1, 2] } ]`)
	defer destroy(nested)
	inside, _, nested_ok := write_table(nested, ',')
	defer delete(inside)
	testing.expect(t, nested_ok)
	testing.expect(t, strings.contains(inside, "\"[ 1, 2 ]\""), inside)
}

@(test)
test_a_file_is_told_by_the_end_of_its_name :: proc(t: ^testing.T) {
	testing.expect_value(t, format_of("birds.json"), Format.Json)
	testing.expect_value(t, format_of("data/Birds.JSON"), Format.Json)
	testing.expect_value(t, format_of("a.csv"), Format.Csv)
	testing.expect_value(t, format_of("a.tsv"), Format.Tsv)
	testing.expect_value(t, format_of("a.toml"), Format.Toml)
	testing.expect_value(t, format_of("poem.txt"), Format.Text)
	testing.expect_value(t, format_of("cat.png"), Format.None)
	testing.expect_value(t, format_of("json"), Format.None)
	_, problem, ok := parse(.None, "x")
	testing.expect(t, !ok && problem.why != "")
	_, why, write_ok := write(.None, 1.0)
	testing.expect(t, !write_ok && why != "")
}

@(test)
test_text_is_text_and_lists_of_text_are_lines :: proc(t: ^testing.T) {
	d, _, ok := parse(.Text, "\xef\xbb\xbfone\ntwo\n")
	defer destroy(d)
	testing.expect(t, ok)
	testing.expect_value(t, d.(string), "one\ntwo\n")
	text, _, _ := write(.Text, Datum("hello"))
	defer delete(text)
	testing.expect_value(t, text, "hello")
	lines, _, _ := write(.Text, []Datum{"a", "b"})
	defer delete(lines)
	testing.expect_value(t, lines, "a\nb\n")
	number, _, _ := write(.Text, Datum(2.5))
	defer delete(number)
	testing.expect_value(t, number, "2.5\n")
	flag, _, _ := write(.Text, Datum(true))
	defer delete(flag)
	testing.expect_value(t, flag, "true\n")
	for bad in ([]Datum{[]Datum{1.0}, Object{}}) {
		_, why, bad_ok := write(.Text, bad)
		testing.expect(t, !bad_ok && why != "")
	}
}

@(test)
test_toml_is_read_as_one_record_and_written_from_one :: proc(t: ^testing.T) {
	d, _, ok := parse(.Toml, "title = \"Birds\"\ncount = 3\nsizes = [1, 2]\nnames = [\"a\", \"b\"]\n\n[owner]\nname = \"Ana\"\nlucky = true\n")
	defer destroy(d)
	testing.expect(t, ok)
	o := d.(Object)
	testing.expect_value(t, len(o), 5)
	testing.expect_value(t, o[0].key, "title")
	count, _ := member(o, "count")
	testing.expect_value(t, count.(f64), 3)
	names, _ := member(o, "names")
	testing.expect_value(t, len(names.([]Datum)), 2)
	owner, _ := member(o, "owner")
	lucky, _ := member(owner.(Object), "lucky")
	testing.expect_value(t, lucky.(bool), true)
	written, why, write_ok := write(.Toml, d)
	defer delete(written)
	testing.expectf(t, write_ok, "%s", why)
	testing.expect(t, strings.contains(written, "title = \"Birds\""), written)
	testing.expect(t, strings.contains(written, "count = 3"), written)
	testing.expect(t, strings.contains(written, "owner = {"), written)
	// and what was written reads back as it was
	again, _, again_ok := parse(.Toml, written)
	defer destroy(again)
	testing.expect(t, again_ok)
	testing.expect_value(t, len(again.(Object)), 5)
	_, bad_why, bad_ok := write(.Toml, []Datum{1.0})
	testing.expect(t, !bad_ok && bad_why != "")
	_, problem, toml_ok := parse(.Toml, "= 1\n")
	testing.expect(t, !toml_ok && problem.line == 1)
}
