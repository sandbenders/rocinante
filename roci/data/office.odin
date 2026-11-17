// SPDX-License-Identifier: 0BSD
//
// Excel (`.xlsx`) and OpenDocument (`.ods`, `.odt`) files: zips of XML, read with `core:encoding/xml`. A
// spreadsheet is read as a table, the first row of a sheet naming its columns (the same table `parse_table`
// makes of a CSV); a document is read as its text, a paragraph to a line. The cells of a sheet are what they
// show, not what they were worked out from: a formula is its last result, a date is the number Excel keeps
// it as, and a number is a number. Nothing here writes these files.
package data

import "core:strconv"
import "core:strings"

@(private)
Xml :: struct {
	doc: ^Xml_Doc,
}

@(private)
read_xml :: proc(z: ^Zip, name: string) -> (x: Xml, why: string) {
	content, read_why := zip_read(z, name, context.temp_allocator)
	if content == nil {
		return {}, read_why
	}
	doc, ok := parse_xml(content, context.temp_allocator)
	if !ok {
		return {}, strings.concatenate({"the file ", name, " inside is not readable"}, context.temp_allocator)
	}
	holder := new(Xml_Doc, context.temp_allocator)
	holder^ = doc
	return Xml{holder}, ""
}

// The elements directly inside an element, in order.
@(private)
children :: proc(x: Xml, id: Element_ID, name := "") -> []Element_ID {
	out := make([dynamic]Element_ID, context.temp_allocator)
	for v in x.doc.elements[id].children {
		if child, is_child := v.(Element_ID); is_child {
			if name == "" || x.doc.elements[child].ident == name {
				append(&out, child)
			}
		}
	}
	return out[:]
}

@(private)
attribute :: proc(x: Xml, id: Element_ID, key: string) -> string {
	for a in x.doc.elements[id].attribs {
		if a.key == key {
			return a.val
		}
	}
	return ""
}

// Every piece of text inside an element, joined: `<si><r><t>a</t></r><r><t>b</t></r></si>` is "ab".
@(private)
all_text :: proc(x: Xml, id: Element_ID, b: ^strings.Builder) {
	for v in x.doc.elements[id].children {
		switch item in v {
		case string:
			strings.write_string(b, item)
		case Element_ID:
			all_text(x, item, b)
		}
	}
}

@(private)
first_child :: proc(x: Xml, id: Element_ID, name: string) -> (Element_ID, bool) {
	for c in children(x, id, name) {
		return c, true
	}
	return 0, false
}

// The cap on the cells read from one file: a sheet that claims a million columns of nothing is not read whole.
MAX_CELLS :: 5_000_000

// A column number (from 0) from the letters of a cell's name: A is 0, Z 25, AA 26.
@(private)
column_of :: proc(ref: string) -> (column: int, ok: bool) {
	n := 0
	for c in ref {
		switch {
		case c >= 'A' && c <= 'Z':
			n = n * 26 + int(c - 'A') + 1
		case c >= 'a' && c <= 'z':
			n = n * 26 + int(c - 'a') + 1
		case:
			return n - 1, n > 0
		}
		if n > 20000 {
			return 0, false
		}
	}
	return n - 1, n > 0
}

// ---- Excel ----

// Reads the sheet called `sheet` of an Excel file (the first when none is named) as a table.
parse_xlsx :: proc(content: []byte, sheet: string, allocator := context.allocator) -> (value: Datum, problem: Problem, ok: bool) {
	context.allocator = allocator
	z, open_why := zip_open(content, context.temp_allocator)
	if open_why != "" {
		return nil, Problem{0, open_why}, false
	}
	workbook, workbook_why := read_xml(&z, "xl/workbook.xml")
	if workbook_why != "" {
		return nil, Problem{0, strings.concatenate({"this does not look like an Excel file: ", workbook_why}, context.temp_allocator)}, false
	}
	root := Element_ID(0)
	sheets_el, has_sheets := first_child(workbook, root, "sheets")
	if !has_sheets {
		return nil, Problem{0, "this Excel file has no sheets"}, false
	}
	names := make([dynamic]string, context.temp_allocator)
	target_id := ""
	for s in children(workbook, sheets_el, "sheet") {
		name := attribute(workbook, s, "name")
		append(&names, name)
		if (sheet == "" && target_id == "") || name == sheet {
			target_id = attribute(workbook, s, "r:id")
		}
	}
	if target_id == "" {
		if sheet == "" {
			return nil, Problem{0, "this Excel file has no sheets"}, false
		}
		return nil, Problem{0, sheet_missing(sheet, names[:])}, false
	}
	// where that sheet's file is
	path := ""
	if rels, rels_why := read_xml(&z, "xl/_rels/workbook.xml.rels"); rels_why == "" {
		for r in children(rels, Element_ID(0), "Relationship") {
			if attribute(rels, r, "Id") == target_id {
				target := attribute(rels, r, "Target")
				path = strings.trim_prefix(target, "/") if strings.has_prefix(target, "/") else strings.concatenate({"xl/", target}, context.temp_allocator)
			}
		}
	}
	if path == "" || !zip_has(&z, path) {
		return nil, Problem{0, "the sheet's file is missing from this Excel file"}, false
	}
	// the texts the sheets share
	shared := make([dynamic]string, context.temp_allocator)
	if strings_xml, strings_why := read_xml(&z, "xl/sharedStrings.xml"); strings_why == "" {
		for si in children(strings_xml, Element_ID(0), "si") {
			b := strings.builder_make(context.temp_allocator)
			collect_t(strings_xml, si, &b)
			append(&shared, strings.to_string(b))
		}
	}
	sheet_xml, sheet_why := read_xml(&z, path)
	if sheet_why != "" {
		return nil, Problem{0, sheet_why}, false
	}
	data_el, has_data := first_child(sheet_xml, Element_ID(0), "sheetData")
	if !has_data {
		return nil, Problem{0, "this sheet has nothing in it: the first row names the columns"}, false
	}
	rows := make([dynamic][]string, context.temp_allocator)
	cells := 0
	for row in children(sheet_xml, data_el, "row") {
		line := make([dynamic]string, context.temp_allocator)
		for c in children(sheet_xml, row, "c") {
			column, has_column := column_of(attribute(sheet_xml, c, "r"))
			if !has_column {
				column = len(line)
			}
			cells += 1
			if cells > MAX_CELLS || column > 16384 {
				return nil, Problem{0, "this sheet is larger than I will read"}, false
			}
			for len(line) <= column {
				append(&line, "")
			}
			line[column] = cell_text(sheet_xml, c, shared[:])
		}
		// rows the sheet skips are empty rows, which a table leaves out
		blank := true
		for cell in line {
			blank &&= strings.trim_space(cell) == ""
		}
		if !blank {
			append(&rows, line[:])
		}
	}
	return table_from_rows(rows[:], nil)
}

