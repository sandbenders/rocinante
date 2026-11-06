// SPDX-License-Identifier: 0BSD
package toml

import "core:math"
import "core:testing"

number_of :: proc(v: Value) -> f64 {
	#partial switch x in v {
	case f64: return x
	case i64: return f64(x)
	}
	return -1
}

@(test)
test_a_file_of_every_kind_of_value_is_read :: proc(t: ^testing.T) {
	text := `# remembered values
title = "garden"   # a comment after it
[ui]
"dot/size" = 60.5
count = 3
lit = true
off = false
mood = [255.0, 165, 0, 255]
words = "tab\there \"quoted\" \\ é"
`
	d := parse(text)
	defer destroy(&d)
	testing.expect_value(t, len(d.problems), 0)
	title, found := get(&d, "", "title")
	testing.expect(t, found)
	testing.expect_value(t, title.(string), "garden")
	size, _ := get(&d, "ui", "dot/size")
	testing.expect_value(t, size.(f64), 60.5)
	count, _ := get(&d, "ui", "count")
	testing.expect_value(t, count.(i64), 3) // a whole number stays whole
	lit, _ := get(&d, "ui", "lit")
	testing.expect_value(t, lit.(bool), true)
	off, _ := get(&d, "ui", "off")
	testing.expect_value(t, off.(bool), false)
	mood, _ := get(&d, "ui", "mood")
	if testing.expect_value(t, len(mood.([]f64)), 4) {
		testing.expect_value(t, mood.([]f64)[1], 165)
	}
	words, _ := get(&d, "ui", "words")
	testing.expect_value(t, words.(string), "tab\there \"quoted\" \\ é")
}

@(test)
test_what_is_written_is_read_back_the_same :: proc(t: ^testing.T) {
	d: Document
	defer destroy(&d)
	set(&d, "ui", "dot/size", 60.0)
	set(&d, "ui", "count", i64(3))
	set(&d, "ui", "lit", true)
	set(&d, "ui", "words", "line\none \"two\" é中")
	set(&d, "ui", "mood", []f64{255, 165.5, 0, 255})
	set(&d, "ui2", "plain", 0.1)
	text := write(&d)
	defer delete(text)
	want := "[ui]\n\"dot/size\" = 60.0\ncount = 3\nlit = true\nwords = \"line\\none \\\"two\\\" é中\"\nmood = [255.0, 165.5, 0.0, 255.0]\n\n[ui2]\nplain = 0.1\n"
	testing.expect_value(t, text, want)
	back := parse(text)
	defer destroy(&back)
	testing.expect_value(t, len(back.problems), 0)
	size, _ := get(&back, "ui", "dot/size")
	testing.expect_value(t, size.(f64), 60) // still a decimal, not a whole number
	count, _ := get(&back, "ui", "count")
	testing.expect_value(t, count.(i64), 3)
	words, _ := get(&back, "ui", "words")
	testing.expect_value(t, words.(string), "line\none \"two\" é中")
	// written again, the same text
	again := write(&back)
	defer delete(again)
	testing.expect_value(t, again, text)
}

@(test)
test_a_bad_line_is_said_with_its_number_and_left_out :: proc(t: ^testing.T) {
	text := "good = 1\nno equals sign\nbad = \n[ui\nalso_good = \"x\"\nbroken = [1, two]\nunclosed = \"abc\n= 5\nlate = 1 2\n"
	d := parse(text)
	defer destroy(&d)
	lines := make([dynamic]int, context.temp_allocator)
	for p in d.problems {
		append(&lines, p.line)
		testing.expect(t, p.why != "")
	}
	testing.expect_value(t, len(d.problems), 7)
	testing.expect_value(t, lines[0], 2)
	testing.expect_value(t, lines[1], 3)
	testing.expect_value(t, lines[2], 4)
	good, found := get(&d, "", "good")
	testing.expect(t, found && number_of(good) == 1)
	_, in_first := get(&d, "", "also_good")
	testing.expect(t, in_first, "a header with no closing bracket makes no table, so the key after it stays in the table before")
}

@(test)
test_a_repeated_key_takes_the_last_value_and_a_repeated_table_adds_to_the_first :: proc(t: ^testing.T) {
	d := parse("[a]\nx = 1\n[b]\ny = 2\n[a]\nx = 3\nz = 4\n")
	defer destroy(&d)
	testing.expect_value(t, len(d.problems), 0)
	x, _ := get(&d, "a", "x")
	testing.expect_value(t, number_of(x), 3)
	z, _ := get(&d, "a", "z")
	testing.expect_value(t, number_of(z), 4)
	testing.expect_value(t, len(d.tables), 3) // the one before the first header, a and b
}

@(test)
test_numbers_text_and_arrays_in_their_odd_forms :: proc(t: ^testing.T) {
	d := parse("a = 1_000\nb = -2.5e2\nc = []\nd = [ 1, 2, ]\ne = \"\"   # nothing\nf = 1e3\ng = true # yes\n")
	defer destroy(&d)
	testing.expect_value(t, len(d.problems), 0)
	a, _ := get(&d, "", "a")
	testing.expect_value(t, a.(i64), 1000)
	b, _ := get(&d, "", "b")
	testing.expect_value(t, b.(f64), -250)
	c, _ := get(&d, "", "c")
	testing.expect_value(t, len(c.([]f64)), 0)
	dd, _ := get(&d, "", "d")
	testing.expect_value(t, len(dd.([]f64)), 2)
	e, _ := get(&d, "", "e")
	testing.expect_value(t, e.(string), "")
	f, _ := get(&d, "", "f")
	testing.expect_value(t, f.(f64), 1000)
	g, _ := get(&d, "", "g")
	testing.expect_value(t, g.(bool), true)
}

@(test)
test_an_empty_file_and_a_document_with_nothing_in_it_are_empty_text :: proc(t: ^testing.T) {
	d := parse("")
	defer destroy(&d)
	testing.expect_value(t, len(d.problems), 0)
	text := write(&d)
	defer delete(text)
	testing.expect_value(t, text, "")
	_, found := get(&d, "ui", "x")
	testing.expect(t, !found)
}

@(test)
test_set_replaces_a_value_and_a_number_that_is_not_a_number_is_written_as_zero :: proc(t: ^testing.T) {
	d: Document
	defer destroy(&d)
	set(&d, "t", "k", 1.0)
	set(&d, "t", "k", "now text")
	nan := math.nan_f64()
	set(&d, "t", "n", nan)
	set(&d, "t", "i", math.inf_f64(1))
	v, _ := get(&d, "t", "k")
	testing.expect_value(t, v.(string), "now text")
	testing.expect_value(t, len(d.tables[0].entries), 3)
	text := write(&d)
	defer delete(text)
	testing.expect_value(t, text, "[t]\nk = \"now text\"\nn = 0.0\ni = 0.0\n")
}
