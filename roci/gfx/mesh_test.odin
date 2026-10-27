// SPDX-License-Identifier: 0BSD
package gfx

import "../geom"
import "../maths"
import "core:math"
import "core:testing"

// The area covered by the triangles of a mesh, on the canvas.
mesh_area :: proc(m: Mesh) -> f64 {
	sum := 0.0
	for i := 0; i < len(m.indices); i += 3 {
		a, b, c := m.vertices[m.indices[i]].position, m.vertices[m.indices[i + 1]].position, m.vertices[m.indices[i + 2]].position
		sum += f64((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)) / 2
	}
	return sum
}

// A command drawn on its own through a list, as a mesh.
mesh_of :: proc(setup: proc(list: ^Command_List)) -> Mesh {
	list := fresh()
	defer destroy(&list)
	setup(&list)
	m: Mesh
	for c in list.commands {
		mesh_add_command(&m, c)
	}
	return m
}

// ---- which commands need a mesh ----

@(test)
test_quads_and_arcs_always_need_a_mesh_and_circles_and_ellipses_never_do :: proc(t: ^testing.T) {
	for join in geom.Join {
		for cap in geom.Cap {
			for stroke in ([?]bool{false, true}) {
				style := DEFAULT_STYLE
				style.join, style.cap, style.stroke_on = join, cap, stroke
				testing.expect(t, needs_mesh(Command{kind = .Quad, style = style}))
				testing.expect(t, needs_mesh(Command{kind = .Arc, style = style}))
				testing.expect(t, !needs_mesh(Command{kind = .Circle, style = style}))
				testing.expect(t, !needs_mesh(Command{kind = .Ellipse, style = style}))
			}
		}
	}
}

@(test)
test_rects_and_triangles_need_a_mesh_only_for_corners_the_shader_cannot_draw :: proc(t: ^testing.T) {
	for kind in ([?]Kind{.Rect, .Triangle}) {
		style := DEFAULT_STYLE
		testing.expect(t, !needs_mesh(Command{kind = kind, style = style}), "no outline")
		style.stroke_on = true
		style.join = .Round
		testing.expect(t, !needs_mesh(Command{kind = kind, style = style}), "round corners are what the shader makes")
		style.join = .Miter
		testing.expect(t, needs_mesh(Command{kind = kind, style = style}), "mitred corners")
		style.join = .Bevel
		testing.expect(t, needs_mesh(Command{kind = kind, style = style}), "bevelled corners")
		style.thickness = 0
		testing.expect(t, !needs_mesh(Command{kind = kind, style = style}), "an outline of no width has no corners")
	}
}

@(test)
test_lines_and_points_need_a_mesh_unless_their_ends_are_round :: proc(t: ^testing.T) {
	for kind in ([?]Kind{.Line, .Point}) {
		for cap in geom.Cap {
			style := DEFAULT_STYLE
			style.cap = cap
			testing.expect_value(t, needs_mesh(Command{kind = kind, style = style}), cap != .Round)
		}
	}
}

@(test)
test_a_butt_capped_point_draws_nothing :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_stroke(&list, maths.grey(0))
	set_thickness(&list, 6)
	set_caps(&list, .Butt)
	point(&list, 5, 5)
	set_caps(&list, .Square)
	point(&list, 5, 5)
	testing.expect(t, !is_visible(list.commands[0]))
	testing.expect(t, is_visible(list.commands[1]))
}

// ---- the style words ----

@(test)
test_caps_and_joins_default_to_processings_round_and_miter :: proc(t: ^testing.T) {
	testing.expect_value(t, DEFAULT_STYLE.cap, geom.Cap.Round)
	testing.expect_value(t, DEFAULT_STYLE.join, geom.Join.Miter)
}

