// SPDX-License-Identifier: 0BSD
//
// A hand-written fragment of the typed IR. The real IR
// is produced by the checker and carries a type on every node and a source span
// everywhere; this fragment has numbers and lists of records of numbers only,
// and a line number per statement.
package codegen_spike

Op :: enum {
	Add,
	Sub,
	Mul,
	Div,
}

Number :: distinct f64

Var :: struct {
	name: string,
}

Binary :: struct {
	op:       Op,
	lhs, rhs: ^Expr,
}

// `p.x`: a field of the record a name holds.
Field :: struct {
	record, name: string,
}

Expr :: union {
	Number,
	Var,
	Binary,
	Field,
}

// `circle 100 100 50`: a verb and its arguments.
Call :: struct {
	verb: string,
	args: []Expr,
	line: int,
}

// `gap = 40`
Assign :: struct {
	name:  string,
	value: Expr,
	line:  int,
}

// `for i from 1 to 5 [ ... ]`, both ends included.
For :: struct {
	var:      string,
	from, to: Expr,
	body:     []Stmt,
	line:     int,
}

// `particles = []`: an empty list of records of one shape.
New_List :: struct {
	name, shape: string,
	line:        int,
}

// `add { x: 1, vy: 2 } to particles`, with the values in the shape's field order.
Add :: struct {
	list, shape: string,
	values:      []Expr,
	line:        int,
}

// `for each p in particles [ ... ]`. `p` shares each item rather than copying
// it (section 5.11), so changes made through it stay in the list.
For_Each :: struct {
	var, list: string,
	body:      []Stmt,
	line:      int,
}

// `p.x = p.x + p.vy`
Set_Field :: struct {
	record, name: string,
	value:        Expr,
	line:         int,
}

Stmt :: union {
	Call,
	Assign,
	For,
	New_List,
	Add,
	For_Each,
	Set_Field,
}

// A record shape: one per place a record is made (section 5.3). Every field
// is a number in this spike.
Shape :: struct {
	name:   string,
	fields: []string,
}

Program :: struct {
	name:   string,
	source: string, // the .roci text, copied into the generated file's header
	shapes: []Shape,
	body:   []Stmt,
}

find_shape :: proc(shapes: []Shape, name: string) -> (Shape, bool) {
	for shape in shapes {
		if shape.name == name {
			return shape, true
		}
	}
	return {}, false
}

// Verbs the core offers to this spike, with their argument counts.
Verb :: struct {
	name:  string,
	arity: int,
}

VERBS :: []Verb{{"circle", 3}}