// Every `<t>` inside an element (the text runs of a shared string), not the phonetic hints beside them.
@(private)
collect_t :: proc(x: Xml, id: Element_ID, b: ^strings.Builder) {
	for v in x.doc.elements[id].children {
		if child, is_child := v.(Element_ID); is_child {
			switch x.doc.elements[child].ident {
			case "t":
				all_text(x, child, b)
			case "r", "is":
				collect_t(x, child, b)
			}
		}
	}
}

// What a cell shows, as text: a number as it is written, a shared or inline text, a truth as `true` or `false`.
@(private)
cell_text :: proc(x: Xml, c: Element_ID, shared: []string) -> string {
	kind := attribute(x, c, "t")
	value := ""
	if v, has_value := first_child(x, c, "v"); has_value {
		b := strings.builder_make(context.temp_allocator)
		all_text(x, v, &b)
		value = strings.to_string(b)
	}
	switch kind {
	case "s":
		if index, ok := strconv.parse_int(value); ok && index >= 0 && index < len(shared) {
			return shared[index]
		}
		return ""
	case "inlineStr":
		if is_el, has := first_child(x, c, "is"); has {
			b := strings.builder_make(context.temp_allocator)
			collect_t(x, is_el, &b)
			return strings.to_string(b)
		}
		return ""
	case "b":
		return "true" if value == "1" else "false"
	case "e":
		return ""
	}
	return value
}

@(private)
sheet_missing :: proc(sheet: string, names: []string) -> string {
	return strings.concatenate({"there is no sheet called \"", sheet, "\" in this file; its sheets are ", strings.join(names, ", ", context.temp_allocator)}, context.temp_allocator)
}

// ---- OpenDocument ----

