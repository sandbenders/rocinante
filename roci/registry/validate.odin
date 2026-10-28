// SPDX-License-Identifier: 0BSD
//
// Checks on the table itself. They run as a unit test on every `ci`, so a bad
// row (a clash in a verb group, a connecting word outside the closed list, a
// verb named like a keyword) is caught when it is written, not when a user
// meets it. Section 5.2: two shapes in one verb group may not share both
// count and kinds.
package registry

import "../maths"
import "core:slice"

Problem_Kind :: enum {
	Empty_Name,
	Bad_Name,            // not lowercase letters and single spaces
	Duplicate_Name,
	Taken_Name,          // a keyword, a built-in value or a colour
	No_Shapes,
	No_Description,
	Clashing_Shapes,     // two shapes with the same count and kinds
	Unknown_Connecting_Word,
	Duplicate_Option,    // the same connecting word twice in one shape
	Option_Without_Kinds,
}

Problem :: struct {
	verb:   string,
	kind:   Problem_Kind,
	detail: string,
}

validate :: proc(allocator := context.allocator) -> []Problem {
	return validate_verbs(ALL_VERBS, allocator)
}

// Every problem in `verbs`; empty when the table is sound. The caller frees the slice.
validate_verbs :: proc(verbs: []Verb, allocator := context.allocator) -> []Problem {
	problems := make([dynamic]Problem, allocator)
	for v, i in verbs {
		if v.name == "" {
			append(&problems, Problem{v.name, .Empty_Name, ""})
			continue
		}
		if !is_plain_name(v.name) {
			append(&problems, Problem{v.name, .Bad_Name, "use lowercase letters, with single spaces between words"})
		}
		for other in verbs[:i] {
			if other.name == v.name {
				append(&problems, Problem{v.name, .Duplicate_Name, "two rows have this name; write one verb with several shapes"})
				break
			}
		}
		// Verbs may share a name with a connecting word (`fill`, `stroke`), because a
		// word is a connecting word only after the required arguments.
		// Keywords, values and colour names may not be verbs.
		_, is_colour := maths.name_lookup(v.name)
		if slice.contains(KEYWORDS[:], v.name) || slice.contains(VALUES[:], v.name) || is_colour {
			append(&problems, Problem{v.name, .Taken_Name, "the language already uses this word"})
		}
		if v.doc == "" {
			append(&problems, Problem{v.name, .No_Description, ""})
		}
		if len(v.shapes) == 0 {
			append(&problems, Problem{v.name, .No_Shapes, ""})
		}
		for shape, a in v.shapes {
			for other in v.shapes[:a] {
				if same_kinds(shape, other) {
					append(&problems, Problem{v.name, .Clashing_Shapes, "two shapes take the same number and kinds of arguments"})
				}
			}
			for option, b in shape.options {
				if !slice.contains(CONNECTING_WORDS[:], option.word) {
					append(&problems, Problem{v.name, .Unknown_Connecting_Word, option.word})
				}
				if len(option.kinds) == 0 {
					append(&problems, Problem{v.name, .Option_Without_Kinds, option.word})
				}
				for earlier in shape.options[:b] {
					if earlier.word == option.word {
						append(&problems, Problem{v.name, .Duplicate_Option, option.word})
					}
				}
			}
		}
	}
	return problems[:]
}

@(private)
same_kinds :: proc(a, b: Shape) -> bool {
	if len(a.params) != len(b.params) {
		return false
	}
	for p, i in a.params {
		if p.kind != b.params[i].kind {
			return false
		}
	}
	return true
}

@(private)
is_plain_name :: proc(name: string) -> bool {
	previous_space := true // so a leading space is caught too
	for c in transmute([]u8)name {
		switch {
		case c >= 'a' && c <= 'z':
			previous_space = false
		case c == ' ' && !previous_space:
			previous_space = true
		case:
			return false
		}
	}
	return !previous_space
}
