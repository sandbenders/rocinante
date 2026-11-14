// SPDX-License-Identifier: 0BSD
//
// The C functions for collision: `touching`, `contact`, `hits`, `inside` and `cast`, on shapes C
// describes with a `roci_shape` (a kind and the fields that kind uses), flat or in space as the
// language's records are, and trees of boxes kept for lists asked about again and again.
package roci

import "collide"
import "core:c"
import "core:math"

// The kinds of shape: the first five are flat, the others in space.
Abi_Shape_Kind :: enum c.int {
	Point,
	Circle,
	Box,
	Segment,
	Polygon,
	Point3,
	Sphere,
	Box3,
	Segment3,
	Mesh,
}

// A shape: `pos` is a point, a circle's or sphere's middle, a flat box's top left corner or a box's middle in space; `radius` is
// a circle's or sphere's; `size` a box's; `angle.x` a flat box's turn in degrees, and `angle` a box's turns about x, y and z in space;
// `from` and `to` a segment's ends; `points` and `count` a polygon's corners (x and y) or a mesh's triangles (three corners each).
Abi_Shape :: struct {
	kind:     c.int,
	pos:      Abi_Vec3,
	radius:   f64,
	size:     Abi_Vec3,
	angle:    Abi_Vec3,
	from, to: Abi_Vec3,
	points:   [^]Abi_Vec3,
	count:    c.int,
}

Abi_Contact :: struct {
	touching: c.int,
	point:    Abi_Vec3,
	normal:   Abi_Vec3,
	depth:    f64,
}

Abi_Cast :: struct {
	index:    c.int, // the item of the list the line meets first, or -1
	point:    Abi_Vec3,
	normal:   Abi_Vec3,
	distance: f64,
}

@(private)
abi_in_space :: proc(s: ^Abi_Shape) -> bool {
	return s != nil && s.kind >= c.int(Abi_Shape_Kind.Point3) && s.kind <= c.int(Abi_Shape_Kind.Mesh)
}

@(private)
abi_is_shape :: proc(s: ^Abi_Shape) -> bool {
	return s != nil && s.kind >= 0 && s.kind <= c.int(Abi_Shape_Kind.Mesh)
}

@(private)
abi_flat :: proc(s: ^Abi_Shape, allocator := context.temp_allocator) -> (shape: collide.Shape, ok: bool) {
	if s == nil {
		return {}, false
	}
	switch Abi_Shape_Kind(s.kind) {
	case .Point:  return collide.point({s.pos.x, s.pos.y}), true
	case .Circle: return collide.circle({s.pos.x, s.pos.y}, s.radius), true
	case .Box:    return collide.box({s.pos.x, s.pos.y}, {s.size.x, s.size.y}, s.angle.x), true
	case .Segment: return collide.segment({s.from.x, s.from.y}, {s.to.x, s.to.y}), true
	case .Polygon:
		count := int(max(s.count, 0)) if s.points != nil else 0
		corners := make([]collide.Vec, count, allocator)
		for i in 0 ..< count {
			corners[i] = {s.points[i].x, s.points[i].y}
		}
		return collide.polygon(corners), true
	case .Point3, .Sphere, .Box3, .Segment3, .Mesh:
	}
	return {}, false
}

@(private)
abi_spatial :: proc(s: ^Abi_Shape, allocator := context.temp_allocator) -> (shape: collide.Shape3, ok: bool) {
	if s == nil {
		return {}, false
	}
	switch Abi_Shape_Kind(s.kind) {
	case .Point3:   return collide.point3(vec3_from_abi(s.pos)), true
	case .Sphere:   return collide.sphere(vec3_from_abi(s.pos), s.radius), true
	case .Box3:     return collide.box3(vec3_from_abi(s.pos), vec3_from_abi(s.size), vec3_from_abi(s.angle)), true
	case .Segment3: return collide.segment3(vec3_from_abi(s.from), vec3_from_abi(s.to)), true
	case .Mesh:
		count := int(max(s.count, 0)) if s.points != nil else 0
		corners := make([]collide.Vec3, count, allocator)
		for i in 0 ..< count {
			corners[i] = vec3_from_abi(s.points[i])
		}
		return collide.mesh3(corners), true
	case .Point, .Circle, .Box, .Segment, .Polygon:
	}
	return {}, false
}

