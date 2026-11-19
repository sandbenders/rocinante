// SPDX-License-Identifier: 0BSD
package codegen

import "../lang"
import "core:fmt"
import "core:strings"

// A statement of the top level of the sketch, which runs once, in order. The blocks that run every frame or
// when something happens are procedures of their own, registered here where the sketch wrote them.
@(private)
emit_top_level :: proc(g: ^Gen, s: ^lang.IR_Stmt) {
	#partial switch k in s.kind {
	case lang.IR_Draw:
		comment(g, s.span)
		emit_draw(g, s, k)
	case lang.IR_Every:
		comment(g, s.span)
		emit_every(g, s, k)
	case lang.IR_On:
		comment(g, s.span)
		emit_on(g, s, k)
	case lang.IR_Scene:
		comment(g, s.span)
		emit_scene(g, s, k)
	case:
		emit_stmt(g, s)
	}
}

@(private)
emit_block :: proc(g: ^Gen, block: lang.IR_Block) {
	g.indent += 1
	g.dynamic_depth += 1
	for s in block.stmts {
		emit_stmt(g, s)
		if ends_the_verb(s) {
			break // what follows a `give` or a `stop` is never reached, and Odin says so
		}
	}
	g.dynamic_depth -= 1
	g.indent -= 1
}

// The whole of a statement, inside a procedure.
@(private)
emit_stmt :: proc(g: ^Gen, s: ^lang.IR_Stmt) {
	switch k in s.kind {
	case lang.IR_Assign:
		comment(g, s.span)
		emit_assign(g, s, k)
	case lang.IR_Expr_Stmt:
		comment(g, s.span)
		emit_expr_stmt(g, k.expr)
	case lang.IR_If:
		comment(g, s.span)
		line(g, "if %s {{", expr(g, k.cond))
		emit_block(g, k.body)
		if k.has_else {
			line(g, "}} else {{")
			emit_block(g, k.else_body)
		}
		line(g, "}}")
	case lang.IR_Repeat:
		comment(g, s.span)
		// the count is taken once, before the first turn: Odin works out the end of a range again each turn,
		// so a count that the body changes (`repeat COUNT - count list [ add ... ]`) would shrink as it ran
		id := g.next_id
		g.next_id += 1
		line(g, "{{")
		g.indent += 1
		line(g, "times_%d := int(%s)", id, expr(g, k.count))
		line(g, "for _ in 0 ..< times_%d {{", id)
		emit_block(g, k.body)
		line(g, "}}")
		g.indent -= 1
		line(g, "}}")
	case lang.IR_While:
		comment(g, s.span)
		g.no_hoist += 1 // the test is worked out again each turn
		test := expr(g, k.cond)
		g.no_hoist -= 1
		line(g, "for %s {{", test)
		emit_block(g, k.body)
		line(g, "}}")
	case lang.IR_For:
		comment(g, s.span)
		emit_for(g, s, k)
	case lang.IR_For_Each:
		comment(g, s.span)
		emit_for_each(g, s, k)
	case lang.IR_With:
		comment(g, s.span)
		emit_with(g, s, k)
	case lang.IR_Every, lang.IR_On, lang.IR_Draw:
		refuse(g, s.span, "`draw`, `every` or `on` inside another block (they go at the top of the sketch)")
	case lang.IR_Scene:
		refuse(g, s.span, "a `scene` inside another block (scenes go at the top of the sketch)")
	case lang.IR_Give:
		comment(g, s.span)
		if g.in_verb == nil || !g.in_verb.gives {
			return
		}
		line(g, "result__ = %s", stored(g, k.value))
		line(g, "return") // `give` hands the value back and ends the verb
	case lang.IR_Stop:
		comment(g, s.span)
		line(g, "return")
	case lang.IR_Check, lang.IR_Expect, lang.IR_Unchecked, lang.IR_Error_Stmt:
		// a check runs only for `roci test`, and a `learn` makes no code where it stands
	}
}

// Whether a statement ends the verb it is in: `give` and `stop`.
@(private)
ends_the_verb :: proc(s: ^lang.IR_Stmt) -> bool {
	#partial switch _ in s.kind {
	case lang.IR_Give, lang.IR_Stop:
		return true
	}
	return false
}

