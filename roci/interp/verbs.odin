// SPDX-License-Identifier: 0BSD
//
// Calls of the verbs the core offers: each one unpacks its values and calls the
// procedure of package roci that an Odin sketch would call, so both ways draw the
// same commands. The registry says which shape of a verb the checker chose
// (`call.shape`) and the values arrive in the order of that shape's parameters.
package interp

import "../"
import "../lang"
import "../maths"
import "../gfx"
import "core:strings"

eval_call :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call) -> Value {
	if call.instance != nil {
		return call_taught(it, e, call)
	}
	if call.verb == nil {
		return nil // taught in another file: its body is not here
	}
	if is_language_verb(call.verb.name) {
		return call_language(it, e, call)
	}
	return call_builtin(it, e, call)
}

// The values of a call's arguments, in the frame's memory. A block argument has no
// value: the verb runs it itself.
@(private)
eval_args :: proc(it: ^Interp, args: []^lang.IR) -> []Value {
	out := make([]Value, len(args), context.temp_allocator)
	for a, i in args {
		out[i] = eval(it, a)
	}
	return out
}

// The first value of a connecting word, and whether it was written.
@(private)
option_value :: proc(it: ^Interp, options: []lang.IR_Option, word: string, index := 0) -> (Value, bool) {
	for o in options {
		if o.word == word && index < len(o.args) {
			return eval(it, o.args[index]), true
		}
	}
	return nil, false
}

@(private)
option_ir :: proc(options: []lang.IR_Option, word: string, index := 0) -> ^lang.IR {
	for o in options {
		if o.word == word && index < len(o.args) {
			return o.args[index]
		}
	}
	return nil
}

// ---- taught verbs ----

@(private)
call_taught :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call) -> Value {
	inst := call.instance
	args := eval_args(it, call.args)
	given := make([]Value, len(call.options), context.temp_allocator)
	for o, i in call.options {
		if len(o.args) > 0 {
			given[i] = eval(it, o.args[0])
		}
	}
	if it.depth >= MAX_DEPTH {
		line := lang.line_text(it.src, lang.position_of(it.src, e.span.start).line)
		fail(it, .Recursion_Too_Deep, e.span, inst.name, "100", "", fix_text(strings.concatenate({"if ", inst.params[0].name if len(inst.params) > 0 else "count", " < 20 [ "}, context.temp_allocator), line, " ]"))
		return zero_value(it, inst.result, 0) if inst.gives else nil
	}
	it.depth += 1
	frame := Frame{}
	frame.slots = make([dynamic]Slot, 0, len(inst.params) + len(inst.defaults) + 4, context.temp_allocator)
	for p, i in inst.params {
		append(&frame.slots, Slot{p, args[i] if i < len(args) else nil})
	}
	saved := it.frame
	it.frame = &frame
	for d in inst.defaults {
		value: Value
		found := false
		for o, i in call.options {
			if o.word == d.word && len(o.args) > 0 {
				value, found = given[i], true
			}
		}
		if !found {
			value = eval(it, d.value)
		}
		append(&frame.slots, Slot{d.symbol, value})
	}
	flow := exec_block(it, inst.body)
	it.frame = saved
	it.depth -= 1
	if flow == .Abort {
		it.pending = .Abort
	}
	if inst.gives {
		return frame.result
	}
	return nil
}

@(private)
fix_text :: proc(before, line, after: string) -> string {
	return strings.concatenate({before, strings.trim_space(line), after}, context.temp_allocator)
}

// ---- looks and paints ----

// A paint from a value: a colour, a grey, a gradient, or a list of colours.
@(private)
to_paint :: proc(it: ^Interp, v: Value, options: []lang.IR_Option = nil) -> (roci.Paint, bool) {
	#partial switch x in v {
	case maths.Colour:
		return x, true
	case f64:
		return roci.grey(x), true
	case ^roci.Gradient:
		if x != nil {
			return x^, true
		}
	case ^List:
		if g := gradient_from(it, v, options); g != nil {
			return g^, true
		}
	}
	return nil, false
}

