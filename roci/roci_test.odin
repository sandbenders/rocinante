// SPDX-License-Identifier: 0BSD
//
// Tests of the public API, run headless: no SDL, no window, so they need no display
// and run in the pipelines. Every test starts its own sketch (the sketch state is
// thread-local, so parallel tests do not meet).
package roci

import "core:math"
import "core:testing"
import "gfx"
import "maths"
import "registry"
import "platform"
import sdl "vendor:sdl3"

begin :: proc(seed: u64 = 1) {
	start_headless(seed)
}

finish :: proc() {
	shutdown()
}

// The commands recorded in a window, whole.
commands_of :: proc(w: Window) -> []gfx.Command {
	list := &win_for(w).list
	out := make([]gfx.Command, len(list.commands), context.temp_allocator)
	for i in 0 ..< len(out) {
		out[i] = gfx.command_at(list, i)
	}
	return out
}

// ---- the default window and `window` ----

@(test)
test_a_verb_makes_the_default_window :: proc(t: ^testing.T) {
	begin()
	defer finish()
	circle(100, 100, 50)
	testing.expect_value(t, len(the.windows), 1)
	w := the.windows[0]
	testing.expect_value(t, w.width, DEFAULT_WIDTH)
	testing.expect_value(t, w.height, DEFAULT_HEIGHT)
	testing.expect_value(t, len(w.list.commands), 1)
	testing.expect_value(t, gfx.command_at(&w.list, 0).kind, gfx.Kind.Circle)
	a := gfx.command_at(&w.list, 0).args
	testing.expect_value(t, [3]f32{a[0], a[1], a[2]}, [3]f32{100, 100, 50})
}

@(test)
test_the_smallest_program_is_one_circle :: proc(t: ^testing.T) {
	// `circle 100 100 50`: nothing set up, one window, one picture.
	begin()
	defer finish()
	circle(100, 100, 50)
	step()
	testing.expect_value(t, len(the.windows), 1)
	testing.expect_value(t, the.windows[0].batcher.stats.instances, 1)
}

@(test)
test_the_first_window_call_replaces_the_default_window_and_keeps_what_was_drawn :: proc(t: ^testing.T) {
	begin()
	defer finish()
	circle(10, 10, 5)
	w := window(400, 300)
	testing.expect_value(t, len(the.windows), 1)
	testing.expect_value(t, w, the.windows[0].id)
	testing.expect_value(t, the.windows[0].width, 400)
	testing.expect_value(t, the.windows[0].height, 300)
	testing.expect_value(t, len(the.windows[0].list.commands), 1)
	second := window(200, 200)
	testing.expect_value(t, len(the.windows), 2)
	testing.expect(t, second != w)
}

@(test)
test_a_window_made_first_is_where_later_verbs_draw :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(300, 200)
	circle(1, 2, 3)
	testing.expect_value(t, len(the.windows), 1)
	testing.expect_value(t, len(commands_of(w)), 1)
	testing.expect_value(t, width(), f64(300))
	testing.expect_value(t, height(), f64(200))
}

@(test)
test_window_sizes_that_make_no_sense_get_the_default_or_one :: proc(t: ^testing.T) {
	begin()
	defer finish()
	a := window(0, -5)
	testing.expect_value(t, the.windows[0].width, DEFAULT_WIDTH)
	testing.expect_value(t, the.windows[0].height, DEFAULT_HEIGHT)
	circle(0, 0, 1)
	b := window(0, 0) // a second window
	testing.expect(t, a != b)
	testing.expect_value(t, the.windows[1].width, DEFAULT_WIDTH)
}

@(test)
test_the_replaced_default_window_cannot_shrink_to_nothing :: proc(t: ^testing.T) {
	begin()
	defer finish()
	circle(0, 0, 1)
	window(0, -3)
	testing.expect_value(t, the.windows[0].width, 1)
	testing.expect_value(t, the.windows[0].height, 1)
}

@(test)
test_title_and_fullscreen_are_kept_on_the_window :: proc(t: ^testing.T) {
	begin()
	defer finish()
	title("my sketch")
	fullscreen()
	testing.expect_value(t, the.windows[0].title, "my sketch")
	testing.expect(t, the.windows[0].fullscreen)
	fullscreen(false)
	testing.expect(t, !the.windows[0].fullscreen)
	title("again")
	testing.expect_value(t, the.windows[0].title, "again")
}

// ---- draw blocks ----

@(thread_local)
frames_drawn: int

@(thread_local)
fills_seen: [dynamic]Colour

