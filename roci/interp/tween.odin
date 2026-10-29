// SPDX-License-Identifier: 0BSD
//
// Tweens: `tween ball.pos to mouse over 0.5 as out` moves a number, a vector or a
// colour from where it is to a value, a little each frame, on an ease curve. The
// place is found once, when the tween starts: a name of the sketch, or a record
// and the path into it (records are shared, so a field of a loop's item lasts).
// A new tween of the same place replaces the old one, and the last step lands
// exactly on the value. Tweens belong to the running sketch: a reload or a restart
// drops them.
package interp

import "../"
import "../lang"
import "../maths"
import "base:runtime"
import "core:strings"

Tween :: struct {
	symbol:   ^lang.Symbol, // the sketch-wide name the place starts from, or nil
	record:   ^Record,      // or the record it starts from
	path:     []string,     // fields and vector parts after it, on the heap
	from, to: Value,
	start:    f64, // the sketch's clock when it began
	duration: f64,
	curve:    maths.Ease,
}

// `tween place to value over seconds as curve`.
@(private)
start_tween :: proc(it: ^Interp, call: lang.IR_Call) {
	if len(call.args) == 0 {
		return
	}
	tw: Tween
	parts := make([dynamic]string, context.temp_allocator)
	node := call.args[0]
	root: ^lang.Symbol
	walk: for {
		#partial switch k in node.kind {
		case lang.IR_Load:
			root = k.symbol
			break walk
		case lang.IR_Field:
			append(&parts, k.name)
			node = k.base
		case lang.IR_Swizzle:
			append(&parts, k.parts)
			node = k.base
		case:
			return // the checker allows nothing else
		}
	}
	// The parts were met from the end; the place is root.parts[n-1]...parts[0].
	path := make([dynamic]string, context.temp_allocator)
	#reverse for p in parts {
		append(&path, p)
	}
	if is_global(root) {
		tw.symbol = root
	} else {
		// A local or loop name: the place lasts only through the record it holds.
		r := as_record(load_symbol(it, root))
		if r == nil || !r.long || len(path) == 0 {
			return
		}
		tw.record = r
	}
	// A tween outlives the frame that starts it, and the frame's memory, so it is on the heap.
	heap := runtime.heap_allocator()
	tw.path = make([]string, len(path), heap)
	for p, i in path {
		tw.path[i] = strings.clone(p, heap)
	}
	tw.from = read_place(it, tw)
	tw.to, _ = option_value(it, call.options, "to")
	seconds, _ := option_value(it, call.options, "over")
	tw.duration = as_number(seconds)
	tw.start = roci.time_now()
	if word, found := option_value(it, call.options, "as"); found {
		tw.curve, _ = maths.ease_by_name(as_text(word))
	}
	for &old, i in it.tweens {
		if same_place(old, tw) {
			drop_tween(&old)
			unordered_remove(&it.tweens, i)
			break
		}
	}
	if it.tweens.allocator.procedure == nil {
		it.tweens = make([dynamic]Tween, heap)
	}
	append(&it.tweens, tw)
}

@(private = "file")
same_place :: proc(a, b: Tween) -> bool {
	if a.symbol != b.symbol || a.record != b.record || len(a.path) != len(b.path) {
		return false
	}
	for p, i in a.path {
		if p != b.path[i] {
			return false
		}
	}
	return true
}

@(private)
drop_tween :: proc(t: ^Tween) {
	heap := runtime.heap_allocator()
	for p in t.path {
		delete(p, heap)
	}
	delete(t.path, heap)
	t^ = {}
}

@(private = "file")
read_place :: proc(it: ^Interp, t: Tween) -> Value {
	v: Value = t.record if t.record != nil else load_symbol(it, t.symbol)
	for p in t.path {
		if vec, is_vec := v.(Vec); is_vec {
			v = swizzle(vec, p)
		} else {
			v = read_field(it, v, p)
		}
	}
	return v
}

@(private = "file")
write_place :: proc(it: ^Interp, t: Tween, v: Value) {
	if t.record != nil {
		assign_path(it, t.record, t.path, v)
		return
	}
	if len(t.path) == 0 {
		store_symbol(it, t.symbol, v)
		return
	}
	store_symbol(it, t.symbol, assign_path(it, load_symbol(it, t.symbol), t.path, v))
}

// Moves every tween to where it should be now, once a frame; the finished ones land
// on their value and go.
@(private)
step_tweens :: proc(it: ^Interp) {
	now := roci.time_now()
	for i := 0; i < len(it.tweens); {
		t := &it.tweens[i]
		amount := (now - t.start) / t.duration if t.duration > 0 else 1
		if amount >= 1 {
			write_place(it, t^, t.to)
			drop_tween(t)
			ordered_remove(&it.tweens, i)
			continue
		}
		write_place(it, t^, between(t.from, t.to, maths.ease(amount, t.curve)))
		i += 1
	}
}

// The value `along` of the way from `a` to `b` (beyond them when the curve overshoots).
@(private)
between :: proc(a, b: Value, along: f64) -> Value {
	#partial switch x in a {
	case f64:
		return x + (as_number(b) - x) * along
	case Vec:
		y, _ := b.(Vec)
		out := x
		for i in 0 ..< x.n {
			out.v[i] = x.v[i] + (y.v[i] - x.v[i]) * along
		}
		return out
	case maths.Colour:
		return maths.mix(x, as_colour(b), along)
	}
	return b
}
