// SPDX-License-Identifier: 0BSD
package data

import "core:os"
import "core:strings"
import "core:testing"

// The files in tests/office were made by LibreOffice from book.fods and letter.html, so they are what a
// real program writes.
@(private = "file")
fixture :: proc(t: ^testing.T, name: string) -> []byte {
	bytes, err := os.read_entire_file(strings.concatenate({"tests/office/", name}, context.temp_allocator), context.temp_allocator)
	testing.expectf(t, err == nil, "cannot read tests/office/%s (tests run from the repository root)", name)
	return bytes
}

@(private = "file")
expect_stock :: proc(t: ^testing.T, d: Datum, truths_are_text: bool) {
	items, is_list := d.([]Datum)
	if !testing.expect(t, is_list) {
		return
	}
	testing.expect_value(t, len(items), 3)
	first := items[0].(Object)
	testing.expect_value(t, first[0].key, "item_name")
	testing.expect_value(t, first[1].key, "count")
	testing.expect_value(t, first[2].key, "price")
	testing.expect_value(t, first[3].key, "in_stock")
	testing.expect_value(t, first[0].value.(string), "Brass key")
	testing.expect_value(t, first[1].value.(f64), 12)
	testing.expect_value(t, first[2].value.(f64), 2.5)
	// LibreOffice keeps a truth in an Excel file as 1 or 0 and only formats it as TRUE or FALSE; an
	// OpenDocument file says what it is
	if truths_are_text {
		testing.expect_value(t, first[3].value.(string), "true")
	} else {
		testing.expect_value(t, first[3].value.(f64), 1)
	}
	testing.expect_value(t, items[1].(Object)[0].value.(string), "Lamp & shade")
	testing.expect_value(t, items[1].(Object)[2].value.(f64), 19.99)
	if truths_are_text {
		testing.expect_value(t, items[1].(Object)[3].value.(string), "false")
	} else {
		testing.expect_value(t, items[1].(Object)[3].value.(f64), 0)
	}
	testing.expect_value(t, items[2].(Object)[1].value.(f64), 0) // an empty cell of a column of numbers
}

@(test)
test_the_first_sheet_of_an_excel_file_is_a_table :: proc(t: ^testing.T) {
	d, problem, ok := parse(.Xlsx, string(fixture(t, "book.xlsx")))
	defer destroy(d)
	testing.expectf(t, ok, "%s", problem.why)
	expect_stock(t, d, false)
}

@(test)
test_a_sheet_of_an_excel_file_is_found_by_its_name :: proc(t: ^testing.T) {
	d, _, ok := parse(.Xlsx, string(fixture(t, "book.xlsx")), sheet = "Notes")
	defer destroy(d)
	testing.expect(t, ok)
	items := d.([]Datum)
	testing.expect_value(t, len(items), 2)
	testing.expect_value(t, items[0].(Object)[0].key, "day")
	testing.expect_value(t, items[1].(Object)[1].value.(string), "closed")
	_, problem, missing_ok := parse(.Xlsx, string(fixture(t, "book.xlsx")), sheet = "Nope")
	testing.expect(t, !missing_ok)
	testing.expect(t, strings.contains(problem.why, "no sheet called \"Nope\"") && strings.contains(problem.why, "Stock, Notes"), problem.why)
}

@(test)
test_an_opendocument_spreadsheet_is_a_table_too :: proc(t: ^testing.T) {
	d, problem, ok := parse(.Ods, string(fixture(t, "book.ods")))
	defer destroy(d)
	testing.expectf(t, ok, "%s", problem.why)
	expect_stock(t, d, false)
	notes, _, notes_ok := parse(.Ods, string(fixture(t, "book.ods")), sheet = "Notes")
	defer destroy(notes)
	testing.expect(t, notes_ok)
	testing.expect_value(t, len(notes.([]Datum)), 2)
	_, missing, missing_ok := parse(.Ods, string(fixture(t, "book.ods")), sheet = "Nope")
	testing.expect(t, !missing_ok && strings.contains(missing.why, "no sheet called"))
}

@(test)
test_an_opendocument_text_is_its_paragraphs :: proc(t: ^testing.T) {
	d, problem, ok := parse(.Odt, string(fixture(t, "letter.odt")))
	defer destroy(d)
	testing.expectf(t, ok, "%s", problem.why)
	text := d.(string)
	testing.expect(t, strings.has_prefix(text, "The Letter\nDear reader,\n"), text)
	testing.expect(t, strings.contains(text, "This has bold and italic words, and spaces.\n"), text)
	testing.expect(t, strings.contains(text, "one\ntwo\n"), text)
	testing.expect(t, strings.contains(text, "Café ünïcode & symbols."), text)
	testing.expect(t, strings.has_suffix(text, "\n"))
}