@(private)
emit_assign :: proc(g: ^Gen, s: ^lang.IR_Stmt, k: lang.IR_Assign) {
	name := name_of(g, k.target)
	value := stored(g, k.value)
	if len(k.fields) == 0 {
		line(g, "%s = %s", name, value)
		return
	}
	path := strings.builder_make(context.temp_allocator)
	strings.write_string(&path, name)
	// the fields of a record, or the part of a vector at the end
	holder := k.target.type
	for part, i in k.fields {
		resolved := lang.resolve(g.types, holder)
		item := g.types.items[resolved]
		#partial switch item.kind {
		case .Record:
			strings.write_string(&path, ".")
			strings.write_string(&path, field_name(part))
			if shape_field, found := lang.shape_field(g.types, item.a, part); found {
				holder = shape_field.type
			}
		case .Vector:
			strings.write_string(&path, ".")
			strings.write_string(&path, part)
		case .Colour:
			if len(part) == 1 && i == len(k.fields) - 1 && (part == "r" || part == "g" || part == "b") {
				line(g, "%s.%s = f32(%s)", strings.to_string(path), part, value)
				return
			}
			if part == "a" && i == len(k.fields) - 1 {
				line(g, "%s.a = f32(rt.alpha_to_byte(%s))", strings.to_string(path), value)
				return
			}
			refuse(g, s.span, "changing a part of a color")
			return
		case:
			refuse(g, s.span, fmt.tprintf("changing a part of %s", lang.describe(g.types, holder)))
			return
		}
		_ = i
	}
	line(g, "%s = %s", strings.to_string(path), value)
}

// A call written as a statement: a value it gives back is let go, which Odin wants said.
@(private)
emit_expr_stmt :: proc(g: ^Gen, e: ^lang.IR) {
	call_ir, is_call := e.kind.(lang.IR_Call)
	if !is_call {
		return
	}
	if call_ir.verb != nil && call_ir.instance == nil && call_ir.verb.name == "push" {
		emit_push(g, call_ir)
		return
	}
	if call_ir.verb != nil && call_ir.instance == nil && call_ir.verb.name == "draw into" {
		emit_draw_into(g, e, call_ir)
		return
	}
	if call_ir.verb != nil && call_ir.instance == nil && call_ir.verb.name == "set" {
		emit_set(g, e, call_ir)
		return
	}
	if call_ir.verb != nil && call_ir.instance == nil && call_ir.verb.name == "window" && len(call_ir.options) > 0 {
		emit_window(g, e, call_ir)
		return
	}
	text, gives := call(g, e, call_ir)
	if text == "" {
		return
	}
	if gives {
		line(g, "_ = %s", text)
	} else {
		line(g, "%s", text)
	}
}

// `push [ ... ]`: the style, the transforms and the turtle come back as they were when the block ends.
@(private)
emit_push :: proc(g: ^Gen, c: lang.IR_Call) {
	line(g, "roci.push()")
	if len(c.args) > 0 {
		if block, ok := c.args[0].kind.(lang.IR_Block_Value); ok {
			emit_block(g, block.block)
		}
	}
	line(g, "roci.pop()")
}

// `set w size 400 300 resizable false`, `set rain volume 50`, `set clip at 10`: each word changes what the first value is.
@(private)
emit_set :: proc(g: ^Gen, e: ^lang.IR, c: lang.IR_Call) {
	if len(c.args) == 0 {
		return
	}
	target := expr(g, c.args[0])
	switch c.shape {
	case 0: // a window
		for o in c.options {
			if len(o.args) == 0 {
				continue
			}
			switch o.word {
			case "size":
				if len(o.args) == 2 {
					line(g, "roci.set_window_size(%s, int(%s), int(%s))", target, expr(g, o.args[0]), expr(g, o.args[1]))
				}
			case "title":
				line(g, "roci.title_window(%s, %s)", target, expr(g, o.args[0]))
			case "cursor":
				if word, ok := word_of(o.args[0]); ok {
					line(g, "rt.set_cursor(%s, %q)", target, word)
				}
			case "resizable", "bordered", "topmost", "focusable", "grab", "modal", "fullscreen":
				line(g, "roci.set_%s(%s, %s)", o.word, target, expr(g, o.args[0]))
			case "smallest", "largest":
				holder := point2(g, o)
				line(g, "roci.set_%s(%s, int((%s)[0]), int((%s)[1]))", o.word, target, holder, holder)
			case "ratio":
				line(g, "roci.set_ratio(%s, %s)", target, expr(g, o.args[0]))
			case "alpha":
				line(g, "roci.set_window_alpha(%s, rt.alpha_to_byte(%s))", target, expr(g, o.args[0]))
			case:
				refuse(g, e.span, fmt.tprintf("`set` of a window with `%s`", o.word))
			}
		}
	case 1: // a sound
		line(g, "roci.set_sound(%s, at = %s, volume = %s, pan = %s, speed = %s, looping = %s, note = %s, pitch = %s)", target, maybe(g, c.options, "at"), maybe(g, c.options, "volume"), maybe(g, c.options, "pan"), maybe(g, c.options, "speed"), maybe(g, c.options, "loop"), maybe(g, c.options, "note"), maybe(g, c.options, "pitch"))
		if option(c.options, "bend") != nil || option(c.options, "vibrato") != nil {
			line(g, "roci.set_wheels(%s, %s, %s)", target, maybe(g, c.options, "bend"), maybe(g, c.options, "vibrato"))
		}
		if option(c.options, "attack") != nil || option(c.options, "decay") != nil || option(c.options, "sustain") != nil || option(c.options, "release") != nil {
			line(g, "roci.set_envelope(%s, %s, %s, %s, %s)", target, maybe(g, c.options, "attack"), maybe(g, c.options, "decay"), maybe(g, c.options, "sustain"), maybe(g, c.options, "release"))
		}
	case 2: // a movie
		line(g, "roci.movie_set(%s, at = %s, speed = %s, looping = %s)", target, maybe(g, c.options, "at"), maybe(g, c.options, "speed"), maybe(g, c.options, "loop"))
	}
}

