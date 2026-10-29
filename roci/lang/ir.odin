// SPDX-License-Identifier: 0BSD
//
// The typed IR: what the checker makes of a
// sketch and what the interpreter runs and the code generator reads. Every node
// has a type and a span; names are resolved to symbols; a verb call carries the
// registry verb and the shape of its group that was chosen. Nothing here is a
// tree of strings.
//
// Phase 7's optimisation passes need a few facts the interpreter
// ignores: the variables a block captures (`captures`), and the lists changed
// inside a loop (`changed_lists`, step 3b). They are carried, not used.
package lang

import "../maths"
import "../registry"

Symbol_Kind :: enum u8 {
	Variable,
	Constant, // written in capitals: assigned once, never changed
	Loop,     // the name of a `for` loop
	Item,     // `it` inside a list verb's block
	Result,   // `result` inside `combine`'s block
	Message,  // the name of a message in `on w receive msg`
	Parameter, // a parameter of a taught verb
	Local,    // a name made inside a taught verb that does not exist at top level
}

Symbol :: struct {
	name:        string,
	kind:        Symbol_Kind,
	type:        Type_Id,
	first_write: Span,  // where it is first given a value, in reading order
	written:     bool,  // set when the checker reaches that first write
	scope:       int,   // 0 for a sketch-wide name; the depth of the block a local belongs to
	mutated:     bool,  // a taught verb changes what this parameter holds (`p.x = 1`, `add x to p`)
	slot:        int,   // for a sketch-wide name, its place in `IR_Program.symbols`, where the interpreter keeps its value
}

IR_Number :: struct {
	value: f64,
}

IR_Text :: struct {
	value: string,
}

IR_Colour :: struct {
	value: maths.Colour,
}

IR_Boolean :: struct {
	value: bool,
}

// A plain word where a call takes one: `center` in `as center`, `round` in `caps round`.
IR_Word :: struct {
	word: string,
}

IR_Load :: struct {
	symbol: ^Symbol,
}

// A built-in value: `width`, `mouse`, `pi`.
IR_Builtin :: struct {
	name: string,
}

// `p.xy`, `p.x`, `c.r`: parts of a vector or colour.
IR_Swizzle :: struct {
	base:  ^IR,
	parts: string,
}

// `p.pos` on a record (step 3b); until then records are boxed and only get here.
IR_Field :: struct {
	base: ^IR,
	name: string,
}

IR_Vector :: struct {
	items: []^IR,
}

IR_List :: struct {
	items: []^IR,
}

IR_Record :: struct {
	shape:  int, // the record's shape (types.shapes), the root of any merge
	names:  []string,
	values: []^IR,
	class:  Shape_Class, // the collision shape its fields make, decided here once
}

IR_Unary :: struct {
	op:      Unary_Op,
	operand: ^IR,
}

IR_Binary :: struct {
	op:       Binary_Op,
	lhs, rhs: ^IR,
}

IR_Option :: struct {
	word: string,
	args: []^IR,
}

// A call of a built-in verb, with the shape of its group the checker chose. A taught
// verb (step 3b) has `taught` set and no `verb`.
IR_Call :: struct {
	verb:     ^registry.Verb,
	taught:   ^Taught_Verb,
	instance: ^IR_Instance, // the version of the taught verb for these argument types
	shape:    int,
	args:    []^IR,
	options: []IR_Option,
}

IR_Block :: struct {
	span:     Span,
	stmts:    []^IR_Stmt,
	captures: []^Symbol, // names from outside the block that it reads or writes
}

IR_Block_Value :: struct {
	block:      IR_Block,
	value_type: Type_Id, // for a block that holds one expression: what the expression gives
}

IR_Error :: struct {}

IR_Kind :: union {
	IR_Number,
	IR_Text,
	IR_Colour,
	IR_Boolean,
	IR_Word,
	IR_Load,
	IR_Builtin,
	IR_Swizzle,
	IR_Field,
	IR_Vector,
	IR_List,
	IR_Record,
	IR_Unary,
	IR_Binary,
	IR_Call,
	IR_Block_Value,
	IR_Error,
}

// An expression: a value with its type.
IR :: struct {
	span: Span,
	type: Type_Id,
	kind: IR_Kind,
}

IR_Assign :: struct {
	target: ^Symbol,
	fields: []string, // `p.x = 1` sets a part of the vector `p`
	value:  ^IR,
}

IR_Expr_Stmt :: struct {
	expr: ^IR,
}

IR_If :: struct {
	cond:      ^IR,
	body:      IR_Block,
	has_else:  bool,
	else_body: IR_Block,
}

IR_Repeat :: struct {
	count: ^IR,
	body:  IR_Block,
}

IR_While :: struct {
	cond: ^IR,
	body: IR_Block,
}

IR_For :: struct {
	var:      ^Symbol,
	from, to: ^IR,
	by:       ^IR, // nil when absent
	body:     IR_Block,
}

IR_For_Each :: struct {
	var:  ^Symbol,
	list: ^IR,
	body: IR_Block,
}

IR_With :: struct {
	styles: []IR_Option,
	record: ^IR,
	body:   IR_Block,
}

IR_Every :: struct {
	count: ^IR,
	unit:  string,
	body:  IR_Block,
}

IR_On :: struct {
	event:   string,
	args:    []^IR,
	window:  ^IR,
	message: ^Symbol,
	body:    IR_Block,
}

IR_Draw :: struct {
	window: ^IR, // nil for the default window
	body:   IR_Block,
}

// A `learn` or `use`: nothing runs where it stands. A taught verb runs through its
// instances (below).
IR_Unchecked :: struct {}

IR_Give :: struct {
	value: ^IR,
}

IR_Stop :: struct {}

// A word of a `learn` header after `with`: its own name inside the verb, and the
// value it has when the call does not give one.
IR_Default :: struct {
	word:   string,
	symbol: ^Symbol,
	value:  ^IR,
}

// One version of a taught verb, for one tuple of argument types : a record shape makes its own, so compiled code gets one plain procedure
// per shape. A verb nobody calls is checked once with mixed parameters and marked
// `unused`.
IR_Instance :: struct {
	name:      string,
	params:    []^Symbol,
	defaults:  []IR_Default,
	body:      IR_Block,
	arg_types: []Type_Id,
	result:    Type_Id, // what `give` hands back; None when the verb has no `give`
	gives:     bool,
	mutated:   []bool,  // which parameters the body changes
	unused:    bool,
}

IR_Error_Stmt :: struct {}

IR_Stmt_Kind :: union {
	IR_Assign,
	IR_Expr_Stmt,
	IR_If,
	IR_Repeat,
	IR_While,
	IR_For,
	IR_For_Each,
	IR_With,
	IR_Every,
	IR_On,
	IR_Draw,
	IR_Unchecked,
	IR_Give,
	IR_Stop,
	IR_Error_Stmt,
}

IR_Stmt :: struct {
	span: Span,
	kind: IR_Stmt_Kind,
}

IR_Program :: struct {
	stmts:   []^IR_Stmt,
	symbols:   []^Symbol, // the sketch-wide names, in the order they are first written
	instances: []^IR_Instance,
	types:     ^Types,
}
