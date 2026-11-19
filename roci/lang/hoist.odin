// SPDX-License-Identifier: 0BSD
package lang

import "core:slice"
import "core:strings"

// Words that make a value differ from one run, one moment or one place to the next, so a constant
// written with one is never moved.
@(private = "file")
IMPURE_WORDS :: [?]string{"random", "noise", "load", "recall", "read", "clipboard", "chosen", "time", "frame", "mouse", "screens", "now"}

// The top-level statements in the order they run: every constant whose value is made only of
// literals and other constants comes first, in the order its own needs allow, then everything else
// as written. The files of a sketch are read in the order of their names, and without this a
// constant in a later file would not exist yet for a line of an earlier one; a constant is the same
// wherever it is read, so it can be made before anything else without changing what a sketch does.
// A constant that uses a name that changes (a variable, or a verb the sketch taught) stays where it
// is written, and so does one that waits on such a constant.
@(private)
hoist_constants :: proc(c: ^Checker, stmts: []^Stmt) -> []^Stmt {
	Candidate :: struct {
		stmt:  ^Stmt,
		name:  string,
		needs: [dynamic]string,
	}
	candidates := make([dynamic]Candidate, context.temp_allocator)
	for s in stmts {
		k, is_assign := s.kind.(Assign)
		if !is_assign || len(k.target.parts) != 1 || !is_constant_name(k.target.parts[0]) {
			continue
		}
		cand := Candidate{stmt = s, name = k.target.parts[0], needs = make([dynamic]string, context.temp_allocator)}
		movable := true
		text := span_text(c.src, k.value.span)
		start := -1
		for i := 0; i <= len(text); i += 1 {
			in_name := i < len(text) && is_name_rune(rune(text[i]))
			if in_name && start < 0 {
				start = i
			} else if !in_name && start >= 0 {
				word := text[start:i]
				start = -1
				if is_constant_name(word) {
					if word != cand.name {
						append(&cand.needs, word)
					}
					continue
				}
				if sym, found := c.globals[word]; found && sym.kind == .Variable {
					movable = false
				}
				if is_taught(c, word) {
					movable = false
				}
				for impure in IMPURE_WORDS {
					movable &&= word != impure
				}
			}
		}
		if movable {
			append(&candidates, cand)
		}
	}
	// A constant given twice is an error the checker says where it is written, so it stays there.
	for i := len(candidates) - 1; i >= 0; i -= 1 {
		for j in 0 ..< i {
			if candidates[j].name == candidates[i].name {
				ordered_remove(&candidates, i)
				break
			}
		}
	}
	// Whatever waits on a constant that cannot move cannot move either.
	for changed := true; changed; {
		changed = false
		#reverse for cand, i in candidates {
			unmovable := false
			for need in cand.needs {
				if sym, found := c.globals[need]; !found || sym.kind != .Constant {
					unmovable = true
				} else if !has_candidate(candidates[:], need) {
					unmovable = true
				}
			}
			if unmovable {
				ordered_remove(&candidates, i)
				changed = true
			}
		}
	}
	// Each in the order written once what it needs has been made; a loop of constants never gets out.
	out := make([dynamic]^Stmt, 0, len(stmts), c.alloc)
	made := make([dynamic]string, context.temp_allocator)
	for progress := true; progress; {
		progress = false
		for cand in candidates {
			if slice.contains(made[:], cand.name) {
				continue
			}
			ready := true
			for need in cand.needs {
				ready &&= slice.contains(made[:], need)
			}
			if ready {
				append(&out, cand.stmt)
				append(&made, cand.name)
				progress = true
			}
		}
	}
	for s in stmts {
		moved := false
		for cand in candidates {
			moved ||= cand.stmt == s && slice.contains(made[:], cand.name)
		}
		if !moved {
			append(&out, s)
		}
	}
	return out[:]
}

// Whether a word is a verb the sketch or one of its libraries teaches. The verbs are kept under their
// library and name (`learn_key`), so the word is looked for by its name in every library.
@(private = "file")
is_taught :: proc(c: ^Checker, word: string) -> bool {
	for key in c.learns {
		if name := key[strings.last_index_byte(key, '/') + 1:]; name == word {
			return true
		}
	}
	return false
}

@(private = "file")
has_candidate :: proc(candidates: []$T, name: string) -> bool {
	for cand in candidates {
		if cand.name == name {
			return true
		}
	}
	return false
}
