// SPDX-License-Identifier: 0BSD
//
// Expressions: one switch over the kinds of the typed IR. Arithmetic follows the
// checker's array programming (numbers, vectors and colours), `+` with text joins,
// and every failure gives 0 or an empty value and a runtime error, never a stop.
package interp

import "../"
import "../lang"
import "../maths"
import "core:math"
import "core:strings"

eval :: proc(it: ^Interp, e: ^lang.IR) -> Value {
	if e == nil {
		return nil
	}
	switch &k in e.kind {
	case lang.IR_Number:
		return k.value
	case lang.IR_Text:
		return k.value
	case lang.IR_Colour:
		return k.value
	case lang.IR_Boolean:
		return k.value
	case lang.IR_Word:
		return k.word
	case lang.IR_Load:
		return load_symbol(it, k.symbol, e.span)
	case lang.IR_Builtin:
		switch k.name {
		case "finger":  return finger_record(it, e.type, it.finger)
		case "touches": return touches_list(it, e.type)
		case "turtle":  return turtle_record(it, e.type)
		case "midi":    return midi_record(it, e.type, it.midi)
		case "scene":   return scene_record(it, e.type)
		case "osc":     return osc_record(it, e.type, it.osc)
		case "packet":  return packet_record(it, e.type, it.packet)
		case "received": return received_record(it, e.type, it.received)
		case "reply":   return reply_record(it, e.type)
		case "gamepad": return gamepad_value(it, e.type)
		case "gamepads": return gamepads_list(it, e.type)
		case "joysticks": return joysticks_list(it, e.type)
		case "screens": return screens_list(it, e.type)
		case "safe":    return safe_record(it, e.type)
		case "webcam":  return webcam_value(it, e.span)
		}
		return builtin_value(it, k.name)
	case lang.IR_Swizzle:
		return swizzle(eval(it, k.base), k.parts)
	case lang.IR_Field:
		base := eval(it, k.base)
		if k.at.slot != 0 {
			// a record of the shape the pass found the place in: no names to compare
			if r, is_record := base.(^Record); is_record && r != nil && r.shape == k.at.shape {
				if r.unset != 0 && k.at.slot <= 64 && r.unset & (u64(1) << u64(k.at.slot - 1)) != 0 {
					say_field_missing(it, r, k.name, e.span)
				}
				return r.fields[k.at.slot - 1]
			}
		}
		return read_field(it, base, k.name, e.span)
	case lang.IR_Vector:
		v := Vec{n = len(k.items)}
		for item, i in k.items {
			if i < 4 {
				v.v[i] = as_number(eval(it, item))
			}
		}
		return v
	case lang.IR_List:
		l := new_list(it)
		for item in k.items {
			append(&l.items, eval(it, item))
		}
		return l
	case lang.IR_Record:
		shape := lang.shape_root(it.types, k.shape)
		r := new_record(it, shape)
		r.class = k.class
		if len(k.slots) == len(k.names) {
			for slot, i in k.slots {
				r.fields[slot - 1] = eval(it, k.values[i])
			}
			if it.depth > 0 {
				r.unset = fields_left_out(len(r.fields), k.slots)
			}
			return r
		}
		given := make([dynamic]int, 0, len(k.names), context.temp_allocator)
		for name, i in k.names {
			if at := field_index(it, shape, name); at >= 0 {
				r.fields[at] = eval(it, k.values[i])
				append(&given, at + 1)
			}
		}
		if it.depth > 0 {
			r.unset = fields_left_out(len(r.fields), given[:])
		}
		return r
	case lang.IR_Unary:
		return unary(it, e, k)
	case lang.IR_Binary:
		return binary(it, e, k)
	case lang.IR_Call:
		return eval_call(it, e, k)
	case lang.IR_Convert:
		return eval(it, k.value) // made only by the code generator
	case lang.IR_Block_Value, lang.IR_Error:
		return nil
	}
	return nil
}

// ---- names ----

// A name that lives in the sketch's own memory, or in a frame.
@(private)
is_global :: proc(s: ^lang.Symbol) -> bool {
	return s.kind == .Variable || s.kind == .Constant
}