// A gradient from a list of colours and the connecting words that shape it.
@(private)
gradient_from :: proc(it: ^Interp, colours: Value, options: []lang.IR_Option) -> ^roci.Gradient {
	list := as_list(colours)
	if list == nil {
		return nil
	}
	items := make([]maths.Colour, len(list.items), context.temp_allocator)
	for item, i in list.items {
		items[i] = as_colour(item)
	}
	kind := gfx.Gradient_Kind.Linear
	space := maths.Mix_Space.Oklab
	angle := 0.0
	centre := [2]f32{50, 50}
	stops: []f32
	for o in options {
		if len(o.args) == 0 {
			continue
		}
		switch o.word {
		case "angle":
			angle = as_number(eval(it, o.args[0]))
		case "as":
			switch as_text(eval(it, o.args[0])) {
			case "radial": kind = .Radial
			case "conic":  kind = .Conic
			case "linear": kind = .Linear
			}
		case "in":
			switch as_text(eval(it, o.args[0])) {
			case "rgb":   space = .Rgb
			case "oklch": space = .Oklch
			case "oklab": space = .Oklab
			}
		case "at":
			if len(o.args) >= 2 {
				centre = {f32(as_number(eval(it, o.args[0]))), f32(as_number(eval(it, o.args[1])))}
			} else {
				pair := as_pair(eval(it, o.args[0]))
				centre = {f32(pair.x), f32(pair.y)}
			}
		case "stops":
			if l := as_list(eval(it, o.args[0])); l != nil {
				stops = make([]f32, len(l.items), context.temp_allocator)
				for s, i in l.items {
					stops[i] = f32(as_number(s))
				}
			}
		}
	}
	g := new(roci.Gradient, it.alloc)
	g^ = roci.gradient(items, kind, angle, space, stops, centre)
	return g
}

// The style of one element: the words that follow its arguments.
@(private)
make_look :: proc(it: ^Interp, options: []lang.IR_Option) -> (look: roci.Look, origin: roci.Origin) {
	for o in options {
		if len(o.args) == 0 {
			continue
		}
		switch o.word {
		case "fill":
			if paint, ok := to_paint(it, eval(it, o.args[0])); ok {
				look.fill = paint
			}
		case "stroke":
			if paint, ok := to_paint(it, eval(it, o.args[0])); ok {
				look.stroke = paint
			}
		case "thickness":
			look.thickness = as_number(eval(it, o.args[0]))
		case "alpha":
			look.alpha = as_number(eval(it, o.args[0]))
		case "style":
			merge_style_record(it, &look, eval(it, o.args[0]))
		case "as":
			switch as_text(eval(it, o.args[0])) {
			case "center": origin = .Center
			case "corner": origin = .Corner
			}
		}
	}
	return
}

// A named style is a record whose fields are style words.
@(private)
merge_style_record :: proc(it: ^Interp, look: ^roci.Look, v: Value) {
	r := as_record(v)
	if r == nil {
		return
	}
	for f, i in it.types.shapes[r.shape].fields {
		switch f.name {
		case "fill":
			if paint, ok := to_paint(it, r.fields[i]); ok {
				look.fill = paint
			}
		case "stroke":
			if paint, ok := to_paint(it, r.fields[i]); ok {
				look.stroke = paint
			}
		case "thickness":
			look.thickness = as_number(r.fields[i])
		case "alpha":
			look.alpha = as_number(r.fields[i])
		}
	}
}

@(private)
apply_style_record :: proc(it: ^Interp, v: Value) {
	look := roci.Look{}
	merge_style_record(it, &look, v)
	apply_look(look)
}

// Sets the current style from a look, until the enclosing scope ends.
@(private)
apply_look :: proc(look: roci.Look) {
	if look.fill != nil {
		roci.fill_paint(look.fill)
	}
	if look.stroke != nil {
		roci.stroke_paint(look.stroke)
	}
	if t, ok := look.thickness.?; ok {
		roci.thickness(t)
	}
	if a, ok := look.alpha.?; ok {
		roci.alpha(a)
	}
}

// ---- the verbs ----

