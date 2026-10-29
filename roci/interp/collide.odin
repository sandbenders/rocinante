// SPDX-License-Identifier: 0BSD
//
// The collision verbs: `touching contact hits inside cast`, on package collide.
// A vector is a point, and a record is the shape the fields of its `{ }` made it
// (the class the checker worked out, kept by copies): `points` an outline, `from`
// and `to` a line, `pos` and `radius` a circle, `pos` and `size` (and `angle`) a
// rectangle. A value that is none of these touches nothing.
package interp

import "../collide"
import "../lang"
import "core:math"

@(private)
is_collision_verb :: proc(name: string) -> bool {
	switch name {
	case "touching", "contact", "hits", "inside", "cast":
		return true
	}
	return false
}

@(private)
collision_verb :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call) -> Value {
	if len(call.args) < 2 {
		return nil
	}
	a := eval(it, call.args[0])
	b := eval(it, call.args[1])
	switch call.verb.name {
	case "touching":
		sa, ok_a := to_shape(it, a)
		sb, ok_b := to_shape(it, b)
		return ok_a && ok_b && collide.touching(sa, sb)
	case "inside":
		sb, ok := to_shape(it, b)
		return ok && collide.inside(as_pair(a), sb)
	case "contact":
		sa, ok_a := to_shape(it, a)
		sb, ok_b := to_shape(it, b)
		if !ok_a || !ok_b {
			return make_result(it, e.type, nil)
		}
		c, touching := collide.contact(sa, sb)
		if !touching {
			return make_result(it, e.type, nil) // empty: every field 0
		}
		return make_result(it, e.type, {{"point", vec2(c.point)}, {"normal", vec2(c.normal)}, {"depth", c.depth}})
	case "hits":
		out := new_list(it)
		sa, ok := to_shape(it, a)
		list := as_list(b)
		if !ok || list == nil {
			return out
		}
		if tree := tree_for(it, list); tree != nil {
			for i in collide.tree_hits(tree, sa) {
				append(&out.items, list.items[i])
			}
			return out
		}
		box := collide.bounds(sa)
		for item in list.items {
			if s, is_shape := to_shape(it, item); is_shape && collide.bounds_overlap(box, collide.bounds(s)) && collide.touching(sa, s) {
				append(&out.items, item)
			}
		}
		return out
	case "cast":
		line := as_record(a)
		list := as_list(b)
		if line == nil || list == nil {
			return make_result(it, e.type, nil)
		}
		from, to := as_pair(read_field(it, line, "from")), as_pair(read_field(it, line, "to"))
		best: collide.Hit
		found: Value
		met := false
		if tree := tree_for(it, list); tree != nil {
			index: int
			index, best, met = collide.tree_cast(tree, from, to)
			if met {
				found = list.items[index]
			}
		} else {
			for item in list.items {
				s, is_shape := to_shape(it, item)
				if !is_shape {
					continue
				}
				if h, hit := collide.cast_shape(from, to, s); hit && (!met || h.at < best.at) {
					best, found, met = h, item, true
				}
			}
		}
		if !met {
			return make_result(it, e.type, nil) // empty: every field 0, and no item
		}
		d := to - from
		distance := best.at * math.sqrt(d.x * d.x + d.y * d.y)
		return make_result(it, e.type, {{"item", found}, {"point", vec2(best.point)}, {"normal", vec2(best.normal)}, {"distance", distance}})
	}
	return nil
}

// A record of the type the checker gave the call, its fields filled by name.
@(private = "file")
Named :: struct {
	name:  string,
	value: Value,
}

@(private = "file")
make_result :: proc(it: ^Interp, type: lang.Type_Id, fields: []Named) -> Value {
	shape := lang.shape_of(it.types, type)
	if shape < 0 {
		return nil
	}
	r := new_record(it, shape)
	for f in fields {
		if at := field_index(it, shape, f.name); at >= 0 {
			r.fields[at] = f.value
		}
	}
	return r
}