// `draw into canvas [ ... ]`: everything the block draws goes onto the canvas; a picture that is no canvas gets nothing.
@(private)
emit_draw_into :: proc(g: ^Gen, e: ^lang.IR, c: lang.IR_Call) {
	if len(c.args) < 1 {
		return
	}
	line(g, "if rt.begin_into(%s) {{", expr(g, c.args[0]))
	if len(c.args) > 1 {
		if block, ok := c.args[1].kind.(lang.IR_Block_Value); ok {
			emit_block(g, block.block)
		}
	}
	g.indent += 1
	line(g, "roci.end_into()")
	g.indent -= 1
	line(g, "}}")
}

// `with fill red thickness 3 [ ... ]`: the style holds for the block and is put back after it.
@(private)
emit_with :: proc(g: ^Gen, s: ^lang.IR_Stmt, k: lang.IR_With) {
	if k.record != nil {
		refuse(g, s.span, "`with` a named style")
		return
	}
	line(g, "roci.push(.Style)")
	for o in k.styles {
		if len(o.args) == 0 {
			continue
		}
		switch o.word {
		case "fill":
			line(g, "roci.fill_paint(%s)", paint(g, o.args[0]))
		case "stroke":
			line(g, "roci.stroke_paint(%s)", paint(g, o.args[0]))
		case "thickness":
			line(g, "roci.thickness(%s)", expr(g, o.args[0]))
		case "alpha":
			line(g, "roci.alpha(rt.alpha_to_byte(%s))", expr(g, o.args[0]))
		case "blend":
			if word, ok := word_of(o.args[0]); ok {
				line(g, "if mode, found := roci.blend_named(%q); found {{ roci.blend(mode) }}", word)
			} else {
				refuse(g, s.span, "`with blend` that is not written as a word")
			}
		case:
			refuse(g, s.span, fmt.tprintf("`with %s`", o.word))
		}
	}
	emit_block(g, k.body)
	line(g, "roci.pop()")
}

// `window size 800 600 title "x" resizable false`: the window, then each of the words that set it.
@(private)
emit_window :: proc(g: ^Gen, e: ^lang.IR, c: lang.IR_Call) {
	line(g, "{{")
	g.indent += 1
	window_lines(g, e, c)
	g.indent -= 1
	line(g, "}}")
}

