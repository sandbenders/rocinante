// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "core:strings"
import "core:testing"
import sdl "vendor:sdl3"

@(test)
test_a_sketch_starts_in_its_first_scene_and_a_go_at_the_top_picks_another :: proc(t: ^testing.T) {
	p := run_text(t, `
scene "a" [ on enter [ print "enter a" ] ]
scene "b" [ on enter [ print "enter b" ] ]
`)
	defer finish(p)
	testing.expect_value(t, current_scene_name(p), "a")
	testing.expect_value(t, printed(p), "enter a")
	q := run_text(t, `
go "b"
scene "a" [ on enter [ print "enter a" ] ]
scene "b" [ on enter [ print "enter b" ] ]
`)
	defer finish(q)
	testing.expect_value(t, current_scene_name(q), "b")
	testing.expect_value(t, printed(q), "enter b")
}

@(test)
test_a_sketch_with_no_scenes_works_as_it_always_did :: proc(t: ^testing.T) {
	p := run_text(t, "n = 0\ndraw [ n = n + 1 ]\nwho = scene.name\nsince = scene.frame\n", 3)
	defer finish(p)
	testing.expect_value(t, current_scene_name(p), "")
	testing.expect_value(t, as_number(global_named(p, "n")), 3)
	testing.expect_value(t, as_text(global_named(p, "who")), "")
}

@(test)
test_go_changes_scene_when_the_frame_ends_and_the_code_after_it_still_runs :: proc(t: ^testing.T) {
	p := run_text(t, `
window size 100 100
scene "a" [
  on key "space" [
    go "b"
    print "after go in {scene.name}"
  ]
  on leave [ print "leave a" ]
  draw [ print "draw a" ]
]
scene "b" [
  on enter [ print "enter b" ]
  draw [ print "draw b" ]
]
`, 1)
	defer finish(p)
	w := first_window()
	clear(&p.printed)
	roci.step({key_event(w, sdl.Scancode.SPACE)})
	// the handler ran and drew a, then the frame ended and the scene changed
	testing.expect_value(t, printed(p), "after go in a\ndraw a\nleave a\nenter b")
	testing.expect_value(t, current_scene_name(p), "b")
	clear(&p.printed)
	roci.step()
	testing.expect_value(t, printed(p), "draw b")
}

@(test)
test_the_first_change_asked_in_a_frame_is_the_one_made :: proc(t: ^testing.T) {
	p := run_text(t, `
window size 100 100
scene "a" [ on key "space" [ go "b"
 go "c" ] ]
scene "b" [ draw [ print "b" ] ]
scene "c" [ draw [ print "c" ] ]
`, 1)
	defer finish(p)
	roci.step({key_event(first_window(), sdl.Scancode.SPACE)})
	testing.expect_value(t, current_scene_name(p), "b")
}

@(test)
test_shared_blocks_run_in_every_scene_first_and_a_scene_runs_only_while_it_is_current :: proc(t: ^testing.T) {
	p := run_text(t, `
window size 100 100
draw [ print "shared draw" ]
on key "space" [ print "shared key" ]
every 1 frames [ print "shared every" ]
scene "a" [
  draw [ print "a" ]
  on key "space" [ print "a key"
   go "b" ]
]
scene "b" [
  draw [ print "b" ]
  on key "space" [ print "b key" ]
]
`, 1)
	defer finish(p)
	clear(&p.printed)
	roci.step({key_event(first_window(), sdl.Scancode.SPACE)})
	got := printed(p)
	testing.expect(t, strings.index(got, "shared key") >= 0 && strings.index(got, "a key") >= 0, got)
	testing.expect(t, strings.index(got, "b key") < 0, got)
	testing.expect(t, strings.index(got, "shared draw") < strings.index(got, "\na\n") || strings.has_suffix(got, "a") || strings.contains(got, "shared draw\na"), got)
	clear(&p.printed)
	roci.step({key_event(first_window(), sdl.Scancode.SPACE, false)})
	roci.step({key_event(first_window(), sdl.Scancode.SPACE)})
	got = printed(p)
	testing.expect(t, strings.contains(got, "b key") && !strings.contains(got, "a key"), got)
}

