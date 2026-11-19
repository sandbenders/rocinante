// SPDX-License-Identifier: 0BSD
//
// A value whose kind is only known while the sketch runs, for the places where the checker could not settle one kind
// (a field that holds a number in one record and text in another, a list of numbers and text). The interpreter holds
// every value this way; a compiled sketch holds only these, and only where it must. What each operation does with a
// value of the wrong kind is what the interpreter does (a number where text was wanted is 0, text where a number was
// wanted is 0, and so on), so the two never differ.
package rt

import "core:strings"
import "../"
import "../maths"
import "../osc"

// A record, list or table held in a box: the object, and the Odin type it was made as, so that taking it out again
// as another kind of object gives nothing instead of reading it as the wrong thing.
Heap_Ref :: struct {
	object: ^Header,
	type:   typeid,
	ops:    ^Heap_Ops, // what can be done with it without knowing its type; nil for none
}

// What a boxed object can do that needs its type, written by the generator for each type that goes in a box.
Heap_Ops :: struct {
	copy: proc(object: ^Header) -> ^Header, // an independent copy, items and fields inside included
	show: proc(object: ^Header) -> string,  // how it reads in text, for a list of what `show` reads
}

Box :: union {
	f64,
	bool,
	string,
	[2]f64,
	[3]f64,
	[4]f64,
	maths.Colour,
	roci.Image,
	roci.Sound,
	roci.Window,
	^Gradient_Box,
	Heap_Ref,
}

// ---- putting a value in a box ----

box_number :: proc(v: f64) -> Box { return v }
box_bool :: proc(v: bool) -> Box { return v }
box_text :: proc(v: string) -> Box { return v }
box_vector2 :: proc(v: [2]f64) -> Box { return v }
box_vector3 :: proc(v: [3]f64) -> Box { return v }
box_vector4 :: proc(v: [4]f64) -> Box { return v }
box_colour :: proc(v: maths.Colour) -> Box { return v }
box_image :: proc(v: roci.Image) -> Box { return v }
box_sound :: proc(v: roci.Sound) -> Box { return v }
box_window :: proc(v: roci.Window) -> Box { return v }
box_gradient :: proc(v: ^Gradient_Box) -> Box { return v }

// A record, a list or a table (they all begin with the collector's header); nothing for no object.
box_heap :: proc(object: $T, ops: ^Heap_Ops = nil) -> Box {
	if object == nil {
		return nil
	}
	return Heap_Ref{object = &object.gc__, type = T, ops = ops}
}

// A copy of a boxed value as `copy` makes it: a number, text, vector or color is itself, an object is copied by what
// the generator wrote for its type (and is shared when it wrote nothing).
copy_box :: proc(b: Box) -> Box {
	#partial switch x in b {
	case string:
		return keep(x)
	case Heap_Ref:
		if x.ops != nil && x.ops.copy != nil && x.object != nil {
			return Heap_Ref{object = x.ops.copy(x.object), type = x.type, ops = x.ops}
		}
	}
	return b
}

// ---- taking a value out of a box ----

// A number, or 0 for anything else (true is 1), as the interpreter reads it.
unbox_number :: proc(b: Box) -> f64 {
	#partial switch x in b {
	case f64:
		return x
	case bool:
		return 1 if x else 0
	}
	return 0
}

unbox_bool :: proc(b: Box) -> bool {
	#partial switch x in b {
	case bool:
		return x
	case f64:
		return x != 0
	}
	return false
}

unbox_text :: proc(b: Box) -> string {
	if s, ok := b.(string); ok {
		return s
	}
	return ""
}

// The first components of a vector, padded with zeros, or zeros for anything else.
unbox_vector :: proc(b: Box, $N: int) -> [N]f64 {
	out: [N]f64
	#partial switch x in b {
	case [2]f64:
		for i in 0 ..< min(N, 2) { out[i] = x[i] }
	case [3]f64:
		for i in 0 ..< min(N, 3) { out[i] = x[i] }
	case [4]f64:
		for i in 0 ..< min(N, 4) { out[i] = x[i] }
	}
	return out
}

unbox_vector2 :: proc(b: Box) -> [2]f64 { return unbox_vector(b, 2) }
unbox_vector3 :: proc(b: Box) -> [3]f64 { return unbox_vector(b, 3) }
unbox_vector4 :: proc(b: Box) -> [4]f64 { return unbox_vector(b, 4) }

// A new list of what each box of a list holds, taken out as one kind (a list that is read, such as the corners of a
// polygon: changing the new list does not change the old).
list_unboxed :: proc(list: ^List(Box), convert: proc(b: Box) -> $T, mark: proc(item: T)) -> ^List(T) {
	out := new_list(T, mark)
	if list != nil {
		for item in list.items {
			add(convert(item), out)
		}
	}
	return out
}

// A new list of boxes, one for each item of a list of one kind.
list_boxed :: proc(list: ^List($T), convert: proc(item: T) -> Box) -> ^List(Box) {
	out := new_list(Box, mark_box)
	if list != nil {
		for item in list.items {
			add(convert(item), out)
		}
	}
	return out
}