draw_circle_with_fill_on_first_frame_only :: proc() {
	if frames_drawn == 0 {
		fill(rgb(255, 0, 0))
	}
	circle(50, 50, 10)
	append(&fills_seen, win_for(current_window()).list.style.fill)
	frames_drawn += 1
}

@(test)
test_a_draw_block_runs_every_frame_and_style_resets_between_frames :: proc(t: ^testing.T) {
	begin()
	defer finish()
	frames_drawn = 0
	fills_seen = {}
	defer delete(fills_seen)
	draw(draw_circle_with_fill_on_first_frame_only)
	for _ in 0 ..< 3 {
		step()
	}
	testing.expect_value(t, frames_drawn, 3)
	testing.expect_value(t, fills_seen[0], Colour{255, 0, 0, 255})
	testing.expect_value(t, fills_seen[1], gfx.DEFAULT_STYLE.fill) // the red did not leak into the next frame
	testing.expect_value(t, fills_seen[2], gfx.DEFAULT_STYLE.fill)
	testing.expect_value(t, len(the.windows[0].list.commands), 1) // each frame starts empty
}

@(test)
test_statements_before_a_draw_block_are_set_up_and_do_not_stay_on_screen :: proc(t: ^testing.T) {
	begin()
	defer finish()
	circle(1, 1, 1) // set-up drawing
	draw(proc() {square(0, 0, 5)})
	step()
	cmds := commands_of(the.windows[0].id)
	testing.expect_value(t, len(cmds), 1)
	testing.expect_value(t, cmds[0].kind, gfx.Kind.Rect) // a square is a rect with equal sides
}

@(test)
test_without_a_draw_block_the_picture_stays_as_drawn :: proc(t: ^testing.T) {
	begin()
	defer finish()
	circle(1, 1, 1)
	circle(2, 2, 2)
	for _ in 0 ..< 4 {
		step()
	}
	testing.expect_value(t, len(the.windows[0].list.commands), 2)
	testing.expect_value(t, the.windows[0].batcher.stats.instances, 2)
}

@(thread_local)
which_window: [dynamic]Window

record_window :: proc() {
	append(&which_window, current_window())
	circle(0, 0, 1)
}

@(test)
test_each_window_has_its_own_draw_block_and_verbs_go_to_its_window :: proc(t: ^testing.T) {
	begin()
	defer finish()
	which_window = {}
	defer delete(which_window)
	a := window(100, 100)
	b := window(200, 200)
	draw(a, record_window)
	draw(b, proc() {
		append(&which_window, current_window())
		rect(0, 0, 1, 1)
		rect(1, 1, 1, 1)
	})
	step()
	testing.expect_value(t, len(commands_of(a)), 1)
	testing.expect_value(t, len(commands_of(b)), 2)
	testing.expect_value(t, which_window[0], a)
	testing.expect_value(t, which_window[1], b)
	// Outside any draw block the verbs go to the window the last `window` call made.
	testing.expect_value(t, current_window(), b)
}

@(test)
test_drawing_into_a_window_that_is_not_there_does_nothing :: proc(t: ^testing.T) {
	begin()
	defer finish()
	draw(Window(99), proc() {})
	title("x")
	testing.expect_value(t, len(the.windows), 1)
}

// ---- verbs ----

@(test)
test_vector_forms_of_the_shape_verbs_record_the_same_commands :: proc(t: ^testing.T) {
	begin()
	defer finish()
	circle(1, 2, 3)
	circle([2]f64{1, 2}, 3)
	ellipse(1, 2, 3, 4)
	ellipse([2]f64{1, 2}, [2]f64{3, 4})
	rect(1, 2, 3, 4)
	rect([2]f64{1, 2}, [2]f64{3, 4})
	square(1, 2, 3)
	square([2]f64{1, 2}, 3)
	line(1, 2, 3, 4)
	line([2]f64{1, 2}, [2]f64{3, 4})
	point(1, 2)
	point([2]f64{1, 2})
	triangle(1, 2, 3, 4, 5, 6)
	triangle([2]f64{1, 2}, [2]f64{3, 4}, [2]f64{5, 6})
	quad(1, 2, 3, 4, 5, 6, 7, 8)
	quad([2]f64{1, 2}, [2]f64{3, 4}, [2]f64{5, 6}, [2]f64{7, 8})
	cmds := commands_of(the.windows[0].id)
	testing.expect_value(t, len(cmds), 16)
	for i := 0; i < 16; i += 2 {
		testing.expect_value(t, cmds[i].kind, cmds[i + 1].kind)
		testing.expect_value(t, cmds[i].args, cmds[i + 1].args)
	}
}