// A sketch-wide name's value, and whether it has been given one.
Global :: struct {
	value: Value,
	set:   bool,
}

global_value :: proc(it: ^Interp, s: ^lang.Symbol) -> (Value, bool) {
	if s.slot < 0 || s.slot >= len(it.globals) {
		return nil, false
	}
	g := it.globals[s.slot]
	return g.value, g.set
}

set_global :: proc(it: ^Interp, s: ^lang.Symbol, v: Value) {
	if s.slot >= 0 && s.slot < len(it.globals) {
		it.globals[s.slot] = {v, true}
	}
}

load_symbol :: proc(it: ^Interp, s: ^lang.Symbol, at := lang.Span{}) -> Value {
	switch s.kind {
	case .Variable, .Constant:
		if v, found := global_value(it, s); found {
			return v
		}
	case .Item:
		if n := len(it.items); n > 0 {
			return it.items[n - 1]
		}
		return nil
	case .Result:
		if n := len(it.results); n > 0 {
			return it.results[n - 1]
		}
		return nil
	case .Loop, .Message, .Parameter, .Local:
		if it.frame != nil {
			#reverse for slot in it.frame.slots {
				if slot.symbol == s {
					return slot.value
				}
			}
		}
	}
	// A constant is the same wherever it is read, so one read before it has its value is a mistake worth saying.
	if s.kind == .Constant && at.end != 0 {
		words := lang.constant_not_made_args(s.name, context.temp_allocator)
		fail(it, .Constant_Not_Made, at, words[0], words[1], words[2], words[3])
	}
	// A name read before it was ever given a value reads as the zero of its kind.
	return zero_value(it, s.type, 0)
}

// Values stored in something that outlives the frame are copied into the sketch's
// own memory; during set-up everything is already there.
@(private)
keep :: proc(it: ^Interp, v: Value) -> Value {
	if it.alloc == it.long {
		return v
	}
	return promote(it, v)
}

store_symbol :: proc(it: ^Interp, s: ^lang.Symbol, v: Value) {
	if is_global(s) {
		set_global(it, s, keep(it, v))
		return
	}
	if it.frame == nil {
		return
	}
	#reverse for &slot in it.frame.slots {
		if slot.symbol == s {
			slot.value = v
			return
		}
	}
	append(&it.frame.slots, Slot{s, v})
}

@(private)
builtin_value :: proc(it: ^Interp, name: string) -> Value {
	switch name {
	case "width":
		return roci.width()
	case "height":
		return roci.height()
	case "mouse":
		return vec2(roci.mouse())
	case "wheel":
		return vec2(roci.wheel())
	case "mic":
		return roci.mic()
	case "speakers":
		return roci.the_speakers()
	case "pmouse":
		return vec2(roci.pmouse())
	case "time":
		return roci.time_now()
	case "frame":
		return f64(roci.frame_count())
	case "fps":
		return roci.frame_rate()
	case "pi":
		return math.PI
	case "tau":
		return math.TAU
	case "anywhere":
		return vec2(roci.anywhere())
	case "key":
		return roci.last_key()
	case "chosen":
		return strings.clone(it.chosen, it.alloc)
	case "clipboard":
		return roci.clipboard(it.alloc)
	case "platform":
		return roci.platform_name()
	case "language":
		return roci.language_name(it.alloc)
	case "pressed":
		return roci.pressed()
	case "true":
		return true
	case "false":
		return false
	}
	return nil
}

// ---- parts of values ----

@(private)
swizzle :: proc(base: Value, parts: string) -> Value {
	#partial switch b in base {
	case Vec:
		if len(parts) == 1 {
			return component(b, parts[0])
		}
		out := Vec{n = len(parts)}
		for letter, i in transmute([]u8)parts {
			if i < 4 {
				out.v[i] = component(b, letter)
			}
		}
		return out
	case maths.Colour:
		if len(parts) == 1 {
			switch parts[0] {
			case 'r': return f64(b.r)
			case 'g': return f64(b.g)
			case 'b': return f64(b.b)
			case 'a': return byte_to_alpha(f64(b.a))
			}
		}
	}
	return 0.0
}

