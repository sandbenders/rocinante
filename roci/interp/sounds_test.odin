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

// The bricks example plays a sound for each hit: glass for a brick, wood for a wall, a plate for
// the paddle, each from the start and from where the ball is between the speakers.
@(test)
test_the_bricks_example_sounds_every_hit :: proc(t: ^testing.T) {
	text, read := os.read_entire_file("examples/bricks/sketch.roci", context.temp_allocator)
	testing.expect(t, read == nil)
	p := run_with_sounds(t, "bricks_example", string(text), "examples/bricks/assets/sounds", {"brick.ogg", "wall.ogg", "paddle.ogg", "miss.ogg"})
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	for name in ([]string{"brick_sound", "wall_sound", "paddle_sound", "miss_sound"}) {
		st := sound_of(p, name)
		testing.expectf(t, st.length > 0.1 && st.length < 1.6 && st.at == 0 && !st.playing, "%s: %v", name, st)
	}
	// up and to the right from the middle: the lowest row of bricks is reached in under thirty frames
	before := len(as_list(global_named(p, "bricks")).items)
	frames := 0
	for len(as_list(global_named(p, "bricks")).items) == before && frames < 60 {
		roci.step()
		frames += 1
	}
	brick := sound_of(p, "brick_sound")
	testing.expectf(t, brick.playing && brick.at < 0.05, "a brick broke and its sound started: %v", brick)
	testing.expect(t, brick.pan > 0, "the ball is right of the middle")
	testing.expect(t, sound_of(p, "wall_sound").at == 0)
	// the paddle is under the mouse: put it where the ball comes down, and it plays the plate
	w := first_window()
	paddle_played, wall_played := false, false
	for _ in 0 ..< 200 {
		x := as_vec(read_field(p, global_named(p, "ball"), "pos")).v[0]
		roci.step({platform.Mouse_Moved{window = platform.Window_Id(w), x = f32(x), y = 300}})
		paddle_played ||= sound_of(p, "paddle_sound").at > 0
		wall_played ||= sound_of(p, "wall_sound").at > 0
	}
	testing.expect(t, paddle_played, "the paddle sounded")
	testing.expect(t, wall_played, "a wall sounded")
	testing.expect(t, sound_of(p, "miss_sound").at == 0, "the paddle missed nothing")
	// with the paddle far to the left the ball falls out: the bell tolls and the ball is served again
	missed := false
	for _ in 0 ..< 300 {
		roci.step({platform.Mouse_Moved{window = platform.Window_Id(w), x = 0, y = 300}})
		if sound_of(p, "miss_sound").playing {
			missed = true
			break
		}
	}
	testing.expect(t, missed, "the bell tolled")
	ball := global_named(p, "ball")
	testing.expect_value(t, as_pair(read_field(p, ball, "pos")), [2]f64{240, 250})
	testing.expect_value(t, as_pair(read_field(p, ball, "vel")), [2]f64{3, -4})
	// the last brick broken, the wall is built again and the ball served
	clear(&as_list(global_named(p, "bricks")).items)
	roci.step()
	testing.expect_value(t, len(as_list(global_named(p, "bricks")).items), 40)
	testing.expect_value(t, as_pair(read_field(p, ball, "pos")), [2]f64{240, 250})
	testing.expect_value(t, len(p.errors), 0)
}

