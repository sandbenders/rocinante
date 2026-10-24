// SPDX-License-Identifier: 0BSD
//
// A hand-written fragment of the typed IR (CLAUDE.md section 4.7). The real IR
// is produced by the checker and carries a type on every node and a source span
// everywhere; this fragment has numbers only, and a line number per statement.
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

Expr :: union {
	Number,
	Var,
	Binary,
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

Stmt :: union {
	Call,
	Assign,
	For,
}

Program :: struct {
	name:   string,
	source: string, // the .roci text, copied into the generated file's header
	body:   []Stmt,
}

// Verbs the core offers to this spike, with their argument counts.
Verb :: struct {
	name:  string,
	arity: int,
}

VERBS :: []Verb{{"circle", 3}}