@(test)
test_a_scene_that_is_visited_over_stops_and_return_lets_it_go_on_without_entering_again :: proc(t: ^testing.T) {
	p := run_text(t, `
window size 100 100
ticks = 0
scene "play" [
  on enter [ print "enter play" ]
  on leave [ print "leave play" ]
  every 1 frames [ ticks = ticks + 1 ]
  on key "p" [ visit "pause" ]
  on key "q" [ go "play" ]
]
scene "pause" [
  on enter [ print "enter pause" ]
  on leave [ print "leave pause" ]
  on key "p" [ return ]
]
`, 3)
	defer finish(p)
	w := first_window()
	ran := as_number(global_named(p, "ticks"))
	testing.expect(t, ran >= 1)
	clear(&p.printed)
	roci.step({key_event(w, sdl.Scancode.P)})
	testing.expect_value(t, current_scene_name(p), "pause")
	testing.expect_value(t, len(p.scene_stack), 2)
	roci.step({key_event(w, sdl.Scancode.P, false)})
	frozen := as_number(global_named(p, "ticks"))
	for _ in 0 ..< 10 {
		roci.step()
	}
	testing.expect_value(t, as_number(global_named(p, "ticks")), frozen)
	roci.step({key_event(w, sdl.Scancode.P)})
	testing.expect_value(t, current_scene_name(p), "play")
	testing.expect_value(t, len(p.scene_stack), 1)
	roci.step()
	roci.step()
	testing.expect(t, as_number(global_named(p, "ticks")) > frozen)
	// pause entered and left, play was left alone: no second enter, no leave
	testing.expect_value(t, printed(p), "enter pause\nleave pause")
	// a go from the visited scene's neighbours ends the whole stack
	roci.step({key_event(w, sdl.Scancode.P, false)})
	roci.step({key_event(w, sdl.Scancode.P)})
	roci.step({key_event(w, sdl.Scancode.P, false)})
	clear(&p.printed)
	roci.step({key_event(w, sdl.Scancode.P)}) // back to play from pause
	roci.step({key_event(w, sdl.Scancode.P, false)})
	roci.step({key_event(w, sdl.Scancode.Q)})
	testing.expect(t, strings.contains(printed(p), "leave play\nenter play"), printed(p))
}

@(test)
test_a_scene_keeps_its_own_time_which_stops_while_it_is_visited_over :: proc(t: ^testing.T) {
	p := run_text(t, `
window size 100 100
since = 0
frames_in = 0
scene "play" [
  draw [
    since = scene.time
    frames_in = scene.frame
  ]
  on key "p" [ visit "pause" ]
]
scene "pause" [ on key "p" [ return ] ]
`, 61)
	defer finish(p)
	w := first_window()
	before := as_number(global_named(p, "since"))
	testing.expect(t, before > 0.9 && before < 1.2, "a second into the scene")
	testing.expect(t, as_number(global_named(p, "frames_in")) >= 60)
	roci.step({key_event(w, sdl.Scancode.P)})
	roci.step({key_event(w, sdl.Scancode.P, false)})
	for _ in 0 ..< 120 {
		roci.step()
	}
	roci.step({key_event(w, sdl.Scancode.P)})
	roci.step({key_event(w, sdl.Scancode.P, false)})
	roci.step()
	after := as_number(global_named(p, "since"))
	testing.expect(t, after < before + 0.2, "the two seconds of the pause did not count")
}

@(test)
test_return_with_nothing_visited_is_said_and_the_sketch_goes_on :: proc(t: ^testing.T) {
	p := run_text(t, `
scene "play" [
  on enter [ return ]
  on enter [ print "still here" ]
]
`, 2)
	defer finish(p)
	testing.expect_value(t, printed(p), "still here")
	found := false
	for e in p.errors {
		found ||= e.id == .Return_Nothing
	}
	testing.expect(t, found)
	testing.expect_value(t, current_scene_name(p), "play")
}

