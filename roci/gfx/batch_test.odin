// SPDX-License-Identifier: 0BSD
package gfx

import "../maths"
import "core:math"
import "core:testing"

// ---- describe ----

@(test)
test_a_circle_describes_its_box_and_colour :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_fill(&list, maths.rgb(255, 128, 0))
	circle(&list, 100, 50, 10)
	d := describe(list.commands[0])
	testing.expect_value(t, d.kind, Kind.Circle)
	testing.expect_value(t, d.x, f32(90))
	testing.expect_value(t, d.y, f32(40))
	testing.expect_value(t, d.width, f32(20))
	testing.expect_value(t, d.height, f32(20))
	testing.expect_value(t, d.colour, maths.Colour{255, 128, 0, 255})
	testing.expect(t, d.visible)
}

@(test)
test_origin_moves_the_described_box :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	rect(&list, 100, 100, 40, 20)
	rect(&list, 100, 100, 40, 20, .Center)
	circle(&list, 100, 100, 10, .Corner)
	ellipse(&list, 100, 100, 40, 20)
	ellipse(&list, 100, 100, 40, 20, .Corner)
	testing.expect_value(t, describe(list.commands[0]).x, f32(100))
	testing.expect_value(t, describe(list.commands[1]).x, f32(80))
	testing.expect_value(t, describe(list.commands[1]).y, f32(90))
	testing.expect_value(t, describe(list.commands[2]).x, f32(100))
	testing.expect_value(t, describe(list.commands[3]).x, f32(80)) // an ellipse is centred, as in Processing
	testing.expect_value(t, describe(list.commands[3]).y, f32(90))
	testing.expect_value(t, describe(list.commands[4]).x, f32(100))
}

@(test)
test_the_transform_is_applied_to_the_described_box :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	move(&list, 10, 20)
	grow(&list, 2, 2)
	rect(&list, 1, 1, 5, 5)
	d := describe(list.commands[0])
	testing.expect_value(t, d.x, f32(12))
	testing.expect_value(t, d.y, f32(22))
	testing.expect_value(t, d.width, f32(10))
	// A quarter turn swaps the sides of the upright box.
	begin_frame(&list)
	turn(&list, 90)
	rect(&list, 0, 0, 40, 10)
	d = describe(list.commands[0])
	testing.expect_value(t, d.width, f32(10))
	testing.expect_value(t, d.height, f32(40))
}

@(test)
test_every_kind_has_a_box_and_a_name :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	line(&list, 10, 40, 30, 20)
	point(&list, 5, 6)
	triangle(&list, 0, 0, 10, 0, 5, 8)
	quad(&list, 1, 1, 9, 2, 8, 9, 2, 7)
	arc(&list, 5, 5, 20, 10, 0, 90)
	ellipse(&list, 0, 0, 6, 4)
	boxes := [?][4]f32{{10, 20, 20, 20}, {5, 6, 0, 0}, {0, 0, 10, 8}, {1, 1, 8, 8}, {-5, 0, 20, 10}, {-3, -2, 6, 4}}
	for box, i in boxes {
		d := describe(list.commands[i])
		testing.expect_value(t, [4]f32{d.x, d.y, d.width, d.height}, box)
	}
	for kind in Kind {
		testing.expect(t, kind_name(kind) != "")
	}
	testing.expect_value(t, kind_name(.Rect), "rectangle")
}

@(test)
test_a_line_and_a_point_take_their_colour_from_the_stroke :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_stroke(&list, maths.rgb(1, 2, 3))
	line(&list, 0, 0, 5, 5)
	testing.expect_value(t, describe(list.commands[0]).colour, maths.Colour{1, 2, 3, 255})
	// A shape with no fill shows its stroke colour; with neither it has none.
	no_fill(&list)
	circle(&list, 0, 0, 5)
	testing.expect_value(t, describe(list.commands[1]).colour, maths.Colour{1, 2, 3, 255})
	no_stroke(&list)
	circle(&list, 0, 0, 5)
	testing.expect_value(t, describe(list.commands[2]).colour, maths.Colour{})
}