unbox_colour :: proc(b: Box) -> maths.Colour {
	if c, ok := b.(maths.Colour); ok {
		return c
	}
	return {}
}

unbox_image :: proc(b: Box) -> roci.Image {
	if v, ok := b.(roci.Image); ok {
		return v
	}
	return 0
}

unbox_sound :: proc(b: Box) -> roci.Sound {
	if v, ok := b.(roci.Sound); ok {
		return v
	}
	return 0
}

unbox_window :: proc(b: Box) -> roci.Window {
	if v, ok := b.(roci.Window); ok {
		return v
	}
	return 0
}

unbox_gradient :: proc(b: Box) -> ^Gradient_Box {
	if v, ok := b.(^Gradient_Box); ok {
		return v
	}
	return nil
}

// A record, list or table of the type asked for, or nothing when the box holds something else.
unbox_heap :: proc(b: Box, $T: typeid) -> T {
	if h, ok := b.(Heap_Ref); ok && h.type == T {
		return (T)(rawptr(h.object))
	}
	return nil
}

// ---- what the collector keeps ----

mark_box :: proc(b: Box) {
	#partial switch x in b {
	case string:
		mark_text(x)
	case Heap_Ref:
		mark(x.object)
	case ^Gradient_Box:
		if x != nil {
			mark(&x.gc__)
		}
	}
}

// Text held in a box that lives on: a text made while the frame ran is copied, as it is where a name keeps one.
keep_box :: proc(b: Box) -> Box {
	if s, ok := b.(string); ok {
		return keep(s)
	}
	return b
}

// ---- comparing, showing, working out ----

// `is`: the same kind and the same contents; objects are the same object.
box_equal :: proc(a, b: Box) -> bool {
	switch x in a {
	case f64:
		y, ok := b.(f64)
		return ok && x == y
	case bool:
		y, ok := b.(bool)
		return ok && x == y
	case string:
		y, ok := b.(string)
		return ok && x == y
	case [2]f64:
		y, ok := b.([2]f64)
		return ok && x == y
	case [3]f64:
		y, ok := b.([3]f64)
		return ok && x == y
	case [4]f64:
		y, ok := b.([4]f64)
		return ok && x == y
	case maths.Colour:
		y, ok := b.(maths.Colour)
		return ok && x == y
	case roci.Image:
		y, ok := b.(roci.Image)
		return ok && x == y
	case roci.Sound:
		y, ok := b.(roci.Sound)
		return ok && x == y
	case roci.Window:
		y, ok := b.(roci.Window)
		return ok && x == y
	case ^Gradient_Box:
		y, ok := b.(^Gradient_Box)
		return ok && x == y
	case Heap_Ref:
		y, ok := b.(Heap_Ref)
		return ok && x.object == y.object
	}
	return b == nil
}

// How a boxed value reads in text: as the interpreter writes it.
show_box :: proc(b: Box, allocator := context.temp_allocator) -> string {
	switch x in b {
	case f64:
		return format_number(x, allocator)
	case bool:
		return "true" if x else "false"
	case string:
		return x
	case [2]f64:
		return show_vector(x, allocator)
	case [3]f64:
		return show_vector(x, allocator)
	case [4]f64:
		return show_vector(x, allocator)
	case maths.Colour:
		return strings.concatenate({"rgb ", format_number(f64(x.r), allocator), " ", format_number(f64(x.g), allocator), " ", format_number(f64(x.b), allocator), " alpha ", format_number(byte_to_alpha(f64(x.a)), allocator)}, allocator)
	case roci.Window:
		return strings.concatenate({"window ", format_number(f64(x), allocator)}, allocator)
	case roci.Image:
		return strings.concatenate({"a ", format_number(roci.image_size(x).x, allocator), " by ", format_number(roci.image_size(x).y, allocator), " picture"}, allocator)
	case roci.Sound:
		return strings.concatenate({"a ", format_number(roci.sound_state(x).length, allocator), " second sound"}, allocator)
	case ^Gradient_Box:
		return "a gradient"
	case Heap_Ref:
		if x.ops != nil && x.ops.show != nil && x.object != nil {
			return x.ops.show(x.object)
		}
		return "a record or a list"
	}
	return ""
}

// The operators of the language as the interpreter works them out on values of any kind.
Box_Op :: enum u8 {
	Add,
	Subtract,
	Multiply,
	Divide,
}

@(private)
box_arith_number :: proc "contextless" (op: Box_Op, a, b: f64) -> f64 {
	switch op {
	case .Add:      return a + b
	case .Subtract: return a - b
	case .Multiply: return a * b
	case .Divide:   return divide(a, b)
	}
	return 0
}

@(private)
box_vector_of :: proc(b: Box) -> (v: [4]f64, n: int, ok: bool) {
	#partial switch x in b {
	case [2]f64:
		return {x[0], x[1], 0, 0}, 2, true
	case [3]f64:
		return {x[0], x[1], x[2], 0}, 3, true
	case [4]f64:
		return x, 4, true
	}
	return {}, 0, false
}