@(test)
test_files_that_are_not_what_their_name_says_are_said_in_words :: proc(t: ^testing.T) {
	for format in ([]Format{.Xlsx, .Ods, .Odt}) {
		_, problem, ok := parse(format, "just some text, not a zip file at all, long enough to look")
		testing.expectf(t, !ok && strings.contains(problem.why, "not a zip"), "%v: %s", format, problem.why)
		_, empty_problem, empty_ok := parse(format, "")
		testing.expect(t, !empty_ok && empty_problem.why != "")
	}
	// a spreadsheet given as a document, and the other way round
	_, wrong, wrong_ok := parse(.Odt, string(fixture(t, "book.ods")))
	testing.expect(t, !wrong_ok && strings.contains(wrong.why, "not an OpenDocument text"), wrong.why)
	_, wrong2, wrong2_ok := parse(.Ods, string(fixture(t, "letter.odt")))
	testing.expect(t, !wrong2_ok && strings.contains(wrong2.why, "not an OpenDocument spreadsheet"), wrong2.why)
	_, wrong3, wrong3_ok := parse(.Xlsx, string(fixture(t, "book.ods")))
	testing.expect(t, !wrong3_ok && strings.contains(wrong3.why, "Excel"), wrong3.why)
}

@(test)
test_a_zip_that_was_changed_or_cut_short_is_damaged_and_not_a_crash :: proc(t: ^testing.T) {
	good := fixture(t, "book.xlsx")
	// cut short: the end of the file holds the list of what is in it
	_, cut, cut_ok := parse(.Xlsx, string(good[:len(good) / 2]))
	testing.expect(t, !cut_ok && cut.why != "")
	// a changed byte in the middle of the packed data fails the checksum or the unpacking
	changed := make([]byte, len(good), context.temp_allocator)
	copy(changed, good)
	for i := 40; i < len(changed) - 200; i += 97 {
		changed[i] ~= 0x55
	}
	_, damaged, damaged_ok := parse(.Xlsx, string(changed))
	testing.expect(t, !damaged_ok && damaged.why != "")
}

@(test)
test_a_zip_is_listed_and_its_files_unpacked_and_checked :: proc(t: ^testing.T) {
	bytes := fixture(t, "book.ods")
	z, why := zip_open(bytes)
	defer zip_close(&z)
	testing.expect_value(t, why, "")
	testing.expect(t, zip_has(&z, "content.xml"))
	testing.expect(t, zip_has(&z, "mimetype"))
	testing.expect(t, !zip_has(&z, "nothing.xml"))
	mimetype, read_why := zip_read(&z, "mimetype")
	defer delete(mimetype)
	testing.expect_value(t, read_why, "")
	testing.expect_value(t, string(mimetype), "application/vnd.oasis.opendocument.spreadsheet") // a stored entry
	content, content_why := zip_read(&z, "content.xml")
	defer delete(content)
	testing.expect_value(t, content_why, "")
	testing.expect(t, strings.contains(string(content), "office:spreadsheet")) // a deflated one
	_, missing := zip_read(&z, "nothing.xml")
	testing.expect(t, strings.contains(missing, "no file called nothing.xml"))
}

@(test)
test_a_zip_that_unpacks_to_too_much_is_refused :: proc(t: ^testing.T) {
	bytes := fixture(t, "book.ods")
	z, _ := zip_open(bytes)
	defer zip_close(&z)
	z.unpacked = MAX_UNPACKED
	_, why := zip_read(&z, "content.xml")
	testing.expect(t, strings.contains(why, "more than I will read"), why)
}

@(test)
test_a_column_is_counted_from_the_letters_of_a_cell :: proc(t: ^testing.T) {
	cases := [?]struct {
		ref:    string,
		column: int,
		ok:     bool,
	}{{"A1", 0, true}, {"B7", 1, true}, {"Z3", 25, true}, {"AA10", 26, true}, {"AB1", 27, true}, {"c2", 2, true}, {"1", 0, false}, {"", 0, false}, {"ZZZZZZZ1", 0, false}}
	for c in cases {
		column, ok := column_of(c.ref)
		testing.expectf(t, ok == c.ok && (!ok || column == c.column), "%s", c.ref)
	}
}