// The lines that make a window and give it its words; the window is the name they give back.
@(private)
window_lines :: proc(g: ^Gen, e: ^lang.IR, c: lang.IR_Call) -> string {
	id := g.next_id
	g.next_id += 1
	made := fmt.aprintf("window_%d", id, allocator = context.temp_allocator)
	at, hidden := "nil", false
	if o := option(c.options, "at"); o != nil {
		at = point2_int(g, o)
	}
	if o := option(c.options, "visible"); o != nil {
		// a flag the interpreter reads as a value; only a written true or false is kept here
		if b, is_bool := o.args[0].kind.(lang.IR_Boolean); is_bool {
			hidden = !b.value
		} else {
			refuse(g, e.span, "`window visible` that is not written as true or false")
		}
	}
	args := in_order(g, c.args[:2])
	flags := "roci.Window_Flags{hidden = true}" if hidden else "{}"
	line(g, "%s := roci.window(int(%s), int(%s), %s, %s)", made, args[0], args[1], at, flags)
	for o in c.options {
		if len(o.args) == 0 {
			continue
		}
		switch o.word {
		case "at", "visible":
		case "title":
			line(g, "roci.title_window(%s, %s)", made, expr(g, o.args[0]))
		case "resizable", "bordered", "topmost", "focusable", "grab", "modal", "fullscreen":
			line(g, "roci.set_%s(%s, %s)", o.word, made, expr(g, o.args[0]))
		case "smallest", "largest":
			holder := point2(g, o)
			line(g, "roci.set_%s(%s, int((%s)[0]), int((%s)[1]))", o.word, made, holder, holder)
		case "ratio":
			line(g, "roci.set_ratio(%s, %s)", made, expr(g, o.args[0]))
		case "alpha":
			line(g, "roci.set_window_alpha(%s, rt.alpha_to_byte(%s))", made, expr(g, o.args[0]))
		case "cursor":
			if word, ok := word_of(o.args[0]); ok {
				line(g, "rt.set_cursor(%s, %q)", made, word)
			} else {
				refuse(g, e.span, "`window cursor` that is not written as a word")
			}
		case "parent":
			line(g, "roci.set_parent(%s, %s)", made, expr(g, o.args[0]))
		case:
			refuse(g, e.span, fmt.tprintf("`window` with `%s`", o.word))
		}
	}
	return made
}

// A place written after `at` as a pair of whole numbers: two numbers or a vector.
@(private)
point2_int :: proc(g: ^Gen, o: ^lang.IR_Option) -> string {
	if len(o.args) >= 2 {
		return fmt.aprintf("[2]int{{int(%s), int(%s)}}", expr(g, o.args[0]), expr(g, o.args[1]), allocator = context.temp_allocator)
	}
	holder := expr(g, o.args[0])
	return fmt.aprintf("[2]int{{int(%s.x), int(%s.y)}}", holder, holder, allocator = context.temp_allocator)
}

// `for i from 0 to 9 [by 2]`: the steps are counted, not added up, so a step of 0.1 does not drift.
@(private)
emit_for :: proc(g: ^Gen, s: ^lang.IR_Stmt, k: lang.IR_For) {
	id := g.next_id
	g.next_id += 1
	step := "-1.0" if k.down else "1.0"
	from, to := expr(g, k.from), expr(g, k.to)
	line(g, "{{")
	g.indent += 1
	line(g, "from_%d, to_%d := %s, %s", id, id, from, to)
	if k.by != nil {
		by := expr(g, k.by)
		line(g, "step_%d := %s", id, by)
		line(g, "if step_%d == 0 {{ step_%d = 1 }}", id, id)
		if k.down {
			line(g, "step_%d = -abs(step_%d)", id, id)
		}
	} else {
		line(g, "step_%d := %s", id, step)
	}
	line(g, "count_%d := int(math.floor((to_%d - from_%d) / step_%d + 1e-9)) + 1", id, id, id, id)
	line(g, "for n_%d in 0 ..< max(count_%d, 0) {{", id, id)
	g.indent += 1
	line(g, "%s := from_%d + f64(n_%d) * step_%d", name_of(g, k.var), id, id, id)
	g.indent -= 1
	emit_block(g, k.body)
	line(g, "}}")
	g.indent -= 1
	line(g, "}}")
}

// `for each item in list`: by place, so a list that grows or shrinks in the body is read as it is.
@(private)
emit_for_each :: proc(g: ^Gen, s: ^lang.IR_Stmt, k: lang.IR_For_Each) {
	if kind_of(g, k.list) != .List {
		refuse(g, s.span, "`for each` over something that is not a list")
		return
	}
	id := g.next_id
	g.next_id += 1
	line(g, "{{")
	g.indent += 1
	line(g, "list_%d := %s", id, expr(g, k.list))
	line(g, "if list_%d != nil {{", id)
	g.indent += 1
	line(g, "for at_%d := 0; at_%d < len(list_%d.items); at_%d += 1 {{", id, id, id, id)
	g.indent += 1
	item := name_of(g, k.var)
	line(g, "%s := list_%d.items[at_%d]", item, id, id)
	g.indent -= 1
	emit_block(g, k.body)
	g.indent += 1
	// a vector or number changed in the body stays in the list; a record is shared and needs nothing
	if kind_of_symbol(g, k.var) != .Record {
		line(g, "if at_%d < len(list_%d.items) {{ list_%d.items[at_%d] = %s }}", id, id, id, id, item)
	} else {
		line(g, "_ = %s", item)
	}
	g.indent -= 1
	line(g, "}}")
	g.indent -= 1
	line(g, "}}")
	g.indent -= 1
	line(g, "}}")
}

