// SPDX-License-Identifier: 0BSD
//
// `check "name" [ expect ... ]`: tests a library or a sketch carries for itself. A sketch
// that is running never looks at them; `run_checks` (what `roci test` calls) runs each
// check once, after the sketch has set itself up, in a frame of its own, so the names a
// check makes are its own and it sees the sketch's. A failed `expect` is a runtime error
// of the message `Expect_Failed`, which says what both sides were.
package interp

import "../lang"
import "core:fmt"
import "core:math"
import "core:strings"

// What running one check found.
Check_Result :: struct {
	name:     string,
	span:     lang.Span, // the check's line
	expects:  int,       // how many `expect` lines ran
	failed:   int,       // how many did not hold
	problems: int,       // runtime errors the check ran into (an item that is not there, a division by zero)
	stopped:  bool,      // it ran too long and was cut off
}

// Whether the check held: every `expect` did, and nothing went wrong on the way.
passed :: proc(r: Check_Result) -> bool {
	return r.failed == 0 && r.problems == 0 && !r.stopped
}

// How many checks the program has.
check_count :: proc(p: ^Interp) -> int {
	n := 0
	for s in p.checked.program.stmts {
		if _, is_check := s.kind.(lang.IR_Check); is_check {
			n += 1
		}
	}
	return n
}

// Runs every check of the program, in the order written, after `start`. The results
// are in `p.checks`, and what failed is in `p.errors`. Does nothing for a program with
// check errors.
run_checks :: proc(p: ^Interp) {
	if p.has_errors {
		return
	}
	current = p
	for s in p.checked.program.stmts {
		check, is_check := s.kind.(lang.IR_Check)
		if !is_check {
			continue
		}
		append(&p.checks, Check_Result{name = check.name, span = s.span})
		p.check_at = len(p.checks)
		events := p.events
		saved_alloc, saved_frame := p.alloc, p.frame
		p.alloc = context.temp_allocator
		frame := Frame{}
		frame.slots = make([dynamic]Slot, 0, 8, context.temp_allocator)
		p.frame = &frame
		p.depth = 0
		begin_block(p)
		flow := exec_stmts(p, check.body.stmts)
		p.alloc, p.frame = saved_alloc, saved_frame
		result := &p.checks[p.check_at - 1]
		result.stopped = flow == .Abort
		// Everything that went wrong in it that was not a failed `expect` is a problem.
		result.problems = p.events - events - result.failed
		p.check_at = 0
	}
}

// One `expect`: works out the condition, and when it does not hold says what the two
// sides of a comparison were.
@(private)
exec_expect :: proc(it: ^Interp, s: ^lang.IR_Stmt, k: lang.IR_Expect) {
	if it.check_at == 0 {
		return // an `expect` the checker already refused outside a check
	}
	result := &it.checks[it.check_at - 1]
	result.expects += 1
	cond := k.cond
	if bin, is_bin := cond.kind.(lang.IR_Binary); is_bin {
		#partial switch bin.op {
		case .Is, .Is_Not, .Less, .Less_Equal, .Greater, .Greater_Equal:
			left, right := eval(it, bin.lhs), eval(it, bin.rhs)
			if !compare_values(bin.op, left, right) {
				fail_expect(it, s, result, explain_comparison(it, bin, left, right))
			}
			return
		}
	}
	if !eval_cond(it, cond) {
		fail_expect(it, s, result, fmt.tprintf("`%s` is false.", source_of(it, cond)))
	}
}

@(private)
fail_expect :: proc(it: ^Interp, s: ^lang.IR_Stmt, result: ^Check_Result, sentence: string) {
	result.failed += 1
	fail(it, .Expect_Failed, s.span, result.name, sentence, "", "")
}

@(private)
source_of :: proc(it: ^Interp, e: ^lang.IR) -> string {
	return strings.trim_space(lang.span_text(it.src, e.span))
}

// A value as a check shows it: text in quotes, so "" and 0 are not mistaken for each other.
@(private)
shown :: proc(it: ^Interp, v: Value) -> string {
	if text, is_text := v.(string); is_text {
		return fmt.tprintf("\"%s\"", text)
	}
	return format(it, v, context.temp_allocator)
}

// Whether the expression is written as a plain value, so that saying what it gives adds nothing.
@(private)
is_literal :: proc(e: ^lang.IR) -> bool {
	#partial switch _ in e.kind {
	case lang.IR_Number, lang.IR_Text, lang.IR_Boolean, lang.IR_Colour:
		return true
	}
	return false
}

@(private)
COMPARISON_WORDS := [lang.Binary_Op]string {
	.Add = "+", .Subtract = "-", .Multiply = "*", .Divide = "/", .Modulo = "%",
	.Less = "<", .Less_Equal = "<=", .Greater = ">", .Greater_Equal = ">=",
	.Is = "is", .Is_Not = "is not", .And = "and", .Or = "or",
}

// The sentence of a comparison that did not hold, in plain words.
@(private)
explain_comparison :: proc(it: ^Interp, bin: lang.IR_Binary, left, right: Value) -> string {
	l, r := source_of(it, bin.lhs), source_of(it, bin.rhs)
	x, y := shown(it, left), shown(it, right)
	#partial switch bin.op {
	case .Is:
		sentence: string
		if is_literal(bin.rhs) {
			sentence = fmt.tprintf("I expected `%s` to be %s, but it is %s.", l, y, x)
		} else {
			sentence = fmt.tprintf("`%s` is %s and `%s` is %s, but they should be the same.", l, x, r, y)
		}
		a, a_ok := left.(f64)
		b, b_ok := right.(f64)
		if a_ok && b_ok && math.abs(a - b) <= 1e-9 * max(1, math.abs(a), math.abs(b)) {
			sentence = fmt.tprintf("%s They differ only by rounding, which is normal for decimals: compare whole numbers, or check that the difference is small.", sentence)
		}
		return sentence
	case .Is_Not:
		return fmt.tprintf("`%s` and `%s` are both %s, but they should differ.", l, r, x)
	}
	return fmt.tprintf("`%s` is %s and `%s` is %s, so `%s %s %s` does not hold.", l, x, r, y, l, COMPARISON_WORDS[bin.op], r)
}
