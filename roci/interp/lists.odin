// SPDX-License-Identifier: 0BSD
//
// The verbs only the language has: `add remove count item print copy`, the list
// verbs `keep skip collect combine find sort` (whose blocks hold one expression,
// with `it` and `result`), and `send`.
package interp

import "../"
import "../lang"
import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"
import "core:unicode/utf8"

is_language_verb :: proc(name: string) -> bool {
	switch name {
	case "add", "remove", "count", "item", "print", "copy", "keep", "skip", "collect", "combine", "find", "sort", "shuffle", "send", "set", "held", "tween", "table", "put", "get", "keys":
		return true
	}
	return is_collision_verb(name)
}

// The one expression inside the `[ ]` of a list verb.
@(private)
block_expr :: proc(ir: ^lang.IR) -> ^lang.IR {
	if ir == nil {
		return nil
	}
	if block, ok := ir.kind.(lang.IR_Block_Value); ok && len(block.block.stmts) == 1 {
		if stmt, is_expr := block.block.stmts[0].kind.(lang.IR_Expr_Stmt); is_expr {
			return stmt.expr
		}
	}
	return nil
}

// What the block gives for one item (and, for `combine`, the running value).
@(private)
run_item :: proc(it: ^Interp, expr: ^lang.IR, item: Value, running: Value = nil, has_running := false) -> Value {
	append(&it.items, item)
	if has_running {
		append(&it.results, running)
	}
	value := eval(it, expr)
	if has_running {
		pop(&it.results)
	}
	pop(&it.items)
	return value
}

// Is it the very same list or record, not only equal to it?
@(private)
same :: proc(a, b: Value) -> bool {
	#partial switch x in a {
	case ^List:
		y, ok := b.(^List)
		return ok && x == y
	case ^Record:
		y, ok := b.(^Record)
		return ok && x == y
	case ^Table:
		y, ok := b.(^Table)
		return ok && x == y
	}
	return false
}

@(private)
call_language :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call) -> Value {
	if is_collision_verb(call.verb.name) {
		return collision_verb(it, e, call)
	}
	switch call.verb.name {
	case "add":
		item := eval(it, call.args[0])
		list := as_list(option_or_nil(it, call.options, "to"))
		if list != nil {
			append(&list.items, promote(it, item) if list.long && it.alloc != it.long else item)
			list.stamp = next_write(it)
		}
	case "remove":
		item := eval(it, call.args[0])
		from := option_or_nil(it, call.options, "from")
		if t := as_table(from); t != nil {
			table_remove(it, t, as_text(item))
			return nil
		}
		list := as_list(from)
		if list != nil {
			// The very item first, then one that is equal to it.
			for x, i in list.items {
				if same(x, item) {
					ordered_remove(&list.items, i)
					list.stamp = next_write(it)
					return nil
				}
			}
			for x, i in list.items {
				if equal(x, item) {
					ordered_remove(&list.items, i)
					list.stamp = next_write(it)
					return nil
				}
			}
		}
	case "count":
		v := eval(it, call.args[0])
		if l := as_list(v); l != nil {
			return f64(len(l.items))
		}
		if t := as_table(v); t != nil {
			return f64(len(t.keys))
		}
		if s, ok := v.(string); ok {
			return f64(utf8.rune_count_in_string(s))
		}
		return 0.0
	case "item":
		return item_of(it, e, call)
	case "print":
		text := format(it, eval(it, call.args[0]), it.long)
		append(&it.printed, text)
		if it.echo {
			fmt.println(text)
		}
	case "copy":
		return deep_copy(it, eval(it, call.args[0]))
	case "keep", "skip":
		list := as_list(eval(it, call.args[0]))
		expr := block_expr(call.args[1])
		out := new_list(it)
		if list != nil {
			for item in list.items {
				passes := as_bool(run_item(it, expr, item))
				if passes == (call.verb.name == "keep") {
					append(&out.items, item)
				}
			}
		}
		return out
	case "find":
		list := as_list(eval(it, call.args[0]))
		expr := block_expr(call.args[1])
		if list != nil {
			for item in list.items {
				if as_bool(run_item(it, expr, item)) {
					return item
				}
			}
		}
		return nil
	case "collect":
		list := as_list(eval(it, call.args[0]))
		expr := block_expr(call.args[1])
		out := new_list(it)
		if list != nil {
			for item in list.items {
				append(&out.items, run_item(it, expr, item))
			}
		}
		return out
	case "combine":
		list := as_list(eval(it, call.args[0]))
		result, _ := option_value(it, call.options, "from", 0)
		expr := block_expr(option_ir(call.options, "from", 1))
		if list != nil {
			for item in list.items {
				result = run_item(it, expr, item, result, true)
			}
		}
		return result
	case "sort":
		return sort_list(it, call)
	case "shuffle":
		// A new list, mixed by the sketch's own random numbers (so a seed repeats it).
		out := new_list(it)
		if list := as_list(eval(it, call.args[0])); list != nil {
			append(&out.items, ..list.items[:])
			for i := len(out.items) - 1; i > 0; i -= 1 {
				j := min(int(roci.random(f64(i + 1))), i)
				out.items[i], out.items[j] = out.items[j], out.items[i]
			}
		}
		return out
	case "send":
		send_message(it, eval(it, call.args[0]), eval(it, call.args[1]))
	case "set":
		set_window(it, eval(it, call.args[0]), call.options)
	case "held":
		return roci.key_down(as_text(eval(it, call.args[0])))
	case "tween":
		start_tween(it, call)
	case "table":
		return new_table(it)
	case "put":
		if t := as_table(eval(it, call.args[0])); t != nil {
			table_put(it, t, as_text(eval(it, call.args[1])), eval(it, call.args[2]))
		}
	case "get":
		t := as_table(eval(it, call.args[0]))
		if v, found := table_get(t, as_text(eval(it, call.args[1]))); found {
			return v
		}
		return zero_value(it, e.type, 0)
	case "keys":
		out := new_list(it)
		if t := as_table(eval(it, call.args[0])); t != nil {
			for name in t.keys {
				append(&out.items, name)
			}
		}
		return out
	}
	return nil
}

