// SPDX-License-Identifier: 0BSD
package codegen_spike

import "core:slice"

num :: proc(x: f64) -> Expr {
	return Number(x)
}

ref :: proc(name: string) -> Expr {
	return Var{name}
}

bin :: proc(op: Op, lhs, rhs: Expr) -> Expr {
	return Binary{op, new_clone(lhs), new_clone(rhs)}
}

// Odin refuses to return a slice literal that points into the procedure's
// stack frame, so the programs copy their slices onto the heap.
stmts :: proc(items: ..Stmt) -> []Stmt {
	return slice.clone(items)
}

exprs :: proc(items: ..Expr) -> []Expr {
	return slice.clone(items)
}

// The first project regression test (CLAUDE.md section 1): one line, one circle.
program_circle :: proc() -> Program {
	return Program{
		name   = "circle",
		source = "circle 100 100 50\n",
		body   = stmts(
			Call{verb = "circle", args = exprs(num(100), num(100), num(50)), line = 1},
		),
	}
}

// A variable, a loop and arithmetic.
program_loop :: proc() -> Program {
	return Program{
		name   = "loop",
		source = "gap = 40\nfor i from 1 to 5 [\n  circle (i * gap) 100 (i * 4)\n]\n",
		body   = stmts(
			Assign{name = "gap", value = num(40), line = 1},
			For{
				var  = "i", from = num(1), to = num(5), line = 2,
				body = stmts(
					Call{
						verb = "circle",
						args = exprs(bin(.Mul, ref("i"), ref("gap")), num(100), bin(.Mul, ref("i"), num(4))),
						line = 3,
					},
				),
			},
		),
	}
}