@(private)
kind_of_symbol :: proc(g: ^Gen, sym: ^lang.Symbol) -> lang.Type_Kind {
	return g.types.items[lang.resolve(g.types, sym.type)].kind
}

// ---- blocks that are procedures of their own ----

// Writes a package-level procedure for a block: `signature` is everything after the name.
@(private)
emit_proc :: proc(g: ^Gen, name, signature: string, body: lang.IR_Block, locals: []^lang.Symbol = nil, gives: bool = false) {
	saved_body, saved_indent, saved_line := g.body, g.indent, g.comment_line
	g.body = strings.builder_make(context.temp_allocator)
	g.indent = 1
	g.comment_line = -1
	for sym in locals {
		type, ok := odin_type(g, sym.type, sym.first_write, sym.name)
		if ok && type != "" {
			line(g, "%s: %s", name_of(g, sym), type)
		}
	}
	saved_depth := g.dynamic_depth
	g.dynamic_depth = 1
	ended := false
	for s in body.stmts {
		emit_stmt(g, s)
		if ends_the_verb(s) {
			ended = true
			break
		}
	}
	g.dynamic_depth = saved_depth
	if gives && !ended {
		line(g, "return") // hands back what `give` put in the result
	}
	text := strings.to_string(g.body)
	g.body, g.indent, g.comment_line = saved_body, saved_indent, saved_line
	fmt.sbprintf(&g.procs, "%s :: proc%s {{\n%s}}\n\n", name, signature, text)
}

@(private)
emit_draw :: proc(g: ^Gen, s: ^lang.IR_Stmt, k: lang.IR_Draw) {
	if k.ui {
		refuse(g, s.span, "`ui`, which makes widgets")
		return
	}
	id := g.next_id
	g.next_id += 1
	name := fmt.aprintf("draw_%d", id, allocator = context.temp_allocator)
	emit_proc(g, name, "()", k.body)
	if k.window != nil {
		if g.has_scenes {
			refuse(g, s.span, "`draw` for a window of its own in a sketch with scenes")
			return
		}
		line(g, "roci.draw_window(%s, %s)", expr(g, k.window), name)
		return
	}
	if g.has_scenes {
		// the draw blocks of a sketch with scenes are run by one procedure that picks the ones that take part
		append(&g.scene_draws, Scene_Draw{scene = g.registering, proc_name = name})
		if !g.draw_registered {
			g.draw_registered = true
			line(g, "roci.draw(scene_draw)")
		}
		return
	}
	line(g, "roci.draw(%s)", name)
}

@(private)
emit_every :: proc(g: ^Gen, s: ^lang.IR_Stmt, k: lang.IR_Every) {
	id := len(g.handlers) + 1
	frames := k.unit == "frame" || k.unit == "frames"
	name := fmt.aprintf("every_%d", id, allocator = context.temp_allocator)
	emit_proc(g, name, "()", k.body)
	append(&g.handlers, Handler{kind = .Every, proc_name = name, frames = frames, index = id, scene = g.registering})
	fmt.sbprintf(&g.procs, "%s_next, %s_period: f64\n%s_window: roci.Window\n\n", name, name, name)
	line(g, "{{")
	g.indent += 1
	line(g, "n := math.floor(%s)", expr(g, k.count))
	line(g, "if n >= 1 {{")
	g.indent += 1
	line(g, "%s_window = roci.current_window()", name)
	line(g, "%s_period = n", name)
	line(g, "%s_next = n + %s", name, "f64(roci.frame_count())" if frames else "roci.time_now()")
	g.indent -= 1
	line(g, "}}")
	g.indent -= 1
	line(g, "}}")
}