@(test)
test_caps_and_joins_are_recorded_scoped_and_hashed :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	push(&list, .Style)
	set_caps(&list, .Square)
	set_joins(&list, .Bevel)
	line(&list, 0, 0, 1, 1)
	pop(&list)
	line(&list, 0, 0, 1, 1)
	testing.expect_value(t, list.commands[0].style.cap, geom.Cap.Square)
	testing.expect_value(t, list.commands[0].style.join, geom.Join.Bevel)
	testing.expect_value(t, list.commands[1].style.cap, geom.Cap.Round)
	testing.expect(t, command_hash(list.commands[0]) != command_hash(list.commands[1]))
	begin_frame(&list)
	testing.expect_value(t, list.style.cap, geom.Cap.Round)
}

// ---- the triangles ----

@(test)
test_a_quad_fills_its_area :: proc(t: ^testing.T) {
	m := mesh_of(proc(list: ^Command_List) {
		set_fill(list, maths.rgb(255, 0, 0))
		quad(list, 0, 0, 10, 0, 10, 10, 0, 10)
	})
	defer mesh_destroy(&m)
	testing.expect_value(t, len(m.indices), 6)
	testing.expect(t, math.abs(mesh_area(m) - 100) < 1e-4)
	for v in m.vertices {
		testing.expect_value(t, v.colour, [4]f32{1, 0, 0, 1})
	}
}

@(test)
test_a_concave_quad_is_filled_without_covering_the_notch :: proc(t: ^testing.T) {
	m := mesh_of(proc(list: ^Command_List) {quad(list, 0, 0, 10, 0, 5, 3, 0, 10)}) // an arrowhead
	defer mesh_destroy(&m)
	want := 0.5 * abs(f64(10 * 3 - 0) + f64(5 * 10 - 10 * 3) + f64(0)) // shoelace of the four points
	_ = want
	testing.expect(t, mesh_area(m) > 0)
	// The four points (0,0) (10,0) (5,3) (0,10): shoelace area.
	shoelace := geom.signed_area({{0, 0}, {10, 0}, {5, 3}, {0, 10}})
	testing.expect(t, math.abs(mesh_area(m) - abs(shoelace)) < 1e-4)
}

@(test)
test_the_transform_moves_the_triangles_onto_the_canvas :: proc(t: ^testing.T) {
	m := mesh_of(proc(list: ^Command_List) {
		move(list, 100, 50)
		grow(list, 2, 2)
		quad(list, 0, 0, 10, 0, 10, 10, 0, 10)
	})
	defer mesh_destroy(&m)
	testing.expect(t, math.abs(mesh_area(m) - 400) < 1e-3)
	for v in m.vertices {
		testing.expect(t, v.position.x >= 100 && v.position.x <= 120 && v.position.y >= 50 && v.position.y <= 70)
	}
}

@(test)
test_a_mitred_rect_outline_has_square_corners :: proc(t: ^testing.T) {
	m := mesh_of(proc(list: ^Command_List) {
		no_fill(list)
		set_stroke(list, maths.grey(0))
		set_thickness(list, 2)
		rect(list, 0, 0, 10, 10) // join defaults to miter
	})
	defer mesh_destroy(&m)
	// The ring between a 12 x 12 outside and an 8 x 8 inside.
	testing.expect(t, math.abs(mesh_area(m) - 80) < 1e-3)
}

@(test)
test_a_bevelled_rect_outline_loses_its_corners :: proc(t: ^testing.T) {
	m := mesh_of(proc(list: ^Command_List) {
		no_fill(list)
		set_stroke(list, maths.grey(0))
		set_thickness(list, 2)
		set_joins(list, .Bevel)
		rect(list, 0, 0, 10, 10)
	})
	defer mesh_destroy(&m)
	testing.expect(t, math.abs(mesh_area(m) - (80 - 4 * 0.5)) < 1e-3)
}

@(test)
test_the_outline_is_drawn_after_the_fill_and_in_its_own_colour :: proc(t: ^testing.T) {
	m := mesh_of(proc(list: ^Command_List) {
		set_fill(list, maths.rgb(255, 255, 0))
		set_stroke(list, maths.rgb(0, 0, 255))
		set_thickness(list, 2)
		rect(list, 0, 0, 10, 10)
	})
	defer mesh_destroy(&m)
	testing.expect_value(t, m.vertices[m.indices[0]].colour, [4]f32{1, 1, 0, 1})
	last := m.vertices[m.indices[len(m.indices) - 1]]
	testing.expect_value(t, last.colour, [4]f32{0, 0, 1, 1})
}