@(test)
test_arc_and_text_and_background :: proc(t: ^testing.T) {
	begin()
	defer finish()
	circle(0, 0, 1)
	background(rgb(10, 20, 30))
	arc(50, 50, 40, 40, 0, 90)
	debug_text("hi", 5, 5)
	list := &the.windows[0].list
	testing.expect_value(t, len(list.commands), 2) // the circle was wiped
	testing.expect_value(t, list.background, Colour{10, 20, 30, 255})
	testing.expect_value(t, gfx.command_at(list, 0).kind, gfx.Kind.Arc)
	testing.expect_value(t, gfx.command_at(list, 1).kind, gfx.Kind.Text)
	background_grey(100)
	testing.expect_value(t, len(list.commands), 0)
	testing.expect_value(t, list.background, maths.grey(100))
	circle(0, 0, 1)
	clear_window()
	testing.expect_value(t, len(list.commands), 0)
	testing.expect_value(t, list.background, Colour{0, 0, 0, 0})
	g := gradient({named("navy"), named("black")}, angle = 90)
	background(g)
	testing.expect_value(t, list.background_paint.id, u32(1))
}

@(test)
test_style_verbs_change_what_later_shapes_look_like :: proc(t: ^testing.T) {
	begin()
	defer finish()
	fill(rgb(1, 2, 3))
	stroke(rgb(4, 5, 6))
	thickness(7)
	alpha(100)
	caps(.Square)
	joins(.Bevel)
	circle(0, 0, 1)
	no_fill()
	no_stroke()
	circle(0, 0, 1)
	cmds := commands_of(the.windows[0].id)
	s0 := cmds[0].style
	testing.expect_value(t, s0.fill, Colour{1, 2, 3, 255})
	testing.expect_value(t, s0.stroke, Colour{4, 5, 6, 255})
	testing.expect_value(t, s0.thickness, f32(7))
	testing.expect_value(t, s0.alpha, f32(100))
	testing.expect_value(t, s0.cap, Cap.Square)
	testing.expect_value(t, s0.join, Join.Bevel)
	testing.expect(t, cmds[1].style.fill_on == false && cmds[1].style.stroke_on == false)
}

@(test)
test_grey_forms_of_fill_and_stroke :: proc(t: ^testing.T) {
	begin()
	defer finish()
	fill(128)
	stroke(32)
	circle(0, 0, 1)
	s := commands_of(the.windows[0].id)[0].style
	testing.expect_value(t, s.fill, maths.grey(128))
	testing.expect_value(t, s.stroke, maths.grey(32))
}

@(test)
test_a_gradient_can_be_a_fill_or_a_stroke :: proc(t: ^testing.T) {
	begin()
	defer finish()
	g := gradient({named("red"), named("blue")})
	fill(g)
	stroke(g)
	circle(0, 0, 5)
	s := commands_of(the.windows[0].id)[0].style
	testing.expect_value(t, s.fill_paint.id, u32(1))
	testing.expect_value(t, s.stroke_paint.id, u32(1))
	bad := gradient({}) // no colours: fills with nothing
	fill(bad)
	testing.expect_value(t, the.windows[0].list.style.fill_paint.id, u32(1))
}

@(test)
test_a_look_styles_one_shape_and_leaves_the_style_alone :: proc(t: ^testing.T) {
	begin()
	defer finish()
	fill(rgb(9, 9, 9))
	circle(0, 0, 5, Look{fill = rgb(255, 0, 0), stroke = rgb(0, 0, 255), thickness = 3.0, alpha = 128.0})
	circle(0, 0, 5)
	rect(0, 0, 5, 5, Look{no_fill = true})
	cmds := commands_of(the.windows[0].id)
	testing.expect_value(t, cmds[0].style.fill, Colour{255, 0, 0, 255})
	testing.expect_value(t, cmds[0].style.stroke, Colour{0, 0, 255, 255})
	testing.expect_value(t, cmds[0].style.thickness, f32(3))
	testing.expect_value(t, cmds[0].style.alpha, f32(128))
	testing.expect_value(t, cmds[1].style.fill, Colour{9, 9, 9, 255}) // back to the current style
	testing.expect(t, cmds[1].style.thickness == gfx.DEFAULT_STYLE.thickness)
	testing.expect(t, !cmds[2].style.fill_on)
	testing.expect_value(t, len(the.windows[0].list.saved), 0)
}