@(test)
test_a_shape_with_no_area_has_nothing_to_fill :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	circle(&list, 5, 5, 0)                  // 0
	rect(&list, 5, 5, 0, 10)                // 1
	rect(&list, 5, 5, 10, 0)                // 2
	ellipse(&list, 5, 5, 0, 0)              // 3
	arc(&list, 5, 5, 0, 4, 0, 90)           // 4
	triangle(&list, 0, 0, 5, 5, 10, 10)     // 5: the points are in a line
	triangle(&list, 0, 0, 5, 5, 5, 5)       // 6: two points are the same
	quad(&list, 3, 3, 3, 3, 3, 3, 3, 3)     // 7
	circle(&list, 5, 5, 0.1)                // 8: tiny, but it has area
	triangle(&list, 0, 0, 10, 0, 0, 10)     // 9
	rect(&list, 5, 5, 3, 4)                 // 10
	for i in 0 ..< 8 {
		testing.expectf(t, !has_area(list.commands[i]), "command %d", i)
		testing.expectf(t, !is_visible(list.commands[i]), "command %d is filled but has no area", i)
	}
	for i in 8 ..< 11 {
		testing.expectf(t, has_area(list.commands[i]), "command %d", i)
		testing.expectf(t, is_visible(list.commands[i]), "command %d", i)
	}
	// With an outline, a shape with no area still shows.
	set_stroke(&list, maths.grey(0))
	circle(&list, 5, 5, 0)
	testing.expect(t, is_visible(list.commands[len(list.commands) - 1]))
	// Lines and points never have an area; they are drawn by their stroke.
	line(&list, 0, 0, 1, 1)
	point(&list, 0, 0)
	testing.expect(t, !has_area(list.commands[len(list.commands) - 1]))
	testing.expect(t, !has_area(list.commands[len(list.commands) - 2]))
}

@(test)
test_visibility_rules :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	circle(&list, 0, 0, 5)                  // 0: filled: visible
	no_fill(&list)
	circle(&list, 0, 0, 5)                  // 1: no fill, no stroke: invisible
	set_stroke(&list, maths.grey(0))
	circle(&list, 0, 0, 5)                  // 2: outline only: visible
	set_thickness(&list, 0)
	circle(&list, 0, 0, 5)                  // 3: outline of no width: invisible
	set_thickness(&list, 2)
	line(&list, 0, 0, 5, 5)                 // 4: line with stroke: visible
	no_stroke(&list)
	line(&list, 0, 0, 5, 5)                 // 5: line without: invisible
	set_fill(&list, maths.grey(0))
	line(&list, 0, 0, 5, 5)                 // 6: a fill does not draw a line
	point(&list, 1, 1)                      // 7: nor a point
	set_alpha(&list, 0)
	circle(&list, 0, 0, 5)                  // 8: fully transparent: invisible
	want := [?]bool{true, false, true, false, true, false, false, false, false}
	for w, i in want {
		testing.expectf(t, is_visible(list.commands[i]) == w, "command %d", i)
	}
}

// ---- hashes ----

@(test)
test_hashes_repeat_and_react_to_every_part_of_a_command :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	circle(&list, 1, 2, 3)
	circle(&list, 1, 2, 3)
	base := command_hash(list.commands[0])
	testing.expect_value(t, command_hash(list.commands[1]), base)

	changed := list.commands[0]
	changed.args[0] = 1.5
	testing.expect(t, command_hash(changed) != base, "args")
	changed = list.commands[0]
	changed.kind = .Ellipse
	testing.expect(t, command_hash(changed) != base, "kind")
	changed = list.commands[0]
	changed.origin = .Corner
	testing.expect(t, command_hash(changed) != base, "origin")
	changed = list.commands[0]
	changed.transform.e = 1
	testing.expect(t, command_hash(changed) != base, "transform")
	changed = list.commands[0]
	changed.style.fill.r = 1
	testing.expect(t, command_hash(changed) != base, "fill")
	changed = list.commands[0]
	changed.style.stroke_on = true
	testing.expect(t, command_hash(changed) != base, "stroke switch")
	changed = list.commands[0]
	changed.style.thickness = 2
	testing.expect(t, command_hash(changed) != base, "thickness")
	changed = list.commands[0]
	changed.style.alpha = 10
	testing.expect(t, command_hash(changed) != base, "alpha")
}