@(test)
test_office_files_are_told_by_their_names_and_are_not_written :: proc(t: ^testing.T) {
	testing.expect_value(t, format_of("a.XLSX"), Format.Xlsx)
	testing.expect_value(t, format_of("a.ods"), Format.Ods)
	testing.expect_value(t, format_of("a.odt"), Format.Odt)
	for format in ([]Format{.Xlsx, .Ods, .Odt}) {
		_, why, ok := write(format, []Datum{})
		testing.expect(t, !ok && strings.contains(why, "do not write"))
	}
}

@(test)
test_xml_keeps_the_spaces_between_words_and_decodes_entities :: proc(t: ^testing.T) {
	doc, ok := parse_xml(transmute([]byte)string("\xef\xbb\xbf<?xml version=\"1.0\"?><!DOCTYPE a [<!ENTITY x \"y\">]><!-- c --><a k=\"1 &amp; 2\" j='q'>one <b>two</b> three &lt;&#65;&#x42;&#9731;&nbsp;<![CDATA[<raw>]]><e/></a>"))
	testing.expect(t, ok)
	x := Xml{&doc}
	testing.expect_value(t, attribute(x, 0, "k"), "1 & 2")
	testing.expect_value(t, attribute(x, 0, "j"), "q")
	b := strings.builder_make(context.temp_allocator)
	all_text(x, 0, &b)
	testing.expect_value(t, strings.to_string(b), "one two three <AB☃&nbsp;<raw>") // an entity that is not one of those stays as written
	testing.expect_value(t, len(children(x, 0)), 2)
	testing.expect_value(t, len(children(x, 0, "e")), 1)
}

@(test)
test_xml_that_is_not_well_formed_is_refused :: proc(t: ^testing.T) {
	for text in ([]string{"", "<a>", "<a></b>", "<a><b></a>", "<a k=1/>", "<a k=\"1/>", "<a/><b/>", "</a>", "<a><!-- never", "<a><![CDATA[ never", "<a", "<a k/>", "text only"}) {
		_, ok := parse_xml(transmute([]byte)text)
		testing.expectf(t, !ok, "`%s` is not XML", text)
	}
	deep := strings.concatenate({strings.repeat("<a>", 600, context.temp_allocator), strings.repeat("</a>", 600, context.temp_allocator)}, context.temp_allocator)
	_, deep_ok := parse_xml(transmute([]byte)deep)
	testing.expect(t, !deep_ok, "nesting without end is a problem")
}

@(test)
test_the_kinds_of_cell_each_kind_of_file_has_are_read_as_what_they_show :: proc(t: ^testing.T) {
	sheet, _ := parse_xml(transmute([]byte)string("<w><c t=\"s\"><v>1</v></c><c t=\"inlineStr\"><is><r><t>in</t></r><r><t>line</t></r></is></c><c t=\"b\"><v>1</v></c><c t=\"b\"><v>0</v></c><c t=\"e\"><v>#N/A</v></c><c t=\"str\"><f>A1</f><v>result</v></c><c><v>1.5E-3</v></c><c t=\"s\"><v>99</v></c><c/></w>"))
	x := Xml{&sheet}
	shared := []string{"zero", "one"}
	want := []string{"one", "inline", "true", "false", "", "result", "1.5E-3", "", ""}
	for c, i in children(x, 0, "c") {
		testing.expectf(t, cell_text(x, c, shared) == want[i], "cell %d is `%s`, wanted `%s`", i, cell_text(x, c, shared), want[i])
	}
	content, _ := parse_xml(transmute([]byte)string("<w><c office:value-type=\"boolean\" office:boolean-value=\"true\"/><c office:value-type=\"date\" office:date-value=\"2026-11-17\"/><c office:value-type=\"percentage\" office:value=\"0.5\"/><c office:value-type=\"string\" office:string-value=\"direct\"/><c office:value-type=\"string\"><text:p>a</text:p><text:p>b<text:s text:c=\"3\"/>c<text:tab/>d</text:p></c><c/></w>"))
	y := Xml{&content}
	want_ods := []string{"true", "2026-11-17", "0.5", "direct", "a\nb   c\td", ""}
	for c, i in children(y, 0, "c") {
		testing.expectf(t, ods_cell_text(y, c) == want_ods[i], "cell %d is `%s`, wanted `%s`", i, ods_cell_text(y, c), want_ods[i])
	}
}