@(export, link_name = "roci_touching")
abi_touching :: proc "c" (a, b: ^Abi_Shape) -> c.int {
	context = abi_context()
	if abi_in_space(a) != abi_in_space(b) {
		return 0 // a flat shape and a shape in space never touch
	}
	if abi_in_space(a) {
		sa, ok_a := abi_spatial(a)
		sb, ok_b := abi_spatial(b)
		return 1 if ok_a && ok_b && collide.touching3(sa, sb) else 0
	}
	sa, ok_a := abi_flat(a)
	sb, ok_b := abi_flat(b)
	return 1 if ok_a && ok_b && collide.touching(sa, sb) else 0
}

// Where two shapes touch: `normal` is the direction to move the first one to part them and `depth` how far. Every field is 0
// when they are apart.
@(export, link_name = "roci_contact")
abi_contact :: proc "c" (a, b: ^Abi_Shape) -> Abi_Contact {
	context = abi_context()
	if abi_in_space(a) != abi_in_space(b) {
		return {}
	}
	if abi_in_space(a) {
		sa, ok_a := abi_spatial(a)
		sb, ok_b := abi_spatial(b)
		if !ok_a || !ok_b {
			return {}
		}
		found, touching := collide.contact3(sa, sb)
		if !touching {
			return {}
		}
		return {1, {found.point.x, found.point.y, found.point.z}, {found.normal.x, found.normal.y, found.normal.z}, found.depth}
	}
	sa, ok_a := abi_flat(a)
	sb, ok_b := abi_flat(b)
	if !ok_a || !ok_b {
		return {}
	}
	found, touching := collide.contact(sa, sb)
	if !touching {
		return {}
	}
	return {1, {found.point.x, found.point.y, 0}, {found.normal.x, found.normal.y, 0}, found.depth}
}

// Whether a point is inside a shape, edges included. The point is flat (its z unused) for a flat shape.
@(export, link_name = "roci_inside")
abi_inside :: proc "c" (point: Abi_Vec3, shape: ^Abi_Shape) -> c.int {
	context = abi_context()
	if abi_in_space(shape) {
		s, ok := abi_spatial(shape)
		return 1 if ok && collide.inside3(vec3_from_abi(point), s) else 0
	}
	s, ok := abi_flat(shape)
	return 1 if ok && collide.inside({point.x, point.y}, s) else 0
}

@(private)
abi_list_hits :: proc(a: ^Abi_Shape, list: [^]Abi_Shape, count: c.int, out: [^]c.int, capacity: c.int) -> c.int {
	if !abi_is_shape(a) || list == nil || count < 1 {
		return 0
	}
	total := 0
	space := abi_in_space(a)
	sa3: collide.Shape3
	sa: collide.Shape
	if space {
		sa3, _ = abi_spatial(a)
	} else {
		sa, _ = abi_flat(a)
	}
	for i in 0 ..< int(count) {
		item := &list[i]
		if !abi_is_shape(item) || abi_in_space(item) != space {
			continue
		}
		touching := false
		if space {
			other, ok := abi_spatial(item)
			touching = ok && collide.touching3(sa3, other)
		} else {
			other, ok := abi_flat(item)
			touching = ok && collide.touching(sa, other)
		}
		if touching {
			if out != nil && total < int(max(capacity, 0)) {
				out[total] = c.int(i)
			}
			total += 1
		}
	}
	return c.int(total)
}

// Which items of a list a shape touches: copies their places in the list (from 0, in list order) into `out` as far as
// `capacity` allows (it may be NULL) and gives how many there are. A flat shape touches only flat items and one in space only
// items in space.
@(export, link_name = "roci_hits")
abi_hits :: proc "c" (a: ^Abi_Shape, list: [^]Abi_Shape, count: c.int, out: [^]c.int, capacity: c.int) -> c.int {
	context = abi_context()
	return abi_list_hits(a, list, count, out, capacity)
}

@(private)
abi_cast_result :: proc(index: int, point, normal: [3]f64, at: f64, from, to: [3]f64) -> Abi_Cast {
	d := to - from
	return {c.int(index), {point.x, point.y, point.z}, {normal.x, normal.y, normal.z}, at * math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z)}
}