@(test)
test_the_source_span_does_not_change_the_hash :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	circle(&list, 1, 2, 3)
	list.span = Span{1, 9, 9, 9}
	circle(&list, 1, 2, 3)
	testing.expect_value(t, command_hash(list.commands[0]), command_hash(list.commands[1]))
}

@(test)
test_zero_and_negative_zero_hash_differently :: proc(t: ^testing.T) {
	testing.expect(t, hash_f32(FNV_OFFSET, 0) != hash_f32(FNV_OFFSET, math.copy_sign(f32(0), -1)))
}

@(test)
test_a_pair_hash_tells_the_two_floats_and_their_order_apart :: proc(t: ^testing.T) {
	base := hash_f32_pair(FNV_OFFSET, 1, 2)
	testing.expect_value(t, hash_f32_pair(FNV_OFFSET, 1, 2), base)
	testing.expect(t, hash_f32_pair(FNV_OFFSET, 2, 1) != base, "order")
	testing.expect(t, hash_f32_pair(FNV_OFFSET, 1, 3) != base, "second")
	testing.expect(t, hash_f32_pair(FNV_OFFSET, 0, 2) != base, "first")
	testing.expect(t, hash_f32_pair(FNV_OFFSET, 0, 0) != hash_f32_pair(FNV_OFFSET, 0, math.copy_sign(f32(0), -1)), "-0")
}

@(test)
test_every_number_of_a_command_reaches_its_hash :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	quad(&list, 1, 2, 3, 4, 5, 6, 7, 8)
	base := command_hash(list.commands[0])
	for i in 0 ..< 8 {
		changed := list.commands[0]
		changed.args[i] += 0.5
		testing.expectf(t, command_hash(changed) != base, "args[%d]", i)
	}
	tr := [6]f32{1, 0, 0, 1, 0, 0}
	for i in 0 ..< 6 {
		changed := list.commands[0]
		moved := tr
		moved[i] += 0.5
		changed.transform = transmute(Transform)moved
		testing.expectf(t, command_hash(changed) != base, "transform[%d]", i)
	}
	for i in 0 ..< 4 {
		changed := list.commands[0]
		changed.style.stroke[i] += 1
		testing.expectf(t, command_hash(changed) != base, "stroke[%d]", i)
		changed = list.commands[0]
		changed.style.fill[i] += 1
		testing.expectf(t, command_hash(changed) != base, "fill[%d]", i)
	}
	changed := list.commands[0]
	changed.style.cap = .Butt
	testing.expect(t, command_hash(changed) != base, "cap")
	changed = list.commands[0]
	changed.style.join = .Bevel
	testing.expect(t, command_hash(changed) != base, "join")
	changed = list.commands[0]
	changed.style.fill_paint.hash = 9
	testing.expect(t, command_hash(changed) != base, "fill gradient")
	changed = list.commands[0]
	changed.style.stroke_paint.hash = 9
	testing.expect(t, command_hash(changed) != base, "stroke gradient")
	changed = list.commands[0]
	changed.content = 9
	testing.expect(t, command_hash(changed) != base, "content")
}

@(test)
test_a_command_hash_is_its_shape_and_its_look :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_fill(&list, maths.rgb(10, 20, 30))
	move(&list, 5, 6)
	circle(&list, 1, 2, 3)
	c := list.commands[0]
	testing.expect_value(t, command_hash(c), hash_u64(shape_hash(c), look_hash(c.style, c.transform)))
	// the look does not reach the shape part, nor the shape the look part
	other := c
	other.style.alpha = 1
	other.transform.e = 9
	testing.expect_value(t, shape_hash(other), shape_hash(c))
	other = c
	other.args[0] = 9
	testing.expect_value(t, look_hash(other.style, other.transform), look_hash(c.style, c.transform))
}

