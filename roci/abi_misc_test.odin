// SPDX-License-Identifier: 0BSD
package roci

import "core:testing"

@(thread_local) abi_message_seen: struct {
	count:  int,
	kinds:  [8]Abi_Value_Kind,
	number: f64,
	inner:  f64,
}

abi_catch :: proc "c" (value: ^Abi_Value) {
	context = abi_context()
	m := &abi_message_seen
	m.count += 1
	if value.kind == .List && value.count >= 3 {
		for i in 0 ..< 3 {
			m.kinds[i] = value.items[i].kind
		}
		m.number = value.items[0].number
		if value.items[2].kind == .List && value.items[2].count == 2 {
			m.inner = value.items[2].items[1].number
		}
	}
}

@(test)
test_the_c_messages_carry_lists_and_lists_of_lists :: proc(t: ^testing.T) {
	begin()
	defer finish()
	abi_message_seen = {}
	w := i32(window(100, 100))
	abi_on_receive(w, abi_catch)
	nested := [2]Abi_Value{{kind = .Number, number = 1}, {kind = .Number, number = 42}}
	items := [3]Abi_Value{{kind = .Number, number = 7}, {kind = .Text, text = "hi"}, {kind = .List, items = raw_data(nested[:]), count = 2}}
	abi_send(w, &Abi_Value{kind = .List, items = raw_data(items[:]), count = 3})
	abi_send(w, &Abi_Value{kind = .Boolean, number = 1})
	abi_send_boolean(w, 0)
	abi_send(w, nil) // nothing to send is a number 0
	abi_send(w, &Abi_Value{kind = .List}) // an empty list
	step()
	step()
	testing.expect_value(t, abi_message_seen.count, 5)
	testing.expect(t, abi_message_seen.kinds[0] == .Number && abi_message_seen.kinds[1] == .Text && abi_message_seen.kinds[2] == .List, "the kinds of the items")
	testing.expect_value(t, abi_message_seen.number, 7)
	testing.expect_value(t, abi_message_seen.inner, 42)
}

@(thread_local)
abi_tween_places: struct {
	x, y:  f64,
	point: Abi_Vec2,
	space: Abi_Vec3,
	color: Abi_Color,
}

@(test)
test_the_c_tweens_move_a_place_and_land_on_the_value :: proc(t: ^testing.T) {
	begin()
	defer finish()
	window(100, 100)
	abi_tween_places = {color = {0, 0, 0, 255}}
	abi_tween(&abi_tween_places.x, 100, 0.5, "linear")
	abi_tween_vec2(&abi_tween_places.point, {10, 20}, 0.5, "smooth")
	abi_tween_vec3(&abi_tween_places.space, {1, 2, 3}, 0.5, "")
	abi_tween_color(&abi_tween_places.color, {255, 255, 255, 255}, 0.5, "out")
	abi_tween(nil, 1, 1, "linear") // no place: nothing
	abi_tween(&abi_tween_places.x, 100, 0.5, "linear") // the same place again replaces the old tween
	for _ in 0 ..< 15 {
		step()
	}
	testing.expect(t, abi_tween_places.x > 0 && abi_tween_places.x < 100, "on the way")
	testing.expect(t, abi_tween_places.point.x > 0 && abi_tween_places.point.x < 10, "a point on the way")
	testing.expect(t, abi_tween_places.color.r > 0 && abi_tween_places.color.r < 255, "a color on the way")
	for _ in 0 ..< 30 {
		step()
	}
	testing.expect_value(t, abi_tween_places.x, 100)
	testing.expect_value(t, abi_tween_places.point, Abi_Vec2{10, 20})
	testing.expect_value(t, abi_tween_places.space, Abi_Vec3{1, 2, 3})
	testing.expect_value(t, abi_tween_places.color, Abi_Color{255, 255, 255, 255})
	// a tween that is stopped stays where it was; one of no length lands at once
	abi_tween_places.y = 5
	abi_tween(&abi_tween_places.y, 50, 10, "linear")
	step()
	abi_stop_tweens()
	stopped := abi_tween_places.y
	step()
	testing.expect_value(t, abi_tween_places.y, stopped)
	abi_tween(&abi_tween_places.y, 9, 0, "linear")
	step()
	testing.expect_value(t, abi_tween_places.y, 9)
}

