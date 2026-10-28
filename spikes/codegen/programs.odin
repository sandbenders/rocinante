// SPDX-License-Identifier: 0BSD
package codegen_spike

import "core:slice"

num :: proc(x: f64) -> Expr {
	return Number(x)
}

ref :: proc(name: string) -> Expr {
	return Var{name}
}

field :: proc(record, name: string) -> Expr {
	return Field{record, name}
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

// The first project regression test: one line, one circle.
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

// A list of records changed in place, as in the particle sketch (section 5.4).
// The second `for each` shows that the changes made through `p` stayed in the
// list, because records are shared (section 5.11).
program_records :: proc() -> Program {
	fields := []string{"x", "vy"}
	return Program{
		name   = "records",
		source = "particles = []\nfor i from 1 to 3 [\n  add { x: i * 10, vy: i } to particles\n]\nfor each p in particles [\n  p.x = p.x + p.vy\n  circle p.x 100 p.vy\n]\nfor each p in particles [ circle p.x 200 p.vy ]\n",
		shapes = slice.clone([]Shape{{name = "Particle", fields = slice.clone(fields)}}),
		body   = stmts(
			New_List{name = "particles", shape = "Particle", line = 1},
			For{
				var  = "i", from = num(1), to = num(3), line = 2,
				body = stmts(Add{list = "particles", shape = "Particle", values = exprs(bin(.Mul, ref("i"), num(10)), ref("i")), line = 3}),
			},
			For_Each{
				var  = "p", list = "particles", line = 5,
				body = stmts(
					Set_Field{record = "p", name = "x", value = bin(.Add, field("p", "x"), field("p", "vy")), line = 6},
					Call{verb = "circle", args = exprs(field("p", "x"), num(100), field("p", "vy")), line = 7},
				),
			},
			For_Each{
				var  = "p", list = "particles", line = 9,
				body = stmts(Call{verb = "circle", args = exprs(field("p", "x"), num(200), field("p", "vy")), line = 9}),
			},
		),
	}
}
