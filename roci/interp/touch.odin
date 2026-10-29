// SPDX-License-Identifier: 0BSD
//
// Fingers as values: `finger`, the finger an `on touch down` or `on touch up` block
// runs for, and `touches`, every finger down in the window now. Each is a record of
// the one shape the checker gives fingers: `id`, `pos`, `start` and `pressure`.
package interp

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
