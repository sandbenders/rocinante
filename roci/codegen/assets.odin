// SPDX-License-Identifier: 0BSD
//
// Pictures, fonts, sounds, windows that are values, and the actions a player's controls make: the verbs whose
// values are the numbers the core hands out (`roci.Image`, `roci.Sound`, `roci.Window`), and the paints made of
// a picture or a list of colors.
package codegen

import "../data"
import "../lang"
import "core:fmt"
import "core:strings"

// A paint: a color is one, a number is a grey, a picture is a fill with the words that say how it sits, and a
// list of colors is a gradient shaped by its words (`extra`, the options that followed the value).
@(private)
paint :: proc(g: ^Gen, e: ^lang.IR, extra: []lang.IR_Option = nil) -> string {
	#partial switch kind_of(g, e) {
	case .Colour:
		return expr(g, e)
	case .Number:
		return fmt.aprintf("roci.grey(%s)", expr(g, e), allocator = context.temp_allocator)
	case .Image:
		fit, size, at := "-1", "0.0", "[2]f64{}"
		for o in extra {
			if len(o.args) == 0 {
				continue
			}
			switch o.word {
			case "as":
				word, _ := word_of(o.args[0])
				switch word {
				case "cover":   fit = "0"
				case "fit":     fit = "1"
				case "stretch": fit = "2"
				case "tile":    fit = "3"
				case "center":  fit = "4"
				}
			case "size":
				size = expr(g, o.args[0])
			case "at":
				at = point2(g, o)
			}
		}
		return fmt.aprintf("rt.picture_fill(%s, %s, %s, %s)", expr(g, e), fit, size, at, allocator = context.temp_allocator)
	case .Gradient:
		return fmt.aprintf("rt.gradient_of(%s)", expr(g, e), allocator = context.temp_allocator)
	case .List:
		if kind_of_list_element(g, e) != .Colour {
			break
		}
		return fmt.aprintf("rt.gradient_paint(%s)", gradient_arguments(g, e, extra), allocator = context.temp_allocator)
	}
	refuse(g, e.span, fmt.tprintf("%s as a color", lang.describe(g.types, e.type)))
	return "maths.Colour{}"
}

// What makes a gradient of a list of colors and the words that shape it, as the arguments of `rt.gradient_paint` and
// `rt.new_gradient`.
@(private)
gradient_arguments :: proc(g: ^Gen, e: ^lang.IR, extra: []lang.IR_Option) -> string {
	kind, space, angle, stops, centre := "0", "0", "0.0", "nil", "[2]f32{50, 50}"
	for o in extra {
		if len(o.args) == 0 {
			continue
		}
		switch o.word {
		case "as":
			word, _ := word_of(o.args[0])
			switch word {
			case "radial": kind = "1"
			case "conic":  kind = "2"
			}
		case "in":
			word, _ := word_of(o.args[0])
			switch word {
			case "rgb":   space = "1"
			case "oklch": space = "2"
			}
		case "angle":
			angle = expr(g, o.args[0])
		case "at":
			holder := point2(g, o)
			centre = fmt.tprintf("[2]f32{{f32((%s)[0]), f32((%s)[1])}}", holder, holder)
		case "stops":
			stops = fmt.tprintf("rt.stops_of(%s)", expr(g, o.args[0]))
		}
	}
	colours: string
	if literal, is_literal := e.kind.(lang.IR_List); is_literal {
		b := strings.builder_make(context.temp_allocator)
		strings.write_string(&b, "[]maths.Colour{")
		for item, i in literal.items {
			if i > 0 {
				strings.write_string(&b, ", ")
			}
			strings.write_string(&b, expr(g, item))
		}
		strings.write_string(&b, "}")
		colours = strings.to_string(b)
	} else {
		colours = fmt.tprintf("rt.colours_of(%s)", expr(g, e))
	}
	return fmt.aprintf("%s, %s, %s, %s, %s, %s", colours, kind, angle, space, stops, centre, allocator = context.temp_allocator)
}

// A place written after `at`: two numbers or a vector, as a pair of numbers.
@(private)
point2 :: proc(g: ^Gen, o: lang.IR_Option) -> string {
	if len(o.args) >= 2 {
		return fmt.aprintf("[2]f64{{%s, %s}}", expr(g, o.args[0]), expr(g, o.args[1]), allocator = context.temp_allocator)
	}
	return expr(g, o.args[0])
}

// The type of the values of a table type.
@(private)
table_value :: proc(g: ^Gen, table: lang.Type_Id) -> lang.Type_Id {
	return lang.Type_Id(g.types.items[lang.resolve(g.types, table)].a)
}

@(private)
kind_of_list_element :: proc(g: ^Gen, e: ^lang.IR) -> lang.Type_Kind {
	return g.types.items[lang.resolve(g.types, list_element(g, e.type))].kind
}

// A `Maybe` made of an option, or `nil` when the word was not written.
@(private)
maybe :: proc(g: ^Gen, options: []lang.IR_Option, word: string) -> string {
	if o := option(options, word); o != nil {
		return expr(g, o.args[0])
	}
	return "nil"
}

