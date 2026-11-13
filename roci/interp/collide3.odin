// SPDX-License-Identifier: 0BSD
//
// The collision verbs for shapes in space: the same `touching contact hits inside cast` as in the
// plane (collide.odin), taken here when either side holds three numbers where it has places: a vector
// of three is a point, and a record is the shape its `{ }` made it, with `pos` (the middle) and `radius`
// a sphere, `pos`, `size` and `angle` (three turns, in degrees) a box, `from` and `to` a segment, `triangles` (three
// places for each) a mesh. A list asked about twice unchanged is kept as a tree of boxes
// (collide.Tree3), as in the plane.
package interp

import "../"
import "../collide"
import "../lang"
import "core:math"

// A place in space as a value.
vec3 :: proc(v: [3]f64) -> Vec {
	return Vec{n = 3, v = {v.x, v.y, v.z, 0}}
}

as_triple :: proc(v: Value) -> [3]f64 {
	if x, ok := v.(Vec); ok {
		return {x.v[0], x.v[1], x.v[2]}
	}
	return {}
}

// Whether a value is in space: a vector of three numbers, a record whose `pos`, `from` or `to` is one, or a
// list whose first item is.
@(private)
is_space :: proc(it: ^Interp, v: Value) -> bool {
	#partial switch x in v {
	case Vec:
		return x.n == 3
	case ^Record:
		if x == nil {
			return false
		}
		for name in ([?]string{"pos", "from", "to"}) {
			if p, is_vec := read_field(it, x, name).(Vec); is_vec {
				return p.n == 3
			}
		}
		if x.class == .Mesh {
			return true
		}
	case ^List:
		if x != nil && len(x.items) > 0 {
			return is_space(it, x.items[0])
		}
	}
	return false
}

// A value as a shape in space: a vector is a point, a record what its class says.
@(private)
to_shape3 :: proc(it: ^Interp, v: Value, allocator := context.temp_allocator) -> (s: collide.Shape3, ok: bool) {
	#partial switch x in v {
	case Vec:
		if x.n != 3 {
			return {}, false
		}
		return collide.point3(as_triple(x)), true
	case ^Record:
		if x == nil {
			return {}, false
		}
		switch x.class {
		case .None, .Polygon:
			return {}, false
		case .Mesh:
			list := as_list(read_field(it, x, "triangles"))
			if list == nil {
				return collide.mesh3(nil), true
			}
			corners := make([]collide.Vec3, len(list.items), allocator)
			for p, i in list.items {
				corners[i] = as_triple(p)
			}
			return collide.mesh3(corners), true
		case .Segment:
			return collide.segment3(as_triple(read_field(it, x, "from")), as_triple(read_field(it, x, "to"))), true
		case .Circle:
			return collide.sphere(as_triple(read_field(it, x, "pos")), as_number(read_field(it, x, "radius"))), true
		case .Box:
			return collide.box3(as_triple(read_field(it, x, "pos")), as_triple(read_field(it, x, "size")), as_triple(read_field(it, x, "angle"))), true
		}
	}
	return {}, false
}

@(private)
collision_verb3 :: proc(it: ^Interp, e: ^lang.IR, code: Verb_Code, a, b: Value) -> Value {
	#partial switch code {
	case .Touching:
		sa, ok_a := to_shape3(it, a)
		sb, ok_b := to_shape3(it, b)
		return ok_a && ok_b && collide.touching3(sa, sb)
	case .Inside:
		sb, ok := to_shape3(it, b)
		return ok && is_space(it, a) && collide.inside3(as_triple(a), sb)
	case .Contact:
		sa, ok_a := to_shape3(it, a)
		sb, ok_b := to_shape3(it, b)
		if !ok_a || !ok_b {
			return make_result(it, e.type, nil)
		}
		c, touching := collide.contact3(sa, sb)
		if !touching {
			return make_result(it, e.type, nil)
		}
		return make_result(it, e.type, {{"point", vec3(c.point)}, {"normal", vec3(c.normal)}, {"depth", c.depth}})
	case .Hits:
		out := new_list(it)
		sa, ok := to_shape3(it, a)
		list := as_list(b)
		if !ok || list == nil {
			return out
		}
		if tree := tree3_for(it, list); tree != nil {
			for i in collide.tree3_hits(tree, sa) {
				append(&out.items, list.items[i])
			}
			return out
		}
		box := collide.bounds3(sa)
		for item in list.items {
			if s, is_shape := to_shape3(it, item); is_shape && collide.bounds3_overlap(box, collide.bounds3(s)) && collide.touching3(sa, s) {
				append(&out.items, item)
			}
		}
		return out
	case .Cast:
		line := as_record(a)
		list := as_list(b)
		if line == nil || list == nil {
			return make_result(it, e.type, nil)
		}
		from, to := as_triple(read_field(it, line, "from")), as_triple(read_field(it, line, "to"))
		best: collide.Hit3
		found: Value
		met := false
		if tree := tree3_for(it, list); tree != nil {
			index: int
			index, best, met = collide.tree3_cast(tree, from, to)
			if met {
				found = list.items[index]
			}
		} else {
			for item in list.items {
				s, is_shape := to_shape3(it, item)
				if !is_shape {
					continue
				}
				if h, hit := collide.cast_shape3(from, to, s); hit && (!met || h.at < best.at) {
					best, found, met = h, item, true
				}
			}
		}
		if !met {
			return make_result(it, e.type, nil)
		}
		d := to - from
		distance := best.at * math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
		return make_result(it, e.type, {{"item", found}, {"point", vec3(best.point)}, {"normal", vec3(best.normal)}, {"distance", distance}})
	}
	return nil
}

// `ray pixel`: the line from the eye of the camera through a pixel, a record of `from` and `to` that
// `cast` takes as a line.
@(private)
ray_verb :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call) -> Value {
	spot := as_pair(eval(it, call.args[0]))
	from, to := roci.pixel_ray(spot.x, spot.y)
	result := make_result(it, e.type, {{"from", vec3(from)}, {"to", vec3(to)}})
	if record, ok := result.(^Record); ok && record != nil {
		record.class = .Segment
	}
	return result
}

// `triangles "hall.glb" at 0 0 0 size 500`: the corners of a model's triangles, three for each, as a list of
// vectors, placed and sized as `model` draws it, which makes a shape with `{ triangles: ... }`.
@(private)
triangles_verb :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call) -> Value {
	out := new_list(it)
	name := as_text(eval(it, call.args[0]))
	id := load_model(it, name, e.span)
	if id == 0 {
		return out
	}
	corners: [][3]f64
	if call.shape == 0 {
		corners = roci.model_triangles(id, as_number(eval(it, call.args[1])), as_number(eval(it, call.args[2])), as_number(eval(it, call.args[3])), as_number(eval(it, call.args[4])), context.temp_allocator)
	} else {
		at := as_triple(eval(it, call.args[1]))
		corners = roci.model_triangles(id, at.x, at.y, at.z, as_number(eval(it, call.args[2])), context.temp_allocator)
	}
	for corner in corners {
		append(&out.items, vec3(corner))
	}
	return out
}