@(private)
abi_list_cast :: proc(from, to: Abi_Vec3, list: [^]Abi_Shape, count: c.int) -> Abi_Cast {
	none := Abi_Cast{index = -1}
	if list == nil || count < 1 {
		return none
	}
	// a line is flat when the first item is: the places are read as 2D then
	space := abi_in_space(&list[0])
	best := -1
	best_at := math.INF_F64
	best_point, best_normal: [3]f64
	for i in 0 ..< int(count) {
		item := &list[i]
		if !abi_is_shape(item) || abi_in_space(item) != space {
			continue
		}
		if space {
			s, ok := abi_spatial(item)
			if !ok {
				continue
			}
			if hit, found := collide.cast_shape3(vec3_from_abi(from), vec3_from_abi(to), s); found && hit.at < best_at {
				best, best_at, best_point, best_normal = i, hit.at, hit.point, hit.normal
			}
		} else {
			s, ok := abi_flat(item)
			if !ok {
				continue
			}
			if hit, found := collide.cast_shape({from.x, from.y}, {to.x, to.y}, s); found && hit.at < best_at {
				best, best_at, best_point, best_normal = i, hit.at, {hit.point.x, hit.point.y, 0}, {hit.normal.x, hit.normal.y, 0}
			}
		}
	}
	if best < 0 {
		return none
	}
	f, t := vec3_from_abi(from), vec3_from_abi(to)
	if !space {
		f.z, t.z = 0, 0
	}
	return abi_cast_result(best, best_point, best_normal, best_at, f, t)
}

// The first item of a list a line from `from` to `to` meets: its place in the list, the point, the normal out of the shape and
// how far along the line. `index` is -1 (and the rest 0) when it meets nothing. The line is flat when the first item is.
@(export, link_name = "roci_cast")
abi_cast :: proc "c" (from, to: Abi_Vec3, list: [^]Abi_Shape, count: c.int) -> Abi_Cast {
	context = abi_context()
	return abi_list_cast(from, to, list, count)
}

// ---- trees of boxes ----

@(private)
Abi_Tree :: struct {
	live:    bool,
	space:   bool,
	count:   int,
	shapes:  []collide.Shape,
	shapes3: []collide.Shape3,
	tree:    collide.Tree,
	tree3:   collide.Tree3,
}

@(private, thread_local)
abi_trees: [dynamic]Abi_Tree

@(private)
abi_tree_free :: proc(t: ^Abi_Tree) {
	if !t.live {
		return
	}
	for s in t.shapes {
		delete(s.points)
	}
	delete(t.shapes)
	collide.tree_destroy(&t.tree)
	for s in t.shapes3 {
		delete(s.triangles)
	}
	delete(t.shapes3)
	collide.tree3_destroy(&t.tree3)
	t^ = {}
}

// Builds a tree of boxes for a list of shapes, to ask about again and again; it answers what checking every shape answers, much
// faster for a long list. The shapes are copied. The list is flat when its first shape is, and its items of the other kind touch
// nothing. Gives the tree's number, or 0 for an empty list.
@(export, link_name = "roci_collision_tree")
abi_collision_tree :: proc "c" (list: [^]Abi_Shape, count: c.int) -> c.int {
	context = abi_context()
	if list == nil || count < 1 {
		return 0
	}
	space := abi_in_space(&list[0])
	tree := Abi_Tree{live = true, space = space, count = int(count)}
	if space {
		tree.shapes3 = make([]collide.Shape3, count)
		for i in 0 ..< int(count) {
			item := &list[i]
			if abi_in_space(item) {
				if s, ok := abi_spatial(item, context.allocator); ok {
					tree.shapes3[i] = s
					continue
				}
			}
			tree.shapes3[i] = collide.mesh3(nil) // touches nothing, and keeps the places
		}
		tree.tree3 = collide.tree3_build(tree.shapes3)
	} else {
		tree.shapes = make([]collide.Shape, count)
		for i in 0 ..< int(count) {
			item := &list[i]
			if abi_is_shape(item) && !abi_in_space(item) {
				if s, ok := abi_flat(item, context.allocator); ok {
					tree.shapes[i] = s
					continue
				}
			}
			tree.shapes[i] = collide.polygon(nil)
		}
		tree.tree = collide.tree_build(tree.shapes)
	}
	for &slot, i in abi_trees {
		if !slot.live {
			slot = tree
			return c.int(i + 1)
		}
	}
	append(&abi_trees, tree)
	return c.int(len(abi_trees))
}

@(export, link_name = "roci_tree_free")
abi_tree_release :: proc "c" (tree: c.int) {
	context = abi_context()
	if tree >= 1 && int(tree) <= len(abi_trees) {
		abi_tree_free(&abi_trees[tree - 1])
	}
}

// The items of a tree a shape touches, in list order, as roci_hits gives them.
@(export, link_name = "roci_tree_hits")
abi_tree_hits :: proc "c" (tree: c.int, a: ^Abi_Shape, out: [^]c.int, capacity: c.int) -> c.int {
	context = abi_context()
	if tree < 1 || int(tree) > len(abi_trees) || !abi_trees[tree - 1].live || !abi_is_shape(a) {
		return 0
	}
	t := &abi_trees[tree - 1]
	if abi_in_space(a) != t.space {
		return 0
	}
	found: []int
	if t.space {
		s, ok := abi_spatial(a)
		if !ok {
			return 0
		}
		found = collide.tree3_hits(&t.tree3, s)
	} else {
		s, ok := abi_flat(a)
		if !ok {
			return 0
		}
		found = collide.tree_hits(&t.tree, s)
	}
	if out != nil {
		for index, i in found[:min(len(found), int(max(capacity, 0)))] {
			out[i] = c.int(index)
		}
	}
	return c.int(len(found))
}