// The music example draws what plays, and M turns it to the microphone, which a test feeds.
@(test)
test_the_music_example_draws_what_it_hears :: proc(t: ^testing.T) {
	text, read := os.read_entire_file("examples/music/sketch.roci", context.temp_allocator)
	testing.expect(t, read == nil)
	p := run_with_sounds(t, "music_example", string(text), "examples/music/assets/sounds", {"title.ogg"})
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	for _ in 0 ..< 30 {
		roci.step()
	}
	testing.expectf(t, as_number(global_named(p, "loud")) > 10, "the tune is loud: %v", global_named(p, "loud"))
	heard := as_list(global_named(p, "heard"))
	testing.expect_value(t, len(heard.items), 32)
	risen := 0
	for bar in as_list(global_named(p, "bars")).items {
		if as_number(read_field(p, bar, "high")) > 5 {
			risen += 1
		}
	}
	testing.expectf(t, risen > 16, "most bars rose: %d", risen)
	// M: the microphone, silent until it hears something
	w := first_window()
	roci.step({key_event(w, sdl.Scancode.M)})
	testing.expect(t, as_bool(global_named(p, "listening")))
	testing.expect(t, !sound_of(p, "tune").playing, "the tune pauses")
	paused_at := sound_of(p, "tune").at
	roci.step()
	testing.expect_value(t, as_number(global_named(p, "loud")), 0)
	clap := make([]f32, 2048, context.temp_allocator)
	for &v, i in clap {
		v = 0.8 if (i / 20) % 2 == 0 else -0.8
	}
	roci.feed_microphone(clap)
	roci.step()
	testing.expectf(t, as_number(global_named(p, "loud")) > 50, "the clap is loud: %v", global_named(p, "loud"))
	testing.expect_value(t, sound_of(p, "tune").at, paused_at)
	// M again: the tune goes on from where it paused
	roci.step({key_event(w, sdl.Scancode.M, false)})
	roci.step({key_event(w, sdl.Scancode.M)})
	tune := sound_of(p, "tune")
	testing.expect(t, !as_bool(global_named(p, "listening")))
	testing.expect(t, tune.playing && tune.looping, "the tune goes on, looping")
	testing.expectf(t, tune.at > paused_at && tune.at < paused_at + 0.1, "from where it was: %v after %v", tune.at, paused_at)
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_level_bands_and_mic_in_a_sketch :: proc(t: ^testing.T) {
	text := `tone = load "tone.wav"
print (level)
print (count (bands))
print (count (bands 4))
print (count (bands tone 300))
nothing = 0 / 0
print (count (bands tone nothing))
print mic.playing
loop tone
draw [
  if frame is 5 [
    tone_level = level tone
    print (tone_level > 10 and tone_level < 15)
    print ((level) > 10)
    print (level mic)
    b = bands tone 8
    fourth = item 4 of b
    print (fourth > 50)
  ]
]
`
	p := run_with_sounds(t, "level_words", text, "tests/sounds", {"tone.wav"})
	defer finish(p)
	for _ in 0 ..< 10 {
		roci.step()
	}
	// 0 / 0 is 0 (said once as a division by zero), and fewer than one band is one
	testing.expect_value(t, printed(p), "0\n16\n4\n256\n1\nfalse\ntrue\ntrue\n0\ntrue")
}

// The keys example: a held key plays its note and letting it go lets the note go; keys held
// together sound together, and a click plays a key too.
@(test)
test_the_keys_example_plays_held_keys :: proc(t: ^testing.T) {
	text, read := os.read_entire_file("examples/keys/sketch.roci", context.temp_allocator)
	testing.expect(t, read == nil)
	p := run_with_sounds(t, "keys_example", string(text), "examples/keys", {})
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	piano := as_sound(global_named(p, "piano"))
	notes_on := roci.sound_notes
	testing.expect_value(t, notes_on(piano), 3) // the chord it starts with
	for _ in 0 ..< 80 {
		roci.step()
	}
	testing.expect_value(t, notes_on(piano), 0)
	w := first_window()
	roci.step({key_event(w, sdl.Scancode.A), key_event(w, sdl.Scancode.D), key_event(w, sdl.Scancode.G)})
	testing.expect_value(t, notes_on(piano), 3)
	testing.expect(t, roci.sound_state(piano).playing)
	roci.step({key_event(w, sdl.Scancode.D, false)})
	for _ in 0 ..< 10 {
		roci.step()
	}
	testing.expect_value(t, notes_on(piano), 2)
	roci.step({key_event(w, sdl.Scancode.A, false), key_event(w, sdl.Scancode.G, false)})
	for _ in 0 ..< 10 {
		roci.step()
	}
	testing.expect_value(t, notes_on(piano), 0)
	// a click on the fourth key plays F until the button comes up
	roci.step({platform.Mouse_Moved{window = platform.Window_Id(w), x = 260, y = 200}, click_event(w, 260, 200)})
	roci.step()
	testing.expect_value(t, as_number(global_named(p, "clicked")), 65)
	testing.expect_value(t, len(p.errors), 0)
}

// A sketch plays an instrument from a MIDI keyboard, and reads a controller.
@(test)
test_midi_in_a_sketch :: proc(t: ^testing.T) {
	text := `piano = synth triangle
on midi down [ play piano note midi.note volume midi.velocity ]
on midi up [ pause piano note midi.note ]
on midi control [ print midi.control  print (round midi.value) ]
draw [ wheel_now = midi control 1 ]
`
	p := run_with_sounds(t, "midi_words", text, "tests/sounds", {})
	defer finish(p)
	piano := as_sound(global_named(p, "piano"))
	roci.feed_midi({0x90, 60, 64, 0x90, 64, 127})
	roci.step()
	testing.expect_value(t, roci.sound_notes(piano), 2)
	testing.expectf(t, abs(roci.sound_state(piano).volume - 100) < 1e-9, "the louder key last: %v", roci.sound_state(piano).volume)
	roci.feed_midi({0x90, 60, 0, 0xB0, 1, 127})
	roci.step()
	testing.expect_value(t, roci.sound_notes(piano), 1)
	testing.expect_value(t, printed(p), "1\n100")
	roci.step()
	testing.expect_value(t, as_number(global_named(p, "wheel_now")), 100)
	testing.expect_value(t, len(p.errors), 0)
}

// The MIDI example: a chord held plays three notes, lights three keys and leaves three rings; the
// knob or wheel turns the colors and controller 7 also sets the volume.
@(test)
test_the_midi_example_plays_and_draws :: proc(t: ^testing.T) {
	text, read := os.read_entire_file("examples/midi/sketch.roci", context.temp_allocator)
	testing.expect(t, read == nil)
	p := run_with_sounds(t, "midi_example", string(text), "examples/midi", {})
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	piano := as_sound(global_named(p, "piano"))
	roci.feed_midi({0x90, 60, 100, 0x90, 64, 80, 0x90, 67, 60})
	roci.step()
	testing.expect_value(t, roci.sound_notes(piano), 3)
	testing.expect_value(t, len(as_list(global_named(p, "down_notes")).items), 3)
	testing.expect_value(t, len(as_list(global_named(p, "rings")).items), 3)
	roci.feed_midi({0x80, 64, 0, 0xB0, 70, 127})
	roci.step()
	testing.expect_value(t, roci.sound_notes(piano), 2)
	testing.expect_value(t, len(as_list(global_named(p, "down_notes")).items), 2)
	testing.expect_value(t, as_number(global_named(p, "turn_colors")), 360)
	roci.feed_midi({0xB0, 7, 64})
	roci.step()
	testing.expectf(t, abs(roci.sound_state(piano).volume - 50.39) < 0.01, "%v", roci.sound_state(piano).volume)
	// the rings fade away after a hundred frames
	for _ in 0 ..< 101 {
		roci.step()
	}
	testing.expect_value(t, len(as_list(global_named(p, "rings")).items), 0)
	testing.expect_value(t, len(p.errors), 0)
}

// An instrument from a SoundFont in the assets, by preset number or name; a synth in draw makes one
// instrument, not one a frame.
@(test)
test_soundfonts_in_a_sketch :: proc(t: ^testing.T) {
	text := `sine = synth "tiny.sf2"
split = synth "tiny.sf2" preset 1
drums = synth "tiny.sf2" preset "drums"
play sine note 69
print sine.pitch
draw [
  again = synth "tiny.sf2" preset 1
  if frame is 3 [ print (again is split)  print ((level sine) > 10) ]
]
`
	p := run_with_sounds(t, "soundfont_words", text, "tests/sounds", {"tiny.sf2"})
	defer finish(p)
	for _ in 0 ..< 4 {
		roci.step()
	}
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, printed(p), "440\ntrue\ntrue")
	testing.expect(t, as_sound(global_named(p, "drums")) != as_sound(global_named(p, "split")))
}