@(test)
test_a_look_with_a_gradient_and_origin_words :: proc(t: ^testing.T) {
	begin()
	defer finish()
	g := gradient({named("red"), named("blue")})
	circle(10, 10, 5, Look{fill = g, stroke = g}, .Corner)
	c := commands_of(the.windows[0].id)[0]
	testing.expect_value(t, c.origin, Origin.Corner)
	testing.expect(t, c.style.fill_paint.id != 0 && c.style.stroke_paint.id != 0)
}

@(test)
test_transforms_and_scopes :: proc(t: ^testing.T) {
	begin()
	defer finish()
	move(10, 20)
	move([2]f64{1, 1})
	grow(2)
	grow(2, 3)
	turn(90)
	shear(10, 0)
	circle(0, 0, 1)
	testing.expect(t, commands_of(the.windows[0].id)[0].transform != gfx.IDENTITY)
	push()
	move(100, 0)
	push(.Style)
	fill(rgb(1, 1, 1))
	testing.expect(t, pop())
	testing.expect(t, pop())
	testing.expect(t, !pop())
}

@(test)
test_colour_helpers :: proc(t: ^testing.T) {
	testing.expect_value(t, rgb(255, 128, 0), Colour{255, 128, 0, 255})
	testing.expect_value(t, grey(10, 20), Colour{10, 10, 10, 20})
	testing.expect_value(t, hex("#ff8800"), Colour{255, 136, 0, 255})
	testing.expect_value(t, hex("nope"), Colour{})
	testing.expect_value(t, named("orange"), Colour{255, 165, 0, 255})
	testing.expect_value(t, named("grey"), Colour{}) // the language's word is "gray"
	c := hsb(0, 255, 255)
	testing.expect(t, c.r > 250 && c.g < 5)
	testing.expect(t, oklch(0.7, 0.1, 30).a == 255)
	m := mix_colours(grey(0), grey(255), 0.5, .Rgb)
	testing.expect_value(t, m, grey(127.5))
	testing.expect_value(t, mix(grey(0), grey(255), 0.5, .Rgb), grey(127.5)) // the group picks colours
	testing.expect_value(t, mix(10.0, 20.0, 0.25), 12.5)                       // and numbers
	testing.expect_value(t, mix_numbers(0, 100, 0), 0.0)
	testing.expect_value(t, mix_numbers(0, 100, 1), 100.0)
}

// ---- maths ----

@(test)
test_the_same_seed_gives_the_same_numbers_and_another_seed_does_not :: proc(t: ^testing.T) {
	begin()
	defer finish()
	seed(42)
	a := [?]f64{random(10), random_between(5, 6), gaussian(0, 1), noise(0.3), noise(0.3, 0.4)}
	seed(42)
	b := [?]f64{random(10), random_between(5, 6), gaussian(0, 1), noise(0.3), noise(0.3, 0.4)}
	testing.expect_value(t, a, b)
	seed(43)
	c := [?]f64{random(10), random_between(5, 6), gaussian(0, 1), noise(0.3), noise(0.3, 0.4)}
	testing.expect(t, a != c)
	testing.expect_value(t, current_seed(), u64(43))
}

@(test)
test_a_sketch_that_never_seeds_still_has_a_seed_to_report :: proc(t: ^testing.T) {
	start_headless(0)
	defer finish()
	testing.expect(t, the.seed_chosen)
	_ = random(1)
}

@(test)
test_seed_zero_is_a_seed_and_a_bad_seed_becomes_zero :: proc(t: ^testing.T) {
	begin()
	defer finish()
	seed(0)
	a := random(1)
	seed(math.nan_f64())
	b := random(1)
	testing.expect_value(t, a, b)
	testing.expect_value(t, current_seed(), u64(0))
}

@(test)
test_random_ranges :: proc(t: ^testing.T) {
	begin()
	defer finish()
	for _ in 0 ..< 1000 {
		x := random(5)
		testing.expect(t, x >= 0 && x < 5)
		y := random_between(10, 20)
		testing.expect(t, y >= 10 && y < 20)
		p := anywhere()
		testing.expect(t, p.x >= 0 && p.x < DEFAULT_WIDTH && p.y >= 0 && p.y < DEFAULT_HEIGHT)
	}
}