@(private)
box_vector_made :: proc(v: [4]f64, n: int) -> Box {
	switch n {
	case 2: return [2]f64{v[0], v[1]}
	case 3: return [3]f64{v[0], v[1], v[2]}
	}
	return v
}

@(private)
clamp_colour_box :: proc(c: [4]f32) -> maths.Colour {
	return {clamp(c.r, 0, 255), clamp(c.g, 0, 255), clamp(c.b, 0, 255), clamp(c.a, 0, 255)}
}

// `a + b`, `a - b`, `a * b` and `a / b` where one side or both could be of any kind: text joins with anything
// through plus; vectors and colours work part by part; anything else is a number or 0.
box_arith :: proc(op: Box_Op, a, b: Box) -> Box {
	if op == .Add {
		_, left_text := a.(string)
		_, right_text := b.(string)
		if left_text || right_text {
			return keep(join(show_box(a), show_box(b)))
		}
	}
	if left, left_n, left_vector := box_vector_of(a); left_vector {
		out := left
		if right, right_n, right_vector := box_vector_of(b); right_vector {
			n := min(left_n, right_n)
			for i in 0 ..< n {
				out[i] = box_arith_number(op, left[i], right[i])
			}
			return box_vector_made(out, n)
		}
		number := unbox_number(b)
		for i in 0 ..< left_n {
			out[i] = box_arith_number(op, left[i], number)
		}
		return box_vector_made(out, left_n)
	}
	if left, left_colour := a.(maths.Colour); left_colour {
		out: [4]f32
		if right, right_colour := b.(maths.Colour); right_colour {
			for i in 0 ..< 4 {
				out[i] = f32(box_arith_number(op, f64(left[i]), f64(right[i])))
			}
		} else {
			number := unbox_number(b)
			for i in 0 ..< 4 {
				out[i] = f32(box_arith_number(op, f64(left[i]), number))
			}
		}
		return clamp_colour_box(out)
	}
	if right, right_n, right_vector := box_vector_of(b); right_vector {
		number := unbox_number(a)
		out := right
		for i in 0 ..< right_n {
			out[i] = box_arith_number(op, number, right[i])
		}
		return box_vector_made(out, right_n)
	}
	if right, right_colour := b.(maths.Colour); right_colour {
		number := unbox_number(a)
		out: [4]f32
		for i in 0 ..< 4 {
			out[i] = f32(box_arith_number(op, number, f64(right[i])))
		}
		return clamp_colour_box(out)
	}
	return box_arith_number(op, unbox_number(a), unbox_number(b))
}

// `-a`.
box_negate :: proc(a: Box) -> Box {
	if v, n, ok := box_vector_of(a); ok {
		out := v
		for i in 0 ..< n {
			out[i] = -out[i]
		}
		return box_vector_made(out, n)
	}
	if c, ok := a.(maths.Colour); ok {
		return clamp_colour_box({-c.r, -c.g, -c.b, -c.a})
	}
	return -unbox_number(a)
}

// `not a`.
box_not :: proc(a: Box) -> Box {
	return !unbox_bool(a)
}

// `a.x`, `a.y`, `a.r`... of a vector or a colour of any size; nothing else has parts.
box_part :: proc(a: Box, part: string) -> Box {
	if v, n, ok := box_vector_of(a); ok && len(part) == 1 {
		index := -1
		switch part {
		case "x": index = 0
		case "y": index = 1
		case "z": index = 2
		case "w": index = 3
		}
		if index >= 0 && index < n {
			return v[index]
		}
		return 0.0
	}
	if c, ok := a.(maths.Colour); ok && len(part) == 1 {
		switch part {
		case "r": return f64(c.r)
		case "g": return f64(c.g)
		case "b": return f64(c.b)
		case "a": return byte_to_alpha(f64(c.a))
		}
	}
	return 0.0
}

// Whether two boxes could be the same number: used by tests of the operators.
box_is_number :: proc(b: Box) -> bool {
	_, ok := b.(f64)
	return ok
}

// `osc.args`: every value an OSC message carries, in order, numbers, true and false, text, and a blob of bytes as a
// list of numbers.
osc_args :: proc(m: roci.Osc_Message) -> ^List(Box) {
	out := new_list(Box, mark_box)
	for a in m.args {
		switch v in a {
		case f64:
			add(Box(v), out)
		case bool:
			add(Box(v), out)
		case string:
			add(Box(keep(v)), out)
		case osc.Blob:
			bytes := new_list(f64)
			for b in v {
				add(f64(b), bytes)
			}
			add(box_heap(bytes, &number_list_ops), out)
		}
	}
	return out
}

@(private)
number_list_ops := Heap_Ops{
	copy = proc(object: ^Header) -> ^Header {
		list := (^List(f64))(object)
		out := new_list(f64)
		for x in list.items {
			add(x, out)
		}
		return &out.gc__
	},
	show = proc(object: ^Header) -> string {
		return show_list((^List(f64))(object))
	},
}
