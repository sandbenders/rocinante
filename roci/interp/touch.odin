// SPDX-License-Identifier: 0BSD
//
// Fingers as values: `finger`, the finger an `on touch down` or `on touch up` block
// runs for, and `touches`, every finger down in the window now. Each is a record of
// the one shape the checker gives fingers: `id`, `pos`, `start` and `pressure`.
package interp

import "core:strings"

import "../"
import "../lang"

// A finger as a record of the checker's finger type.
finger_record :: proc(it: ^Interp, type: lang.Type_Id, f: roci.Touch) -> Value {
	shape := lang.shape_of(it.types, type)
	if shape < 0 {
		return nil
	}
	r := new_record(it, shape)
	set :: proc(it: ^Interp, r: ^Record, shape: int, name: string, v: Value) {
		if at := field_index(it, shape, name); at >= 0 {
			r.fields[at] = v
		}
	}
	set(it, r, shape, "id", f64(f.id))
	set(it, r, shape, "pos", vec2(f.pos))
	set(it, r, shape, "start", vec2(f.start))
	set(it, r, shape, "pressure", f.pressure)
	return r
}

// `touches`: a list of the fingers down in the current window, of the list type the checker gave it.
touches_list :: proc(it: ^Interp, type: lang.Type_Id) -> Value {
	out := new_list(it)
	item := lang.Type_Id(it.types.items[lang.resolve(it.types, type)].a)
	for f in roci.touches() {
		append(&out.items, finger_record(it, item, f))
	}
	return out
}

// `turtle`: the current window's turtle as a record of the checker's turtle type
// (`pos`, `angle` and `down`).
turtle_record :: proc(it: ^Interp, type: lang.Type_Id) -> Value {
	shape := lang.shape_of(it.types, type)
	if shape < 0 {
		return nil
	}
	state := roci.turtle_state()
	r := new_record(it, shape)
	if at := field_index(it, shape, "pos"); at >= 0 {
		r.fields[at] = vec2(state.pos)
	}
	if at := field_index(it, shape, "angle"); at >= 0 {
		r.fields[at] = state.angle
	}
	if at := field_index(it, shape, "down"); at >= 0 {
		r.fields[at] = state.down
	}
	return r
}

// `safe`: how far in from each side of the window the screen is free, as a record of the checker's type.
safe_record :: proc(it: ^Interp, type: lang.Type_Id) -> Value {
	shape := lang.shape_of(it.types, type)
	if shape < 0 {
		return nil
	}
	area := roci.safe_area()
	r := new_record(it, shape)
	set :: proc(it: ^Interp, r: ^Record, shape: int, name: string, v: Value) {
		if at := field_index(it, shape, name); at >= 0 {
			r.fields[at] = v
		}
	}
	set(it, r, shape, "top", area.top)
	set(it, r, shape, "bottom", area.bottom)
	set(it, r, shape, "left", area.left)
	set(it, r, shape, "right", area.right)
	return r
}

// `midi`: the key or controller an `on midi` block runs for, as a record of the checker's type.
midi_record :: proc(it: ^Interp, type: lang.Type_Id, m: roci.Midi_Message) -> Value {
	shape := lang.shape_of(it.types, type)
	if shape < 0 {
		return nil
	}
	r := new_record(it, shape)
	fields := [8]struct{name: string, value: f64}{{"note", m.note}, {"velocity", m.velocity}, {"channel", m.channel}, {"control", m.control}, {"value", m.value}, {"bend", m.bend}, {"program", m.program}, {"pressure", m.pressure}}
	for f in fields {
		if at := field_index(it, shape, f.name); at >= 0 {
			r.fields[at] = f.value
		}
	}
	return r
}

