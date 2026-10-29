// SPDX-License-Identifier: 0BSD
//
// Keeping the sketch's memory from growing. Values stored in sketch-wide names live
// in an arena (`Interp.long`), which frees nothing, so a `draw` block that replaces
// a name every frame (`dots = keep dots [ ... ]`) would leave every old copy behind.
// Now and then, between frames, the values still reachable are copied into a fresh
// arena and the old one is dropped whole: a small copying collector. Between frames
// no block runs and the frame's own memory has been freed, so the only references
// into the arena are the roots below. A map from old to new addresses keeps every
// sharing (`b = a`, a record in two lists, a record that holds itself) as it was,
// and lists, records and tables keep their ids and stamps, so nothing else can tell.
package interp

import "../"
import "../maths"
import "core:mem/virtual"
import "core:strings"

// The arena is copied once it holds this much more than was live after the last copy.
COLLECT_SLACK :: 1 << 20

// Copies what is live when the arena has grown enough since the last time; called
// at the start of a frame, before any block runs.
maybe_collect :: proc(p: ^Interp) {
	if p.values[p.values_now].total_used >= 2 * p.live + COLLECT_SLACK {
		collect(p)
	}
}

// Copies every value reachable from the roots into the other arena and frees this one.
collect :: proc(p: ^Interp) {
	old, next := p.values_now, 1 - p.values_now
	if err := virtual.arena_init_growing(&p.values[next]); err != nil {
		return // no memory for a copy: keep going in the old arena
	}
	was_long := p.alloc == p.long
	p.long = virtual.arena_allocator(&p.values[next])
	if was_long {
		p.alloc = p.long
	}
	moved := make(map[rawptr]rawptr, 64, context.temp_allocator)

	for &g in p.globals {
		if g.set {
			g.value = move_value(p, g.value, &moved)
		}
	}
	for &t in p.tweens {
		t.from = move_value(p, t.from, &moved)
		t.to = move_value(p, t.to, &moved)
		if t.record != nil {
			t.record = as_record(move_value(p, t.record, &moved))
		}
	}
	// A cached tree belongs to a list; a list nothing reaches any more is gone.
	for &e in p.shape_cache {
		if e.list == nil {
			continue
		}
		if to, found := moved[e.list]; found {
			e.list = (^List)(to)
		} else {
			drop_entry(&e)
		}
	}

	virtual.arena_destroy(&p.values[old])
	p.values_now = next
	p.live = p.values[next].total_used
	p.collections += 1
}

// A copy of `v` in the new arena (`p.long`), each list, record and table copied once
// however many places hold it. Text has no identity, so each place gets its own copy.
@(private = "file")
move_value :: proc(p: ^Interp, v: Value, moved: ^map[rawptr]rawptr) -> Value {
	switch x in v {
	case string:
		return strings.clone(x, p.long)
	case ^List:
		if x == nil {
			return v
		}
		if to, found := moved[x]; found {
			return (^List)(to)
		}
		l := new(List, p.long)
		l^ = {long = x.long, id = x.id, stamp = x.stamp}
		moved[x] = l
		l.items = make([dynamic]Value, 0, len(x.items), p.long)
		for item in x.items {
			append(&l.items, move_value(p, item, moved))
		}
		return l
	case ^Record:
		if x == nil {
			return v
		}
		if to, found := moved[x]; found {
			return (^Record)(to)
		}
		r := new(Record, p.long)
		r^ = {shape = x.shape, long = x.long, class = x.class, stamp = x.stamp}
		moved[x] = r
		r.fields = make([]Value, len(x.fields), p.long)
		for f, i in x.fields {
			r.fields[i] = move_value(p, f, moved)
		}
		return r
	case ^Table:
		if x == nil {
			return v
		}
		if to, found := moved[x]; found {
			return (^Table)(to)
		}
		t := new(Table, p.long)
		t^ = {long = x.long, id = x.id, stamp = x.stamp}
		moved[x] = t
		t.keys = make([dynamic]string, 0, len(x.keys), p.long)
		t.values = make([dynamic]Value, 0, len(x.keys), p.long)
		t.index = make(map[string]int, len(x.keys), p.long)
		for name, i in x.keys {
			key := strings.clone(name, p.long)
			t.index[key] = i
			append(&t.keys, key)
			append(&t.values, move_value(p, x.values[i], moved))
		}
		return t
	case ^roci.Gradient:
		if x == nil {
			return v
		}
		if to, found := moved[x]; found {
			return (^roci.Gradient)(to)
		}
		g := new(roci.Gradient, p.long)
		g^ = x^
		moved[x] = g
		return g
	case f64, bool, Vec, maths.Colour, roci.Window:
	}
	return v
}
