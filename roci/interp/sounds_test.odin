// SPDX-License-Identifier: 0BSD
package interp

import "core:os"
import "core:testing"
import "../"
import "../folder"
import "../lang"
import "../platform"
import sdl "vendor:sdl3"

// Runs a sketch in a folder whose assets/sounds hold copies of the files named, from `from`.
@(private = "file")
run_with_sounds :: proc(t: ^testing.T, folder_name, text, from: string, files: []string) -> ^Interp {
	root := concat("output/tests/", folder_name)
	_ = os.remove_all(root)
	testing.expect(t, folder.ensure_directory(concat(root, "/assets/sounds")))
	for name in files {
		data, err := os.read_entire_file(concat(from, "/", name), context.temp_allocator)
		testing.expect(t, err == nil)
		testing.expect(t, os.write_entire_file(concat(root, "/assets/sounds/", name), data) == nil)
	}
	path := concat(root, "/sketch.roci")
	testing.expect(t, os.write_entire_file(path, transmute([]byte)text) == nil)
	roci.start_headless(1)
	p, ok := load(path, text)
	if !testing.expectf(t, ok, "the sketch has errors:\n%s", lang.render_all(p.src, p.checked.diagnostics, context.temp_allocator)) {
		return p
	}
	watch(p, path)
	start(p)
	roci.step()
	return p
}

@(private = "file")
sound_of :: proc(p: ^Interp, name: string) -> roci.Sound_State {
	return roci.sound_state(as_sound(global_named(p, name)))
}

// The example: the rain loops at a volume and pan that follow the mouse, a click plays the click
// from where it is pressed and leaves a ring, and space pauses the rain and goes on.
@(test)
test_the_sound_example_follows_the_mouse_and_clicks :: proc(t: ^testing.T) {
	text, read := os.read_entire_file("examples/sound/sketch.roci", context.temp_allocator)
	testing.expect(t, read == nil)
	p := run_with_sounds(t, "sound_example", string(text), "examples/sound/assets/sounds", {"rain.ogg", "click.wav"})
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	rain := sound_of(p, "rain")
	testing.expect(t, rain.playing && rain.looping)
	testing.expectf(t, rain.length > 3.9 && rain.length < 4.1, "rain is %v seconds", rain.length)
	testing.expect(t, !sound_of(p, "click").playing)
	w := first_window()
	// the mouse three quarters across and a quarter down: three quarters loud, half to the right
	roci.step({platform.Mouse_Moved{window = platform.Window_Id(w), x = 480, y = 100}})
	rain = sound_of(p, "rain")
	testing.expectf(t, abs(rain.volume - 75) < 1e-9 && abs(rain.pan - 50) < 1e-9, "volume %v pan %v", rain.volume, rain.pan)
	roci.step({click_event(w, 480, 100)})
	click := sound_of(p, "click")
	testing.expect(t, click.playing)
	testing.expectf(t, abs(click.pan - 50) < 1e-9, "the click is at %v", click.pan)
	testing.expect_value(t, len(as_list(global_named(p, "rings")).items), 1)
	// the click is short, and has ended a few frames on; its ring goes after 33 frames
	for _ in 0 ..< 40 {
		roci.step()
	}
	testing.expect(t, !sound_of(p, "click").playing)
	testing.expect_value(t, len(as_list(global_named(p, "rings")).items), 0)
	// space pauses the rain where it is, and again goes on
	roci.step({key_event(w, sdl.Scancode.SPACE)})
	at := sound_of(p, "rain").at
	testing.expect(t, !sound_of(p, "rain").playing)
	roci.step()
	testing.expect_value(t, sound_of(p, "rain").at, at)
	roci.step({key_event(w, sdl.Scancode.SPACE, false)})
	roci.step({key_event(w, sdl.Scancode.SPACE)})
	testing.expect(t, sound_of(p, "rain").playing)
	testing.expect_value(t, len(p.errors), 0)
}