@(private)
emit_on :: proc(g: ^Gen, s: ^lang.IR_Stmt, k: lang.IR_On) {
	if k.message != nil {
		emit_receive(g, s, k)
		return
	}
	id := len(g.handlers) + 1
	name := fmt.aprintf("on_%d", id, allocator = context.temp_allocator)
	handler := Handler{kind = .Event, proc_name = name, index = id, scene = g.registering}
	if k.window != nil {
		handler.window = expr(g, k.window)
	}
	switch k.event {
	case "key":
		handler.event = "Key_Down"
		if len(k.args) > 0 {
			handler.arg = fmt.tprintf("happening.name == %s", expr(g, k.args[0]))
		}
	case "mouse down", "mouse up":
		handler.event = "Mouse_Down" if k.event == "mouse down" else "Mouse_Up"
		if len(k.args) > 0 {
			handler.arg = fmt.tprintf("happening.name == %s", expr(g, k.args[0]))
		}
	case "touch down", "touch up", "resize", "move", "focus":
		handler.event = happening_of(k.event)
	case "press", "release":
		handler.event = happening_of(k.event)
		if len(k.args) > 0 {
			handler.arg = fmt.tprintf("happening.name == %s", expr(g, k.args[0]))
		}
	case "midi down", "midi up", "midi control", "midi bend", "midi program", "midi pressure", "midi start", "midi stop":
		handler.event = happening_of(k.event)
		line(g, "roci.start_midi()")
	case "osc":
		handler.event = "Osc"
		if len(k.args) > 0 {
			handler.arg = fmt.tprintf("rt.osc_match(%s, happening.osc.address)", expr(g, k.args[0]))
		}
		line(g, "_ = roci.start_osc()")
	case "udp":
		handler.event = "Udp"
		if len(k.args) > 0 {
			port := expr(g, k.args[0])
			handler.arg = fmt.tprintf("happening.udp.to == int(%s)", port)
			line(g, "_ = roci.udp_listen(%s)", port)
		}
	case "tcp", "tcp open", "tcp close", "websocket", "websocket open", "websocket close":
		handler.event = happening_of(k.event)
		if len(k.args) > 0 {
			handler.arg = fmt.tprintf("happening.tcp.label == %s", expr(g, k.args[0]))
		}
	case "enter", "leave":
		handler.kind = .Scene_Event
		handler.event = k.event
	case:
		refuse(g, s.span, fmt.tprintf("`on %s`", k.event))
		return
	}
	emit_proc(g, name, "()", k.body)
	append(&g.handlers, handler)
}

// The procedure the app loop calls in each window's frame, before its `draw` block, which runs the `every`
// blocks that are due and the `on` blocks for what happened.
@(private)
emit_handlers :: proc(g: ^Gen, out: ^strings.Builder) {
	if len(g.handlers) == 0 && !g.uses_tweens {
		return
	}
	fmt.sbprintf(out, "hook :: proc(w: roci.Window) {{\n")
	if g.uses_tweens {
		fmt.sbprintf(out, "\trt.step_tweens()\n")
	}
	receives := false
	for h in g.handlers {
		receives ||= h.kind == .Receive
	}
	if receives {
		// what was sent last frame arrives now, and what arrived last frame is gone
		fmt.sbprintf(out, "\tif inbox_frame != roci.frame_count() {{\n\t\tinbox_frame = roci.frame_count()\n")
		for h in g.handlers {
			if h.kind == .Receive {
				fmt.sbprintf(out, "\t\tinbox_%d_now, inbox_%d_next = inbox_%d_next, inbox_%d_now\n\t\tclear(&inbox_%d_next)\n", h.index, h.index, h.index, h.index, h.index)
			}
		}
		fmt.sbprintf(out, "\t}}\n")
		for h in g.handlers {
			if h.kind == .Receive {
				gate := fmt.tprintf(" && rt.takes_part(%d)", h.scene) if h.scene > 0 else ""
				fmt.sbprintf(out, "\tif w == %s%s {{\n\t\tfor message in inbox_%d_now {{ %s(message) }}\n\t}}\n", h.window, gate, h.index, h.proc_name)
			}
		}
	}
	events := false
	for h in g.handlers {
		events ||= h.kind == .Event
	}
	if events {
		fmt.sbprintf(out, "\tfor happening in roci.happened() {{\n\t\tif happening.window != w {{ continue }}\n")
		for h in g.handlers {
			if h.kind != .Event {
				continue
			}
			test := fmt.tprintf("happening.kind == .%s", h.event)
			if h.arg != "" {
				test = fmt.tprintf("%s && %s", test, h.arg)
			}
			if h.window != "" {
				test = fmt.tprintf("%s && w == %s", test, h.window)
			}
			if h.scene > 0 {
				test = fmt.tprintf("%s && rt.takes_part(%d)", test, h.scene)
			}
			fmt.sbprintf(out, "\t\tif %s {{\n\t\t\trt.happening = happening\n\t\t\t%s()\n\t\t\trt.happening = {{}}\n\t\t}}\n", test, h.proc_name)
		}
		fmt.sbprintf(out, "\t}}\n")
	}
	for h in g.handlers {
		if h.kind != .Every {
			continue
		}
		gate := fmt.tprintf(" && rt.takes_part(%d)", h.scene) if h.scene > 0 else ""
		fmt.sbprintf(out, "\tif %s_window == w && %s_period >= 1%s {{\n", h.proc_name, h.proc_name, gate)
		fmt.sbprintf(out, "\t\tnow := %s\n", "f64(roci.frame_count())" if h.frames else "roci.time_now()")
		fmt.sbprintf(out, "\t\tif now >= %s_next {{\n", h.proc_name)
		fmt.sbprintf(out, "\t\t\t%s_next = now + %s_period if now >= %s_next + %s_period else %s_next + %s_period\n", h.proc_name, h.proc_name, h.proc_name, h.proc_name, h.proc_name, h.proc_name)
		fmt.sbprintf(out, "\t\t\t%s()\n\t\t}}\n\t}}\n", h.proc_name)
	}
	fmt.sbprintf(out, "}}\n\n")
}