@(private)
component :: proc(v: Vec, letter: u8) -> f64 {
	index := strings.index_byte("xyzw", letter)
	if index < 0 || index >= v.n {
		return 0
	}
	return v.v[index]
}

@(private)
read_field :: proc(it: ^Interp, base: Value, name: string, at := lang.Span{}) -> Value {
	if w, is_window := base.(roci.Window); is_window {
		switch name {
		case "width":      return roci.window_size(w).x
		case "height":     return roci.window_size(w).y
		case "title":      return roci.window_title(w)
		case "at":         return vec2(roci.window_position(w))
		case "mouse":      return vec2(roci.window_mouse(w))
		case "fullscreen", "resizable", "bordered", "topmost", "visible", "focusable", "grab", "modal", "focused", "hovered", "maximized", "minimized", "covered":
			return roci.window_flag(w, name)
		case "alpha":    return byte_to_alpha(roci.window_alpha(w))
		case "ratio":    return roci.window_ratio(w)
		case "smallest": return vec2(roci.window_smallest(w))
		case "largest":  return vec2(roci.window_largest(w))
		case "cursor":   return roci.CURSOR_NAMES[roci.window_cursor(w)]
		case "parent":
			if owner := roci.window_parent(w); owner != 0 {
				return owner
			}
			return nil
		}
		return nil
	}
	if s, is_sound := base.(roci.Sound); is_sound {
		return sound_field(s, name)
	}
	if picture, is_picture := base.(roci.Image); is_picture {
		switch name {
		case "width":  return roci.image_size(picture).x
		case "height": return roci.image_size(picture).y
		case "playing": return roci.movie_state(picture).playing
		case "loop":    return roci.movie_state(picture).looping
		case "at":      return roci.movie_state(picture).at
		case "length":  return roci.movie_state(picture).length
		case "speed":   return roci.movie_state(picture).speed
		}
		return nil
	}
	if r := as_record(base); r != nil {
		if place := field_index(it, r.shape, name); place >= 0 {
			if r.unset != 0 && place < 64 && r.unset & (u64(1) << u64(place)) != 0 && at.end != 0 {
				say_field_missing(it, r, name, at)
			}
			return r.fields[place]
		}
		if at.end != 0 {
			say_field_missing(it, r, name, at)
		}
	}
	// A vector or a color whose type the checker could not settle when it read this line (a list that starts
	// empty and is filled in a verb that is written further down) is read by its parts, as a vector is.
	#partial switch _ in base {
	case Vec, maths.Colour:
		if len(name) == 1 {
			return swizzle(base, name)
		}
	}
	return nil
}

// The value after `path` of `base` has been set to `value`: a field of a record,
// or parts of a vector or colour. A record changes where it is (it is shared); a
// vector or colour comes back changed, for the caller to store.
assign_path :: proc(it: ^Interp, base: Value, path: []string, value: Value, first := lang.Field_Slot{}) -> Value {
	if len(path) == 0 {
		return value
	}
	#partial switch b in base {
	case roci.Window:
		// Assigning a window's property does what the connecting word of that name does.
		if len(path) > 1 {
			if child, is_window := read_field(it, base, path[0]).(roci.Window); is_window {
				assign_path(it, child, path[1:], value)
			}
		} else {
			set_window_property(it, b, path[0], value)
		}
		return base
	case ^Record:
		if b == nil {
			return base
		}
		at := first.slot - 1 if first.slot != 0 && b.shape == first.shape else field_index(it, b.shape, path[0])
		if at < 0 {
			return base
		}
		changed := assign_path(it, b.fields[at], path[1:], value)
		if b.long && it.alloc != it.long {
			changed = promote(it, changed)
		}
		b.fields[at] = changed
		if at < 64 {
			b.unset &= ~(u64(1) << u64(at))
		}
		b.stamp = next_write(it)
		return base
	case Vec:
		out := b
		parts := path[0]
		if len(parts) == 1 {
			if index := strings.index_byte("xyzw", parts[0]); index >= 0 && index < out.n {
				out.v[index] = as_number(value)
			}
		} else if v, ok := value.(Vec); ok {
			for letter, i in transmute([]u8)parts {
				if index := strings.index_byte("xyzw", letter); index >= 0 && index < out.n && i < v.n {
					out.v[index] = v.v[i]
				}
			}
		}
		return out
	case maths.Colour:
		out := b
		if len(path[0]) == 1 {
			n := f32(as_number(value))
			switch path[0][0] {
			case 'r': out.r = n
			case 'g': out.g = n
			case 'b': out.b = n
			case 'a': out.a = f32(alpha_to_byte(f64(n)))
			}
		}
		return out
	}
	return base
}