@(test)
test_pick_gives_an_item_or_the_zero_value :: proc(t: ^testing.T) {
	begin()
	defer finish()
	items := [?]int{3, 5, 7}
	seen: [3]bool
	for _ in 0 ..< 200 {
		v := pick(items[:])
		testing.expect(t, v == 3 || v == 5 || v == 7)
		seen[(v - 3) / 2] = true
	}
	testing.expect(t, seen[0] && seen[1] && seen[2], "every item turns up")
	testing.expect_value(t, pick([]int{}), 0)
	one := [?]string{"only"}
	testing.expect_value(t, pick(one[:]), "only")
}

@(test)
test_noise_comes_in_four_dimensions_and_two_kinds :: proc(t: ^testing.T) {
	begin()
	defer finish()
	vals := [?]f64{noise(0.3), noise(0.3, 0.4), noise(0.3, 0.4, 0.5), noise(0.3, 0.4, 0.5, 0.6), noise(0.3, simplex = true), noise(0.3, 0.4, simplex = true), noise(0.3, 0.4, 0.5, simplex = true), noise(0.3, 0.4, 0.5, 0.6, simplex = true), fbm(0.3, 0.4, 0.5)}
	for v in vals {
		testing.expect(t, v >= 0 && v <= 1)
	}
	testing.expect(t, noise(0.3) != noise(0.3, simplex = true))
}

@(test)
test_number_verbs :: proc(t: ^testing.T) {
	testing.expect_value(t, map_range(5, 0, 10, 0, 100), 50.0)
	testing.expect_value(t, clamp_between(15, 0, 10), 10.0)
	testing.expect_value(t, clamp_between(-5, 0, 10), 0.0)
	testing.expect_value(t, dist(0, 0, 3, 4), 5.0)
	testing.expect_value(t, dist([2]f64{0, 0}, [2]f64{3, 4}), 5.0)
	testing.expect_value(t, absolute(-3), 3.0)
	testing.expect_value(t, square_root(16), 4.0)
	testing.expect_value(t, square_root(-1), 0.0)
	testing.expect_value(t, sin_deg(90), 1.0)
	testing.expect_value(t, cos_deg(180), -1.0)
	testing.expect_value(t, sin_deg(0), 0.0)
	testing.expect(t, math.abs(sin_deg(30) - 0.5) < 1e-12)
	testing.expect_value(t, sin_deg(math.nan_f64()), 0.0)
	testing.expect_value(t, cos_deg(math.inf_f64(1)), 1.0)
	testing.expect_value(t, cos_deg(-90), 0.0)
}

// ---- messages ----

@(thread_local)
received: [dynamic]Value

collect :: proc(v: Value) {
	append(&received, value_clone(v))
}

@(test)
test_a_message_arrives_on_the_next_frame_in_order :: proc(t: ^testing.T) {
	begin()
	defer finish()
	received = {}
	defer {
		for v in received {value_destroy(v)}
		delete(received)
	}
	a := window(100, 100)
	b := window(100, 100)
	on_receive(b, collect)
	send(b, 1.0)
	send(b, "two")
	send(b, [2]f64{3, 4})
	testing.expect_value(t, len(received), 0) // not yet
	step()
	testing.expect_value(t, len(received), 3)
	testing.expect_value(t, received[0].(f64), 1.0)
	testing.expect_value(t, received[1].(string), "two")
	testing.expect_value(t, received[2].([2]f64), [2]f64{3, 4})
	step()
	testing.expect_value(t, len(received), 3) // delivered once
	_ = a
}

@(test)
test_a_message_sent_while_handling_waits_for_the_next_frame :: proc(t: ^testing.T) {
	begin()
	defer finish()
	received = {}
	defer {
		for v in received {value_destroy(v)}
		delete(received)
	}
	w := window(100, 100)
	on_receive(w, proc(v: Value) {
		collect(v)
		if len(received) < 3 {
			send(current_window(), f64(len(received)))
		}
	})
	send(w, 0.0)
	step()
	testing.expect_value(t, len(received), 1)
	step()
	testing.expect_value(t, len(received), 2)
	step()
	testing.expect_value(t, len(received), 3)
}

@(test)
test_messages_are_copied_so_the_sender_can_change_its_data :: proc(t: ^testing.T) {
	begin()
	defer finish()
	received = {}
	defer {
		for v in received {value_destroy(v)}
		delete(received)
	}
	w := window(100, 100)
	on_receive(w, collect)
	text := make([]u8, 3)
	defer delete(text)
	copy(text, "abc")
	list := []Value{string(text), 5.0, []Value{true}}
	send(w, list)
	text[0] = 'X' // the sender changes it after sending
	step()
	got := received[0].([]Value)
	testing.expect_value(t, got[0].(string), "abc")
	testing.expect_value(t, got[1].(f64), 5.0)
	testing.expect_value(t, got[2].([]Value)[0].(bool), true)
}

