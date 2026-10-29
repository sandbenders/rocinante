// SPDX-License-Identifier: 0BSD
//
// The broad phase: a tree of boxes over a list of shapes, so asking which of a
// thousand walls a particle touches looks at a few boxes instead of a thousand
// shapes. It is built once for a list and asked many times; it answers exactly
// what checking every shape would, in the same order (by place in the list).
package collide

import "core:math"
import "core:slice"

Tree :: struct {
	nodes:  [dynamic]Node,
	bounds: [dynamic]Bounds, // of each shape, by its place in the list
	order:  [dynamic]int,    // places in the list, grouped by leaf
	shapes: []Shape,
}

// A node holds either two children or a run of shapes (`first` and `count`
// into `order`).
@(private)
Node :: struct {
	box:         Bounds,
	left, right: int, // 0 for a leaf: the root is node 0, so no child is
	first:       int,
	count:       int,
}

@(private)
LEAF_SIZE :: 4

tree_destroy :: proc(t: ^Tree) {
	delete(t.nodes)
	delete(t.bounds)
	delete(t.order)
	t^ = {}
}

// Builds the tree over `shapes`, which must stay as they are while it is used.
// Splits are made at the middle of the longest side, ordering by centre and then
// by place in the list, so the same shapes always give the same tree.
tree_build :: proc(shapes: []Shape, allocator := context.allocator) -> Tree {
	t := Tree{shapes = shapes}
	t.nodes = make([dynamic]Node, allocator)
	t.bounds = make([dynamic]Bounds, 0, len(shapes), allocator)
	t.order = make([dynamic]int, 0, len(shapes), allocator)
	for s, i in shapes {
		append(&t.bounds, bounds(s))
		append(&t.order, i)
	}
	if len(shapes) > 0 {
		append(&t.nodes, Node{})
		build_node(&t, 0, 0, len(shapes))
	}
	return t
}

@(private)
build_node :: proc(t: ^Tree, node, first, count: int) {
	box := t.bounds[t.order[first]]
	for i in first + 1 ..< first + count {
		b := t.bounds[t.order[i]]
		box = {{min(box.low.x, b.low.x), min(box.low.y, b.low.y)}, {max(box.high.x, b.high.x), max(box.high.y, b.high.y)}}
	}
	t.nodes[node].box = box
	if count <= LEAF_SIZE {
		t.nodes[node].first, t.nodes[node].count = first, count
		return
	}
	axis := 0 if box.high.x - box.low.x >= box.high.y - box.low.y else 1
	context.user_ptr = t
	context.user_index = axis
	slice.sort_by(t.order[first:first + count], proc(a, b: int) -> bool {
		t := (^Tree)(context.user_ptr)
		axis := context.user_index
		ca := t.bounds[a].low[axis] + t.bounds[a].high[axis]
		cb := t.bounds[b].low[axis] + t.bounds[b].high[axis]
		if ca != cb && !math.is_nan(ca) && !math.is_nan(cb) {
			return ca < cb
		}
		return a < b
	})
	half := count / 2
	left := len(t.nodes)
	append(&t.nodes, Node{}, Node{})
	t.nodes[node].left, t.nodes[node].right = left, left + 1
	build_node(t, left, first, half)
	build_node(t, left + 1, first + half, count - half)
}

// The places of the shapes whose boxes meet `box`, smallest first.
tree_query :: proc(t: ^Tree, box: Bounds, allocator := context.temp_allocator) -> []int {
	out := make([dynamic]int, allocator)
	if len(t.nodes) == 0 {
		return out[:]
	}
	stack := make([dynamic]int, context.temp_allocator)
	append(&stack, 0)
	for len(stack) > 0 {
		n := t.nodes[pop(&stack)]
		if !bounds_overlap(n.box, box) {
			continue
		}
		if n.left == 0 {
			for i in n.first ..< n.first + n.count {
				if bounds_overlap(t.bounds[t.order[i]], box) {
					append(&out, t.order[i])
				}
			}
		} else {
			append(&stack, n.right, n.left)
		}
	}
	slice.sort(out[:])
	return out[:]
}

// The places of the shapes that touch `s`, smallest first.
tree_hits :: proc(t: ^Tree, s: Shape, allocator := context.temp_allocator) -> []int {
	out := make([dynamic]int, allocator)
	for i in tree_query(t, bounds(s)) {
		if touching(s, t.shapes[i]) {
			append(&out, i)
		}
	}
	return out[:]
}

// The first shape the line from `from` to `to` meets: its place and the hit.
// Of shapes met at the same point along the line, the first in the list.
tree_cast :: proc(t: ^Tree, from, to: Vec) -> (index: int, h: Hit, ok: bool) {
	line := Bounds{{min(from.x, to.x), min(from.y, to.y)}, {max(from.x, to.x), max(from.y, to.y)}}
	h.at = math.INF_F64
	for i in tree_query(t, line) {
		if found, hit := cast_shape(from, to, t.shapes[i]); hit && found.at < h.at {
			index, h, ok = i, found, true
		}
	}
	return
}