// ---- operators ----

@(private)
unary :: proc(it: ^Interp, e: ^lang.IR, k: lang.IR_Unary) -> Value {
	v := eval(it, k.operand)
	if k.op == .Not {
		return !as_bool(v)
	}
	#partial switch x in v {
	case Vec:
		out := x
		for i in 0 ..< out.n {
			out.v[i] = -out.v[i]
		}
		return out
	case maths.Colour:
		return clamp_colour({-x.r, -x.g, -x.b, -x.a})
	}
	return -as_number(v)
}

@(private)
clamp_colour :: proc(c: [4]f32) -> maths.Colour {
	return {clamp(c.r, 0, 255), clamp(c.g, 0, 255), clamp(c.b, 0, 255), clamp(c.a, 0, 255)}
}

@(private)
binary :: proc(it: ^Interp, e: ^lang.IR, k: lang.IR_Binary) -> Value {
	// Arithmetic on two numbers, a comparison of two numbers, and `and` and `or` by
	// their typed paths, which finish these without coming back here.
	numbers := lang.is_number(k.lhs.fast) && lang.is_number(k.rhs.fast)
	#partial switch k.op {
	case .Add, .Subtract, .Multiply, .Divide, .Modulo, .Power:
		if numbers && lang.is_number(e.fast) {
			return eval_number(it, e)
		}
	case .Less, .Less_Equal, .Greater, .Greater_Equal:
		if numbers && e.fast == .Boolean {
			return eval_bool(it, e)
		}
	case .And, .Or:
		if e.fast == .Boolean {
			return eval_bool(it, e)
		}
	}
	left := eval(it, k.lhs)
	// `and` and `or` leave the right side alone when the left decides.
	#partial switch k.op {
	case .And:
		return as_bool(left) && as_bool(eval(it, k.rhs))
	case .Or:
		return as_bool(left) || as_bool(eval(it, k.rhs))
	}
	right := eval(it, k.rhs)
	#partial switch k.op {
	case .Is, .Is_Not, .Less, .Less_Equal, .Greater, .Greater_Equal:
		return compare_values(k.op, left, right)
	case .And, .Or:
		return false
	}
	switch k.op {
	case .Is, .Is_Not, .Less, .Less_Equal, .Greater, .Greater_Equal, .And, .Or:
	case .Add, .Subtract, .Multiply, .Divide, .Modulo, .Power:
	}
	if k.op == .Add {
		if a, is_list := left.(^List); is_list {
			if b, other := right.(^List); other {
				return joined(it, a, b)
			}
		}
	}
	if k.op == .Add {
		_, left_text := left.(string)
		_, right_text := right.(string)
		if left_text || right_text {
			return strings.concatenate({format(it, left, it.alloc), format(it, right, it.alloc)}, it.alloc)
		}
	}
	// Dividing by zero says so once for the place and gives 0.
	zero := false
	arith :: proc(it: ^Interp, op: lang.Binary_Op, a, b: f64, zero: ^bool) -> f64 {
		switch op {
		case .Add:
			return a + b
		case .Subtract:
			return a - b
		case .Multiply:
			return a * b
		case .Divide:
			if b == 0 {
				zero^ = true
				return 0
			}
			return a / b
		case .Modulo:
			if b == 0 {
				zero^ = true
				return 0
			}
			return a - b * maths.floor(a / b)
		case .Power:
			return power(a, b)
		case .Is, .Is_Not, .Less, .Less_Equal, .Greater, .Greater_Equal, .And, .Or:
		}
		return 0
	}
	result: Value
	#partial switch l in left {
	case Vec:
		out := l
		#partial switch r in right {
		case Vec:
			out.n = min(l.n, r.n)
			for i in 0 ..< out.n {
				out.v[i] = arith(it, k.op, l.v[i], r.v[i], &zero)
			}
		case:
			n := as_number(right)
			for i in 0 ..< out.n {
				out.v[i] = arith(it, k.op, l.v[i], n, &zero)
			}
		}
		result = out
	case maths.Colour:
		out: [4]f32
		#partial switch r in right {
		case maths.Colour:
			for i in 0 ..< 4 {
				out[i] = f32(arith(it, k.op, f64(l[i]), f64(r[i]), &zero))
			}
		case:
			n := as_number(right)
			for i in 0 ..< 4 {
				out[i] = f32(arith(it, k.op, f64(l[i]), n, &zero))
			}
		}
		result = clamp_colour(out)
	case:
		#partial switch r in right {
		case Vec:
			n := as_number(left)
			out := r
			for i in 0 ..< out.n {
				out.v[i] = arith(it, k.op, n, r.v[i], &zero)
			}
			result = out
		case maths.Colour:
			n := as_number(left)
			out: [4]f32
			for i in 0 ..< 4 {
				out[i] = f32(arith(it, k.op, n, f64(r[i]), &zero))
			}
			result = clamp_colour(out)
		case:
			result = arith(it, k.op, as_number(left), as_number(right), &zero)
		}
	}
	if zero {
		report_division(it, e, k)
	}
	return result
}

