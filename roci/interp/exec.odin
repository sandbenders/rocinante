// SPDX-License-Identifier: 0BSD
//
// Statements: assignment, `if`, the loops, `with`, `draw`, and the flow of `give`
// and `stop` out of a taught verb, which is a status that every loop and block
// passes upward, never an exception.
package interp

import "../"
import "../lang"
import "core:math"

exec_stmts :: proc(it: ^Interp, stmts: []^lang.IR_Stmt) -> Flow {
	for s in stmts {
		if flow := exec_stmt(it, s); flow != .Normal {
			return flow
		}
	}
	return .Normal
}

// A block that runs where it stands (the body of `if`, `repeat`, `with`).
exec_block :: proc(it: ^Interp, block: lang.IR_Block) -> Flow {
	return exec_stmts(it, block.stmts)
}

exec_stmt :: proc(it: ^Interp, s: ^lang.IR_Stmt) -> Flow {
	if !tick(it, s.span) {
		return .Abort
	}
	switch k in s.kind {
	case lang.IR_Assign:
		value := eval(it, k.value)
		if len(k.fields) == 0 {
			store_symbol(it, k.target, value)
		} else {
			base := load_symbol(it, k.target)
			store_symbol(it, k.target, assign_path(it, base, k.fields, value))
		}
	case lang.IR_Expr_Stmt:
		eval(it, k.expr)
		if it.pending != .Normal {
			flow := it.pending
			it.pending = .Normal
			return flow
		}
	case lang.IR_If:
		if as_bool(eval(it, k.cond)) {
			return exec_block(it, k.body)
		} else if k.has_else {
			return exec_block(it, k.else_body)
		}
	case lang.IR_Repeat:
		count := as_number(eval(it, k.count))
		for _ in 0 ..< int(math.floor(count)) {
			if flow := exec_block(it, k.body); flow != .Normal {
				return flow
			}
		}
	case lang.IR_While:
		for as_bool(eval(it, k.cond)) {
			if flow := exec_block(it, k.body); flow != .Normal {
				return flow
			}
			if !tick(it, s.span) {
				return .Abort
			}
		}
	case lang.IR_For:
		return exec_for(it, s, k)
	case lang.IR_For_Each:
		return exec_for_each(it, k)
	case lang.IR_With:
		return exec_with(it, k)
	case lang.IR_Draw:
		window := roci.current_window()
		if k.window != nil {
			if w, ok := eval(it, k.window).(roci.Window); ok {
				window = w
			}
		}
		if draw, is_draw := &s.kind.(lang.IR_Draw); is_draw {
			it.draws[window] = &draw.body
		}
		roci.draw_window(window, draw_trampoline)
	case lang.IR_On, lang.IR_Every:
	case lang.IR_Give:
		if it.frame != nil {
			it.frame.result = eval(it, k.value)
		}
		return .Give
	case lang.IR_Stop:
		return .Stop
	case lang.IR_Unchecked, lang.IR_Error_Stmt:
	}
	return .Normal
}

@(private)
exec_for :: proc(it: ^Interp, s: ^lang.IR_Stmt, k: lang.IR_For) -> Flow {
	from, to := as_number(eval(it, k.from)), as_number(eval(it, k.to))
	step := 1.0 if from <= to else -1.0
	if k.by != nil {
		step = as_number(eval(it, k.by))
		if step == 0 {
			step = 1
		}
	}
	// Counting steps, not adding to a running total, so a step of 0.1 does not drift.
	count := int(math.floor((to - from) / step + 1e-9)) + 1
	for n in 0 ..< max(count, 0) {
		store_symbol(it, k.var, from + f64(n) * step)
		if flow := exec_block(it, k.body); flow != .Normal {
			return flow
		}
		if !tick(it, s.span) {
			return .Abort
		}
	}
	return .Normal
}

// Walks the list by position, and writes each item back after its turn, so a
// change to a vector item (`p.x = 1`) stays in the list; records are shared and
// need no writing back.
@(private)
exec_for_each :: proc(it: ^Interp, k: lang.IR_For_Each) -> Flow {
	list := as_list(eval(it, k.list))
	if list == nil {
		return .Normal
	}
	for i := 0; i < len(list.items); i += 1 {
		store_symbol(it, k.var, list.items[i])
		flow := exec_block(it, k.body)
		if i < len(list.items) {
			list.items[i] = load_symbol(it, k.var)
		}
		if flow != .Normal {
			return flow
		}
	}
	return .Normal
}

// A style that lasts for the block: the same words that style one element, and a
// record of them.
@(private)
exec_with :: proc(it: ^Interp, k: lang.IR_With) -> Flow {
	roci.push(.Style)
	if k.record != nil {
		apply_style_record(it, eval(it, k.record))
	}
	look, _ := make_look(it, k.styles)
	apply_look(look)
	flow := exec_block(it, k.body)
	roci.pop()
	return flow
}