// The first item of a tree a line meets, as roci_cast gives it.
@(export, link_name = "roci_tree_cast")
abi_tree_cast :: proc "c" (tree: c.int, from, to: Abi_Vec3) -> Abi_Cast {
	context = abi_context()
	none := Abi_Cast{index = -1}
	if tree < 1 || int(tree) > len(abi_trees) || !abi_trees[tree - 1].live {
		return none
	}
	t := &abi_trees[tree - 1]
	if t.space {
		f, e := vec3_from_abi(from), vec3_from_abi(to)
		index, hit, found := collide.tree3_cast(&t.tree3, f, e)
		if !found {
			return none
		}
		return abi_cast_result(index, hit.point, hit.normal, hit.at, f, e)
	}
	index, hit, found := collide.tree_cast(&t.tree, {from.x, from.y}, {to.x, to.y})
	if !found {
		return none
	}
	return abi_cast_result(index, {hit.point.x, hit.point.y, 0}, {hit.normal.x, hit.normal.y, 0}, hit.at, {from.x, from.y, 0}, {to.x, to.y, 0})
}

// Lets go of the trees (`shutdown`).
@(private)
abi_collide_stop :: proc() {
	for &t in abi_trees {
		abi_tree_free(&t)
	}
	delete(abi_trees)
	abi_trees = nil
}

// The table rows of the functions above.
abi_collide_group :: proc(all: ^[dynamic]Abi_Entry) {
	append(all, abi_entry("roci_touching", typeid_of(type_of(abi_touching)), "int roci_touching(const roci_shape *a, const roci_shape *b)", "Whether two shapes touch, edges included. A flat shape and a shape in space never touch."))
	append(all, abi_entry("roci_contact", typeid_of(type_of(abi_contact)), "roci_contact_info roci_contact(const roci_shape *a, const roci_shape *b)", "Where two shapes touch: `normal` is the direction to move `a` to part them, `depth` how far, `point` a place where they touch. `touching` is 0, and every field 0, when they are apart."))
	append(all, abi_entry("roci_inside", typeid_of(type_of(abi_inside)), "int roci_inside(roci_vec3 point, const roci_shape *shape)", "Whether a point is inside a shape, edges included. The point's z is not used for a flat shape."))
	append(all, abi_entry("roci_hits", typeid_of(type_of(abi_hits)), "int roci_hits(const roci_shape *shape, const roci_shape *list, int count, int *out, int capacity)", "Which items of a list a shape touches: copies their places in the list (from 0, in list order) into `out` as far as `capacity` allows (it may be NULL) and gives how many there are. A flat shape touches only flat items, and one in space only items in space."))
	append(all, abi_entry("roci_cast", typeid_of(type_of(abi_cast)), "roci_cast_hit roci_cast(roci_vec3 from, roci_vec3 to, const roci_shape *list, int count)", "The first item of a list a line from `from` to `to` meets: its place in the list, the point, the normal out of the shape and how far along the line. `index` is -1 (and the rest 0) when it meets nothing. The line is flat when the first item is."))
	append(all, abi_entry("roci_collision_tree", typeid_of(type_of(abi_collision_tree)), "roci_tree_id roci_collision_tree(const roci_shape *list, int count)", "Builds a tree of boxes for a list of shapes to ask about again and again; it answers what checking every shape answers, much faster for a long list. The shapes are copied. The tree is flat when the first shape is, and items of the other kind touch nothing. Gives the tree's number, or 0 for an empty list."))
	append(all, abi_entry("roci_tree_free", typeid_of(type_of(abi_tree_release)), "void roci_tree_free(roci_tree_id tree)", "Lets a tree go."))
	append(all, abi_entry("roci_tree_hits", typeid_of(type_of(abi_tree_hits)), "int roci_tree_hits(roci_tree_id tree, const roci_shape *shape, int *out, int capacity)", "The items of a tree a shape touches, in list order, as roci_hits gives them."))
	append(all, abi_entry("roci_tree_cast", typeid_of(type_of(abi_tree_cast)), "roci_cast_hit roci_tree_cast(roci_tree_id tree, roci_vec3 from, roci_vec3 to)", "The first item of a tree a line meets, as roci_cast gives it."))
}