@(private)
report_division :: proc(it: ^Interp, e: ^lang.IR, k: lang.IR_Binary) {
	if said_already(it, .Division_By_Zero, e.span) {
		return
	}
	divisor := lang.span_text(it.src, k.rhs.span)
	line := strings.trim_space(lang.line_text(it.src, lang.position_of(it.src, e.span.start).line))
	fail(it, .Division_By_Zero, e.span, "", "", "", strings.concatenate({"if ", divisor, " is not 0 [ ", line, " ]"}, context.temp_allocator))
}

// A comparison of two values: `is` and `is not` by what they hold, the others as numbers.
// `expect` uses it too, so a check says exactly what an `if` would.
compare_values :: proc(op: lang.Binary_Op, left, right: Value) -> bool {
	#partial switch op {
	case .Is:
		return equal(left, right)
	case .Is_Not:
		return !equal(left, right)
	case .Less:
		return as_number(left) < as_number(right)
	case .Less_Equal:
		return as_number(left) <= as_number(right)
	case .Greater:
		return as_number(left) > as_number(right)
	case .Greater_Equal:
		return as_number(left) >= as_number(right)
	}
	return false
}

// `a ^ b`. A power that is not a number (a negative number to a fraction, zero to a negative) is 0, as a
// division by zero is, so no value is ever not-a-number in a sketch.
power :: proc(a, b: f64) -> f64 {
	result := math.pow(a, b)
	if result != result || math.is_inf(result) {
		return 0
	}
	return result
}

// A field the record this line reads does not have: says which it has, and the nearest of them to what was written.
@(private)
say_field_missing :: proc(it: ^Interp, r: ^Record, name: string, at: lang.Span) {
	names := make([dynamic]string, context.temp_allocator)
	shape_fields := it.types.shapes[r.shape].fields
	for f, i in shape_fields {
		// the fields that were never given a value are not ones it has
		if i < 64 && r.unset & (u64(1) << u64(i)) != 0 {
			continue
		}
		append(&names, f.name)
	}
	if len(shape_fields) == 0 {
		return // an empty record: there is nothing for it to have, and nothing was made to be read
	}
	words := lang.field_missing_args(it.src, at, name, names[:], context.temp_allocator)
	fail(it, .Field_Missing, at, words[0], words[1], words[2], words[3])
}

// The fields of a record of `count` fields that a `{ }` left out, as the bits of `unset`: the places (counted from 1) it gave are not.
@(private)
fields_left_out :: proc(count: int, given: []int) -> u64 {
	if len(given) >= count {
		return 0 // the common case: every field was written
	}
	left: u64
	for i in 0 ..< min(count, 64) {
		left |= u64(1) << u64(i)
	}
	for place in given {
		if place >= 1 && place <= 64 {
			left &= ~(u64(1) << u64(place - 1))
		}
	}
	return left
}
