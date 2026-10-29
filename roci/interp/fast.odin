// SPDX-License-Identifier: 0BSD
//
// Typed paths: nodes the optimisation pass marked as giving a number or true or
// false are worked out here as a plain f64 or bool, never as a general `Value`,
// which comes back from `eval` through memory (a value is 48 bytes). Each case does
// exactly what its general case does for those types, and anything not handled here
// goes the general way, so with the passes off (`lang.optimise` with no passes)
// nothing here runs and the results are the same.
package interp

import "../"
import "../lang"
import "../maths"

// A node marked as a number, as an f64. Callers use it where the general path would
// take `as_number` of the value, or for a `Sure_Number`, which is never empty.
eval_number :: proc(it: ^Interp, e: ^lang.IR) -> f64 {
	switch &k in e.kind {
	case lang.IR_Number:
		return k.value
	case lang.IR_Load:
		s := k.symbol
		if is_global(s) && s.slot >= 0 && s.slot < len(it.globals) {
			g := it.globals[s.slot]
			if g.set {
				if n, ok := g.value.(f64); ok {
					return n
				}
				return as_number(g.value)
			}
		}
		return as_number(load_symbol(it, s))
	case lang.IR_Binary:
		if !lang.is_number(k.lhs.fast) || !lang.is_number(k.rhs.fast) {
			break
		}
		a := eval_number(it, k.lhs)
		b := eval_number(it, k.rhs)
		switch k.op {
		case .Add:      return a + b
		case .Subtract: return a - b
		case .Multiply: return a * b
		case .Divide:
			if b == 0 {
				report_division(it, e, k)
				return 0
			}
			return a / b
		case .Modulo:
			if b == 0 {
				report_division(it, e, k)
				return 0
			}
			return a - b * maths.floor(a / b)
		case .Is, .Is_Not, .Less, .Less_Equal, .Greater, .Greater_Equal, .And, .Or:
		}
	case lang.IR_Unary:
		if k.op == .Negate && lang.is_number(k.operand.fast) {
			return -eval_number(it, k.operand)
		}
	case lang.IR_Call:
		// The maths verbs of one number with no style words: what `call_builtin` does for them.
		if k.instance != nil || len(k.args) != 1 || len(k.options) != 0 {
			break
		}
		code := verb_code(k.verb)
		#partial switch code {
		case .Abs, .Floor, .Round, .Ceil, .Sqrt, .Sin, .Cos:
			x := eval_number(it, k.args[0]) if lang.is_number(k.args[0].fast) else as_number(eval(it, k.args[0]))
			#partial switch code {
			case .Abs:   return roci.absolute(x)
			case .Floor: return roci.floor(x)
			case .Round: return roci.round(x)
			case .Ceil:  return roci.ceil(x)
			case .Sqrt:  return roci.square_root(x)
			case .Sin:   return roci.sin_deg(x)
			case .Cos:   return roci.cos_deg(x)
			}
		}
	case lang.IR_Text, lang.IR_Colour, lang.IR_Boolean, lang.IR_Word, lang.IR_Builtin, lang.IR_Swizzle, lang.IR_Field, lang.IR_Vector, lang.IR_List, lang.IR_Record, lang.IR_Block_Value, lang.IR_Error:
	}
	return as_number(eval(it, e))
}

// A node marked as true or false, as a bool: where the general path takes `as_bool`.
eval_bool :: proc(it: ^Interp, e: ^lang.IR) -> bool {
	#partial switch &k in e.kind {
	case lang.IR_Boolean:
		return k.value
	case lang.IR_Binary:
		#partial switch k.op {
		case .Less, .Less_Equal, .Greater, .Greater_Equal:
			if !lang.is_number(k.lhs.fast) || !lang.is_number(k.rhs.fast) {
				break
			}
			a := eval_number(it, k.lhs)
			b := eval_number(it, k.rhs)
			#partial switch k.op {
			case .Less:          return a < b
			case .Less_Equal:    return a <= b
			case .Greater:       return a > b
			case .Greater_Equal: return a >= b
			}
		case .And:
			return eval_cond(it, k.lhs) && eval_cond(it, k.rhs)
		case .Or:
			return eval_cond(it, k.lhs) || eval_cond(it, k.rhs)
		}
	case lang.IR_Unary:
		if k.op == .Not {
			return !eval_cond(it, k.operand)
		}
	}
	return as_bool(eval(it, e))
}

// A condition, by its typed path when it has one.
eval_cond :: proc(it: ^Interp, e: ^lang.IR) -> bool {
	if e != nil && e.fast == .Boolean {
		return eval_bool(it, e)
	}
	return as_bool(eval(it, e))
}