@(test)
test_alpha_reaches_the_vertices :: proc(t: ^testing.T) {
	m := mesh_of(proc(list: ^Command_List) {
		set_alpha(list, 51)
		quad(list, 0, 0, 1, 0, 1, 1, 0, 1)
	})
	defer mesh_destroy(&m)
	testing.expect(t, math.abs(f64(m.vertices[0].colour.a) - 0.2) < 1e-6)
}

@(test)
test_an_outline_is_as_thick_as_the_style_says_and_follows_the_transform :: proc(t: ^testing.T) {
	m := mesh_of(proc(list: ^Command_List) {
		set_stroke(list, maths.grey(0))
		set_thickness(list, 4)
		set_caps(list, .Butt)
		grow(list, 3, 3)
		line(list, 0, 0, 10, 0)
	})
	defer mesh_destroy(&m)
	// 10 long and 4 wide in its own space, then 3 times bigger each way.
	testing.expect(t, math.abs(mesh_area(m) - 10 * 4 * 9) < 1e-2)
}

@(test)
test_line_caps_change_the_length :: proc(t: ^testing.T) {
	area :: proc(cap: geom.Cap) -> f64 {
		list := fresh()
		defer destroy(&list)
		set_stroke(&list, maths.grey(0))
		set_thickness(&list, 4)
		set_caps(&list, cap)
		line(&list, 0, 0, 10, 0)
		m: Mesh
		defer mesh_destroy(&m)
		mesh_add_command(&m, list.commands[0])
		return mesh_area(m)
	}
	testing.expect(t, math.abs(area(.Butt) - 40) < 1e-3)
	testing.expect(t, math.abs(area(.Square) - 56) < 1e-3)
	testing.expect(t, math.abs(area(.Round) - (40 + math.PI * 4)) < 1.0, "the polygon is inside the true half circles")
}

@(test)
test_a_square_capped_point_is_a_square :: proc(t: ^testing.T) {
	m := mesh_of(proc(list: ^Command_List) {
		set_stroke(list, maths.grey(0))
		set_thickness(list, 6)
		set_caps(list, .Square)
		point(list, 20, 20)
	})
	defer mesh_destroy(&m)
	testing.expect(t, math.abs(mesh_area(m) - 36) < 1e-3)
}

@(test)
test_a_whole_arc_is_an_ellipse_and_a_part_is_a_slice_of_pie :: proc(t: ^testing.T) {
	area :: proc(start, stop: f32) -> f64 {
		list := fresh()
		defer destroy(&list)
		arc(&list, 0, 0, 20, 20, start, stop)
		m: Mesh
		defer mesh_destroy(&m)
		mesh_add_command(&m, list.commands[0])
		return mesh_area(m)
	}
	// The polyline stays inside the true curve by up to a tenth of a pixel, so the
	// area is a little short; a few per cent covers it.
	disc := math.PI * 100
	close :: proc(got, want: f64) -> bool {
		return got < want && got > want * 0.95
	}
	testing.expect(t, close(area(0, 360), disc), "the whole ellipse")
	testing.expect(t, close(area(0, 90), disc / 4), "a quarter")
	testing.expect(t, close(area(0, 180), disc / 2), "half")
	testing.expect(t, close(area(0, 270), disc * 0.75), "three quarters: the pie is concave")
	testing.expect(t, close(area(300, 60), disc / 3), "across the right, the long way round from 300 to 60")
	testing.expect(t, area(30, 30) == 0, "no sweep")
}

