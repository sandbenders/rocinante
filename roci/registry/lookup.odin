// SPDX-License-Identifier: 0BSD
//
// Questions the checker, the docs and the editor tools ask the registry: which
// verb is this, which shape do these arguments fit, did you mean something
// else, is this word taken. All of it reads the tables; none of it is written
// by hand a second time.
package registry

import "../maths"
import "core:slice"
import "core:strings"

find_verb :: proc(name: string) -> (verb: ^Verb, ok: bool) {
	return find_in(ALL_VERBS, name)
}

find_in :: proc(verbs: []Verb, name: string) -> (verb: ^Verb, ok: bool) {
	for &v in verbs {
		if v.name == name {
			return &v, true
		}
	}
	return nil, false
}

// The multi-word verbs are a fixed table of phrases matched longest first,
// before a word is read on its own. `words` are the words of a
// line from the start of a statement. Gives the verb and how many words it used.
match_phrase :: proc(words: []string) -> (verb: ^Verb, used: int) {
	return match_phrase_in(ALL_VERBS, words)
}

match_phrase_in :: proc(verbs: []Verb, words: []string) -> (verb: ^Verb, used: int) {
	for &v in verbs {
		n := word_count(v.name)
		if n <= used || n > len(words) {
			continue
		}
		if phrase_starts(v.name, words[:n]) {
			verb, used = &v, n
		}
	}
	return
}

@(private)
word_count :: proc(name: string) -> int {
	if name == "" {
		return 0
	}
	return strings.count(name, " ") + 1
}

@(private)
phrase_starts :: proc(name: string, words: []string) -> bool {
	rest := name
	for w in words {
		word: string
		if i := strings.index_byte(rest, ' '); i >= 0 {
			word, rest = rest[:i], rest[i + 1:]
		} else {
			word, rest = rest, ""
		}
		if word != w {
			return false
		}
	}
	return rest == ""
}

Shape_Result :: enum {
	Found,
	Wrong_Count, // no shape takes this many arguments
	Wrong_Kinds, // some do, but not with these kinds
	Ambiguous,   // more than one fits and none fits exactly
}

// Whether an argument of kind `got` can go where a parameter of kind `want` is
// expected. A colour parameter also takes a number (a grey), a list of colours
// and a gradient (a gradient is a paint like any colour).
accepts :: proc(want, got: Kind) -> bool {
	// A Boxed value (kind Any) is checked while the sketch runs, so it fits anywhere.
	if want == got || want == .Any || got == .Any {
		return true
	}
	if want == .Expr_Block && got == .Block {
		return true
	}
	return want == .Colour && (got == .Number || got == .List || got == .Gradient)
}

// Picks the shape of a verb group for these argument kinds: first by count,
// then by kinds. A shape that matches exactly wins over one that
// only fits through `accepts`, so `mix 1 2 0.5` is the number shape even though
// a colour could be a grey.
shape_for :: proc(verb: ^Verb, kinds: []Kind) -> (index: int, result: Shape_Result) {
	counted, exact_at, exact_n, fit_at, fit_n := 0, 0, 0, 0, 0
	for shape, i in verb.shapes {
		if len(shape.params) != len(kinds) {
			continue
		}
		counted += 1
		is_exact, fits := true, true
		for param, j in shape.params {
			if param.kind != kinds[j] {
				is_exact = false
			}
			if !accepts(param.kind, kinds[j]) {
				fits = false
			}
		}
		if is_exact {
			exact_at, exact_n = i, exact_n + 1
		}
		if fits {
			fit_at, fit_n = i, fit_n + 1
		}
	}
	switch {
	case counted == 0:
		return -1, .Wrong_Count
	case exact_n == 1:
		return exact_at, .Found
	case exact_n > 1:
		return -1, .Ambiguous
	case fit_n == 1:
		return fit_at, .Found
	case fit_n > 1:
		return -1, .Ambiguous
	}
	return -1, .Wrong_Kinds
}

// The fewest single-letter changes (add, drop, change, or swap two neighbours)
// that turn `a` into `b` (optimal string alignment). Words longer than 64 bytes
// are never close to anything.
edit_distance :: proc(a, b: string) -> int {
	if len(a) > 64 || len(b) > 64 {
		return max(len(a), len(b))
	}
	rows: [3][65]int // the row before last, the last, and this one
	for j in 0 ..= len(b) {
		rows[1][j] = j
	}
	prev2, prev, cur := 0, 1, 2
	for i in 1 ..= len(a) {
		rows[cur][0] = i
		for j in 1 ..= len(b) {
			cost := 0 if a[i - 1] == b[j - 1] else 1
			best := min(rows[prev][j] + 1, rows[cur][j - 1] + 1, rows[prev][j - 1] + cost)
			if i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1] {
				best = min(best, rows[prev2][j - 2] + 1)
			}
			rows[cur][j] = best
		}
		prev2, prev, cur = prev, cur, prev2
	}
	return rows[prev][len(b)]
}

// "Did you mean ...?": the known word closest to `word`, if one is close
// enough. A word that is already known gets no suggestion. Verbs come first,
// then keywords, values, connecting words and colour names; a tie goes to the
// earlier one, so the answer never depends on anything but the tables.
suggest :: proc(word: string) -> (suggestion: string, ok: bool) {
	if word == "" || is_reserved(word) {
		return "", false
	}
	limit := clamp(len(word) / 3, 1, 3)
	best := limit + 1
	consider :: proc(word, candidate: string, best: ^int, found: ^string) {
		if abs(len(candidate) - len(word)) >= best^ {
			return
		}
		if d := edit_distance(word, candidate); d < best^ {
			best^, found^ = d, candidate
		}
	}
	found: string
	for v in ALL_VERBS {
		if word_count(v.name) == 1 {
			consider(word, v.name, &best, &found)
		}
	}
	for w in KEYWORDS {
		consider(word, w, &best, &found)
	}
	for w in VALUES {
		consider(word, w, &best, &found)
	}
	for w in CONNECTING_WORDS {
		consider(word, w, &best, &found)
	}
	for c in maths.NAMED_COLOURS {
		consider(word, c.name, &best, &found)
	}
	return found, found != ""
}

// Whether the language already uses this word: a verb (the whole name of a
// multi-word verb), a keyword, a built-in value, a connecting word or a colour
// name.
is_reserved :: proc(word: string) -> bool {
	if _, found := find_verb(word); found {
		return true
	}
	if slice.contains(KEYWORDS[:], word) || slice.contains(VALUES[:], word) || slice.contains(CONNECTING_WORDS[:], word) {
		return true
	}
	_, is_colour := maths.name_lookup(word)
	return is_colour
}

// Whether a sketch may not use this word as a variable or parameter name. The
// words that are both values and connecting words stay free.
is_reserved_name :: proc(word: string) -> bool {
	return is_reserved(word) && !slice.contains(FREE_AS_PARAMETERS[:], word)
}

// Every reserved word, sorted and without repeats, for the docs.
// The caller frees the slice.
reserved_words :: proc(allocator := context.allocator) -> []string {
	all := make([dynamic]string, allocator)
	for v in ALL_VERBS {
		append(&all, v.name)
	}
	append(&all, ..KEYWORDS[:])
	append(&all, ..VALUES[:])
	append(&all, ..CONNECTING_WORDS[:])
	for c in maths.NAMED_COLOURS {
		append(&all, c.name)
	}
	slice.sort(all[:])
	unique := slice.unique(all[:])
	resize(&all, len(unique))
	return all[:]
}
