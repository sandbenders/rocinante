// SPDX-License-Identifier: 0BSD
package codegen_spike

import "core:fmt"

// A minimal stand-in for the checker: every verb exists and gets the right
// number of arguments, and every name is set before it is read. The real
// checker also infers types and gives errors in plain words (section 5.7).
check_program :: proc(p: Program) -> (errors: [dynamic]string) {
	known := make(map[string]bool)
	defer delete(known)
	check_body(p.body, &known, &errors)
	return
}

check_body :: proc(body: []Stmt, known: ^map[string]bool, errors: ^[dynamic]string) {
	for stmt in body {
		switch s in stmt {
		case Call:
			arity := -1
			for verb in VERBS {
				if verb.name == s.verb {
					arity = verb.arity
				}
			}
			if arity < 0 {
				append(errors, fmt.aprintf("line %d: I don't know the word \"%s\"", s.line, s.verb))
			} else if len(s.args) != arity {
				append(errors, fmt.aprintf("line %d: %s needs %d values but got %d", s.line, s.verb, arity, len(s.args)))
			}
			for arg in s.args {
				check_expr(arg, s.line, known, errors)
			}
		case Assign:
			check_expr(s.value, s.line, known, errors)
			known[s.name] = true
		case For:
			check_expr(s.from, s.line, known, errors)
			check_expr(s.to, s.line, known, errors)
			// The loop name exists only inside the loop in this spike.
			was_known := known[s.var]
			known[s.var] = true
			check_body(s.body, known, errors)
			known[s.var] = was_known
		}
	}
}

check_expr :: proc(e: Expr, line: int, known: ^map[string]bool, errors: ^[dynamic]string) {
	switch v in e {
	case Number:
	case Var:
		if !known[v.name] {
			append(errors, fmt.aprintf("line %d: \"%s\" has no value yet", line, v.name))
		}
	case Binary:
		check_expr(v.lhs^, line, known, errors)
		check_expr(v.rhs^, line, known, errors)
	}
}
