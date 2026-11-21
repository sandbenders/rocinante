// SPDX-License-Identifier: 0BSD
//
// `mesh corners` draws a list of vectors of three numbers as the triangles of a mesh, three corners for each, flat
// shaded or (`as wireframe`) as its edges. What the graphics card holds for a mesh is kept under the call that
// draws it: its place in the sketch and, when one call draws several (in a loop), which time it was in the frame.
package interp

import "../"
import "../lang"
import "core:fmt"

// How many meshes each call has drawn in the frame `frame`.
Mesh_Calls :: struct {
	frame:  int,
	counts: map[string]int,
}

@(private)
mesh_verb :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call) {
	list := as_list(eval(it, call.args[0]))
	if list == nil || len(list.items) < 3 {
		return
	}
	corners := make([dynamic][3]f64, 0, len(list.items), context.temp_allocator)
	for item in list.items {
		append(&corners, as_triple(item))
	}
	wireframe := false
	if word, found := option_value(it, call.options, "as"); found {
		wireframe = as_text(word) == "wireframe"
	}
	look, _ := make_look(it, call.options)
	frame := roci.frame_count()
	if it.mesh_calls.counts == nil {
		it.mesh_calls.counts = make(map[string]int)
	}
	if it.mesh_calls.frame != frame {
		clear(&it.mesh_calls.counts)
		it.mesh_calls.frame = frame
	}
	site := fmt.tprintf("mesh:%d:%d:%d", e.span.file, e.span.start, e.span.end)
	n := it.mesh_calls.counts[site]
	it.mesh_calls.counts[site] = n + 1
	roci.mesh(fmt.tprintf("%s:%d", site, n), corners[:], wireframe, look)
}

// `polygon [ ... ]`: the corners are a list of vectors, or a list of such lists, which are the contours of one
// shape (a list inside another is a hole).
@(private)
polygon_verb :: proc(it: ^Interp, call: lang.IR_Call) {
	contours := polygon_contours(it, call)
	if len(contours) == 0 {
		return
	}
	look := &NO_LOOK
	own_look: roci.Look
	origin: roci.Origin
	if len(call.options) > 0 {
		own_look, origin = make_look(it, call.options)
		look = &own_look
	}
	roci.polygons(contours[:], look^)
}

@(private)
drop_meshes :: proc(it: ^Interp) {
	delete(it.mesh_calls.counts)
	it.mesh_calls = {}
}

// The contours of a `polygon` or a `clip polygon`: one list of corners, or a list of such lists. Nothing for an empty list.
@(private)
polygon_contours :: proc(it: ^Interp, call: lang.IR_Call) -> [][][2]f64 {
	list := as_list(eval(it, call.args[0]))
	if list == nil || len(list.items) == 0 {
		return nil
	}
	contours := make([dynamic][][2]f64, 0, 4, context.temp_allocator)
	if _, nested := list.items[0].(^List); nested {
		for item in list.items {
			inner := as_list(item)
			if inner == nil {
				continue
			}
			corners := make([dynamic][2]f64, 0, len(inner.items), context.temp_allocator)
			for corner in inner.items {
				append(&corners, as_pair(corner))
			}
			append(&contours, corners[:])
		}
	} else {
		corners := make([dynamic][2]f64, 0, len(list.items), context.temp_allocator)
		for item in list.items {
			append(&corners, as_pair(item))
		}
		append(&contours, corners[:])
	}
	return contours[:]
}
