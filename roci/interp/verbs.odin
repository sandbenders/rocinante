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
import "core:fmt"
import "core:strings"

eval_call :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call) -> Value {
	if call.instance != nil {
		return call_taught(it, e, call)
	}
	if call.verb == nil {
		return nil // taught in another file: its body is not here
	}
	if is_language_code(verb_code(call.verb)) {
		return call_language(it, e, call)
	}
	return call_builtin(it, e, call)
}

// The values of a call's arguments: in `buffer` when it has room (the caller's stack),
// otherwise in the frame's memory. A block argument has no
// value: the verb runs it itself.
@(private)
eval_args :: proc(it: ^Interp, args: []^lang.IR, buffer: []Value = nil) -> []Value {
	out := buffer[:len(args)] if len(args) <= len(buffer) else make([]Value, len(args), context.temp_allocator)
	for a, i in args {
		out[i] = eval_number(it, a) if a.fast == .Sure_Number else eval(it, a)
	}
	return out
}

// How many arguments a core verb's values are kept on the stack for: every core
// verb has fewer, so a call never asks the frame's memory for them.
ARGS_ON_STACK :: 8

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
		if said_already(it, .Recursion_Too_Deep, e.span) {
			return zero_value(it, inst.result, 0) if inst.gives else nil
		}
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
	case roci.Image:
		return picture_fill(it, x, options), true
	}
	return nil, false
}