@(test)
test_the_look_cache_reuses_an_equal_look_and_rehashes_a_different_one :: proc(t: ^testing.T) {
	cache: Look_Cache
	s, tr := DEFAULT_STYLE, IDENTITY
	testing.expect_value(t, look_cache_hash(&cache, s, tr), look_hash(s, tr))
	testing.expect_value(t, look_cache_hash(&cache, s, tr), look_hash(s, tr))

	s2 := s
	s2.fill.g = 7
	testing.expect_value(t, look_cache_hash(&cache, s2, tr), look_hash(s2, tr))
	tr2 := tr
	tr2.f = 3
	testing.expect_value(t, look_cache_hash(&cache, s2, tr2), look_hash(s2, tr2))
	// and back
	testing.expect_value(t, look_cache_hash(&cache, s, tr), look_hash(s, tr))
}

@(test)
test_the_look_cache_tells_zero_from_negative_zero :: proc(t: ^testing.T) {
	cache: Look_Cache
	s, tr := DEFAULT_STYLE, IDENTITY
	_ = look_cache_hash(&cache, s, tr)
	tr2 := tr
	tr2.e = math.copy_sign(f32(0), -1)
	testing.expect_value(t, look_cache_hash(&cache, s, tr2), look_hash(s, tr2))
	testing.expect(t, look_hash(s, tr2) != look_hash(s, tr))
	s2 := s
	s2.thickness = math.copy_sign(f32(0), -1)
	s.thickness = 0
	_ = look_cache_hash(&cache, s, tr)
	testing.expect_value(t, look_cache_hash(&cache, s2, tr), look_hash(s2, tr))
}

@(test)
test_same_look_bits_reads_every_field_the_hash_reads :: proc(t: ^testing.T) {
	s, tr := DEFAULT_STYLE, IDENTITY
	testing.expect(t, same_look_bits(s, tr, s, tr))
	changes := [?]proc(s: ^Style){
		proc(s: ^Style) {s.fill.a = 1},
		proc(s: ^Style) {s.stroke.b = 1},
		proc(s: ^Style) {s.thickness = 3},
		proc(s: ^Style) {s.alpha = 3},
		proc(s: ^Style) {s.fill_on = !s.fill_on},
		proc(s: ^Style) {s.stroke_on = !s.stroke_on},
		proc(s: ^Style) {s.cap = .Square},
		proc(s: ^Style) {s.join = .Round},
		proc(s: ^Style) {s.fill_paint.hash = 1},
		proc(s: ^Style) {s.stroke_paint.hash = 1},
	}
	for change, i in changes {
		s2 := s
		change(&s2)
		testing.expectf(t, !same_look_bits(s, tr, s2, tr), "change %d", i)
	}
	tr2 := tr
	tr2.c = 0.5
	testing.expect(t, !same_look_bits(s, tr, s, tr2))
	// a gradient's number is not hashed, so it does not count
	s2 := s
	s2.fill_paint.id = 4
	testing.expect(t, same_look_bits(s, tr, s2, tr))
}

@(test)
test_a_batch_hash_folds_the_command_hashes_in_order :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	circle(&list, 1, 2, 3)
	circle(&list, 4, 5, 6)
	set_fill(&list, maths.rgb(1, 2, 3))
	circle(&list, 7, 8, 9)
	move(&list, 1, 1)
	circle(&list, 7, 8, 9)
	set_fill(&list, maths.rgb(255, 255, 255)) // back to the first look
	move(&list, -1, -1)
	circle(&list, 1, 1, 1)
	b := drawn(&list)
	defer batcher_destroy(&b)
	testing.expect_value(t, len(b.batches), 1)
	want := FNV_OFFSET
	for c in list.commands {
		want = hash_u64(want, command_hash(c))
	}
	testing.expect_value(t, b.batches[0].hash, want)
}

@(test)
test_fill_and_stroke_switches_hash_apart :: proc(t: ^testing.T) {
	a, b := DEFAULT_STYLE, DEFAULT_STYLE
	a.fill_on, a.stroke_on = true, false
	b.fill_on, b.stroke_on = false, true
	testing.expect(t, hash_style(FNV_OFFSET, a) != hash_style(FNV_OFFSET, b))
}

// ---- batching ----

drawn :: proc(list: ^Command_List) -> Batcher {
	b: Batcher
	build(&b, list)
	return b
}