@(private)
call_builtin :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call) -> Value {
	verb := call.verb
	// `push` runs its block itself; no other core verb takes one.
	if verb.name == "push" {
		roci.push()
		if len(call.args) > 0 {
			if block, ok := call.args[0].kind.(lang.IR_Block_Value); ok {
				if flow := exec_block(it, block.block); flow != .Normal {
					it.pending = flow
				}
			}
		}
		roci.pop()
		return nil
	}
	a := eval_args(it, call.args)
	look, origin := make_look(it, call.options)
	n :: proc(a: []Value, i: int) -> f64 {
		return as_number(a[i]) if i < len(a) else 0
	}
	p :: proc(a: []Value, i: int) -> [2]f64 {
		return as_pair(a[i]) if i < len(a) else {}
	}
	switch verb.name {
	case "window":
		at: Maybe([2]int)
		if x, found := option_value(it, call.options, "at", 0); found {
			y, _ := option_value(it, call.options, "at", 1)
			if _, is_vec := x.(Vec); is_vec {
				at = [2]int{int(as_pair(x).x), int(as_pair(x).y)}
			} else {
				at = [2]int{int(as_number(x)), int(as_number(y))}
			}
		}
		w := roci.window(int(n(a, 0)), int(n(a, 1)), at)
		if text, found := option_value(it, call.options, "title"); found {
			roci.title_window(w, as_text(text))
		}
		return w
	case "title":
		if call.shape == 0 {
			roci.title_text(as_text(a[0]))
		} else if w, ok := a[0].(roci.Window); ok {
			roci.title_window(w, as_text(a[1]))
		}
	case "fullscreen":
		roci.fullscreen()
	case "quit":
		roci.quit()
	case "background":
		if paint, ok := to_paint(it, a[0], call.options); ok {
			roci.background(paint)
		}
	case "clear":
		roci.clear_window()

	case "circle":
		if call.shape == 0 {
			roci.circle_xyr(n(a, 0), n(a, 1), n(a, 2), look, origin)
		} else {
			roci.circle_vr(p(a, 0), n(a, 1), look, origin)
		}
	case "ellipse":
		if call.shape == 0 {
			roci.ellipse_xywh(n(a, 0), n(a, 1), n(a, 2), n(a, 3), look, origin)
		} else {
			roci.ellipse_vs(p(a, 0), p(a, 1), look, origin)
		}
	case "rect":
		if call.shape == 0 {
			roci.rect_xywh(n(a, 0), n(a, 1), n(a, 2), n(a, 3), look, origin)
		} else {
			roci.rect_vs(p(a, 0), p(a, 1), look, origin)
		}
	case "square":
		if call.shape == 0 {
			roci.square_xys(n(a, 0), n(a, 1), n(a, 2), look, origin)
		} else {
			roci.square_vs(p(a, 0), n(a, 1), look, origin)
		}
	case "line":
		if call.shape == 0 {
			roci.line_xyxy(n(a, 0), n(a, 1), n(a, 2), n(a, 3), look)
		} else {
			roci.line_vv(p(a, 0), p(a, 1), look)
		}
	case "point":
		if call.shape == 0 {
			roci.point_xy(n(a, 0), n(a, 1), look)
		} else {
			roci.point_v(p(a, 0), look)
		}
	case "triangle":
		if call.shape == 0 {
			roci.triangle_xy(n(a, 0), n(a, 1), n(a, 2), n(a, 3), n(a, 4), n(a, 5), look)
		} else {
			roci.triangle_v(p(a, 0), p(a, 1), p(a, 2), look)
		}
	case "quad":
		if call.shape == 0 {
			roci.quad_xy(n(a, 0), n(a, 1), n(a, 2), n(a, 3), n(a, 4), n(a, 5), n(a, 6), n(a, 7), look)
		} else {
			roci.quad_v(p(a, 0), p(a, 1), p(a, 2), p(a, 3), look)
		}
	case "arc":
		roci.arc(n(a, 0), n(a, 1), n(a, 2), n(a, 3), n(a, 4), n(a, 5), look, origin)

	case "fill":
		if paint, ok := to_paint(it, a[0], call.options); ok {
			roci.fill_paint(paint)
		}
	case "no fill":
		roci.no_fill()
	case "stroke":
		if paint, ok := to_paint(it, a[0], call.options); ok {
			roci.stroke_paint(paint)
		}
	case "no stroke":
		roci.no_stroke()
	case "thickness":
		roci.thickness(n(a, 0))
	case "alpha":
		roci.alpha(n(a, 0))
	case "caps":
		switch as_text(a[0]) {
		case "butt":   roci.caps(.Butt)
		case "round":  roci.caps(.Round)
		case "square": roci.caps(.Square)
		}
	case "joins":
		switch as_text(a[0]) {
		case "miter": roci.joins(.Miter)
		case "round": roci.joins(.Round)
		case "bevel": roci.joins(.Bevel)
		}

	case "rgb", "hsb", "oklch":
		alpha := 255.0
		if v, found := option_value(it, call.options, "alpha"); found {
			alpha = as_number(v)
		}
		switch verb.name {
		case "rgb":   return roci.rgb(n(a, 0), n(a, 1), n(a, 2), alpha)
		case "hsb":   return roci.hsb(n(a, 0), n(a, 1), n(a, 2), alpha)
		case:         return roci.oklch(n(a, 0), n(a, 1), n(a, 2), alpha)
		}
	case "gradient":
		return gradient_from(it, a[0], call.options)
	case "mix":
		if call.shape == 0 {
			return roci.mix_colours(as_colour(a[0]), as_colour(a[1]), n(a, 2))
		}
		return roci.mix_numbers(n(a, 0), n(a, 1), n(a, 2))

	case "move":
		if call.shape == 0 {
			roci.move_xy(n(a, 0), n(a, 1))
		} else {
			roci.move_v(p(a, 0))
		}
	case "turn":
		roci.turn(n(a, 0))
	case "grow":
		if call.shape == 0 {
			roci.grow_factor(n(a, 0))
		} else {
			roci.grow_xy(n(a, 0), n(a, 1))
		}
	case "shear":
		roci.shear(n(a, 0), n(a, 1))

	case "map":
		return roci.map_range(n(a, 0), n(a, 1), n(a, 2), n(a, 3), n(a, 4))
	case "clamp":
		return roci.clamp_between(n(a, 0), n(a, 1), n(a, 2))
	case "dist":
		if call.shape == 0 {
			return roci.dist_xy(n(a, 0), n(a, 1), n(a, 2), n(a, 3))
		}
		return roci.dist_v(p(a, 0), p(a, 1))
	case "abs":
		return roci.absolute(n(a, 0))
	case "sqrt":
		return roci.square_root(n(a, 0))
	case "sin":
		return roci.sin_deg(n(a, 0))
	case "cos":
		return roci.cos_deg(n(a, 0))

	case "random":
		if call.shape == 0 {
			return roci.random(n(a, 0))
		}
		low, _ := option_value(it, call.options, "from")
		high, _ := option_value(it, call.options, "to")
		return roci.random_between(as_number(low), as_number(high))
	case "pick":
		if l := as_list(a[0]); l != nil {
			return roci.pick(l.items[:])
		}
		return nil
	case "gaussian":
		return roci.gaussian(n(a, 0), n(a, 1))
	case "seed":
		roci.seed(n(a, 0))
	case "noise":
		simplex := false
		if word, found := option_value(it, call.options, "as"); found {
			simplex = as_text(word) == "simplex"
		}
		switch len(a) {
		case 1: return roci.noise_1(n(a, 0), simplex)
		case 2: return roci.noise_2(n(a, 0), n(a, 1), simplex)
		case 3: return roci.noise_3(n(a, 0), n(a, 1), n(a, 2), simplex)
		case:   return roci.noise_4(n(a, 0), n(a, 1), n(a, 2), n(a, 3), simplex)
		}
	case "fbm":
		return roci.fbm(n(a, 0), n(a, 1), n(a, 2))
	}
	return nil
}

// Every core verb the interpreter runs, so a test can tell when the registry gains
// one it does not.
HANDLED := [?]string{
	"window", "title", "fullscreen", "quit", "background", "clear",
	"circle", "ellipse", "rect", "square", "line", "point", "triangle", "quad", "arc",
	"fill", "no fill", "stroke", "no stroke", "thickness", "alpha", "caps", "joins",
	"rgb", "hsb", "oklch", "gradient", "mix", "move", "turn", "grow", "shear", "push",
	"map", "clamp", "dist", "abs", "sqrt", "sin", "cos",
	"random", "pick", "gaussian", "seed", "noise", "fbm",
}

handled :: proc(name: string) -> bool {
	for h in HANDLED {
		if h == name {
			return true
		}
	}
	return is_language_verb(name)
}