// ---- taught verbs ----

// A taught verb's Odin name: its own, and a number when the checker made several versions of it.
@(private)
instance_name :: proc(g: ^Gen, instance: ^lang.IR_Instance) -> string {
	key := fmt.aprintf("verb:%s:%p", instance.name, instance, allocator = context.temp_allocator)
	for sym, name in g.names {
		_ = sym
		_ = name
	}
	if found, ok := g.verb_names[instance]; ok {
		return found
	}
	same := 0
	for other in g.program.instances {
		if other.name == instance.name && !other.unused {
			same += 1
		}
	}
	base := clean(instance.name)
	name := base
	if g.taken[name] || same > 1 {
		name = fmt.aprintf("%s_%d", base, len(g.verb_names) + 1, allocator = context.temp_allocator)
	}
	for g.taken[name] {
		name = fmt.aprintf("%s_%d", name, len(g.verb_names) + 1, allocator = context.temp_allocator)
	}
	g.taken[name] = true
	g.verb_names[instance] = name
	_ = key
	return name
}

@(private)
emit_instance :: proc(g: ^Gen, instance: ^lang.IR_Instance) {
	name := instance_name(g, instance)
	params := strings.builder_make(context.temp_allocator)
	for p, i in instance.params {
		if i > 0 {
			strings.write_string(&params, ", ")
		}
		type, _ := odin_type(g, instance.arg_types[i] if i < len(instance.arg_types) else p.type, p.first_write, p.name)
		fmt.sbprintf(&params, "%s: %s", name_of(g, p), type)
	}
	for d, i in instance.defaults {
		if len(instance.params) > 0 || i > 0 {
			strings.write_string(&params, ", ")
		}
		type, _ := odin_type(g, d.symbol.type, d.symbol.first_write, d.word)
		g.no_hoist += 1 // a default is worked out when the verb is called, in the call
		fmt.sbprintf(&params, "%s: %s = %s", name_of(g, d.symbol), type, expr(g, d.value))
		g.no_hoist -= 1
	}
	signature := fmt.aprintf("(%s)", strings.to_string(params), allocator = context.temp_allocator)
	if instance.gives {
		result, _ := odin_type(g, instance.result, lang.Span{}, instance.name)
		signature = fmt.aprintf("(%s) -> (result__: %s)", strings.to_string(params), result, allocator = context.temp_allocator)
	}
	// the names the verb makes for itself
	locals := make([dynamic]^lang.Symbol, context.temp_allocator)
	collect_locals(instance.body, &locals)
	saved := g.in_verb
	g.in_verb = instance
	emit_proc(g, name, signature, instance.body, locals[:], instance.gives)
	g.in_verb = saved
}

// The names a verb's body makes (`Local`), each once, in the order they are first assigned.
@(private)
collect_locals :: proc(block: lang.IR_Block, out: ^[dynamic]^lang.Symbol) {
	for s in block.stmts {
		#partial switch k in s.kind {
		case lang.IR_Assign:
			if k.target.kind == .Local && len(k.fields) == 0 {
				seen := false
				for known in out {
					seen ||= known == k.target
				}
				if !seen {
					append(out, k.target)
				}
			}
		case lang.IR_If:
			collect_locals(k.body, out)
			collect_locals(k.else_body, out)
		case lang.IR_Repeat:
			collect_locals(k.body, out)
		case lang.IR_While:
			collect_locals(k.body, out)
		case lang.IR_For:
			collect_locals(k.body, out)
		case lang.IR_For_Each:
			collect_locals(k.body, out)
		}
	}
}