// Every word of a sound, read and written by a sketch, in the frames of a headless run.
@(test)
test_sound_words :: proc(t: ^testing.T) {
	text := `tone = load "tone.wav"
same = load "tone.wav"
print tone
print (tone is same)
loop tone volume 30 pan 20 speed 0.5
draw [
  if frame is 10 [
    print tone.playing
    print tone.loop
    print tone.volume
    print tone.pan
    print tone.speed
    print tone.length
    set tone at 0.2 loop false speed 1
    rewind tone by 0.05
    print tone.at
    forward tone by 0.01
    print tone.at
    rewind tone
    print tone.at
    pause tone
    print tone.playing
    play tone volume 10
    forward tone by 1
    print tone.playing
  ]
]
`
	p := run_with_sounds(t, "sound_words", text, "tests/sounds", {"tone.wav"})
	defer finish(p)
	for _ in 0 ..< 12 {
		roci.step()
	}
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, printed(p), "a 0.25 second sound\ntrue\ntrue\ntrue\n30\n20\n0.5\n0.25\n0.15\n0.16\n0\nfalse\nfalse")
}

// A file saved again is decoded into the same sound, which goes on as it was.
@(test)
test_sound_file_saved_again :: proc(t: ^testing.T) {
	text := "tone = load \"tone.wav\"\nloop tone volume 40\ndraw [ circle at 10 10 radius tone.length ]\n"
	p := run_with_sounds(t, "sound_saved", text, "tests/sounds", {"tone.wav"})
	defer finish(p)
	s := as_sound(global_named(p, "tone"))
	entry := p.sounds["tone.wav"]
	// the file changes: a FLAC of the same tone under the WAV's name, with another time
	data, _ := os.read_entire_file("tests/sounds/tone.flac", context.temp_allocator)
	testing.expect(t, os.write_entire_file(entry.path, data) == nil)
	stale := entry
	stale.mtime._nsec -= 1_000_000_000
	stale.checked = -1
	p.sounds["tone.wav"] = stale
	testing.expect_value(t, load_sound(p, "tone.wav", {}), Value(s))
	st := roci.sound_state(s)
	testing.expect(t, st.playing && st.looping && abs(st.volume - 40) < 1e-9)
	testing.expect(t, p.sounds["tone.wav"].mtime != stale.mtime)
}

@(test)
test_sound_problems_are_said_once :: proc(t: ^testing.T) {
	source :: "output/tests/sound_problems_source"
	testing.expect(t, folder.ensure_directory(source))
	testing.expect(t, os.write_entire_file(source + "/broken.wav", transmute([]byte)string("nope")) == nil)
	text := "a = load \"none.wav\"\nb = load \"broken.wav\"\nplay a\nplay b\ndraw [ c = load \"none.wav\" ]\n"
	p := run_with_sounds(t, "sound_problems", text, source, {"broken.wav"})
	defer finish(p)
	testing.expect_value(t, p.sounds["broken.wav"].state, Picture_State.Unreadable)
	testing.expect_value(t, p.sounds["none.wav"].state, Picture_State.Missing)
	for _ in 0 ..< 3 {
		roci.step()
	}
	// each place that loads the missing file says so once, however many frames ask
	missing, unreadable := 0, 0
	for e in p.errors {
		#partial switch e.id {
		case .Sound_Missing:    missing += 1
		case .Sound_Unreadable: unreadable += 1
		}
	}
	testing.expect_value(t, missing, 2)
	testing.expect_value(t, unreadable, 1)
	// a sketch with no folder finds nothing
	q, _ := load("", "a = load \"tone.wav\"\n")
	defer destroy(q)
	testing.expect_value(t, load_sound(q, "tone.wav", {}), Value(nil))
}

// Two files of one name: the message names both and suggests one with its folder.
@(test)
test_sound_ambiguous :: proc(t: ^testing.T) {
	p := run_with_sounds(t, "sound_twins", "a = 1\n", "tests/sounds", {})
	defer finish(p)
	root := "output/tests/sound_twins/assets/sounds"
	testing.expect(t, folder.ensure_directory(concat(root, "/a")))
	testing.expect(t, folder.ensure_directory(concat(root, "/b")))
	data, _ := os.read_entire_file("tests/sounds/tone.wav", context.temp_allocator)
	testing.expect(t, os.write_entire_file(concat(root, "/a/twin.wav"), data) == nil)
	testing.expect(t, os.write_entire_file(concat(root, "/b/twin.wav"), data) == nil)
	testing.expect_value(t, load_sound(p, "twin.wav", {}), Value(nil))
	testing.expect_value(t, p.sounds["twin.wav"].state, Picture_State.Ambiguous)
	testing.expect(t, p.sounds["twin.wav"].suggest != "")
	// asked again within the second, it is not looked for again
	testing.expect_value(t, load_sound(p, "twin.wav", {}), Value(nil))
}
