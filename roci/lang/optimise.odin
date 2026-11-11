// SPDX-License-Identifier: 0BSD
//
// The optimisation passes: rewrites of the typed IR that both back ends run, after
// the checker and before the interpreter or the code generator. A pass only adds
// what it has proved (a mark on a node, today), so a node it leaves alone runs the
// general way, and every pass can be switched off. With every pass off the
// interpreter is the reference the others are compared with, byte for byte, so a
// pass is tested on its own long before compiled code exists.
package lang

import "base:runtime"

Pass :: enum u8 {
	Typed_Values, // marks the nodes that give a number or true or false
	Field_Slots,  // finds where a field is in a record of a known shape, so that it is not looked for by name
}
Passes :: bit_set[Pass]

ALL_PASSES :: Passes{.Typed_Values, .Field_Slots}

// What a node is known to give, so a back end can work it out without a general value.
Fast :: enum u8 {
	None,
	Number,      // a number, or the empty value a name, a field or `find` can hold
	Sure_Number, // always an actual number: a literal, arithmetic, a negation, a maths verb
	Boolean,
}

// Whether the node gives a number (`Number` or `Sure_Number`).
is_number :: proc "contextless" (f: Fast) -> bool {
	return f == .Number || f == .Sure_Number
}

// The verbs of one number that always give a number back.
@(private = "file")
NUMBER_VERBS := [?]string{"abs", "floor", "round", "ceil", "sqrt", "sin", "cos"}

// Runs the passes over the whole program: its statements and every version of every taught verb.
// What a pass makes (the places of fields) is made with `allocator`, which should be the one the
// program's IR was made with, so that it goes when the IR does.
optimise :: proc(program: ^IR_Program, passes: Passes, allocator := context.allocator) {
	if passes == {} {
		return
	}
	o := Optimiser{types = program.types, passes = passes, alloc = allocator}
	for s in program.stmts {
		walk_stmt(&o, s)
	}
	for inst in program.instances {
		for d in inst.defaults {
			walk_expr(&o, d.value)
		}
		walk_block(&o, inst.body)
	}
}

@(private = "file")
Optimiser :: struct {
	types:  ^Types,
	passes: Passes,
	alloc:  runtime.Allocator,
}

@(private = "file")
walk_block :: proc(o: ^Optimiser, b: IR_Block) {
	for s in b.stmts {
		walk_stmt(o, s)
	}
}

@(private = "file")
walk_stmt :: proc(o: ^Optimiser, s: ^IR_Stmt) {
	if s == nil {
		return
	}
	switch &k in s.kind {
	case IR_Assign:
		walk_expr(o, k.value)
		if .Field_Slots in o.passes && len(k.fields) > 0 && k.target != nil {
			k.first = slot_of(o.types, shape_of(o.types, k.target.type), k.fields[0])
		}
	case IR_Expr_Stmt:
		walk_expr(o, k.expr)
	case IR_If:
		walk_expr(o, k.cond)
		walk_block(o, k.body)
		walk_block(o, k.else_body)
	case IR_Repeat:
		walk_expr(o, k.count)
		walk_block(o, k.body)
	case IR_While:
		walk_expr(o, k.cond)
		walk_block(o, k.body)
	case IR_For:
		walk_expr(o, k.from)
		walk_expr(o, k.to)
		walk_expr(o, k.by)
		walk_block(o, k.body)
	case IR_For_Each:
		walk_expr(o, k.list)
		walk_block(o, k.body)
	case IR_With:
		walk_options(o, k.styles)
		walk_expr(o, k.record)
		walk_block(o, k.body)
	case IR_Every:
		walk_expr(o, k.count)
		walk_block(o, k.body)
	case IR_On:
		for a in k.args {
			walk_expr(o, a)
		}
		walk_expr(o, k.window)
		walk_block(o, k.body)
	case IR_Check:
		walk_block(o, k.body)
	case IR_Expect:
		walk_expr(o, k.cond)
	case IR_Draw:
		walk_expr(o, k.window)
		walk_block(o, k.body)
	case IR_Give:
		walk_expr(o, k.value)
	case IR_Unchecked, IR_Stop, IR_Error_Stmt:
	}
}

