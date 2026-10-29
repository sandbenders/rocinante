// SPDX-License-Identifier: 0BSD
//
// The syntax tree. Every node has a span, so errors,
// highlighting, the source map for generated Odin and runtime commands can all
// point back at `.roci` text. The parser allocates the whole tree from the
// allocator it is given (an arena per parse), so freeing it is one call.
package lang

import "../registry"

Block :: struct {
	span:  Span, // the square brackets included
	stmts: []^Stmt,
}

Unary_Op :: enum u8 {
	Negate,
	Not,
}

Binary_Op :: enum u8 {
	Add,
	Subtract,
	Multiply,
	Divide,
	Modulo,
	Less,
	Less_Equal,
	Greater,
	Greater_Equal,
	Is,
	Is_Not,
	And,
	Or,
}

Number_Lit :: struct {
	value: f64,
}

Text_Lit :: struct {
	value: string, // unescaped
}

Colour_Lit :: struct {
	text: string, // as written, with the hash
}

// A name or a dotted path: `size`, `p.pos.x`, `physics.push`. The checker decides
// which of a variable, a field, a swizzle and a library name each part is.
Path :: struct {
	parts: []string,
}

Group :: struct {
	inner: ^Expr,
}

Vector_Lit :: struct {
	items: []^Expr,
}

Field :: struct {
	name:  string,
	span:  Span,
	value: ^Expr,
}

Record_Lit :: struct {
	fields: []Field,
}

List_Lit :: struct {
	items: []^Expr,
}

Block_Lit :: struct {
	block: Block,
}

Unary :: struct {
	op:      Unary_Op,
	operand: ^Expr,
}

Binary :: struct {
	op:       Binary_Op,
	lhs, rhs: ^Expr,
}

// A connecting word and the arguments after it: `at 20 20`, `fill red`.
Option_Use :: struct {
	word: string,
	span: Span,
	args: []^Expr,
}

// A verb and what follows it. A verb group's shape is the checker's choice (by
// count, then kinds), so a call keeps only the arguments it was
// written with. `verb` is the registry's row for a built-in and `taught` the
// header for a verb taught with `learn`; exactly one is set.
Call :: struct {
	name:    string, // the words of the verb, as the registry spells them
	verb:    ^registry.Verb,
	taught:  ^Taught_Verb,
	args:    []^Expr,
	options: []Option_Use,
}

Error_Expr :: struct {}

Expr_Kind :: union {
	Number_Lit,
	Text_Lit,
	Colour_Lit,
	Path,
	Group,
	Vector_Lit,
	Record_Lit,
	List_Lit,
	Block_Lit,
	Unary,
	Binary,
	Call,
	Error_Expr,
}

Expr :: struct {
	span: Span,
	kind: Expr_Kind,
}

// `learn star size with points 5 [ ... ]`, read ahead of the parse so that calls
// before the `learn` know how many arguments it takes.
Taught_Verb :: struct {
	name:   string,
	params: []string,
	words:  []string, // the connecting words after `with`, each taking one value
	hidden: bool,
	span:   Span, // the header's name
	library: string, // the library whose file teaches it; empty for the sketch's own files
}

Assign :: struct {
	target: Path,
	value:  ^Expr,
}

Expr_Stmt :: struct {
	expr: ^Expr,
}

If :: struct {
	cond:      ^Expr,
	body:      Block,
	has_else:  bool,
	else_body: Block, // for `else if`, a block holding the one `if`
}

Repeat :: struct {
	count: ^Expr,
	body:  Block,
}

While :: struct {
	cond: ^Expr,
	body: Block,
}

For :: struct {
	var:      string,
	from, to: ^Expr,
	by:       ^Expr, // nil when absent
	body:     Block,
}

For_Each :: struct {
	var:  string,
	list: ^Expr,
	body: Block,
}

Default :: struct {
	word:  string,
	value: ^Expr,
}

Learn :: struct {
	name:     string,
	hidden:   bool,
	params:   []string,
	defaults: []Default,
	body:     Block,
}

Give :: struct {
	value: ^Expr,
}

Stop :: struct {}

// `with fill cyan thickness 2 [ ... ]` has style words; `with glow [ ... ]` has a
// record (or a name that holds one).
With :: struct {
	styles: []Option_Use,
	record: ^Expr,
	body:   Block,
}

Every :: struct {
	count: ^Expr,
	unit:  string, // `seconds`, `second`, `frames` or `frame`
	body:  Block,
}

// `on key "space" [ ... ]`, `on mouse down [ ... ]` have an event and its
// arguments; `on w receive msg [ ... ]` has a window and a message name.
On :: struct {
	event:   string, // empty for the receive form
	args:    []^Expr,
	window:  ^Expr,
	message: string,
	body:    Block,
}

Draw :: struct {
	window: ^Expr, // nil for the default window
	body:   Block,
}

Use :: struct {
	name: string,
}

// A statement the parser could not read. Its error is in the diagnostics; the
// node keeps the place so later steps can skip it.
Error_Stmt :: struct {}

Stmt_Kind :: union {
	Assign,
	Expr_Stmt,
	If,
	Repeat,
	While,
	For,
	For_Each,
	Learn,
	Give,
	Stop,
	With,
	Every,
	On,
	Draw,
	Use,
	Error_Stmt,
}

Stmt :: struct {
	span: Span,
	kind: Stmt_Kind,
}

Program :: struct {
	stmts: []^Stmt,
}