// Reads the sheet called `sheet` of an OpenDocument spreadsheet (the first when none is named) as a table.
parse_ods :: proc(content: []byte, sheet: string, allocator := context.allocator) -> (value: Datum, problem: Problem, ok: bool) {
	context.allocator = allocator
	z, open_why := zip_open(content, context.temp_allocator)
	if open_why != "" {
		return nil, Problem{0, open_why}, false
	}
	doc, doc_why := read_xml(&z, "content.xml")
	if doc_why != "" {
		return nil, Problem{0, strings.concatenate({"this does not look like an OpenDocument file: ", doc_why}, context.temp_allocator)}, false
	}
	body, has_body := first_child(doc, Element_ID(0), "office:body")
	spreadsheet: Element_ID
	has_sheets := false
	if has_body {
		spreadsheet, has_sheets = first_child(doc, body, "office:spreadsheet")
	}
	if !has_sheets {
		return nil, Problem{0, "this is not an OpenDocument spreadsheet (a .ods file)"}, false
	}
	names := make([dynamic]string, context.temp_allocator)
	chosen: Element_ID
	picked := false
	for t in children(doc, spreadsheet, "table:table") {
		name := attribute(doc, t, "table:name")
		append(&names, name)
		if !picked && (sheet == "" || name == sheet) {
			chosen, picked = t, true
		}
	}
	if !picked {
		if sheet == "" {
			return nil, Problem{0, "this spreadsheet has no sheets"}, false
		}
		return nil, Problem{0, sheet_missing(sheet, names[:])}, false
	}
	rows := make([dynamic][]string, context.temp_allocator)
	cells := 0
	read_rows :: proc(doc: Xml, parent: Element_ID, rows: ^[dynamic][]string, cells: ^int) -> bool {
		for row in children(doc, parent) {
			switch doc.doc.elements[row].ident {
			case "table:table-row-group", "table:table-header-rows", "table:table-rows":
				if !read_rows(doc, row, rows, cells) {
					return false
				}
			case "table:table-row":
				repeat := max(strconv.parse_int(attribute(doc, row, "table:number-rows-repeated")) or_else 1, 1)
				line := make([dynamic]string, context.temp_allocator)
				for c in children(doc, row) {
					ident := doc.doc.elements[c].ident
					if ident != "table:table-cell" && ident != "table:covered-table-cell" {
						continue
					}
					times := max(strconv.parse_int(attribute(doc, c, "table:number-columns-repeated")) or_else 1, 1)
					text := ods_cell_text(doc, c)
					// a run of empty cells that closes a row is only the sheet saying it is as wide as it is
					if text == "" && times > 1 {
						for _ in 0 ..< min(times, 1) {
							append(&line, "")
						}
						continue
					}
					for _ in 0 ..< min(times, 1000) {
						cells^ += 1
						if cells^ > MAX_CELLS {
							return false
						}
						append(&line, text)
					}
				}
				blank := true
				for cell in line {
					blank &&= strings.trim_space(cell) == ""
				}
				if !blank {
					for _ in 0 ..< min(repeat, 1000) {
						append(rows, line[:])
					}
				}
			}
		}
		return true
	}
	if !read_rows(doc, chosen, &rows, &cells) {
		return nil, Problem{0, "this sheet is larger than I will read"}, false
	}
	return table_from_rows(rows[:], nil)
}

@(private)
ods_cell_text :: proc(x: Xml, c: Element_ID) -> string {
	switch attribute(x, c, "office:value-type") {
	case "float", "percentage", "currency":
		return attribute(x, c, "office:value")
	case "boolean":
		return attribute(x, c, "office:boolean-value")
	case "date":
		return attribute(x, c, "office:date-value")
	case "time":
		return attribute(x, c, "office:time-value")
	case "string":
		if v := attribute(x, c, "office:string-value"); v != "" {
			return v
		}
		b := strings.builder_make(context.temp_allocator)
		paragraphs(x, c, &b)
		return strings.to_string(b)
	}
	return ""
}

// The text of an OpenDocument element: a paragraph or heading to a line, `text:s` as its spaces, `text:tab`
// as a tab and `text:line-break` as a line break, text inside `text:span` and `text:a` as it comes.
@(private)
paragraphs :: proc(x: Xml, id: Element_ID, b: ^strings.Builder) {
	for v in x.doc.elements[id].children {
		switch item in v {
		case string:
			// the white space between elements of the file is layout, not text
			if strings.trim_space(item) != "" || is_text_container(x.doc.elements[id].ident) {
				strings.write_string(b, item)
			}
		case Element_ID:
			el := x.doc.elements[item]
			switch el.ident {
			case "text:p", "text:h":
				if strings.builder_len(b^) > 0 {
					strings.write_byte(b, '\n')
				}
				paragraphs(x, item, b)
			case "text:s":
				n := max(strconv.parse_int(attribute(x, item, "text:c")) or_else 1, 1)
				for _ in 0 ..< min(n, 1000) {
					strings.write_byte(b, ' ')
				}
			case "text:tab":
				strings.write_byte(b, '\t')
			case "text:line-break":
				strings.write_byte(b, '\n')
			case "text:note", "text:bookmark", "text:bookmark-start", "text:bookmark-end", "text:soft-page-break", "office:annotation":
			case:
				paragraphs(x, item, b)
			}
		}
	}
}

@(private)
is_text_container :: proc(ident: string) -> bool {
	return ident == "text:p" || ident == "text:h" || ident == "text:span" || ident == "text:a"
}

// Reads an OpenDocument text (`.odt`) as its text: the paragraphs and headings, a line each.
parse_odt :: proc(content: []byte, allocator := context.allocator) -> (value: Datum, problem: Problem, ok: bool) {
	context.allocator = allocator
	z, open_why := zip_open(content, context.temp_allocator)
	if open_why != "" {
		return nil, Problem{0, open_why}, false
	}
	doc, doc_why := read_xml(&z, "content.xml")
	if doc_why != "" {
		return nil, Problem{0, strings.concatenate({"this does not look like an OpenDocument file: ", doc_why}, context.temp_allocator)}, false
	}
	body, has_body := first_child(doc, Element_ID(0), "office:body")
	text_el: Element_ID
	has_text := false
	if has_body {
		text_el, has_text = first_child(doc, body, "office:text")
	}
	if !has_text {
		return nil, Problem{0, "this is not an OpenDocument text (a .odt file)"}, false
	}
	b := strings.builder_make(context.temp_allocator)
	paragraphs(doc, text_el, &b)
	if strings.builder_len(b) > 0 {
		strings.write_byte(&b, '\n')
	}
	return strings.clone(strings.to_string(b)), {}, true
}