// A gamepad as a record of the checker's gamepad type; `pad` is nil for no pad, which gives a pad at
// rest that says it is not connected.
pad_record :: proc(it: ^Interp, type: lang.Type_Id, pad: ^roci.Pad_State) -> Value {
	shape := lang.shape_of(it.types, type)
	if shape < 0 {
		return nil
	}
	p := pad^ if pad != nil else roci.Pad_State{}
	r := new_record(it, shape)
	set :: proc(it: ^Interp, r: ^Record, shape: int, name: string, v: Value) {
		if at := field_index(it, shape, name); at >= 0 {
			r.fields[at] = v
		}
	}
	set(it, r, shape, "id", f64(p.id))
	set(it, r, shape, "name", strings.clone(p.name, it.alloc))
	set(it, r, shape, "connected", pad != nil)
	set(it, r, shape, "bottom", p.bottom)
	set(it, r, shape, "right", p.right)
	set(it, r, shape, "left", p.left)
	set(it, r, shape, "top", p.top)
	set(it, r, shape, "leftstick", vec2(p.left_stick))
	set(it, r, shape, "rightstick", vec2(p.right_stick))
	set(it, r, shape, "dpad", vec2(p.dpad))
	set(it, r, shape, "lefttrigger", p.left_trigger)
	set(it, r, shape, "righttrigger", p.right_trigger)
	set(it, r, shape, "leftstickpress", p.left_stick_press)
	set(it, r, shape, "rightstickpress", p.right_stick_press)
	set(it, r, shape, "leftshoulder", p.left_shoulder)
	set(it, r, shape, "rightshoulder", p.right_shoulder)
	set(it, r, shape, "start", p.start)
	set(it, r, shape, "back", p.back)
	set(it, r, shape, "home", p.home)
	extra := new_list(it)
	for on in p.extra {
		append(&extra.items, on)
	}
	set(it, r, shape, "extra", extra)
	return r
}

// `gamepad`: the first pad that is plugged in.
gamepad_value :: proc(it: ^Interp, type: lang.Type_Id) -> Value {
	pad, ok := roci.gamepad()
	return pad_record(it, type, &pad if ok else nil)
}

// `gamepads`: every pad, as a list of the checker's gamepad type.
gamepads_list :: proc(it: ^Interp, type: lang.Type_Id) -> Value {
	out := new_list(it)
	item := lang.Type_Id(it.types.items[lang.resolve(it.types, type)].a)
	all := roci.gamepads()
	for i in 0 ..< len(all) {
		append(&out.items, pad_record(it, item, &all[i]))
	}
	return out
}

// `joysticks`: every joystick that is not a gamepad, as a list of the checker's joystick type.
joysticks_list :: proc(it: ^Interp, type: lang.Type_Id) -> Value {
	out := new_list(it)
	item := lang.Type_Id(it.types.items[lang.resolve(it.types, type)].a)
	shape := lang.shape_of(it.types, item)
	if shape < 0 {
		return out
	}
	for j in roci.joysticks() {
		r := new_record(it, shape)
		if at := field_index(it, shape, "id"); at >= 0 {
			r.fields[at] = f64(j.id)
		}
		if at := field_index(it, shape, "name"); at >= 0 {
			r.fields[at] = strings.clone(j.name, it.alloc)
		}
		axes := new_list(it)
		for a in j.axes {
			append(&axes.items, a)
		}
		if at := field_index(it, shape, "axes"); at >= 0 {
			r.fields[at] = axes
		}
		buttons := new_list(it)
		for b in j.buttons {
			append(&buttons.items, b)
		}
		if at := field_index(it, shape, "buttons"); at >= 0 {
			r.fields[at] = buttons
		}
		append(&out.items, r)
	}
	return out
}

// `screens`: every screen, the main one first, as a list of the checker's screen type.
screens_list :: proc(it: ^Interp, type: lang.Type_Id) -> Value {
	out := new_list(it)
	item := lang.Type_Id(it.types.items[lang.resolve(it.types, type)].a)
	shape := lang.shape_of(it.types, item)
	if shape < 0 {
		return out
	}
	for s in roci.screens() {
		r := new_record(it, shape)
		set :: proc(it: ^Interp, r: ^Record, shape: int, name: string, v: Value) {
			if at := field_index(it, shape, name); at >= 0 {
				r.fields[at] = v
			}
		}
		set(it, r, shape, "name", strings.clone(s.name, it.alloc))
		set(it, r, shape, "pos", vec2({f64(s.x), f64(s.y)}))
		set(it, r, shape, "width", f64(s.width))
		set(it, r, shape, "height", f64(s.height))
		set(it, r, shape, "density", s.density)
		set(it, r, shape, "refresh", s.refresh)
		set(it, r, shape, "main", s.main)
		append(&out.items, r)
	}
	return out
}