// A picture as a fill, and the connecting words that say how it sits in a shape.
@(private)
picture_fill :: proc(it: ^Interp, picture: roci.Image, options: []lang.IR_Option) -> roci.Image_Fill {
	fill := roci.Image_Fill{image = picture}
	for o in options {
		if len(o.args) == 0 {
			continue
		}
		switch o.word {
		case "as":
			switch as_text(eval(it, o.args[0])) {
			case "cover":   fill.fit = .Cover
			case "fit":     fill.fit = .Fit
			case "stretch": fill.fit = .Stretch
			case "tile":    fill.fit = .Tile
			case "center":  fill.fit = .Center
			}
		case "size":
			fill.tile = f32(as_number(eval(it, o.args[0])))
		case "at":
			if len(o.args) >= 2 {
				fill.at = {f32(as_number(eval(it, o.args[0]))), f32(as_number(eval(it, o.args[1])))}
			} else {
				pair := as_pair(eval(it, o.args[0]))
				fill.at = {f32(pair.x), f32(pair.y)}
			}
		}
	}
	return fill
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

// The look of a call with no style words; never written.
@(private)
NO_LOOK: roci.Look

// The style of one element: the words that follow its arguments.
@(private)
make_look :: proc(it: ^Interp, options: []lang.IR_Option) -> (look: roci.Look, origin: roci.Origin) {
	for o in options {
		if len(o.args) == 0 {
			continue
		}
		switch o.word {
		case "fill":
			if paint, ok := to_paint(it, eval(it, o.args[0]), o.extra); ok {
				look.fill = paint
			}
		case "stroke":
			if paint, ok := to_paint(it, eval(it, o.args[0]), o.extra); ok {
				look.stroke = paint
			}
		case "thickness":
			look.thickness = as_number(eval(it, o.args[0]))
		case "alpha":
			look.alpha = alpha_to_byte(as_number(eval(it, o.args[0])))
		case "size":
			look.size = as_number(eval(it, o.args[0]))
		case "font":
			look.font = as_text(eval(it, o.args[0]))
		case "align":
			switch as_text(eval(it, o.args[0])) {
			case "left":   look.align = .Left
			case "center": look.align = .Center
			case "right":  look.align = .Right
			}
		case "leading":
			look.leading = as_number(eval(it, o.args[0]))
		case "tint":
			look.tint = as_colour(eval(it, o.args[0]))
		case "blend":
			if mode, ok := roci.blend_named(as_text(eval(it, o.args[0]))); ok {
				look.blend = mode
			}
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
			look.alpha = alpha_to_byte(as_number(r.fields[i]))
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
	if mode, ok := look.blend.?; ok {
		roci.blend(mode)
	}
}

// ---- the verbs ----

@(private)
call_builtin :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call) -> Value {
	verb := call.verb
	code := verb_code(verb)
	// `draw into` runs its block itself, with every verb drawing onto the canvas.
	if code == .Draw_Into {
		return draw_into(it, e, call)
	}
	// `push` runs its block itself; no other core verb takes one.
	if code == .Push {
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
	buffer: [ARGS_ON_STACK]Value = ---
	a := eval_args(it, call.args, buffer[:])
	// Most calls have no style words: they share one empty look instead of building
	// one (a look is 776 bytes, since a paint can hold a whole gradient).
	own_look: roci.Look = ---
	look := &NO_LOOK
	origin := roci.Origin{}
	if len(call.options) > 0 {
		own_look, origin = make_look(it, call.options)
		look = &own_look
	}
	n :: proc(a: []Value, i: int) -> f64 {
		return as_number(a[i]) if i < len(a) else 0
	}
	p :: proc(a: []Value, i: int) -> [2]f64 {
		return as_pair(a[i]) if i < len(a) else {}
	}
	p3 :: proc(a: []Value, i: int) -> [3]f64 {
		if i < len(a) {
			v := as_vec(a[i])
			return {v.v[0], v.v[1], v.v[2]}
		}
		return {}
	}
	#partial switch code {
	case .Window:
		at: Maybe([2]int)
		if x, found := option_value(it, call.options, "at", 0); found {
			y, _ := option_value(it, call.options, "at", 1)
			if _, is_vec := x.(Vec); is_vec {
				at = [2]int{int(as_pair(x).x), int(as_pair(x).y)}
			} else {
				at = [2]int{int(as_number(x)), int(as_number(y))}
			}
		}
		flags := roci.Window_Flags{}
		if on, found := option_value(it, call.options, "visible"); found {
			flags.hidden = !as_bool(on)
		}
		w := roci.window(int(n(a, 0)), int(n(a, 1)), at, flags)
		apply_window_options(it, w, call.options)
		return w
	case .Title:
		roci.title_text(as_text(a[0]))
	case .Fullscreen:
		roci.fullscreen()
	case .Quit:
		roci.quit()
	case .Background:
		if paint, ok := to_paint(it, a[0], call.options); ok {
			roci.background(paint)
		}
	case .Clear:
		roci.clear_window()

	case .Box:
		switch call.shape {
		case 0: roci.box_xyz_side(n(a, 0), n(a, 1), n(a, 2), n(a, 3), look^)
		case 1: roci.box_xyz(n(a, 0), n(a, 1), n(a, 2), n(a, 3), n(a, 4), n(a, 5), look^)
		case 2: roci.box_v_side(p3(a, 0), n(a, 1), look^)
		case:  roci.box_v_size(p3(a, 0), p3(a, 1), look^)
		}
	case .Sphere:
		if call.shape == 0 {
			roci.sphere_xyzr(n(a, 0), n(a, 1), n(a, 2), n(a, 3), look^)
		} else {
			roci.sphere_vr(p3(a, 0), n(a, 1), look^)
		}
	case .Plane:
		if call.shape == 0 {
			roci.plane_xyz(n(a, 0), n(a, 1), n(a, 2), n(a, 3), n(a, 4), look^)
		} else {
			roci.plane_v(p3(a, 0), p(a, 1), look^)
		}
	case .Cone:
		if call.shape == 0 {
			roci.cone_xyz(n(a, 0), n(a, 1), n(a, 2), n(a, 3), n(a, 4), look^)
		} else {
			roci.cone_v(p3(a, 0), n(a, 1), n(a, 2), look^)
		}
	case .Cylinder:
		if call.shape == 0 {
			roci.cylinder_xyz(n(a, 0), n(a, 1), n(a, 2), n(a, 3), n(a, 4), look^)
		} else {
			roci.cylinder_v(p3(a, 0), n(a, 1), n(a, 2), look^)
		}
	case .Capsule:
		if call.shape == 0 {
			roci.capsule_xyz(n(a, 0), n(a, 1), n(a, 2), n(a, 3), n(a, 4), look^)
		} else {
			roci.capsule_v(p3(a, 0), n(a, 1), n(a, 2), look^)
		}
	case .Torus:
		if call.shape == 0 {
			roci.torus_xyz(n(a, 0), n(a, 1), n(a, 2), n(a, 3), n(a, 4), look^)
		} else {
			roci.torus_v(p3(a, 0), n(a, 1), n(a, 2), look^)
		}
	case .Icosphere:
		if call.shape == 0 {
			roci.icosphere_xyzr(n(a, 0), n(a, 1), n(a, 2), n(a, 3), look^)
		} else {
			roci.icosphere_vr(p3(a, 0), n(a, 1), look^)
		}
	case .Grid:
		roci.grid_size_lines(n(a, 0), int(n(a, 1)), look^)
	case .Axes:
		roci.axes_size(n(a, 0))
	case .Camera:
		fov := 0.0
		if v, found := option_value(it, call.options, "fov"); found {
			fov = as_number(v)
		}
		if call.shape == 0 {
			roci.camera_xyz(n(a, 0), n(a, 1), n(a, 2), fov)
		} else {
			roci.camera_v(p3(a, 0), fov)
		}
	case .Look_At:
		if call.shape == 0 {
			roci.look_at_xyz(n(a, 0), n(a, 1), n(a, 2))
		} else {
			roci.look_at_v(p3(a, 0))
		}
	case .Light:
		kind := roci.Light_Kind.Ambient
		switch as_text(a[0]) {
		case "sun":   kind = .Sun
		case "point": kind = .Point
		case "spot":  kind = .Spot
		}
		at: Maybe([3]f64)
		if place, found := option_point(it, call.options, "at"); found {
			at = place
		} else if source, from_found := option_point(it, call.options, "from"); from_found {
			at = source
		}
		aim: Maybe([3]f64)
		if target, found := option_point(it, call.options, "to"); found {
			aim = target
		}
		colour: Maybe(maths.Colour)
		if given, found := option_value(it, call.options, "fill"); found {
			colour = as_colour(given)
		}
		falloff, angle: Maybe(f64)
		if given, found := option_value(it, call.options, "falloff"); found {
			falloff = as_number(given)
		}
		if given, found := option_value(it, call.options, "angle"); found {
			angle = as_number(given)
		}
		if !roci.light(kind, at, aim, colour, falloff, angle) {
			fail(it, .Too_Many_Lights, e.span, fmt.tprint(gfx.MAX_LIGHTS), "", "", "light sun from 0 -1 1")
		}
	case .Model:
		if id := load_model(it, as_text(a[0]), e.span); id != 0 {
			if call.shape == 0 {
				roci.model_xyz(id, n(a, 1), n(a, 2), n(a, 3), n(a, 4))
			} else {
				roci.model_v(id, p3(a, 1), n(a, 2))
			}
		}
	case .Shadows:
		roci.shadows()
	case .No_Lights:
		roci.no_lights()
	case .Material:
		metallic, roughness, emissive: Maybe(f64)
		if given, found := option_value(it, call.options, "metallic"); found {
			metallic = as_number(given)
		}
		if given, found := option_value(it, call.options, "roughness"); found {
			roughness = as_number(given)
		}
		if given, found := option_value(it, call.options, "emissive"); found {
			emissive = as_number(given)
		}
		roci.material(metallic, roughness, emissive)
	case .Ortho:
		roci.ortho()
	case .Perspective:
		fov := 0.0
		if v, found := option_value(it, call.options, "fov"); found {
			fov = as_number(v)
		}
		roci.perspective(fov)
	case .Screen_Point:
		point := p3(a, 0)
		if call.shape == 0 {
			point = {n(a, 0), n(a, 1), n(a, 2)}
		}
		at, _ := roci.screen_point(point.x, point.y, point.z)
		return vec2(at)
	case .World_Point:
		spot := p(a, 0)
		if call.shape == 0 {
			spot = {n(a, 0), n(a, 1)}
		}
		at, _ := roci.world_point(spot.x, spot.y)
		return Vec{n = 3, v = {at.x, at.y, at.z, 0}}
	case .Arrow:
		if call.shape == 0 {
			roci.arrow_xyz(n(a, 0), n(a, 1), n(a, 2), n(a, 3), n(a, 4), n(a, 5), look^)
		} else {
			roci.arrow_v(p3(a, 0), p3(a, 1), look^)
		}
	case .Circle:
		if call.shape == 0 {
			roci.circle_xyr(n(a, 0), n(a, 1), n(a, 2), look^, origin)
		} else {
			roci.circle_vr(p(a, 0), n(a, 1), look^, origin)
		}
	case .Ellipse:
		if call.shape == 0 {
			roci.ellipse_xywh(n(a, 0), n(a, 1), n(a, 2), n(a, 3), look^, origin)
		} else {
			roci.ellipse_vs(p(a, 0), p(a, 1), look^, origin)
		}
	case .Rect:
		if call.shape == 0 {
			roci.rect_xywh(n(a, 0), n(a, 1), n(a, 2), n(a, 3), look^, origin)
		} else {
			roci.rect_vs(p(a, 0), p(a, 1), look^, origin)
		}
	case .Square:
		if call.shape == 0 {
			roci.square_xys(n(a, 0), n(a, 1), n(a, 2), look^, origin)
		} else {
			roci.square_vs(p(a, 0), n(a, 1), look^, origin)
		}
	case .Line:
		if call.shape == 0 {
			roci.line_xyxy(n(a, 0), n(a, 1), n(a, 2), n(a, 3), look^)
		} else {
			roci.line_vv(p(a, 0), p(a, 1), look^)
		}
	case .Point:
		if call.shape == 0 {
			roci.point_xy(n(a, 0), n(a, 1), look^)
		} else {
			roci.point_v(p(a, 0), look^)
		}
	case .Triangle:
		if call.shape == 0 {
			roci.triangle_xy(n(a, 0), n(a, 1), n(a, 2), n(a, 3), n(a, 4), n(a, 5), look^)
		} else {
			roci.triangle_v(p(a, 0), p(a, 1), p(a, 2), look^)
		}
	case .Quad:
		if call.shape == 0 {
			roci.quad_xy(n(a, 0), n(a, 1), n(a, 2), n(a, 3), n(a, 4), n(a, 5), n(a, 6), n(a, 7), look^)
		} else {
			roci.quad_v(p(a, 0), p(a, 1), p(a, 2), p(a, 3), look^)
		}
	case .Arc:
		roci.arc(n(a, 0), n(a, 1), n(a, 2), n(a, 3), n(a, 4), n(a, 5), look^, origin)

	case .Text:
		if name, named := look.font.?; named && !ensure_font(it, name, e.span) {
			fail(it, .Font_Missing, e.span, name, "", "", "font \"Inter\"")
		}
		wrap := 0.0
		if v, found := option_value(it, call.options, "width"); found {
			wrap = as_number(v)
		}
		if call.shape == 0 {
			roci.text_xy(as_text(a[0]), n(a, 1), n(a, 2), look^, wrap)
		} else {
			roci.text_v(as_text(a[0]), p(a, 1), look^, wrap)
		}
	case .Font:
		size := 0.0
		if v, found := option_value(it, call.options, "size"); found {
			size = as_number(v)
		}
		if !ensure_font(it, as_text(a[0]), e.span) || !roci.font(as_text(a[0]), size) {
			fail(it, .Font_Missing, e.span, as_text(a[0]), "", "", "font \"Inter\"")
		}
	case .Align:
		switch as_text(a[0]) {
		case "left":   roci.align(.Left)
		case "center": roci.align(.Center)
		case "right":  roci.align(.Right)
		}
	case .Leading:
		roci.leading(as_number(a[0]))
	case .Measure:
		return vec2(roci.measure(as_text(a[0])))
	case .Image:
		picture := as_image(a[0])
		width, height: Maybe(f64)
		if call.shape < 2 {
			if v, found := option_value(it, call.options, "width"); found {
				width = as_number(v)
			}
			if v, found := option_value(it, call.options, "height"); found {
				height = as_number(v)
			}
		}
		switch call.shape {
		case 0: roci.image_xy(picture, n(a, 1), n(a, 2), look^, origin, width, height)
		case 1: roci.image_v(picture, p(a, 1), look^, origin, width, height)
		case 2: roci.image_sized_xy(picture, n(a, 1), n(a, 2), n(a, 3), n(a, 4), look^, origin)
		case 3: roci.image_sized_v(picture, p(a, 1), p(a, 2), look^, origin)
		}
	case .Tint:
		roci.tint(as_colour(a[0]))
	case .Canvas:
		picture, made := roci.canvas(n(a, 0), n(a, 1))
		if !made {
			fail(it, .Canvas_Size, e.span, "", "", "", "c = canvas 300 200")
			return nil
		}
		return picture
	case .Fill:
		if paint, ok := to_paint(it, a[0], call.options); ok {
			roci.fill_paint(paint)
		}
	case .No_Fill:
		roci.no_fill()
	case .Stroke:
		if paint, ok := to_paint(it, a[0], call.options); ok {
			roci.stroke_paint(paint)
		}
	case .No_Stroke:
		roci.no_stroke()
	case .Thickness:
		roci.thickness(n(a, 0))
	case .Alpha:
		roci.alpha(alpha_to_byte(n(a, 0)))
	case .Caps:
		switch as_text(a[0]) {
		case "butt":   roci.caps(.Butt)
		case "round":  roci.caps(.Round)
		case "square": roci.caps(.Square)
		}
	case .Joins:
		switch as_text(a[0]) {
		case "miter": roci.joins(.Miter)
		case "round": roci.joins(.Round)
		case "bevel": roci.joins(.Bevel)
		}
	case .Blend:
		if mode, ok := roci.blend_named(as_text(a[0])); ok {
			roci.blend(mode)
		}
	case .Clip:
		if call.shape == 0 {
			roci.clip(n(a, 0), n(a, 1), n(a, 2), n(a, 3))
		} else {
			roci.clip(p(a, 0), p(a, 1))
		}
	case .No_Clip:
		roci.no_clip()

	case .Rgb, .Hsb, .Oklch:
		alpha := 255.0
		if v, found := option_value(it, call.options, "alpha"); found {
			alpha = alpha_to_byte(as_number(v))
		}
		#partial switch code {
		case .Rgb:    return roci.rgb(n(a, 0), n(a, 1), n(a, 2), alpha)
		case .Hsb:    return roci.hsb(n(a, 0), n(a, 1), n(a, 2), alpha)
		case:         return roci.oklch(n(a, 0), n(a, 1), n(a, 2), alpha)
		}
	case .Gradient:
		return gradient_from(it, a[0], call.options)
	case .Mix:
		if call.shape == 0 {
			return roci.mix_colours(as_colour(a[0]), as_colour(a[1]), n(a, 2))
		}
		return roci.mix_numbers(n(a, 0), n(a, 1), n(a, 2))

	case .Move:
		switch call.shape {
		case 0: roci.move_xy(n(a, 0), n(a, 1))
		case 1:
			if v := as_vec(a[0]); v.n >= 3 {
				roci.move_xyz(v.v[0], v.v[1], v.v[2])
			} else {
				roci.move_v(p(a, 0))
			}
		case: roci.move_xyz(n(a, 0), n(a, 1), n(a, 2))
		}
	case .Turn:
		if word, found := option_value(it, call.options, "around"); found {
			axis := roci.Axis.Z
			switch as_text(word) {
			case "x": axis = .X
			case "y": axis = .Y
			}
			roci.turn_about(n(a, 0), axis)
		} else {
			roci.turn(n(a, 0))
		}
	case .Grow:
		switch call.shape {
		case 0: roci.grow_factor(n(a, 0))
		case 1: roci.grow_xy(n(a, 0), n(a, 1))
		case: roci.grow_xyz(n(a, 0), n(a, 1), n(a, 2))
		}
	case .Shear:
		roci.shear(n(a, 0), n(a, 1))

	case .Forward:
		roci.forward(n(a, 0))
	case .Back:
		roci.back(n(a, 0))
	case .Left:
		roci.left(n(a, 0))
	case .Right:
		roci.right(n(a, 0))
	case .Pen_Up:
		roci.pen_up()
	case .Pen_Down:
		roci.pen_down()
	case .Home:
		roci.home()
	case .Show_Turtle:
		roci.show_turtle()

	case .Map:
		return roci.map_range(n(a, 0), n(a, 1), n(a, 2), n(a, 3), n(a, 4))
	case .Clamp:
		return roci.clamp_between(n(a, 0), n(a, 1), n(a, 2))
	case .Dist:
		if call.shape == 0 {
			return roci.dist_xy(n(a, 0), n(a, 1), n(a, 2), n(a, 3))
		}
		return roci.dist_v(p(a, 0), p(a, 1))
	case .Atan:
		if call.shape == 0 {
			return roci.atan_xy(n(a, 0), n(a, 1))
		}
		return roci.atan_v(p(a, 0))
	case .Normalize:
		v := as_vec(a[0]) if len(a) > 0 else Vec{n = 2}
		if v.n == 2 {
			return vec2(roci.normalize({v.v[0], v.v[1]}))
		}
		return Vec{n = v.n, v = maths.vec_normalize(v.v, v.n)}
	case .Limit:
		v := as_vec(a[0]) if len(a) > 0 else Vec{n = 2}
		if v.n == 2 {
			return vec2(roci.limit_length({v.v[0], v.v[1]}, n(a, 1)))
		}
		return Vec{n = v.n, v = maths.vec_limit(v.v, v.n, n(a, 1))}
	case .Abs:
		return roci.absolute(n(a, 0))
	case .Floor:
		return roci.floor(n(a, 0))
	case .Round:
		return roci.round(n(a, 0))
	case .Ceil:
		return roci.ceil(n(a, 0))
	case .Sqrt:
		return roci.square_root(n(a, 0))
	case .Sin:
		return roci.sin_deg(n(a, 0))
	case .Cos:
		return roci.cos_deg(n(a, 0))
	case .Ease:
		curve := roci.Ease.Smooth
		if word, found := option_value(it, call.options, "as"); found {
			curve, _ = maths.ease_by_name(as_text(word))
		}
		return roci.ease(n(a, 0), curve)

	case .Random:
		if call.shape == 0 {
			return roci.random(n(a, 0))
		}
		low, _ := option_value(it, call.options, "from")
		high, _ := option_value(it, call.options, "to")
		return roci.random_between(as_number(low), as_number(high))
	case .Pick:
		if l := as_list(a[0]); l != nil {
			return roci.pick(l.items[:])
		}
		return nil
	case .Gaussian:
		return roci.gaussian(n(a, 0), n(a, 1))
	case .Seed:
		roci.seed(n(a, 0))
	case .Noise:
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
	case .Fbm:
		return roci.fbm(n(a, 0), n(a, 1), n(a, 2))
	}
	return nil
}

// Whether the interpreter runs the verb of this name, so a test can tell when the
// registry gains one it does not.
handled :: proc(name: string) -> bool {
	return code_for_name(name) != .None
}

// `draw into c [ ... ]`: runs the block with every drawing verb recording onto the canvas.
@(private)
draw_into :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call) -> Value {
	picture := as_image(eval(it, call.args[0]))
	if !roci.begin_into(picture) {
		why := "It is not a canvas: a picture loaded from a file cannot be drawn into, and canvases are made with `canvas`."
		if roci.is_drawing_into() {
			why = "A canvas is being drawn into already, and a `draw into` cannot sit inside another."
		}
		fail(it, .Not_A_Canvas, e.span, "", why, "", "c = canvas 300 200")
		return nil
	}
	if len(call.args) > 1 {
		if block, ok := call.args[1].kind.(lang.IR_Block_Value); ok {
			if flow := exec_block(it, block.block); flow != .Normal {
				it.pending = flow
			}
		}
	}
	roci.end_into()
	return nil
}

// A point given after a word as three numbers (`at 0 -100 0`) or as one vector (`at p`).
@(private)
option_point :: proc(it: ^Interp, options: []lang.IR_Option, word: string) -> (point: [3]f64, found: bool) {
	first, ok := option_value(it, options, word, 0)
	if !ok {
		return {}, false
	}
	if v, is_vec := first.(Vec); is_vec {
		return {v.v[0], v.v[1], v.v[2]}, true
	}
	second, _ := option_value(it, options, word, 1)
	third, _ := option_value(it, options, word, 2)
	return {as_number(first), as_number(second), as_number(third)}, true
}