@(test)
test_an_empty_frame_makes_no_batches :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	b := drawn(&list)
	defer batcher_destroy(&b)
	testing.expect_value(t, b.stats, Stats{})
	testing.expect_value(t, len(b.batches), 0)
}

@(test)
test_a_thousand_shapes_are_one_draw :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	for i in 0 ..< 1000 {
		switch i % 4 {
		case 0: circle(&list, f32(i), 0, 5)
		case 1: rect(&list, f32(i), 0, 5, 5)
		case 2: line(&list, f32(i), 0, 5, 5)
		case 3: triangle(&list, 0, 0, 5, 0, 0, 5)
		}
	}
	b := drawn(&list)
	defer batcher_destroy(&b)
	testing.expect_value(t, b.stats.commands, 1000)
	testing.expect_value(t, b.stats.instances, 750) // the lines have no stroke: invisible
	testing.expect_value(t, b.stats.skipped, 250)
	testing.expect_value(t, b.stats.batches, 1)
	testing.expect_value(t, b.stats.draws, 1)
	testing.expect_value(t, b.batches[0].count, 750)
}

@(test)
test_paths_split_the_shapes_into_batches_in_painting_order :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	circle(&list, 0, 0, 5)
	rect(&list, 0, 0, 5, 5)
	quad(&list, 0, 0, 1, 0, 1, 1, 0, 1)
	arc(&list, 0, 0, 5, 5, 0, 90)
	circle(&list, 0, 0, 5)
	b := drawn(&list)
	defer batcher_destroy(&b)
	testing.expect_value(t, len(b.batches), 3)
	testing.expect_value(t, b.batches[0], Batch{.Shapes, 0, 2, b.batches[0].hash})
	testing.expect_value(t, b.batches[1].pipeline, Pipeline.Paths)
	testing.expect_value(t, b.batches[1].first, 0)
	testing.expect_value(t, b.batches[1].count, len(b.mesh.indices)) // the quad's and the arc's triangles
	testing.expect(t, b.batches[1].count > 6, "the arc adds triangles to the quad's two")
	testing.expect_value(t, b.batches[2].pipeline, Pipeline.Shapes)
	testing.expect_value(t, b.batches[2].first, 2)
	testing.expect_value(t, b.stats.instances, 3)
	testing.expect_value(t, b.stats.path_commands, 2)
	testing.expect_value(t, b.stats.mesh_triangles, len(b.mesh.indices) / 3)
}

@(test)
test_invisible_commands_do_not_break_a_batch :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	circle(&list, 0, 0, 5)
	no_fill(&list)
	quad(&list, 0, 0, 1, 0, 1, 1, 0, 1) // invisible: no fill, no stroke
	set_fill(&list, maths.grey(0))
	circle(&list, 0, 0, 5)
	b := drawn(&list)
	defer batcher_destroy(&b)
	testing.expect_value(t, len(b.batches), 1)
	testing.expect_value(t, b.stats.skipped, 1)
}

@(test)
test_a_batch_hash_follows_its_commands :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	circle(&list, 0, 0, 5)
	circle(&list, 10, 0, 5)
	a := drawn(&list)
	defer batcher_destroy(&a)
	b := drawn(&list)
	defer batcher_destroy(&b)
	testing.expect_value(t, a.batches[0].hash, b.batches[0].hash)

	begin_frame(&list)
	circle(&list, 0, 0, 5)
	circle(&list, 11, 0, 5) // one number differs
	c := drawn(&list)
	defer batcher_destroy(&c)
	testing.expect(t, a.batches[0].hash != c.batches[0].hash)

	begin_frame(&list)
	circle(&list, 10, 0, 5) // same commands, other order
	circle(&list, 0, 0, 5)
	d := drawn(&list)
	defer batcher_destroy(&d)
	testing.expect(t, a.batches[0].hash != d.batches[0].hash)
}

@(test)
test_a_steady_scene_stops_allocating :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	b: Batcher
	defer batcher_destroy(&b)
	frame :: proc(list: ^Command_List, b: ^Batcher) {
		begin_frame(list)
		for i in 0 ..< 200 {circle(list, f32(i), 0, 5)}
		quad(list, 0, 0, 1, 0, 1, 1, 0, 1)
		build(b, list)
	}
	frame(&list, &b)
	testing.expect(t, b.stats.reallocations > 0, "the first frame has to make the buffers")
	frame(&list, &b)
	testing.expect_value(t, b.stats.reallocations, 0)
	frame(&list, &b)
	testing.expect_value(t, b.stats.reallocations, 0)
}

