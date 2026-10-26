// SPDX-License-Identifier: 0BSD
package codegen_spike

import "core:fmt"

// A minimal stand-in for the checker: every verb exists and gets the right
// number of arguments, every name is set before it is read, and lists and
// records are used with the shape they were made with. The real checker also
// infers types and gives errors in plain words (section 5.7).
Checker :: struct {
	shapes:  []Shape,
	numbers: map[string]bool,
	lists:   map[string]string, // list name to the shape of its records
	records: map[string]string, // name bound by `for each` to its record's shape
	walking: map[string]bool,   // lists a `for each` is walking right now
	errors:  [dynamic]string,
}

check_program :: proc(p: Program) -> (errors: [dynamic]string) {
	c := Checker{shapes = p.shapes}
	defer {
		delete(c.numbers)
		delete(c.lists)
		delete(c.records)
		delete(c.walking)
	}
	check_body(&c, p.body)
	return c.errors
}

check_body :: proc(c: ^Checker, body: []Stmt) {
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
				append(&c.errors, fmt.aprintf("line %d: I don't know the word \"%s\"", s.line, s.verb))
			} else if len(s.args) != arity {
				append(&c.errors, fmt.aprintf("line %d: %s needs %d values but got %d", s.line, s.verb, arity, len(s.args)))
			}
			for arg in s.args {
				check_expr(c, arg, s.line)
			}
		case Assign:
			check_expr(c, s.value, s.line)
			c.numbers[s.name] = true
		case For:
			check_expr(c, s.from, s.line)
			check_expr(c, s.to, s.line)
			// The loop name exists only inside the loop in this spike.
			was_known := c.numbers[s.var]
			c.numbers[s.var] = true
			check_body(c, s.body)
			c.numbers[s.var] = was_known
		case New_List:
			if _, ok := find_shape(c.shapes, s.shape); !ok {
				append(&c.errors, fmt.aprintf("line %d: there is no record shape called %s", s.line, s.shape))
			}
			check_not_walking(c, s.name, s.line)
			c.lists[s.name] = s.shape
		case Add:
			for value in s.values {
				check_expr(c, value, s.line)
			}
			shape, shape_ok := find_shape(c.shapes, s.shape)
			list_shape, list_ok := c.lists[s.list]
			switch {
			case !shape_ok:
				append(&c.errors, fmt.aprintf("line %d: there is no record shape called %s", s.line, s.shape))
			case !list_ok:
				append(&c.errors, fmt.aprintf("line %d: \"%s\" is not a list yet", s.line, s.list))
			case list_shape != s.shape:
				append(&c.errors, fmt.aprintf("line %d: \"%s\" holds %s records, not %s", s.line, s.list, list_shape, s.shape))
			case len(s.values) != len(shape.fields):
				append(&c.errors, fmt.aprintf("line %d: a %s record has %d fields but got %d", s.line, s.shape, len(shape.fields), len(s.values)))
			}
			check_not_walking(c, s.list, s.line)
		case For_Each:
			list_shape, list_ok := c.lists[s.list]
			if !list_ok {
				append(&c.errors, fmt.aprintf("line %d: \"%s\" is not a list yet", s.line, s.list))
			}
			outer, had_outer := c.records[s.var]
			was_walking := c.walking[s.list]
			c.records[s.var] = list_shape
			c.walking[s.list] = true
			check_body(c, s.body)
			c.walking[s.list] = was_walking
			if had_outer {
				c.records[s.var] = outer
			} else {
				delete_key(&c.records, s.var)
			}
		case Set_Field:
			check_expr(c, s.value, s.line)
			check_field(c, s.record, s.name, s.line)
		}
	}
}

check_expr :: proc(c: ^Checker, e: Expr, line: int) {
	switch v in e {
	case Number:
	case Var:
		if !c.numbers[v.name] {
			append(&c.errors, fmt.aprintf("line %d: \"%s\" has no value yet", line, v.name))
		}
	case Binary:
		check_expr(c, v.lhs^, line)
		check_expr(c, v.rhs^, line)
	case Field:
		check_field(c, v.record, v.name, line)
	}
}

// A field is read or set through a name that holds a record of a shape that has it.
check_field :: proc(c: ^Checker, record, name: string, line: int) {
	shape_name, ok := c.records[record]
	if !ok {
		append(&c.errors, fmt.aprintf("line %d: \"%s\" is not a record here", line, record))
		return
	}
	shape, shape_ok := find_shape(c.shapes, shape_name)
	if !shape_ok {
		return // already reported where the list was made
	}
	for field in shape.fields {
		if field == name {
			return
		}
	}
	append(&c.errors, fmt.aprintf("line %d: a %s record has no field \"%s\"", line, shape_name, name))
}

// Section 5.15: changing a list while `for each` walks it is a load-time error.
check_not_walking :: proc(c: ^Checker, list: string, line: int) {
	if c.walking[list] {
		append(&c.errors, fmt.aprintf("line %d: \"%s\" changes while \"for each\" walks it", line, list))
	}
}