@(test)
test_a_message_to_a_window_with_no_handler_or_no_window_is_dropped :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(100, 100)
	send(w, "nobody listens")
	send(Window(42), "nobody is there")
	send(Window(0), 1.0)
	step()
	testing.expect_value(t, len(the.windows[0].inbox), 0)
}

@(test)
test_a_new_handler_replaces_the_old :: proc(t: ^testing.T) {
	begin()
	defer finish()
	received = {}
	defer delete(received)
	w := window(100, 100)
	on_receive(w, proc(v: Value) {append(&received, 1.0)})
	on_receive(w, proc(v: Value) {append(&received, 2.0)})
	send(w, 0.0)
	step()
	testing.expect_value(t, received[0].(f64), 2.0)
	on_receive(Window(77), collect) // no such window: ignored
}

@(test)
test_values_clone_and_destroy_without_leaking :: proc(t: ^testing.T) {
	v := Value([]Value{"a string", []Value{"nested", 1.0}, true, [2]f64{1, 2}})
	c := value_clone(v)
	value_destroy(c)
	value_destroy(Value(nil))
}

// ---- input and events ----

key_event :: proc(code: sdl.Scancode, down: bool, mods: platform.Modifiers = {}, repeat := false) -> platform.Event {
	return platform.Key_Changed{window = 1, scancode = code, down = down, repeat = repeat, mods = mods}
}

@(test)
test_keys_are_read_by_name_and_released :: proc(t: ^testing.T) {
	begin()
	defer finish()
	circle(0, 0, 1)
	testing.expect(t, !key_down("w"))
	step({key_event(.W, true)})
	testing.expect(t, key_down("w"))
	testing.expect(t, !key_down("a"))
	step({key_event(.W, false)})
	testing.expect(t, !key_down("w"))
	step({key_event(.SPACE, true), key_event(.LEFT, true), key_event(._0, true), key_event(.F5, true)})
	for name in ([?]string{"space", "left", "0", "f5"} ) {
		testing.expect(t, key_down(name), name)
	}
	testing.expect(t, !key_down("Space"), "names are lowercase")
	testing.expect(t, !key_down(""))
	testing.expect(t, !key_down("nonsense"))
}

@(test)
test_every_key_name_maps_to_a_distinct_physical_key :: proc(t: ^testing.T) {
	names := make([dynamic]string)
	defer delete(names)
	for c in 'a' ..= 'z' {append(&names, string([]u8{u8(c)}))}
	_ = names
	seen: map[sdl.Scancode]string
	defer delete(seen)
	list := [?]string{"a", "m", "z", "0", "1", "9", "space", "enter", "escape", "tab", "backspace", "left", "right", "up", "down", "shift", "ctrl", "alt", "f1", "f6", "f12"}
	for name in list {
		code, ok := scancode_for_name(name)
		testing.expect(t, ok, name)
		other, dup := seen[code]
		testing.expectf(t, !dup, "%s and %s are the same key", name, other)
		seen[code] = name
	}
	for bad in ([?]string{"f0", "f13", "fx", "ab", "A", "!", "f1x", "shift ", "ff", "f99"}) {
		_, ok := scancode_for_name(bad)
		testing.expectf(t, !ok, "%s is not a key", bad)
	}
	a, _ := scancode_for_name("a")
	testing.expect_value(t, a, sdl.Scancode.A)
	nine, _ := scancode_for_name("9")
	testing.expect_value(t, nine, sdl.Scancode._9)
}

@(test)
test_losing_focus_releases_every_key_and_button :: proc(t: ^testing.T) {
	begin()
	defer finish()
	circle(0, 0, 1)
	step({key_event(.W, true), platform.Mouse_Button_Changed{window = 1, button = .Left, down = true}})
	testing.expect(t, key_down("w") && mouse_down())
	step({platform.Focus_Changed{window = 1, gained = false}})
	testing.expect(t, !key_down("w") && !mouse_down())
}

@(test)
test_the_mouse_and_where_it_was_a_frame_ago :: proc(t: ^testing.T) {
	begin()
	defer finish()
	circle(0, 0, 1)
	step({platform.Mouse_Moved{window = 1, x = 10, y = 20}})
	testing.expect_value(t, mouse(), [2]f64{10, 20})
	testing.expect_value(t, pmouse(), [2]f64{0, 0}) // within the frame that moved it, it was at the origin
	step({platform.Mouse_Moved{window = 1, x = 30, y = 40}})
	testing.expect_value(t, mouse(), [2]f64{30, 40})
	testing.expect_value(t, pmouse(), [2]f64{10, 20})
}