@(test)
test_the_instance_is_112_bytes :: proc(t: ^testing.T) {
	testing.expect_value(t, size_of(Instance), 112)
}

// ---- instances ----

instance_of :: proc(setup: proc(list: ^Command_List)) -> Instance {
	list := fresh()
	defer destroy(&list)
	setup(&list)
	return to_instance(list.commands[0])
}

@(test)
test_a_filled_circle_instance :: proc(t: ^testing.T) {
	i := instance_of(proc(list: ^Command_List) {
		set_fill(list, maths.rgb(255, 0, 0))
		set_alpha(list, 127.5)
		circle(list, 100, 50, 10)
	})
	testing.expect_value(t, i.kind, Shape_Kind.Circle)
	testing.expect_value(t, i.shape[0], f32(10))
	testing.expect_value(t, i.transform, [6]f32{1, 0, 0, 1, 100, 50})
	testing.expect_value(t, i.half, [2]f32{10 + AA_MARGIN, 10 + AA_MARGIN})
	testing.expect_value(t, i.flags, FLAG_FILL)
	testing.expect_value(t, i.fill, [4]f32{1, 0, 0, 0.5})
}

@(test)
test_a_stroke_widens_the_quad_and_sets_its_flag :: proc(t: ^testing.T) {
	i := instance_of(proc(list: ^Command_List) {
		set_stroke(list, maths.grey(0))
		set_thickness(list, 6)
		circle(list, 0, 0, 10)
	})
	testing.expect_value(t, i.flags, FLAG_FILL | FLAG_STROKE)
	testing.expect_value(t, i.thickness, f32(6))
	testing.expect_value(t, i.half[0], f32(10 + 3 + AA_MARGIN))
}

@(test)
test_rect_and_ellipse_centre_and_halve_their_size :: proc(t: ^testing.T) {
	i := instance_of(proc(list: ^Command_List) {rect(list, 10, 20, 40, 10)})
	testing.expect_value(t, i.kind, Shape_Kind.Rect)
	testing.expect_value(t, i.shape[0], f32(20))
	testing.expect_value(t, i.shape[1], f32(5))
	testing.expect_value(t, i.transform[4], f32(30)) // corner origin: centre is x + w/2
	testing.expect_value(t, i.transform[5], f32(25))

	i = instance_of(proc(list: ^Command_List) {rect(list, 10, 20, 40, 10, .Center)})
	testing.expect_value(t, i.transform[4], f32(10))
	testing.expect_value(t, i.transform[5], f32(20))

	i = instance_of(proc(list: ^Command_List) {ellipse(list, 10, 20, 40, 10)})
	testing.expect_value(t, i.kind, Shape_Kind.Ellipse)
	testing.expect_value(t, i.transform[4], f32(10)) // centred by default, as in Processing
	testing.expect_value(t, i.transform[5], f32(20))

	i = instance_of(proc(list: ^Command_List) {ellipse(list, 10, 20, 40, 10, .Corner)})
	testing.expect_value(t, i.transform[4], f32(30))
	testing.expect_value(t, i.transform[5], f32(25))
}

@(test)
test_which_shapes_are_centred_by_default :: proc(t: ^testing.T) {
	for kind in Kind {
		want := kind == .Circle || kind == .Ellipse || kind == .Arc
		testing.expect_value(t, is_centred(Command{kind = kind}), want)
		testing.expect(t, is_centred(Command{kind = kind, origin = .Center}))
		testing.expect(t, !is_centred(Command{kind = kind, origin = .Corner}))
	}
}

@(test)
test_a_circle_with_corner_origin_is_centred_one_radius_in :: proc(t: ^testing.T) {
	i := instance_of(proc(list: ^Command_List) {circle(list, 10, 10, 5, .Corner)})
	testing.expect_value(t, i.transform[4], f32(15))
	testing.expect_value(t, i.transform[5], f32(15))
}