@(test)
test_the_c_random_helpers_follow_the_seed :: proc(t: ^testing.T) {
	begin()
	defer finish()
	window(100, 100)
	abi_seed(7)
	first := [3]int{int(abi_pick_index(10)), int(abi_pick_index(10)), int(abi_pick_index(10))}
	abi_seed(7)
	again := [3]int{int(abi_pick_index(10)), int(abi_pick_index(10)), int(abi_pick_index(10))}
	testing.expect_value(t, first, again)
	testing.expect_value(t, abi_pick_index(0), -1)
	testing.expect_value(t, abi_pick_index(1), 0)
	for _ in 0 ..< 20 {
		at := abi_anywhere()
		testing.expect(t, at.x >= 0 && at.x <= 100 && at.y >= 0 && at.y <= 100, "in the window")
	}
	items := [8]i32{1, 2, 3, 4, 5, 6, 7, 8}
	abi_seed(3)
	abi_shuffle(raw_data(items[:]), 8, size_of(i32))
	other := [8]i32{1, 2, 3, 4, 5, 6, 7, 8}
	abi_seed(3)
	abi_shuffle(raw_data(other[:]), 8, size_of(i32))
	testing.expect_value(t, items, other) // the same seed mixes the same way
	sum := i32(0)
	for v in items {
		sum += v
	}
	testing.expect_value(t, sum, 36) // nothing lost
	testing.expect(t, items != [8]i32{1, 2, 3, 4, 5, 6, 7, 8}, "mixed")
	abi_shuffle(nil, 8, 4)
	abi_shuffle(raw_data(items[:]), 1, 4)
	abi_shuffle(raw_data(items[:]), 8, 0)
	Pair :: struct {a, b: f64}
	pairs := [4]Pair{{1, 10}, {2, 20}, {3, 30}, {4, 40}}
	abi_shuffle(raw_data(pairs[:]), 4, size_of(Pair))
	for p in pairs {
		testing.expect_value(t, p.b, p.a * 10) // whole items move
	}
}

@(test)
test_the_c_style_scope_origin_and_wrapped_text_work :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(200, 200)
	abi_fill({255, 0, 0, 255})
	abi_push_style()
	abi_fill({0, 255, 0, 255})
	abi_circle(10, 10, 5)
	testing.expect_value(t, abi_pop_style(), 1)
	abi_circle(10, 10, 5)
	testing.expect_value(t, abi_pop_style(), 0) // nothing left to put back
	abi_origin("corner") // the next shape only
	abi_circle(50, 50, 10)
	abi_circle(50, 50, 10)
	abi_origin("center")
	abi_rect(50, 50, 20, 20)
	abi_origin("nonsense") // not a word: nothing changes
	abi_origin("default")
	abi_rect(50, 50, 20, 20)
	commands := commands_of(w)
	testing.expect_value(t, len(commands), 6)
	testing.expect_value(t, commands[0].style.fill, Colour{0, 255, 0, 255})
	testing.expect_value(t, commands[1].style.fill, Colour{255, 0, 0, 255})
	testing.expect(t, commands[2].origin == .Corner && commands[3].origin == .Default, "only the next shape")
	testing.expect(t, commands[4].origin == .Center && commands[5].origin == .Default, "the rectangles")
	abi_text_wrapped("a few words that go over a short line", 0, 0, 40)
	abi_text_wrapped_v("a few words that go over a short line", {0, 50}, 40)
	narrow := abi_measure_wrapped("a few words that go over a short line", 40)
	wide := abi_measure_wrapped("a few words that go over a short line", 4000)
	testing.expect(t, narrow.y > wide.y && narrow.x < wide.x, "wrapped text is taller and narrower")
	testing.expect_value(t, abi_held("space"), 0)
	testing.expect_value(t, abi_held("mouse left"), 0)
	testing.expect_value(t, abi_held("mouse elbow"), 0)
	abi_print("printed from c")
}

@(test)
test_the_c_headless_run_steps_frames_and_hashes_them :: proc(t: ^testing.T) {
	abi_start_headless(11)
	defer abi_shutdown()
	abi_default_window_size(120, 90)
	abi_circle(10, 10, 5)
	abi_step()
	w := abi_current_window()
	testing.expect_value(t, abi_window_width(w), 120)
	first := abi_frame_hash(w)
	testing.expect(t, first != 0, "a frame that has a circle in it")
	abi_step()
	testing.expect_value(t, abi_frame_hash(w), first) // the same picture again
	testing.expect_value(t, string(abi_last_error()), "")
	testing.expect_value(t, abi_current_seed(), 11)
	testing.expect_value(t, abi_frame_hash(999), 0)
}