// A value as a collide shape: a vector is a point, a record what its class says.
@(private)
to_shape :: proc(it: ^Interp, v: Value, allocator := context.temp_allocator) -> (s: collide.Shape, ok: bool) {
	#partial switch x in v {
	case Vec:
		return collide.point({x.v[0], x.v[1]}), true
	case ^Record:
		if x == nil {
			return {}, false
		}
		switch x.class {
		case .None:
			return {}, false
		case .Polygon:
			list := as_list(read_field(it, x, "points"))
			if list == nil {
				return collide.polygon(nil), true
			}
			points := make([]collide.Vec, len(list.items), allocator)
			for p, i in list.items {
				points[i] = as_pair(p)
			}
			return collide.polygon(points), true
		case .Segment:
			return collide.segment(as_pair(read_field(it, x, "from")), as_pair(read_field(it, x, "to"))), true
		case .Circle:
			return collide.circle(as_pair(read_field(it, x, "pos")), as_number(read_field(it, x, "radius"))), true
		case .Box:
			return collide.box(as_pair(read_field(it, x, "pos")), as_pair(read_field(it, x, "size")), as_number(read_field(it, x, "angle"))), true
		}
	}
	return {}, false
}

// ---- the box trees of lists ----

// How many lists keep a box tree at once.
SHAPE_CACHE_SIZE :: 8

// A list the collision verbs were asked about: when it was read, and once it has
// been asked about twice without changing, the tree of its shapes. Checking one
// shape against a list once is cheaper than building a tree, so a tree is built
// only for a list that is asked again (a thousand particles against one list of
// walls). The tree and its shapes are on the heap, and freed when the entry goes.
Shape_Cache :: struct {
	list:   ^List,
	id:     u64, // the list's id, so memory used again for another list is never mistaken for it
	read:   u64, // `Interp.writes` when the list was last found changed
	used:   u64, // when it was last asked, to choose the entry to drop
	asked:  int, // how many times in a row it was asked unchanged
	built:  bool,
	tree:   collide.Tree,
	shapes: []collide.Shape,
}

// The tree of a list's shapes, or nil when checking each shape is the way this time.
@(private = "file")
tree_for :: proc(it: ^Interp, list: ^List) -> ^collide.Tree {
	now := next_write(it)
	entry: ^Shape_Cache
	for &e in it.shape_cache {
		if e.list == list && e.id == list.id {
			entry = &e
			break
		}
	}
	if entry != nil && unchanged(it, list, entry.read) {
		entry.used = now
		entry.asked += 1
		if !entry.built && entry.asked >= 2 {
			entry.shapes = make([]collide.Shape, len(list.items))
			for item, i in list.items {
				if s, ok := to_shape(it, item, context.allocator); ok {
					entry.shapes[i] = s
				} else {
					entry.shapes[i] = collide.polygon(nil) // touches nothing, and keeps the places
				}
			}
			entry.tree = collide.tree_build(entry.shapes)
			entry.built = true
		}
		return &entry.tree if entry.built else nil
	}
	if entry == nil {
		entry = &it.shape_cache[0]
		for &e in it.shape_cache {
			if e.used < entry.used {
				entry = &e
			}
		}
	}
	drop_entry(entry)
	entry^ = Shape_Cache{list = list, id = list.id, read = now, used = now, asked = 1}
	return nil
}

// Whether nothing in the list has changed since `read`: the list itself, any
// record in it, or the points of an outline.
@(private = "file")
unchanged :: proc(it: ^Interp, list: ^List, read: u64) -> bool {
	if list.stamp > read {
		return false
	}
	for item in list.items {
		if r := as_record(item); r != nil {
			if r.stamp > read {
				return false
			}
			if r.class == .Polygon {
				if points := as_list(read_field(it, r, "points")); points != nil && points.stamp > read {
					return false
				}
			}
		}
	}
	return true
}

drop_entry :: proc(e: ^Shape_Cache) {
	if e.built {
		for s in e.shapes {
			delete(s.points)
		}
		delete(e.shapes)
		collide.tree_destroy(&e.tree)
	}
	e^ = {}
}