@(test)
test_a_line_is_all_stroke_and_sits_around_its_midpoint :: proc(t: ^testing.T) {
	i := instance_of(proc(list: ^Command_List) {
		set_stroke(list, maths.rgb(0, 255, 0))
		set_thickness(list, 4)
		line(list, 0, 0, 10, 20)
	})
	testing.expect_value(t, i.kind, Shape_Kind.Line)
	testing.expect_value(t, i.flags, FLAG_STROKE)
	testing.expect_value(t, i.shape, [6]f32{-5, -10, 5, 10, 0, 0})
	testing.expect_value(t, i.transform[4], f32(5))
	testing.expect_value(t, i.transform[5], f32(10))
	testing.expect_value(t, i.thickness, f32(4))
	testing.expect_value(t, i.stroke, [4]f32{0, 1, 0, 1})
}

@(test)
test_a_point_is_a_dot_in_the_stroke_colour :: proc(t: ^testing.T) {
	i := instance_of(proc(list: ^Command_List) {
		set_stroke(list, maths.rgb(255, 0, 0))
		set_thickness(list, 8)
		point(list, 3, 4)
	})
	testing.expect_value(t, i.kind, Shape_Kind.Circle)
	testing.expect_value(t, i.shape[0], f32(4))
	testing.expect_value(t, i.flags, FLAG_FILL)
	testing.expect_value(t, i.fill, [4]f32{1, 0, 0, 1})

	// A hairline stroke still makes a visible dot, one pixel across.
	i = instance_of(proc(list: ^Command_List) {
		set_stroke(list, maths.grey(0))
		set_thickness(list, 0.2)
		point(list, 3, 4)
	})
	testing.expect_value(t, i.shape[0], f32(0.5))
}

@(test)
test_a_triangle_is_kept_relative_to_the_middle_of_its_box :: proc(t: ^testing.T) {
	i := instance_of(proc(list: ^Command_List) {triangle(list, 0, 0, 10, 0, 5, 8)})
	testing.expect_value(t, i.kind, Shape_Kind.Triangle)
	testing.expect_value(t, i.shape, [6]f32{-5, -4, 5, -4, 0, 4})
	testing.expect_value(t, i.transform[4], f32(5))
	testing.expect_value(t, i.transform[5], f32(4))
}

@(test)
test_the_transform_is_folded_into_the_instance :: proc(t: ^testing.T) {
	i := instance_of(proc(list: ^Command_List) {
		move(list, 100, 0)
		turn(list, 90)
		circle(list, 10, 0, 5)
	})
	// The circle's centre (10, 0) turned a quarter lands at (0, 10), then moved.
	testing.expect_value(t, i.transform, [6]f32{0, 1, -1, 0, 100, 10})
}

@(test)
test_quads_and_arcs_give_an_empty_instance :: proc(t: ^testing.T) {
	i := instance_of(proc(list: ^Command_List) {quad(list, 0, 0, 1, 0, 1, 1, 0, 1)})
	testing.expect_value(t, i, Instance{})
	i = instance_of(proc(list: ^Command_List) {arc(list, 0, 0, 1, 1, 0, 90)})
	testing.expect_value(t, i, Instance{})
}

@(test)
test_which_pipeline_draws_which_kind_by_default :: proc(t: ^testing.T) {
	// The default style has a fill and no outline, with round caps.
	for kind in Kind {
		want := Pipeline.Shapes
		if kind == .Quad || kind == .Arc {want = .Paths}
		if kind == .Text {want = .Text}
		testing.expect_value(t, pipeline_for(Command{kind = kind, style = DEFAULT_STYLE}), want)
	}
}

@(test)
test_colour_for_gpu_scales_to_zero_one_and_folds_alpha :: proc(t: ^testing.T) {
	testing.expect_value(t, colour_for_gpu({255, 0, 51, 255}, 255), [4]f32{1, 0, 0.2, 1})
	testing.expect_value(t, colour_for_gpu({255, 255, 255, 255}, 0), [4]f32{1, 1, 1, 0})
	testing.expect_value(t, colour_for_gpu({0, 0, 0, 102}, 127.5), [4]f32{0, 0, 0, 0.2})
}