// The verbs of this file. `handled` is false when the verb is not one of them.
@(private)
asset_verbs :: proc(g: ^Gen, e: ^lang.IR, c: lang.IR_Call, args: []string) -> (text: string, gives: bool, handled: bool) {
	name := c.verb.name
	switch name {
	case "load":
		#partial switch kind_of(g, e) {
		case .Image:
			if option(c.options, "sheet") != nil {
				refuse(g, e.span, "`load` of a picture with `sheet`")
			}
			return fmt.aprintf("rt.load_image(%s)", args[0], allocator = context.temp_allocator), true, true
		case .Sound:
			buffer := "0.0"
			if o := option(c.options, "buffer"); o != nil {
				buffer = expr(g, o.args[0])
			}
			return fmt.aprintf("rt.load_sound(%s, %s)", args[0], buffer, allocator = context.temp_allocator), true, true
		}
		if name, is_text := c.args[0].kind.(lang.IR_Text); is_text && data.format_of(name.value) != .None {
			convert, ok := datum_proc(g, e.type, e.span)
			if !ok {
				return "", false, true
			}
			g.uses_data = true
			sheet := `""`
			if o := option(c.options, "sheet"); o != nil {
				sheet = expr(g, o.args[0])
			}
			return fmt.aprintf("rt.load_data(%s, %s, %s)", args[0], sheet, convert, allocator = context.temp_allocator), true, true
		}
		refuse(g, e.span, "`load` of a file whose kind it cannot tell from the name")
		return "", false, true
	case "font":
		size := "0.0"
		if o := option(c.options, "size"); o != nil {
			size = expr(g, o.args[0])
		}
		return fmt.aprintf("rt.font(%s, %s)", args[0], size, allocator = context.temp_allocator), false, true
	case "pixel":
		at := option(c.options, "at")
		if at == nil {
			refuse(g, e.span, "`pixel` without `at`")
			return "", false, true
		}
		return fmt.aprintf("rt.pixel(%s, %s)", args[0], point2(g, at^), allocator = context.temp_allocator), true, true
	case "pixels":
		return fmt.aprintf("rt.pixels(%s)", args[0], allocator = context.temp_allocator), true, true
	case "picture":
		from, size := option(c.options, "from"), option(c.options, "size")
		if from == nil || size == nil || kind_of(g, from.args[0]) != .List {
			refuse(g, e.span, "`picture` without its colors and its size")
			return "", false, true
		}
		return fmt.aprintf("rt.picture(%s, %s)", expr(g, from.args[0]), point2(g, size^), allocator = context.temp_allocator), true, true
	case "crop":
		at, size := option(c.options, "at"), option(c.options, "size")
		if at == nil || size == nil {
			refuse(g, e.span, "`crop` without `at` and `size`")
			return "", false, true
		}
		return fmt.aprintf("rt.crop(%s, %s, %s)", args[0], point2(g, at^), point2(g, size^), allocator = context.temp_allocator), true, true
	case "resize":
		size := option(c.options, "size")
		if size == nil {
			refuse(g, e.span, "`resize` without `size`")
			return "", false, true
		}
		return fmt.aprintf("rt.resize(%s, %s, %s)", args[0], point2(g, size^), word_option(g, c.options, "as"), allocator = context.temp_allocator), true, true
	case "flip":
		return fmt.aprintf("rt.flip(%s, %s)", args[0], word_option(g, c.options, "as"), allocator = context.temp_allocator), true, true
	case "filter":
		return fmt.aprintf("rt.filter(%s, %s, %s)", args[0], word_option(g, c.options, "as"), maybe(g, c.options, "by"), allocator = context.temp_allocator), true, true
	case "mask":
		by := option(c.options, "by")
		if by == nil {
			refuse(g, e.span, "`mask` without `by`")
			return "", false, true
		}
		return fmt.aprintf("rt.mask(%s, %s)", args[0], expr(g, by.args[0]), allocator = context.temp_allocator), true, true
	case "canvas":
		return fmt.aprintf("rt.canvas(%s, %s)", args[0], args[1], allocator = context.temp_allocator), true, true
	case "svg":
		// shapes 0 and 1 give the place, 2 and 3 the size too: (x y), (v), (x y w h), (v size)
		switch c.shape {
		case 0: return fmt.aprintf("rt.svg(%s, [2]f64{{%s, %s}}, nil)", args[0], args[1], args[2], allocator = context.temp_allocator), false, true
		case 1: return fmt.aprintf("rt.svg(%s, %s, nil)", args[0], args[1], allocator = context.temp_allocator), false, true
		case 2: return fmt.aprintf("rt.svg(%s, [2]f64{{%s, %s}}, [2]f64{{%s, %s}})", args[0], args[1], args[2], args[3], args[4], allocator = context.temp_allocator), false, true
		case 3: return fmt.aprintf("rt.svg(%s, %s, %s)", args[0], args[1], args[2], allocator = context.temp_allocator), false, true
		}
	case "model":
		if c.shape == 0 {
			return fmt.aprintf("rt.model(%s, [3]f64{{%s, %s, %s}}, %s)", args[0], args[1], args[2], args[3], args[4], allocator = context.temp_allocator), false, true
		}
		if vector_size(g, c.args[1]) == 3 {
			return fmt.aprintf("rt.model(%s, %s, %s)", args[0], args[1], args[2], allocator = context.temp_allocator), false, true
		}
		refuse(g, e.span, "`model` at a point that is not in space")
		return "", false, true
	case "tint":
		return fmt.aprintf("roci.tint(%s)", args[0], allocator = context.temp_allocator), false, true
	case "image":
		look, origin := look_of(g, e, c.options)
		width, height := maybe(g, c.options, "width"), maybe(g, c.options, "height")
		switch c.shape {
		case 0:
			return image_call("roci.image_xy", {args[0], args[1], args[2]}, look, origin, width, height), false, true
		case 1:
			return image_call("roci.image_v", {args[0], args[1]}, look, origin, width, height), false, true
		case 2:
			return shape_call("roci.image_sized_xy", {args[0], args[1], args[2], args[3], args[4]}, look, origin), false, true
		case 3:
			return shape_call("roci.image_sized_v", {args[0], args[1], args[2]}, look, origin), false, true
		}
	// ---- sounds ----
	case "play", "loop":
		if c.shape == 1 { // a movie
			return fmt.aprintf("rt.play_movie(%s, %s, %s)", args[0], "true" if name == "loop" else "false", maybe(g, c.options, "speed"), allocator = context.temp_allocator), false, true
		}
		if c.shape != 0 {
			return "", false, false
		}
		return fmt.aprintf("roci.%s(%s, volume = %s, pan = %s, speed = %s, note = %s, pitch = %s, seconds = %s)", name, args[0], maybe(g, c.options, "volume"), maybe(g, c.options, "pan"), maybe(g, c.options, "speed"), maybe(g, c.options, "note"), maybe(g, c.options, "pitch"), maybe(g, c.options, "for"), allocator = context.temp_allocator), false, true
	case "pause":
		if c.shape == 1 {
			return fmt.aprintf("roci.movie_pause(%s)", args[0], allocator = context.temp_allocator), false, true
		}
		if c.shape != 0 {
			return "", false, false
		}
		return fmt.aprintf("roci.pause(%s, note = %s)", args[0], maybe(g, c.options, "note"), allocator = context.temp_allocator), false, true
	case "rewind":
		if c.shape == 1 {
			return fmt.aprintf("roci.movie_rewind(%s, %s)", args[0], maybe(g, c.options, "by"), allocator = context.temp_allocator), false, true
		}
		if c.shape != 0 {
			return "", false, false
		}
		return fmt.aprintf("roci.rewind(%s, %s)", args[0], maybe(g, c.options, "by"), allocator = context.temp_allocator), false, true
	case "forward":
		if c.shape == 2 {
			by := option(c.options, "by")
			if by == nil {
				refuse(g, e.span, "`forward` of a movie without `by`")
				return "", false, true
			}
			return fmt.aprintf("roci.movie_forward(%s, %s)", args[0], expr(g, by.args[0]), allocator = context.temp_allocator), false, true
		}
		if c.shape == 1 {
			by := option(c.options, "by")
			if by == nil {
				refuse(g, e.span, "`forward` of a sound without `by`")
				return "", false, true
			}
			return fmt.aprintf("roci.forward_sound(%s, %s)", args[0], expr(g, by.args[0]), allocator = context.temp_allocator), false, true
		}
	case "label", "button", "toggle", "slider", "number", "knob", "textbox", "dropdown", "choice", "list", "colorpicker", "range", "xypad", "image button", "progress", "separator", "controls", "tip", "forget ui", "ui hide", "ui show", "ui key", "ui theme":
		return widget_call(g, e, c, name, args)
	case "fetch", "fetch picture", "post":
		block, is_block := c.args[len(c.args) - 1].kind.(lang.IR_Block_Value)
		if !is_block || len(c.args) < 2 {
			refuse(g, e.span, "`fetch` without its block")
			return "", false, true
		}
		for sym in block.block.captures {
			if sym.scope != 0 && sym.kind != .Item {
				refuse(g, e.span, "`fetch` whose block reads a name of a taught verb")
				return "", false, true
			}
		}
		g.next_id += 1
		proc_name := fmt.aprintf("fetched_%d", g.next_id, allocator = context.temp_allocator)
		emit_proc(g, proc_name, "()", block.block)
		send := args[1] if name == "post" && len(c.args) > 2 else `""`
		return fmt.aprintf("rt.fetch(%s, %v, %s, %s, %v, %s)", args[0], name == "post", send, maybe_or(g, c.options, "header", `""`), name == "fetch picture", proc_name, allocator = context.temp_allocator), false, true
	case "ask file", "ask folder", "ask save":
		block, is_block := c.args[len(c.args) - 1].kind.(lang.IR_Block_Value)
		if !is_block {
			refuse(g, e.span, "`ask` without its block")
			return "", false, true
		}
		for sym in block.block.captures {
			if sym.scope != 0 && sym.kind != .Item {
				refuse(g, e.span, "`ask` whose block reads a name of a taught verb")
				return "", false, true
			}
		}
		g.next_id += 1
		proc_name := fmt.aprintf("asked_%d", g.next_id, allocator = context.temp_allocator)
		emit_proc(g, proc_name, "()", block.block)
		kind := 0 if name == "ask file" else 1 if name == "ask folder" else 2
		prompt := args[0] if len(c.args) > 1 else `""`
		return fmt.aprintf("rt.ask(%d, %s, %s)", kind, prompt, proc_name, allocator = context.temp_allocator), false, true
	case "read":
		return fmt.aprintf("rt.read(%s)", args[0], allocator = context.temp_allocator), true, true
	case "open":
		return fmt.aprintf("rt.open(%s)", args[0], allocator = context.temp_allocator), false, true
	case "copy to clipboard":
		return fmt.aprintf("roci.set_clipboard(%s)", args[0], allocator = context.temp_allocator), false, true
	case "midi outputs":
		return "rt.text_list(roci.midi_outputs(context.temp_allocator))", true, true
	case "webcam cameras":
		g.uses.camera = true
		return "rt.text_list(roci.webcam_cameras(context.temp_allocator))", true, true
	case "webcam pick":
		g.uses.camera = true
		if kind_of(g, c.args[0]) == .Text {
			return fmt.aprintf("roci.webcam_pick(%s)", args[0], allocator = context.temp_allocator), false, true
		}
		return fmt.aprintf("roci.webcam_pick(int(%s))", args[0], allocator = context.temp_allocator), false, true
	case "numbers":
		from, to := option(c.options, "from"), option(c.options, "to")
		if from == nil || to == nil {
			refuse(g, e.span, "`numbers` without both its ends")
			return "nil", true, true
		}
		return fmt.aprintf("rt.numbers(%s, %s, %s)", expr(g, from.args[0]), expr(g, to.args[0]), maybe_or(g, c.options, "by", "1.0"), allocator = context.temp_allocator), true, true
	case "outline":
		at, size := "[2]f64{}", "nil"
		if o := option(c.options, "at"); o != nil {
			at = point2(g, o^)
		}
		if o := option(c.options, "size"); o != nil {
			size = point2(g, o^)
		}
		return fmt.aprintf("rt.outline_of(%s, %s, %s, %s)", args[0], maybe_or(g, c.options, "alpha", "50.0"), at, size, allocator = context.temp_allocator), true, true
	case "ray":
		g.lenient += 1
		record := record_name(g, e.type, e.span)
		g.lenient -= 1
		if record == "" {
			return "nil", true, true
		}
		fields := record_fields(g, e.type, {{"from", "from"}, {"to", "to"}})
		return fmt.aprintf("(proc(spot: [2]f64) -> ^%s {{\n\tfrom, to := roci.pixel_ray(spot.x, spot.y)\n\treturn rt.new_record(%s{{class__ = %d, %s}}%s)\n}})(%s)", record, record, int(lang.Shape_Class.Segment), fields, trace_arg(g, record), args[0], allocator = context.temp_allocator), true, true
	case "synth":
		if c.shape == 1 {
			preset, preset_name := "nil", `""`
			if o := option(c.options, "preset"); o != nil {
				if kind_of(g, o.args[0]) == .Text {
					preset_name = expr(g, o.args[0])
				} else {
					preset = expr(g, o.args[0])
				}
			}
			return fmt.aprintf("rt.soundfont(%s, %s, %s, %s, %s, %s, %s)", args[0], preset, preset_name, maybe(g, c.options, "attack"), maybe(g, c.options, "decay"), maybe(g, c.options, "sustain"), maybe(g, c.options, "release"), allocator = context.temp_allocator), true, true
		}
		wave, ok := word_of(c.args[0])
		if !ok {
			refuse(g, e.span, "`synth` with a wave that is not written as a word")
			return "", false, true
		}
		return fmt.aprintf("rt.synth(%q, %s, %s, %s, %s)", wave, maybe(g, c.options, "attack"), maybe(g, c.options, "decay"), maybe(g, c.options, "sustain"), maybe(g, c.options, "release"), allocator = context.temp_allocator), true, true
	case "level":
		if c.shape == 0 {
			return "roci.level_all()", true, true
		}
		return fmt.aprintf("roci.level_of(%s)", args[0], allocator = context.temp_allocator), true, true
	case "bands":
		switch c.shape {
		case 0: return "rt.list_from_numbers(roci.bands_all())", true, true
		case 1: return fmt.aprintf("rt.list_from_numbers(roci.bands_all(rt.band_count(%s)))", args[0], allocator = context.temp_allocator), true, true
		case 2: return fmt.aprintf("rt.list_from_numbers(roci.bands_of(%s))", args[0], allocator = context.temp_allocator), true, true
		case 3: return fmt.aprintf("rt.list_from_numbers(roci.bands_of(%s, rt.band_count(%s)))", args[0], args[1], allocator = context.temp_allocator), true, true
		}
	case "effect", "shade":
		if name == "effect" && c.shape == 1 {
			by := option(c.options, "by")
			settings := "nil"
			if by != nil {
				made, ok := sound_settings(g, by.args[0])
				if !ok {
					refuse(g, e.span, "`effect` with settings that are not written as a record")
					return "", false, true
				}
				settings = made
			}
			return fmt.aprintf("rt.sound_effect(%s, %s, %s)", args[0], args[1], settings, allocator = context.temp_allocator), false, true
		}
		values := "nil"
		if by := option(c.options, "by"); by != nil {
			made, ok := effect_values(g, by.args[0])
			if !ok {
				refuse(g, e.span, fmt.tprintf("`%s` with values that are not written as a record", name))
				return "", false, true
			}
			values = made
		}
		return fmt.aprintf("rt.%s(%s, %s)", name, args[0], values, allocator = context.temp_allocator), false, true
	case "no effect":
		return fmt.aprintf("roci.no_sound_effect(%s, %s)", args[0], args[1], allocator = context.temp_allocator), false, true
	case "remember":
		vault := vault_option(c.options)
		key := args[0]
		#partial switch kind_of(g, c.args[1]) {
		case .Number:  return fmt.aprintf("rt.remember_number(%s, %s, %s)", vault, key, args[1], allocator = context.temp_allocator), false, true
		case .Boolean: return fmt.aprintf("rt.remember_bool(%s, %s, %s)", vault, key, args[1], allocator = context.temp_allocator), false, true
		case .Text:    return fmt.aprintf("rt.remember_text(%s, %s, %s)", vault, key, args[1], allocator = context.temp_allocator), false, true
		case .Vector:  return fmt.aprintf("rt.remember_vector(%s, %s, %s)", vault, key, args[1], allocator = context.temp_allocator), false, true
		case .Colour:  return fmt.aprintf("rt.remember_colour(%s, %s, %s)", vault, key, args[1], allocator = context.temp_allocator), false, true
		}
		refuse(g, e.span, fmt.tprintf("`remember` of %s", lang.describe(g.types, c.args[1].type)))
		return "", false, true
	case "recall":
		vault := vault_option(c.options)
		key := args[0]
		start := option(c.options, "start")
		#partial switch kind_of(g, e) {
		case .Number:  return fmt.aprintf("rt.recall_number(%s, %s, %s)", vault, key, expr(g, start.args[0]) if start != nil else "0.0", allocator = context.temp_allocator), true, true
		case .Boolean: return fmt.aprintf("rt.recall_bool(%s, %s, %s)", vault, key, expr(g, start.args[0]) if start != nil else "false", allocator = context.temp_allocator), true, true
		case .Text:    return fmt.aprintf("rt.recall_text(%s, %s, %s)", vault, key, expr(g, start.args[0]) if start != nil else `""`, allocator = context.temp_allocator), true, true
		case .Vector:  return fmt.aprintf("rt.recall_vector(%s, %s, %s)", vault, key, expr(g, start.args[0]) if start != nil else fmt.tprintf("[%d]f64{{}}", vector_size(g, e)), allocator = context.temp_allocator), true, true
		case .Colour:  return fmt.aprintf("rt.recall_colour(%s, %s, %s)", vault, key, expr(g, start.args[0]) if start != nil else "maths.Colour{}", allocator = context.temp_allocator), true, true
		}
		refuse(g, e.span, fmt.tprintf("`recall` of %s", lang.describe(g.types, e.type)))
		return "", false, true
	case "forget":
		if word, is_word := word_of(c.args[0]); is_word && (word == "memory" || word == "vault") {
			return fmt.aprintf("rt.forget_everything(%s)", "true" if word == "vault" else "false", allocator = context.temp_allocator), false, true
		}
		return fmt.aprintf("rt.forget(%s, %s)", vault_option(c.options), args[0], allocator = context.temp_allocator), false, true
	case "shuffle":
		if kind_of(g, c.args[0]) != .List {
			refuse(g, e.span, "`shuffle` of something that is not a list")
			return "", false, true
		}
		list_type, _ := odin_type(g, c.args[0].type, e.span, "a list")
		element := list_type[len("^rt.List("):len(list_type) - 1]
		return fmt.aprintf("rt.shuffle(%s, %s)", args[0], item_marker(g, list_element(g, c.args[0].type), element), allocator = context.temp_allocator), true, true
	case "reverse", "join", "items":
		of := c.args[0]
		if name == "items" {
			if list := option_value(c.options, "of"); list != nil {
				of = list
			}
		}
		if kind_of(g, of) != .List {
			refuse(g, e.span, fmt.tprintf("`%s` of something that is not a list", name))
			return "", false, true
		}
		list_type, _ := odin_type(g, of.type, e.span, "a list")
		if len(list_type) <= len("^rt.List(") {
			return "", false, true // odin_type said why
		}
		element := list_type[len("^rt.List("):len(list_type) - 1]
		marker := item_marker(g, list_element(g, of.type), element)
		switch name {
		case "reverse":
			return fmt.aprintf("rt.reverse(%s, %s)", args[0], marker, allocator = context.temp_allocator), true, true
		case "join":
			return fmt.aprintf("rt.join_lists(%s, %s, %s)", args[0], args[1], marker, allocator = context.temp_allocator), true, true
		}
		return fmt.aprintf("rt.items_between(%s, %s, %s, %s)", maybe_or(g, c.options, "of", "nil"), args[0], maybe_or(g, c.options, "to", "0.0"), marker, allocator = context.temp_allocator), true, true
	case "files":
		return fmt.aprintf("rt.files_in(%s)", maybe_or(g, c.options, "in", `""`), allocator = context.temp_allocator), true, true
	case "lines":
		return fmt.aprintf("rt.lines(%s)", args[0], allocator = context.temp_allocator), true, true
	case "measure":
		return fmt.aprintf("roci.measure(%s)", args[0], allocator = context.temp_allocator), true, true
	case "gradient":
		if kind_of(g, c.args[0]) == .List && kind_of_list_element(g, c.args[0]) == .Colour {
			return fmt.aprintf("rt.new_gradient(%s)", gradient_arguments(g, c.args[0], c.options), allocator = context.temp_allocator), true, true
		}
		refuse(g, e.span, "`gradient` of something that is not a list of colors")
		return "", false, true
	// ---- tables ----
	case "table":
		table_type, ok := odin_type(g, e.type, e.span, "a table")
		if !ok {
			return "nil", true, true
		}
		value := table_type[len("^rt.Table("):len(table_type) - 1]
		return fmt.aprintf("rt.new_table(%s, %s)", value, item_marker(g, table_value(g, e.type), value), allocator = context.temp_allocator), true, true
	case "put":
		if c.shape == 1 {
			return fmt.aprintf("rt.put_item(%s, %s, %s)", args[0], args[1], stored(g, c.args[2]), allocator = context.temp_allocator), false, true
		}
		if c.shape == 0 {
			return fmt.aprintf("rt.put(%s, %s, %s)", args[0], args[1], stored(g, c.args[2]), allocator = context.temp_allocator), false, true
		}
	case "get":
		return fmt.aprintf("rt.get(%s, %s)", args[0], args[1], allocator = context.temp_allocator), true, true
	case "keys":
		return fmt.aprintf("rt.keys(%s)", args[0], allocator = context.temp_allocator), true, true
	case "send":
		return send_call(g, e, c, args), false, true
	case "copy":
		made, _ := copy_value(g, c.args[0].type, args[0], e.span)
		return made, true, true
	case "record":
		if c.shape == 1 {
			return fmt.aprintf("rt.record_sound(%s, %s)", args[0], args[1], allocator = context.temp_allocator), false, true
		}
		return fmt.aprintf("rt.record(%s)", args[0], allocator = context.temp_allocator), false, true
	case "no record":
		if c.shape == 1 {
			return fmt.aprintf("roci.no_record_sound(%s)", args[0], allocator = context.temp_allocator), false, true
		}
		return "roci.no_record()", false, true
	// ---- scenes ----
	case "go":
		return fmt.aprintf("rt.go(%s)", args[0], allocator = context.temp_allocator), false, true
	case "visit":
		return fmt.aprintf("rt.visit(%s)", args[0], allocator = context.temp_allocator), false, true
	case "return":
		return "rt.scene_return()", false, true
	// ---- the network ----
	case "tcp connect":
		return fmt.aprintf("_ = roci.tcp_connect(%s, %s, %s)", args[0], maybe_or(g, c.options, "to", `""`), maybe_or(g, c.options, "port", "0.0"), allocator = context.temp_allocator), false, true
	case "tcp listen":
		return fmt.aprintf("_ = roci.tcp_listen(%s, %s)", args[0], maybe_or(g, c.options, "port", "0.0"), allocator = context.temp_allocator), false, true
	case "tcp send":
		client := fmt.tprintf("rt.whole(%s)", maybe_or(g, c.options, "to", "0.0"))
		if c.shape == 1 {
			return fmt.aprintf("_ = roci.tcp_send(%s, rt.bytes_of(%s), %s)", args[0], args[1], client, allocator = context.temp_allocator), false, true
		}
		return fmt.aprintf("_ = roci.tcp_send(%s, transmute([]byte)rt.join(%s, \"\\n\"), %s)", args[0], args[1], client, allocator = context.temp_allocator), false, true
	case "tcp close":
		return fmt.aprintf("_ = roci.tcp_close(%s, rt.whole(%s))", args[0], maybe_or(g, c.options, "to", "0.0"), allocator = context.temp_allocator), false, true
	case "websocket connect":
		return fmt.aprintf("_ = roci.websocket_connect(%s, %s)", args[0], maybe_or(g, c.options, "to", `""`), allocator = context.temp_allocator), false, true
	case "websocket send":
		if c.shape == 1 {
			return fmt.aprintf("_ = roci.websocket_send(%s, rt.bytes_of(%s), true)", args[0], args[1], allocator = context.temp_allocator), false, true
		}
		return fmt.aprintf("_ = roci.websocket_send(%s, transmute([]byte)%s)", args[0], args[1], allocator = context.temp_allocator), false, true
	case "websocket close":
		return fmt.aprintf("_ = roci.websocket_close(%s)", args[0], allocator = context.temp_allocator), false, true
	case "osc listen":
		return fmt.aprintf("_ = roci.osc_listen(%s)", args[0], allocator = context.temp_allocator), false, true
	case "osc value":
		return fmt.aprintf("roci.osc_value(%s)", args[0], allocator = context.temp_allocator), true, true
	case "osc send":
		host, port := maybe_or(g, c.options, "to", `"127.0.0.1"`), maybe_or(g, c.options, "port", "0.0")
		if c.shape != 0 {
			return fmt.aprintf("rt.osc_bundle(%s, %s, %s)", args[0], host, port, allocator = context.temp_allocator), false, true
		}
		literal, is_literal := c.args[1].kind.(lang.IR_List)
		if !is_literal {
			// a list made elsewhere: its items are read as they are
			list := expr(g, c.args[1])
			#partial switch kind_of_list_element(g, c.args[1]) {
			case .Boxed:
				return fmt.aprintf("rt.osc_send(%s, rt.osc_args_of_boxes(%s), %s, %s)", args[0], list, host, port, allocator = context.temp_allocator), false, true
			case .Number, .Boolean, .Text:
				return fmt.aprintf("rt.osc_send(%s, rt.osc_args_of_values(%s), %s, %s)", args[0], list, host, port, allocator = context.temp_allocator), false, true
			}
			refuse(g, e.span, "`osc send` of a list that holds something OSC cannot carry")
			return "", false, true
		}
		parts := make([dynamic]string, context.temp_allocator)
		for written in literal.items {
			// the list is a mix, so each item was put in a box; what was written is what OSC is given
			item := written
			if convert, boxed := item.kind.(lang.IR_Convert); boxed && kind_of(g, convert.value) != .Boxed {
				item = convert.value
			}
			#partial switch kind_of(g, item) {
			case .Number, .Boolean, .Text:
				append(&parts, fmt.tprintf("rt.Osc_Arg(%s)", expr(g, item)))
			case .Boxed:
				refuse(g, item.span, "`osc send` of a value that may be of any kind inside a list written out")
			case .List:
				append(&parts, fmt.tprintf("rt.osc_blob(%s)", expr(g, item)))
			case:
				refuse(g, item.span, "`osc send` of something that is not a number, a text, true or false, or a list of numbers")
			}
		}
		return fmt.aprintf("rt.osc_send(%s, []rt.Osc_Arg{{%s}}, %s, %s)", args[0], strings.join(parts[:], ", ", context.temp_allocator), host, port, allocator = context.temp_allocator), false, true
	case "udp send":
		data := fmt.tprintf("rt.bytes_of(%s)", args[0]) if c.shape == 1 else fmt.tprintf("transmute([]byte)%s", args[0])
		return fmt.aprintf("rt.udp_send(%s, %s, %s)", data, maybe_or(g, c.options, "to", `"127.0.0.1"`), maybe_or(g, c.options, "port", "0.0"), allocator = context.temp_allocator), false, true
	// ---- MIDI out ----
	case "midi note":
		return fmt.aprintf("_ = roci.midi_note(%s, %s, %s, %s)", args[0], maybe(g, c.options, "velocity"), maybe(g, c.options, "channel"), maybe(g, c.options, "for"), allocator = context.temp_allocator), false, true
	case "midi release":
		first := args[0] if len(args) > 0 else "nil"
		return fmt.aprintf("_ = roci.midi_release(%s, %s)", first, maybe(g, c.options, "channel"), allocator = context.temp_allocator), false, true
	case "midi set":
		return fmt.aprintf("_ = roci.midi_set(%s, %s, %s)", args[0], maybe_or(g, c.options, "to", "0.0"), maybe(g, c.options, "channel"), allocator = context.temp_allocator), false, true
	case "midi bend":
		return fmt.aprintf("_ = roci.midi_bend(%s, %s)", args[0], maybe(g, c.options, "channel"), allocator = context.temp_allocator), false, true
	case "midi program":
		return fmt.aprintf("_ = roci.midi_program(%s, %s)", args[0], maybe(g, c.options, "channel"), allocator = context.temp_allocator), false, true
	case "midi to":
		return fmt.aprintf("roci.midi_to(%s)", args[0], allocator = context.temp_allocator), false, true
	case "midi clock":
		return fmt.aprintf("_ = roci.midi_clock(%s)", args[0], allocator = context.temp_allocator), false, true
	case "midi stop":
		return "roci.midi_clock_stop()", false, true
	case "midi control":
		return fmt.aprintf("roci.midi_control(%s)", args[0], allocator = context.temp_allocator), true, true
	case "midi tempo":
		return "roci.midi_tempo()", true, true
	// ---- the player's controls ----
	case "bind":
		to := option(c.options, "to")
		if to == nil {
			return "", false, true
		}
		return fmt.aprintf("_ = roci.bind(%s, %s)", args[0], expr(g, to.args[0]), allocator = context.temp_allocator), false, true
	case "direction":
		return fmt.aprintf("rt.direction(%s)", args[0], allocator = context.temp_allocator), true, true
	case "held":
		return fmt.aprintf("rt.held(%s)", args[0], allocator = context.temp_allocator), true, true
	case "rumble":
		return fmt.aprintf("_ = roci.rumble(%s, %s, int(%s))", args[0], maybe_or(g, c.options, "for", "0.5"), maybe_or(g, c.options, "player", "1.0"), allocator = context.temp_allocator), false, true
	}
	return "", false, false
}