// The SoundFont example: the chord it starts with, then keys held grow bars that float away when let go.
@(test)
test_the_soundfont_example_plays_the_piano :: proc(t: ^testing.T) {
	text, read := os.read_entire_file("examples/soundfont/sketch.roci", context.temp_allocator)
	testing.expect(t, read == nil)
	p := run_with_sounds(t, "soundfont_example", string(text), "examples/soundfont/assets/sounds", {"upright.sf2"})
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	piano := as_sound(global_named(p, "piano"))
	testing.expect(t, roci.sound_state(piano).playing, "the chord")
	testing.expect_value(t, len(as_list(global_named(p, "bars")).items), 4)
	w := first_window()
	roci.step({key_event(w, sdl.Scancode.A)})
	testing.expect_value(t, len(as_list(global_named(p, "bars")).items), 5)
	roci.feed_midi({0x90, 50, 90})
	roci.step()
	testing.expect_value(t, len(as_list(global_named(p, "bars")).items), 6)
	testing.expect(t, roci.level(piano) > 1)
	roci.feed_midi({0x80, 50, 0})
	roci.step({key_event(w, sdl.Scancode.A, false)})
	// every bar floats off the top in time
	for _ in 0 ..< 300 {
		roci.step()
	}
	testing.expect_value(t, len(as_list(global_named(p, "bars")).items), 0)
	testing.expect_value(t, len(p.errors), 0)
}