@(private = "file")
walk_options :: proc(o: ^Optimiser, options: []IR_Option) {
	for opt in options {
		for a in opt.args {
			walk_expr(o, a)
		}
		walk_options(o, opt.extra)
	}
}

@(private = "file")
walk_expr :: proc(o: ^Optimiser, e: ^IR) {
	if e == nil {
		return
	}
	switch &k in e.kind {
	case IR_Swizzle:
		walk_expr(o, k.base)
	case IR_Field:
		walk_expr(o, k.base)
		if .Field_Slots in o.passes && k.base != nil {
			k.at = slot_of(o.types, shape_of(o.types, k.base.type), k.name)
		}
	case IR_Vector:
		for item in k.items {
			walk_expr(o, item)
		}
	case IR_List:
		for item in k.items {
			walk_expr(o, item)
		}
	case IR_Record:
		for v in k.values {
			walk_expr(o, v)
		}
		if .Field_Slots in o.passes {
			root := shape_root(o.types, k.shape)
			slots := make([]int, len(k.names), o.alloc)
			found := true
			for name, i in k.names {
				slots[i] = slot_of(o.types, root, name).slot
				found &&= slots[i] != 0
			}
			if found {
				k.slots = slots
			} else {
				delete(slots, o.alloc)
			}
		}
	case IR_Unary:
		walk_expr(o, k.operand)
	case IR_Binary:
		walk_expr(o, k.lhs)
		walk_expr(o, k.rhs)
	case IR_Call:
		for a in k.args {
			walk_expr(o, a)
		}
		walk_options(o, k.options)
	case IR_Block_Value:
		walk_block(o, k.block)
	case IR_Number, IR_Text, IR_Colour, IR_Boolean, IR_Word, IR_Load, IR_Builtin, IR_Error:
	}
	if .Typed_Values in o.passes {
		mark_typed(o, e)
	}
}

// A node's mark, from its type once inference is over: the type of a name or a
// call may have been settled by a line after it, so this cannot happen while checking.
@(private = "file")
mark_typed :: proc(o: ^Optimiser, e: ^IR) {
	switch kind_of(o.types, e.type) {
	case .Number:
		e.fast = .Sure_Number if sure_number(e) else .Number
	case .Boolean:
		e.fast = .Boolean
	case .None, .Text, .Colour, .Gradient, .Window, .Image, .Block, .Vector, .List, .Record, .Table, .Variable, .Boxed, .Error:
	}
}

// Whether a number node can never give the empty value: it works the number out
// itself rather than reading one somebody stored.
@(private = "file")
sure_number :: proc(e: ^IR) -> bool {
	#partial switch &k in e.kind {
	case IR_Number:
		return true
	case IR_Binary:
		#partial switch k.op {
		case .Add, .Subtract, .Multiply, .Divide, .Modulo:
			return is_number(k.lhs.fast) && is_number(k.rhs.fast)
		}
	case IR_Unary:
		return k.op == .Negate && is_number(k.operand.fast)
	case IR_Call:
		if k.verb == nil || k.instance != nil || len(k.args) != 1 || len(k.options) != 0 {
			return false
		}
		for name in NUMBER_VERBS {
			if k.verb.name == name {
				return true
			}
		}
	}
	return false
}

// Where `name` is in the shape (its root), or nothing when `shape` is not one (-1) or has no
// such field. The checker has settled every shape by now, so the place does not move.
@(private = "file")
slot_of :: proc(ts: ^Types, shape: int, name: string) -> Field_Slot {
	if shape < 0 {
		return {}
	}
	root := shape_root(ts, shape)
	for f, i in ts.shapes[root].fields {
		if f.name == name {
			return Field_Slot{shape = root, slot = i + 1}
		}
	}
	return {}
}