@(test)
test_a_tween_a_scene_started_ends_with_the_scene_and_waits_while_it_is_visited_over :: proc(t: ^testing.T) {
	p := run_text(t, `
window size 100 100
x = 0
scene "a" [
  on key "t" [ tween x to 100 over 1 ]
  on key "p" [ visit "pause" ]
  on key "g" [ go "b" ]
]
scene "pause" [ on key "p" [ return ] ]
scene "b" [ draw [ x = x ] ]
`, 1)
	defer finish(p)
	w := first_window()
	roci.step({key_event(w, sdl.Scancode.T)})
	roci.step({key_event(w, sdl.Scancode.T, false)})
	testing.expect_value(t, len(p.tweens), 1)
	roci.step({key_event(w, sdl.Scancode.P)})
	roci.step({key_event(w, sdl.Scancode.P, false)})
	at := as_number(global_named(p, "x"))
	for _ in 0 ..< 5 {
		roci.step()
	}
	testing.expect_value(t, as_number(global_named(p, "x")), at) // waiting
	roci.step({key_event(w, sdl.Scancode.P)})
	roci.step({key_event(w, sdl.Scancode.P, false)})
	roci.step({key_event(w, sdl.Scancode.G)})
	testing.expect_value(t, len(p.tweens), 0)
	testing.expect_value(t, current_scene_name(p), "b")
}

@(test)
test_a_reload_keeps_the_scene_it_was_in_and_a_scene_that_is_gone_sends_it_to_the_first :: proc(t: ^testing.T) {
	roci.start_headless(1)
	first := `
window size 100 100
scene "title" [ on key "space" [ go "play" ] ]
scene "play" [ draw [ circle at 50 50 radius 10 ] ]
`
	p, ok := load("test.roci", first)
	testing.expect(t, ok)
	start(p)
	roci.step()
	roci.step({key_event(first_window(), sdl.Scancode.SPACE)})
	testing.expect_value(t, current_scene_name(p), "play")
	// the same scenes, a line changed: still in play
	same, outcome := reload(p, `
window size 100 100
scene "title" [ on key "space" [ go "play" ] ]
scene "play" [ draw [ circle at 50 50 radius 20 ] ]
`)
	testing.expect_value(t, outcome, Outcome.Reloaded)
	testing.expect_value(t, current_scene_name(same), "play")
	// a new scene written first moves the others' places, and the stack follows by name
	moved, outcome2 := reload(same, `
window size 100 100
scene "intro" [ draw [ background 0 ] ]
scene "title" [ on key "space" [ go "play" ] ]
scene "play" [ draw [ circle at 50 50 radius 20 ] ]
`)
	testing.expect_value(t, outcome2, Outcome.Reloaded)
	testing.expect_value(t, current_scene_name(moved), "play")
	// the scene it was in is gone: back to the first one
	gone, outcome3 := reload(moved, `
window size 100 100
scene "intro" [ draw [ background 0 ] ]
scene "title" [ draw [ background 10 ] ]
`)
	testing.expect_value(t, outcome3, Outcome.Reloaded)
	testing.expect_value(t, current_scene_name(gone), "intro")
	finish_all()
}

@(test)
test_enter_and_leave_outside_every_scene_run_for_each_scene :: proc(t: ^testing.T) {
	p := run_text(t, `
window size 100 100
on enter [ print "any enter {scene.name}" ]
on leave [ print "any leave" ]
scene "a" [ on key "space" [ go "b" ] ]
scene "b" [ draw [ background 0 ] ]
`, 1)
	defer finish(p)
	roci.step({key_event(first_window(), sdl.Scancode.SPACE)})
	testing.expect_value(t, printed(p), "any enter a\nany leave\nany enter b")
}

@(test)
test_scenes_may_be_written_in_other_files_of_the_sketch :: proc(t: ^testing.T) {
	roci.start_headless(1)
	defer roci.shutdown()
	p, ok := load_files({
		{name = "title.roci", text = "scene \"title\" [ on enter [ print \"title\" ] ]\n"},
		{name = "sketch.roci", text = "window size 100 100\nscene \"play\" [ draw [ background 0 ] ]\n"},
	})
	defer destroy(p)
	testing.expect(t, ok, "scenes may be in a file of their own")
	start(p)
	testing.expect_value(t, current_scene_name(p), "title")
	testing.expect_value(t, printed(p), "title")
}