@(private)
option_or_nil :: proc(it: ^Interp, options: []lang.IR_Option, word: string) -> Value {
	v, _ := option_value(it, options, word)
	return v
}

// `item 2 of scores`, counting from 1. An item that is not there is an empty value
// and a runtime error that shows the line with a check in front.
@(private)
item_of :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call) -> Value {
	index := as_number(eval(it, call.args[0]))
	list_ir := option_ir(call.options, "of")
	list := as_list(eval(it, list_ir))
	at := int(math.floor(index))
	if list != nil && at >= 1 && at <= len(list.items) {
		return list.items[at - 1]
	}
	count := 0 if list == nil else len(list.items)
	has := "no items" if count == 0 else fmt.tprintf("%d item%s", count, "" if count == 1 else "s")
	name := lang.span_text(it.src, list_ir.span) if list_ir != nil else "the list"
	line := strings.trim_space(lang.line_text(it.src, lang.position_of(it.src, e.span.start).line))
	fail(it, .Index_Out_Of_Range, e.span, name, has, format_number(index), strings.concatenate({"if count ", name, " >= ", format_number(max(math.floor(index), 1)), " [ ", line, " ]"}, context.temp_allocator))
	return zero_value(it, e.type, 0)
}

Sort_Entry :: struct {
	key:  Value,
	item: Value,
}

// A new list, in the order of what the block gives for each item (numbers, or
// text), keeping the order of items that tie.
@(private)
sort_list :: proc(it: ^Interp, call: lang.IR_Call) -> Value {
	list := as_list(eval(it, call.args[0]))
	expr := block_expr(option_ir(call.options, "by"))
	out := new_list(it)
	if list == nil {
		return out
	}
	entries := make([]Sort_Entry, len(list.items), context.temp_allocator)
	for item, i in list.items {
		entries[i] = Sort_Entry{key = run_item(it, expr, item), item = item}
	}
	slice.stable_sort_by(entries, proc(a, b: Sort_Entry) -> bool {
		if x, ok := a.key.(string); ok {
			y, _ := b.key.(string)
			return x < y
		}
		return as_number(a.key) < as_number(b.key)
	})
	for entry in entries {
		append(&out.items, entry.item)
	}
	return out
}