// An `on midi down` block that runs while the loop waits for the screen draws into the frame that
// is then built, and runs once.
@(test)
test_midi_blocks_run_early :: proc(t: ^testing.T) {
	text := `struck = 0
on midi down [
  struck = struck + 1
  circle at 50 50 radius midi.velocity
]
draw [ background 20 ]
`
	p := run_with_sounds(t, "midi_early", text, "tests/sounds", {})
	defer finish(p)
	w := first_window()
	plain := roci.frame_hash(w) // a frame of the background alone
	roci.feed_midi({0x90, 60, 127})
	roci.midi_early()
	testing.expect_value(t, as_number(global_named(p, "struck")), 1)
	roci.step()
	testing.expect_value(t, as_number(global_named(p, "struck")), 1)
	// the frame built after it holds the circle, and the next one does not
	with_circle := roci.frame_hash(w)
	testing.expect(t, with_circle != plain, "the circle drawn early is in the frame")
	roci.step()
	testing.expect_value(t, roci.frame_hash(w), plain)
	testing.expect_value(t, len(p.errors), 0)
}

// Sound effects in a sketch: put on, changed, taken off, on a sound and on the speakers.
@(test)
test_sound_effects_in_a_sketch :: proc(t: ^testing.T) {
	text := `tone = synth saw
effect tone "overdrive" by { drive: 80 }
effect tone "filter" by { kind: "high", cutoff: 2000, resonance: 30 }
effect tone "delay" by { time: 0.1 }
effect tone "delay" by { mix: 60 }
effect speakers "limiter" by { ceiling: 50 }
no effect tone "filter"
no effect tone "chorus"
play tone note 48 for 0.2
print (speakers.playing)
`
	p := run_with_sounds(t, "effect_words", text, "tests/sounds", {})
	defer finish(p)
	for _ in 0 ..< 10 {
		roci.step()
	}
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, printed(p), "false")
	tone := as_sound(global_named(p, "tone"))
	testing.expect(t, roci.level(tone) > 10, "the effects let it through")
	// a peak held at half is at most a square wave's loudness at half, 70.7
	testing.expectf(t, roci.level(roci.SPEAKERS) <= 71, "the limiter holds the speakers at half: %v", roci.level(roci.SPEAKERS))
}

// The pedals example: overdrive and delay are on from its switches; the keys play.
@(test)
test_the_pedals_example :: proc(t: ^testing.T) {
	text, read := os.read_entire_file("examples/pedals/sketch.roci", context.temp_allocator)
	testing.expect(t, read == nil)
	p := run_with_sounds(t, "pedals_example", string(text), "examples/pedals", {})
	defer finish(p)
	for _ in 0 ..< 4 {
		roci.step() // the widgets' panel shows from its third frame
	}
	testing.expect_value(t, len(p.errors), 0)
	on := 0
	for pedal in as_list(global_named(p, "pedals")).items {
		if as_bool(read_field(p, pedal, "on")) {
			on += 1
		}
	}
	testing.expect_value(t, on, 2)
	tone := as_sound(global_named(p, "tone"))
	for _ in 0 ..< 120 {
		roci.step() // the chord ends, and its delay with it
	}
	w := first_window()
	roci.step({key_event(w, sdl.Scancode.A)})
	testing.expect_value(t, roci.sound_notes(tone), 1)
	roci.step({key_event(w, sdl.Scancode.A, false)})
	testing.expect_value(t, roci.sound_notes(tone), 0)
	testing.expect_value(t, len(p.errors), 0)
}