@(test)
test_mouse_buttons_and_the_wheel :: proc(t: ^testing.T) {
	begin()
	defer finish()
	circle(0, 0, 1)
	testing.expect(t, !mouse_down())
	step({platform.Mouse_Button_Changed{window = 1, button = .Right, down = true}})
	testing.expect(t, mouse_down(.Right) && !mouse_down(.Left))
	step({platform.Mouse_Button_Changed{window = 1, button = .Right, down = false}})
	testing.expect(t, !mouse_down(.Right))
	step({platform.Wheel{window = 1, dx = 1, dy = -2}, platform.Wheel{window = 1, dx = 0, dy = -1}})
	testing.expect_value(t, wheel(), [2]f64{1, -3}) // readable by the frame's draw block and after it
	step()
	testing.expect_value(t, wheel(), [2]f64{0, 0}) // only what turned in the last frame
}

@(test)
test_ctrl_q_and_cmd_q_quit_but_escape_does_not :: proc(t: ^testing.T) {
	begin()
	defer finish()
	circle(0, 0, 1)
	step({key_event(.ESCAPE, true)})
	testing.expect(t, !the.quit)
	step({key_event(.Q, true)})
	testing.expect(t, !the.quit, "a plain q is only a key")
	step({key_event(.Q, true, {.Ctrl}, repeat = true)})
	testing.expect(t, !the.quit, "a repeat does not count")
	step({key_event(.Q, true, {.Ctrl})})
	testing.expect(t, the.quit)
	the.quit = false
	step({key_event(.Q, true, {.Super})})
	testing.expect(t, the.quit)
}

@(test)
test_quit_and_the_quit_event :: proc(t: ^testing.T) {
	begin()
	defer finish()
	circle(0, 0, 1)
	quit()
	testing.expect(t, the.quit)
	the.quit = false
	step({platform.Quit{}})
	testing.expect(t, the.quit)
}

@(test)
test_closing_the_last_window_ends_the_sketch_and_closing_one_does_not :: proc(t: ^testing.T) {
	begin()
	defer finish()
	a := window(10, 10)
	b := window(10, 10)
	step({platform.Close_Requested{window = platform.Window_Id(a)}})
	testing.expect_value(t, len(the.windows), 1)
	testing.expect(t, !the.quit)
	send(a, 1.0) // the closed window drops it
	testing.expect_value(t, current_window(), b)
	step({platform.Close_Requested{window = platform.Window_Id(b)}})
	testing.expect_value(t, len(the.windows), 0)
	testing.expect(t, the.quit)
}

@(test)
test_closing_the_default_window_lets_a_verb_make_another :: proc(t: ^testing.T) {
	begin()
	defer finish()
	circle(0, 0, 1)
	first := the.windows[0].id
	step({platform.Close_Requested{window = platform.Window_Id(first)}})
	circle(0, 0, 1)
	testing.expect_value(t, len(the.windows), 1)
	testing.expect(t, the.windows[0].id != first)
}

@(test)
test_a_window_resizing_changes_width_and_height :: proc(t: ^testing.T) {
	begin()
	defer finish()
	circle(0, 0, 1)
	step({platform.Resized{window = 1, width = 321, height = 123}})
	testing.expect_value(t, width(), f64(321))
	testing.expect_value(t, height(), f64(123))
}

@(test)
test_events_for_windows_that_do_not_exist_are_ignored :: proc(t: ^testing.T) {
	begin()
	defer finish()
	circle(0, 0, 1)
	step({
		platform.Mouse_Moved{window = 99, x = 5, y = 5},
		platform.Resized{window = 99, width = 1, height = 1},
		platform.Close_Requested{window = 99},
		platform.Pixel_Size_Changed{window = 1, width = 10, height = 10},
		platform.Scale_Changed{window = 1},
		platform.Moved{window = 1},
	})
	testing.expect_value(t, mouse(), [2]f64{0, 0})
	testing.expect_value(t, len(the.windows), 1)
}

// ---- the clock ----