// The `Happening` of each name `on` uses.
@(private)
happening_of :: proc(name: string) -> string {
	switch name {
	case "touch down":       return "Touch_Down"
	case "touch up":         return "Touch_Up"
	case "resize":           return "Resize"
	case "move":             return "Move"
	case "focus":            return "Focus"
	case "press":            return "Action_Press"
	case "release":          return "Action_Release"
	case "midi down":        return "Midi_Down"
	case "midi up":          return "Midi_Up"
	case "midi control":     return "Midi_Control"
	case "midi bend":        return "Midi_Bend"
	case "midi program":     return "Midi_Program"
	case "midi pressure":    return "Midi_Pressure"
	case "midi start":       return "Midi_Start"
	case "midi stop":        return "Midi_Stop"
	case "tcp":              return "Tcp_Line"
	case "tcp open":         return "Tcp_Open"
	case "tcp close":        return "Tcp_Close"
	case "websocket":        return "Ws_Message"
	case "websocket open":   return "Ws_Open"
	case "websocket close":  return "Ws_Close"
	}
	return ""
}

// `scene "play" [ ... ]`: what is written in it is written where it stands, tagged with the scene.
@(private)
emit_scene :: proc(g: ^Gen, s: ^lang.IR_Stmt, k: lang.IR_Scene) {
	place := 0
	for known, i in g.scenes {
		if known == k.name {
			place = i + 1
		}
	}
	if place == 0 {
		append(&g.scenes, k.name)
		place = len(g.scenes)
	}
	line(g, "_ = rt.scene_register(%q)", k.name)
	saved := g.registering
	g.registering = place
	for inner in k.body.stmts {
		emit_top_level(g, inner)
	}
	g.registering = saved
}

// The procedures the scenes need: the one draw block that runs the ones that take part, the restart of a scene's timers,
// its `on enter` and `on leave` blocks, and the shift of its timers by the time it waited.
@(private)
emit_scene_procs :: proc(g: ^Gen, out: ^strings.Builder) {
	fmt.sbprintf(out, "scene_draw :: proc() {{\n")
	for d in g.scene_draws {
		if d.scene == 0 {
			fmt.sbprintf(out, "\t%s()\n", d.proc_name)
		}
	}
	fmt.sbprintf(out, "\tswitch rt.active_scene() {{\n")
	for place in 1 ..= len(g.scenes) {
		fmt.sbprintf(out, "\tcase %d:\n", place)
		for d in g.scene_draws {
			if d.scene == place {
				fmt.sbprintf(out, "\t\t%s()\n", d.proc_name)
			}
		}
	}
	fmt.sbprintf(out, "\t}}\n}}\n\n")
	fmt.sbprintf(out, "scene_restart :: proc(scene: int) {{\n")
	for h in g.handlers {
		if h.kind == .Every && h.scene > 0 {
			now := "f64(roci.frame_count())" if h.frames else "roci.time_now()"
			fmt.sbprintf(out, "\tif scene == %d {{ %s_next = %s_period + %s }}\n", h.scene, h.proc_name, h.proc_name, now)
		}
	}
	fmt.sbprintf(out, "}}\n\nscene_shift :: proc(scene: int, waited: f64) {{\n")
	for h in g.handlers {
		if h.kind == .Every && h.scene > 0 && !h.frames {
			fmt.sbprintf(out, "\tif scene == %d {{ %s_next += waited }}\n", h.scene, h.proc_name)
		}
	}
	fmt.sbprintf(out, "}}\n\nscene_event :: proc(name: string, scene: int) {{\n")
	for h in g.handlers {
		if h.kind == .Scene_Event {
			if h.scene == 0 {
				fmt.sbprintf(out, "\tif name == %q {{ %s() }}\n", h.event, h.proc_name)
			} else {
				fmt.sbprintf(out, "\tif name == %q && scene == %d {{ %s() }}\n", h.event, h.scene, h.proc_name)
			}
		}
	}
	fmt.sbprintf(out, "}}\n\n")
}

// `on stage receive message [ ... ]`: a procedure that takes the message, run for each one in the window's inbox.
@(private)
emit_receive :: proc(g: ^Gen, s: ^lang.IR_Stmt, k: lang.IR_On) {
	if k.window == nil {
		refuse(g, s.span, "`on receive` without a window")
		return
	}
	g.receiver_next += 1
	if g.receiver_next > len(g.receiver_info) {
		refuse(g, s.span, "`on receive` for a message of a kind a sketch cannot keep yet")
		return
	}
	info := g.receiver_info[g.receiver_next - 1]
	id := len(g.handlers) + 1
	name := fmt.aprintf("on_%d", id, allocator = context.temp_allocator)
	emit_proc(g, name, fmt.tprintf("(%s: %s)", name_of(g, k.message), info.message_type), k.body)
	fmt.sbprintf(&g.procs, "inbox_%d_now, inbox_%d_next: [dynamic]%s\n\n", info.id, info.id, info.message_type)
	append(&g.handlers, Handler{kind = .Receive, proc_name = name, index = info.id, message_type = info.message_type, window = info.window, scene = g.registering})
}