// A word written after a connecting word (`as blur`), as an Odin text, or "" when it was not written.
@(private)
word_option :: proc(g: ^Gen, options: []lang.IR_Option, word: string) -> string {
	if o := option(options, word); o != nil {
		if text, ok := word_of(o.args[0]); ok {
			return fmt.aprintf("%q", text, allocator = context.temp_allocator)
		}
		refuse(g, o.args[0].span, fmt.tprintf("`%s` that is not written as a word", word))
	}
	return `""`
}

// Whether a call says `in vault`: the value is kept in the vault, not in `memory.toml`.
@(private)
vault_option :: proc(options: []lang.IR_Option) -> string {
	for o in options {
		if o.word == "in" && len(o.args) > 0 {
			if word, ok := word_of(o.args[0]); ok && word == "vault" {
				return "true"
			}
		}
	}
	return "false"
}

// An option's value, or what stands in when the word was not written.
@(private)
maybe_or :: proc(g: ^Gen, options: []lang.IR_Option, word, otherwise: string) -> string {
	if o := option(options, word); o != nil {
		return expr(g, o.args[0])
	}
	return otherwise
}

// `roci.image_xy(picture, x, y, look, origin, width, height)`: the look and the origin are written when there are words for
// them, and the sizes always, since they are the last two.
@(private)
image_call :: proc(procedure: string, args: []string, look, origin, width, height: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "%s(%s, %s, %s, %s, %s)", procedure, strings.join(args, ", ", context.temp_allocator), look if look != "" else "roci.Look{}", origin if origin != "" else "roci.Origin.Default", width, height)
	return strings.to_string(b)
}