@(test)
test_the_clock_and_the_frame_count_advance_with_each_step :: proc(t: ^testing.T) {
	begin()
	defer finish()
	circle(0, 0, 1)
	testing.expect_value(t, frame_count(), 0)
	step(dt = 0.5)
	step(dt = 0.5)
	testing.expect_value(t, frame_count(), 2)
	testing.expect_value(t, time_now(), 1.0)
	testing.expect_value(t, frame_rate(), 2.0)
}

@(test)
test_a_step_with_no_windows_still_runs :: proc(t: ^testing.T) {
	begin()
	defer finish()
	step()
	testing.expect_value(t, frame_count(), 1)
	testing.expect_value(t, len(the.windows), 0)
}

@(test)
test_a_headless_sketch_cannot_run_a_loop :: proc(t: ^testing.T) {
	begin()
	testing.expect(t, !run(proc() {}))
}

// ---- the registry ----

@(test)
test_every_registry_verb_has_an_odin_name_and_no_name_is_invented :: proc(t: ^testing.T) {
	for verb in registry.VERBS {
		found := false
		for entry in API_NAMES {
			if entry.verb == verb.name {
				found = true
			}
		}
		testing.expectf(t, found, "the registry's `%s` has no entry in API_NAMES", verb.name)
	}
	for entry in API_NAMES {
		_, ok := registry.find_verb(entry.verb)
		testing.expectf(t, ok, "API_NAMES names `%s`, which the registry does not have", entry.verb)
	}
	for a, i in API_NAMES {
		for b in API_NAMES[i + 1:] {
			testing.expectf(t, a.verb != b.verb, "`%s` is listed twice", a.verb)
		}
	}
}

// ---- the benchmark's work counts ----

draw_many_circles :: proc() {
	no_stroke()
	for i in 0 ..< 100_000 {
		if i % 100 == 0 {
			fill(hsb(f64(i / 100 % 255), 200, 255, 200))
		}
		circle(f64(i * 7919 % 800), f64(i * 104729 % 600), 2 + f64(i % 5))
	}
}

@(test)
test_a_hundred_thousand_circles_are_one_draw_and_a_steady_frame_allocates_nothing :: proc(t: ^testing.T) {
	// Work counts are exact on every machine: the pipelines compare
	// these where timing would be too noisy.
	begin()
	defer finish()
	window(800, 600)
	draw(draw_many_circles)
	step()
	step()
	stats := the.windows[0].batcher.stats
	testing.expect_value(t, stats.commands, 100_000)
	testing.expect_value(t, stats.instances, 100_000)
	testing.expect_value(t, stats.draws, 1)
	testing.expect_value(t, stats.batches, 1)
	testing.expect_value(t, stats.skipped, 0)
	testing.expect_value(t, stats.reallocations, 0)
}

@(test)
test_set_up_verbs_act_on_the_window_just_made :: proc(t: ^testing.T) {
	begin()
	defer finish()
	a := window(100, 100)
	title("first")
	circle(1, 1, 1)
	b := window(200, 200)
	title("second")
	rect(0, 0, 1, 1)
	rect(1, 1, 1, 1)
	testing.expect_value(t, win_for(a).title, "first")
	testing.expect_value(t, win_for(b).title, "second")
	testing.expect_value(t, len(commands_of(a)), 1)
	testing.expect_value(t, len(commands_of(b)), 2)
	testing.expect_value(t, current_window(), b)
}

@(test)
test_the_first_window_call_still_keeps_what_was_drawn_before_it :: proc(t: ^testing.T) {
	begin()
	defer finish()
	circle(1, 1, 1) // makes the default window
	a := window(300, 200)
	testing.expect_value(t, len(the.windows), 1)
	testing.expect_value(t, len(commands_of(a)), 1)
	testing.expect_value(t, current_window(), a)
}

@(test)
test_when_the_newest_window_closes_the_verbs_go_to_the_default_one :: proc(t: ^testing.T) {
	begin()
	defer finish()
	a := window(100, 100)
	b := window(200, 200)
	testing.expect_value(t, current_window(), b)
	close_window(win_for(b))
	testing.expect_value(t, current_window(), a)
	title("still here")
	testing.expect_value(t, win_for(a).title, "still here")
}

@(test)
test_a_draw_block_still_draws_into_its_own_window :: proc(t: ^testing.T) {
	begin()
	defer finish()
	which_window = {}
	defer delete(which_window)
	a := window(100, 100)
	_ = window(200, 200) // the newest, but `a`'s block draws into `a`
	draw(a, record_window)
	step()
	testing.expect_value(t, which_window[0], a)
	testing.expect_value(t, len(commands_of(a)), 1)
}