@(test)
test_an_arc_outline_follows_the_curve_only :: proc(t: ^testing.T) {
	m := mesh_of(proc(list: ^Command_List) {
		no_fill(list)
		set_stroke(list, maths.grey(0))
		set_thickness(list, 2)
		set_caps(list, .Butt)
		arc(list, 0, 0, 20, 20, 0, 90)
	})
	defer mesh_destroy(&m)
	// A quarter of a ring from radius 9 to 11: (121 - 81) pi / 4.
	testing.expect(t, math.abs(mesh_area(m) - (121 - 81) * math.PI / 4) < 0.5)
}

@(test)
test_an_arc_with_origin_corner_is_centred_half_its_size_in :: proc(t: ^testing.T) {
	m := mesh_of(proc(list: ^Command_List) {arc(list, 0, 0, 20, 20, 0, 360, .Corner)})
	defer mesh_destroy(&m)
	lo_x, hi_x := f32(1e9), f32(-1e9)
	for v in m.vertices {
		lo_x, hi_x = min(lo_x, v.position.x), max(hi_x, v.position.x)
	}
	testing.expect(t, math.abs(f64(lo_x)) < 0.3 && math.abs(f64(hi_x) - 20) < 0.3, "spans 0 to 20, as a circle whose top left is at the position")
}

@(test)
test_commands_that_flatten_to_nothing_add_nothing :: proc(t: ^testing.T) {
	m: Mesh
	defer mesh_destroy(&m)
	list := fresh()
	defer destroy(&list)
	grow(&list, 0, 0) // every point lands on one spot
	quad(&list, 0, 0, 10, 0, 10, 10, 0, 10)
	mesh_add_command(&m, list.commands[0])
	testing.expect_value(t, len(m.indices), 0)
	// A quad with no area and no outline.
	begin_frame(&list)
	quad(&list, 3, 3, 3, 3, 3, 3, 3, 3)
	mesh_add_command(&m, list.commands[0])
	testing.expect_value(t, len(m.indices), 0)
}

@(test)
test_the_batcher_counts_mesh_triangles_and_keeps_painting_order :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	circle(&list, 0, 0, 5)
	quad(&list, 0, 0, 10, 0, 10, 10, 0, 10)
	quad(&list, 0, 0, 10, 0, 10, 10, 0, 10)
	circle(&list, 0, 0, 5)
	b: Batcher
	defer batcher_destroy(&b)
	build(&b, &list)
	testing.expect_value(t, len(b.batches), 3)
	testing.expect_value(t, b.batches[1].pipeline, Pipeline.Paths)
	testing.expect_value(t, b.batches[1].count, 12) // two quads of two triangles
	testing.expect_value(t, b.stats.mesh_triangles, 4)
	testing.expect_value(t, b.stats.path_commands, 2)
	testing.expect_value(t, b.stats.instances, 2)
}

@(test)
test_a_command_that_makes_no_triangles_is_skipped_by_the_batcher :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	quad(&list, 3, 3, 3, 3, 3, 3, 3, 3)
	b: Batcher
	defer batcher_destroy(&b)
	build(&b, &list)
	testing.expect_value(t, len(b.batches), 0)
	testing.expect_value(t, b.stats.skipped, 1)
}

@(test)
test_the_vertex_is_24_bytes :: proc(t: ^testing.T) {
	testing.expect_value(t, size_of(Mesh_Vertex), 24)
}

@(test)
test_every_index_is_in_range_and_every_triangle_is_finite :: proc(t: ^testing.T) {
	m := mesh_of(proc(list: ^Command_List) {
		set_stroke(list, maths.grey(0))
		set_thickness(list, 3)
		quad(list, 0, 0, 40, 5, 30, 40, 5, 30)
		arc(list, 50, 50, 40, 30, 20, 300)
		triangle(list, 0, 0, 10, 0, 5, 9)
		rect(list, 1, 1, 8, 8)
		line(list, 0, 0, 9, 9)
		point(list, 4, 4)
	})
	defer mesh_destroy(&m)
	for index in m.indices {
		testing.expect(t, int(index) < len(m.vertices))
	}
	for v in m.vertices {
		testing.expect(t, !math.is_nan(v.position.x) && !math.is_inf(v.position.x) && !math.is_nan(v.position.y))
	}
}