// The values after `by`, written as a record, as a list of what a shader reads.
@(private)
effect_values :: proc(g: ^Gen, e: ^lang.IR) -> (text: string, ok: bool) {
	record, is_record := e.kind.(lang.IR_Record)
	if !is_record {
		return "", false
	}
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, "[]roci.Effect_Value{")
	first := true
	for label, i in record.names {
		value := record.values[i]
		piece: string
		#partial switch kind_of(g, value) {
		case .Number:
			piece = fmt.tprintf("rt.effect_number(%q, %s)", label, expr(g, value))
		case .Boolean:
			piece = fmt.tprintf("rt.effect_number(%q, 1.0 if %s else 0.0)", label, expr(g, value))
		case .Vector:
			piece = fmt.tprintf("rt.effect_vector(%q, %s)", label, expr(g, value))
		case .Colour:
			piece = fmt.tprintf("rt.effect_colour(%q, %s)", label, expr(g, value))
		case:
			continue // a value the shader cannot take is left out, as the interpreter leaves it
		}
		if !first {
			strings.write_string(&b, ", ")
		}
		first = false
		strings.write_string(&b, piece)
	}
	strings.write_string(&b, "}")
	return strings.to_string(b), true
}

// The settings after `by` of a sound effect, written as a record.
@(private)
sound_settings :: proc(g: ^Gen, e: ^lang.IR) -> (text: string, ok: bool) {
	record, is_record := e.kind.(lang.IR_Record)
	if !is_record {
		return "", false
	}
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, "[]roci.Sound_Setting{")
	first := true
	for label, i in record.names {
		value := record.values[i]
		piece: string
		#partial switch kind_of(g, value) {
		case .Number:
			piece = fmt.tprintf("{{name = %q, number = %s}}", label, expr(g, value))
		case .Boolean:
			piece = fmt.tprintf("{{name = %q, number = 1.0 if %s else 0.0}}", label, expr(g, value))
		case .Text:
			piece = fmt.tprintf("{{name = %q, word = %s}}", label, expr(g, value))
		case:
			continue
		}
		if !first {
			strings.write_string(&b, ", ")
		}
		first = false
		strings.write_string(&b, piece)
	}
	strings.write_string(&b, "}")
	return strings.to_string(b), true
}

// "true" when a `save` says `in sketch`, "false" for the output folder it otherwise uses.
@(private)
sketch_option :: proc(options: []lang.IR_Option) -> string {
	for o in options {
		if o.word == "in" && len(o.args) > 0 {
			if word, ok := word_of(o.args[0]); ok && word == "sketch" {
				return "true"
			}
		}
	}
	return "false"
}
