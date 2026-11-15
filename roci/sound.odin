// SPDX-License-Identifier: 0BSD
//
// Sounds: `add_sound` decodes the bytes of a sound file (WAV, FLAC, MP3 or Ogg Vorbis) and gives
// a number for it, which `play`, `loop`, `pause`, `rewind`, `forward_sound` and `set_sound`
// act on and `sound_state` reads. A sound is one player: it is where it is, playing or not,
// and playing it again goes on from there. The mixing is roci/audio's; the device is opened
// by the first sound that plays in a sketch with a window, and a headless sketch moves its
// sounds on by each frame's time without one, so what a sketch reads of a sound is the same
// in a test as in a window. The language's `load` finds the file in the sketch's assets.
//
// Volume is 0 to 100 and pan -100 (left) to 100 (right), as the language writes them, and
// times are in seconds.
package roci

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"

import "audio"
import "platform"
import sound_files "../vendor/sound"

Sound :: audio.Sound

// What a sketch can read of a sound.
Sound_State :: struct {
	playing: bool,
	looping: bool,
	at:      f64, // seconds from its start
	length:  f64, // seconds
	volume:  f64, // 0 to 100
	pan:     f64, // -100 to 100
	speed:   f64, // 1 as recorded
	pitch:   f64, // hertz: an instrument's, or middle C at its speed for a sound from a file
	note:    f64, // the same as a note number, 60 for middle C
}

@(thread_local) @(private) mixer: ^audio.Mixer
@(thread_local) @(private) speakers: ^platform.Audio_Out
@(thread_local) @(private) speakers_tried: bool
@(thread_local) @(private) microphone: ^platform.Audio_In
@(thread_local) @(private) microphone_tried: bool
@(thread_local) @(private) headless_frames: f64 // the fraction of a frame a headless step did not mix yet
@(thread_local) @(private) sounds_epoch: int     // raised each time every sound is let go

// How long a file is, in seconds, before it is read as it plays and not decoded whole. Shorter ones
// (sound effects, loops) are decoded whole, which gives exact positions and costs little memory.
STREAM_MIN_SECONDS :: 30
@(thread_local) @(private) stream_threshold: Maybe(f64)

// For tests: how many seconds a file has to be to be streamed (0 streams every file); with no argument
// the usual 30 again.
set_stream_threshold :: proc(seconds: Maybe(f64) = nil) {
	stream_threshold = seconds
}

// Which sounds exist now: it changes when every sound is let go (`shutdown`), so a number kept
// from before no longer means what it did.
sound_epoch :: proc() -> int {
	return sounds_epoch
}

@(private)
the_mixer :: proc() -> ^audio.Mixer {
	if mixer == nil {
		mixer = audio.make_mixer(the.allocator if the.allocator.procedure != nil else context.allocator)
		// with no device (headless, tests) the mixer reads long files itself, in step with what it mixes
		audio.set_synchronous(mixer, the.headless || graphics_refused)
	}
	return mixer
}

// Keeps the bytes of a sound file as a sound, stopped at its start: decoded whole, or, when it is
// longer than 30 seconds, read as it plays from a copy of the (compressed) bytes, so the caller may
// let go of them at once. False when the bytes are not a sound this reads (or have no sound in them).
add_sound :: proc(bytes: []u8, buffer := Maybe(f64){}) -> (Sound, bool) {
	if source, long := open_long_sound_memory(bytes); long {
		return audio.add_stream(the_mixer(), source, buffer.? or_else audio.RING_SECONDS), true
	}
	return add_sound_whole(bytes)
}

// Decodes a sound file whole and keeps it, whatever its length.
@(private)
add_sound_whole :: proc(bytes: []u8) -> (Sound, bool) {
	m := the_mixer()
	samples, ok := sound_files.decode(bytes, audio.CHANNELS, audio.RATE, m.players.allocator)
	if !ok {
		return 0, false
	}
	return audio.add(m, samples), true
}

// Puts a file saved again into the place of a sound, which goes on playing as it was (a long one is
// read as it plays, as in `add_sound`).
replace_sound :: proc(s: Sound, bytes: []u8, buffer := Maybe(f64){}) -> bool {
	if source, long := open_long_sound_memory(bytes); long {
		return audio.replace_stream(the_mixer(), s, source, buffer.? or_else audio.RING_SECONDS)
	}
	return replace_sound_whole(s, bytes)
}

@(private)
replace_sound_whole :: proc(s: Sound, bytes: []u8) -> bool {
	m := the_mixer()
	samples, ok := sound_files.decode(bytes, audio.CHANNELS, audio.RATE, m.players.allocator)
	if !ok {
		return false
	}
	return audio.replace(m, s, samples)
}

// Applies the settings that `play`, `loop` and `set_sound` take; a nil one stays as it was.
@(private)
sound_change :: proc(s: Sound, volume, pan, speed: Maybe(f64), looping: Maybe(bool)) {
	c: audio.Change
	if v, ok := volume.?; ok {
		c.volume = v / 100
	}
	if v, ok := pan.?; ok {
		c.pan = v / 100
	}
	if v, ok := speed.?; ok {
		c.speed = v
	}
	c.looping = looping
	audio.change(the_mixer(), s, c)
}

// Plays a sound once, from where it is (from the start when it had come to its end). An
// instrument plays a note, at `note` (60 is middle C) or `pitch` (hertz) or its own pitch, held
// until it is paused or for `seconds`; a sound from a file plays as if it were middle C, faster
// for a higher note, and pauses itself after `seconds`.
play :: proc(s: Sound, volume := Maybe(f64){}, pan := Maybe(f64){}, speed := Maybe(f64){}, note := Maybe(f64){}, pitch := Maybe(f64){}, seconds := Maybe(f64){}) {
	start_sound(s, false, volume, pan, speed, note, pitch, seconds)
}

// Plays a sound over and over, from where it is; for an instrument, the same as `play`.
loop :: proc(s: Sound, volume := Maybe(f64){}, pan := Maybe(f64){}, speed := Maybe(f64){}, note := Maybe(f64){}, pitch := Maybe(f64){}, seconds := Maybe(f64){}) {
	start_sound(s, true, volume, pan, speed, note, pitch, seconds)
}

// The pitch a call asks for in hertz: `pitch`, else `note`, else 0 for none.
@(private)
asked_pitch :: proc(note, pitch: Maybe(f64)) -> f64 {
	if hz, ok := pitch.?; ok {
		return hz if hz > 0 else -1
	}
	if n, ok := note.?; ok && n == n {
		return audio.note_hz(n)
	}
	return 0
}

@(private)
start_sound :: proc(s: Sound, looping: bool, volume, pan, speed, note, pitch, seconds: Maybe(f64)) {
	m := the_mixer()
	sound_change(s, volume, pan, speed, nil)
	hz := asked_pitch(note, pitch)
	if hz < 0 {
		return
	}
	for_seconds := seconds.? or_else 0
	if audio.wave_of(m, s) != .None {
		audio.play_note(m, s, hz, for_seconds)
	} else {
		if hz > 0 {
			audio.set_pitch(m, s, hz)
		}
		audio.play(m, s, looping)
		audio.stop_after(m, s, for_seconds)
	}
	open_speakers()
}

// Holds a sound where it is; `play` or `loop` goes on from there. An instrument's notes fade
// out: every one, or those of `note`.
pause :: proc(s: Sound, note := Maybe(f64){}) {
	if n, ok := note.?; ok {
		audio.release_note(the_mixer(), s, n)
		return
	}
	audio.pause(the_mixer(), s)
}

// Makes an instrument from a preset of a SoundFont (the bytes of a .sf2 file): the preset with a
// number (General MIDI's program: 0 a piano, 48 strings), or with a name (in any case), or the
// first one when neither is given. `found` is false when the one asked for is not there, and then
// the first preset plays; ok is false when the bytes are not a SoundFont.
add_soundfont :: proc(bytes: []u8, number := -1, name := "") -> (s: Sound, found: bool, ok: bool) {
	m := the_mixer()
	font, read := audio.font_read(bytes, m.players.allocator)
	if !read {
		return 0, false, false
	}
	preset: int
	preset, found = audio.font_preset(font, number, name)
	return audio.add_font_instrument(m, font, preset), found, true
}

// The presets of a SoundFont instrument's font, as "number name" in the frame's memory (for a
// message that lists them), or nil for any other sound.
soundfont_presets :: proc(s: Sound) -> []string {
	return audio.font_preset_names(the_mixer(), s, context.temp_allocator)
}

// The whole mix, as a sound for `sound_effect` (its effects run over everything that plays, last)
// and for `level` (everything). Playing it does nothing.
SPEAKERS :: audio.SPEAKERS

the_speakers :: proc() -> Sound {
	the_mixer()
	return SPEAKERS
}

// A setting of a sound effect, by its name: a number, or a word for the filter's `kind`.
Sound_Setting :: struct {
	name:   string,
	number: f64,
	word:   string, // when it is a word rather than a number
}

Sound_Effect_Problem :: enum u8 {
	None,
	Unknown_Effect, // no effect has that name (`sound_effect_names` lists them)
	No_Sound,       // the number is no sound
}

// Puts an effect on a sound, or on the speakers, or changes the settings of the one it has (which
// keeps its place, and its echoes); settings not given keep the values they had, at first those of
// the effect. `unknown` holds the settings that are not the effect's (or a word it does not take),
// in the frame's memory, for a message; they are left out.
sound_effect :: proc(s: Sound, name: string, settings: []Sound_Setting = nil) -> (unknown: []string, problem: Sound_Effect_Problem) {
	kind, known := audio.effect_kind(name)
	if !known {
		return nil, .Unknown_Effect
	}
	values := make([dynamic]audio.Effect_Value, context.temp_allocator)
	wrong := make([dynamic]string, context.temp_allocator)
	for setting in settings {
		index := audio.setting_index(kind, setting.name)
		if index < 0 {
			append(&wrong, setting.name)
			continue
		}
		value := setting.number
		if setting.word != "" || (kind == .Filter && setting.name == "kind") {
			// the filter's kind is a word: its place among the kinds
			found := false
			for k, i in audio.FILTER_KINDS {
				if k == setting.word {
					value, found = f64(i), true
				}
			}
			if !found {
				append(&wrong, fmt.tprintf("%s: \"%s\"", setting.name, setting.word))
				continue
			}
		}
		append(&values, audio.Effect_Value{index, value})
	}
	if !audio.effect_put(the_mixer(), s, kind, values[:]) {
		return wrong[:], .No_Sound
	}
	return wrong[:], .None
}

// Takes an effect off a sound or the speakers; false when it had none of that name.
no_sound_effect :: proc(s: Sound, name: string) -> bool {
	kind, known := audio.effect_kind(name)
	return known && audio.effect_take_off(the_mixer(), s, kind)
}

// The value a setting of a sound effect starts at (0 for one it has not).
sound_effect_default :: proc(name, setting: string) -> f64 {
	kind, known := audio.effect_kind(name)
	if !known {
		return 0
	}
	if i := audio.setting_index(kind, setting); i >= 0 {
		return audio.EFFECTS[kind].defaults[i]
	}
	return 0
}

// The names of every sound effect, in order.
sound_effect_names :: proc(allocator := context.temp_allocator) -> []string {
	out := make([]string, len(audio.Effect_Kind), allocator)
	for info, kind in audio.EFFECTS {
		out[int(kind)] = info.name
	}
	return out
}

// The settings of a sound effect, by its name; nil for a name that is no effect.
sound_effect_settings :: proc(name: string, allocator := context.temp_allocator) -> []string {
	kind, known := audio.effect_kind(name)
	if !known {
		return nil
	}
	out := make([dynamic]string, allocator)
	for setting in audio.EFFECTS[kind].settings {
		if setting != "" {
			append(&out, setting)
		}
	}
	return out[:]
}

// How many notes of an instrument are held now, not yet let go (0 for a sound from a file).
sound_notes :: proc(s: Sound) -> int {
	return audio.held_notes(the_mixer(), s)
}

// Makes an instrument: a sound of the sketch's own, of a wave, "sine", "triangle", "square",
// "saw" or "noise" (any other is a sine). Its notes are played with `play` and sound together.
synth :: proc(wave: string) -> Sound {
	chosen := audio.Wave.Sine
	for name, w in audio.WAVE_NAMES {
		if name != "" && name == wave {
			chosen = w
		}
	}
	return audio.add_instrument(the_mixer(), chosen)
}

// Shapes an instrument's notes: how long one takes to come in, to fall to its sustain and to fade out
// after it is let go, in seconds, and the level it sits at while held, 0 to 100. A field left nil stays
// as it was. A SoundFont instrument's own envelope is the least these can make it.
set_envelope :: proc(s: Sound, attack := Maybe(f64){}, decay := Maybe(f64){}, sustain := Maybe(f64){}, release := Maybe(f64){}) {
	c: audio.Change
	c.attack, c.decay, c.release = attack, decay, release
	if v, ok := sustain.?; ok {
		c.sustain = v / 100
	}
	audio.change(the_mixer(), s, c)
}

// How many seconds of a streamed sound are kept ready, 0 for a sound that is whole or not there.
sound_buffer_seconds :: proc(s: Sound) -> f64 {
	m := the_mixer()
	sync.guard(&m.lock)
	if s == 0 || int(s) > len(m.players) || m.players[int(s) - 1].stream == nil {
		return 0
	}
	return f64(m.players[int(s) - 1].stream.ring_frames) / audio.RATE
}

// An instrument's envelope as set: attack, decay and release in seconds and the sustain level 0 to 100,
// each -1 when it was not set (the instrument's own); all -1 for a sound that is not an instrument.
sound_envelope :: proc(s: Sound) -> (attack, decay, sustain, release: f64) {
	m := the_mixer()
	sync.guard(&m.lock)
	if s == 0 || int(s) > len(m.players) || m.players[int(s) - 1].wave == .None {
		return -1, -1, -1, -1
	}
	p := m.players[int(s) - 1]
	return p.attack, p.decay, p.sustain * 100 if p.sustain >= 0 else -1, p.release
}

// Puts a sound back to its start, or `by` seconds back.
rewind :: proc(s: Sound, by := Maybe(f64){}) {
	if seconds, ok := by.?; ok {
		audio.move_by(the_mixer(), s, -seconds)
	} else {
		audio.seek(the_mixer(), s, 0)
	}
}

// Moves a sound `by` seconds ahead; past its end, a sound that does not loop has ended.
forward_sound :: proc(s: Sound, by: f64) {
	audio.move_by(the_mixer(), s, by)
}

// Changes a sound: `at` puts it that many seconds from its start, and the rest are the settings
// of `play`; `looping` false lets a looping sound finish where it is.
set_sound :: proc(s: Sound, at := Maybe(f64){}, volume := Maybe(f64){}, pan := Maybe(f64){}, speed := Maybe(f64){}, looping := Maybe(bool){}, note := Maybe(f64){}, pitch := Maybe(f64){}) {
	sound_change(s, volume, pan, speed, looping)
	if seconds, ok := at.?; ok {
		audio.seek(the_mixer(), s, seconds)
	}
	if hz := asked_pitch(note, pitch); hz > 0 {
		audio.set_pitch(the_mixer(), s, hz)
	}
}

// What a sound is doing now; a number that is no sound gives every field 0. The microphone is
// playing while it is open.
sound_state :: proc(s: Sound) -> Sound_State {
	if s == MIC {
		m := the_mixer()
		return {playing = m.mic_open, volume = 100, speed = 1}
	}
	if s == SPEAKERS {
		return {playing = speakers != nil, volume = 100, speed = 1}
	}
	st := audio.state(the_mixer(), s)
	note := audio.hz_note(st.pitch) if st.pitch > 0 else 0
	return {st.playing, st.looping, st.at, st.length, st.volume * 100, st.pan * 100, st.speed, st.pitch, note}
}

// The microphone, as a sound `level` and `bands` can listen to (playing it does nothing).
MIC :: audio.MIC

// The microphone: the first time it is asked for in a sketch with a window it opens the computer's
// default recording device (the system may ask the person first). A headless sketch and a test
// have none and hear silence, unless a test feeds it (`feed_microphone`).
mic :: proc() -> Sound {
	the_mixer()
	if !microphone_tried && !the.headless && !graphics_refused {
		microphone_tried = true
		microphone = platform.open_microphone(audio.RATE, microphone_heard, mixer, the.allocator if the.allocator.procedure != nil else context.allocator)
		if microphone.stream == nil {
			delete(sound_problem, the.allocator if the.allocator.procedure != nil else context.allocator)
			sound_problem = strings.clone(microphone.error, the.allocator if the.allocator.procedure != nil else context.allocator)
			platform.close_microphone(microphone)
			microphone = nil
		}
	}
	return MIC
}

@(private)
microphone_heard :: proc(user: rawptr, frames: []f32) {
	audio.feed_mic((^audio.Mixer)(user), frames)
}

// Gives the microphone frames to hear, as a recording device would (one float a frame at 48,000 a
// second): for tests, which open no device.
feed_microphone :: proc(frames: []f32) {
	audio.feed_mic(the_mixer(), frames)
}

// How loud everything that plays is now, 0 (silent) to 100 (a full-volume sine).
level_all :: proc() -> f64 {
	return audio.level(the_mixer(), 0, everything = true)
}

// How loud one sound, or the microphone, is now, 0 to 100.
level_of :: proc(s: Sound) -> f64 {
	return audio.level(the_mixer(), s)
}

level :: proc{level_all, level_of}

// How many bands `bands` gives when it is not told, and the most it gives.
BANDS_USUAL :: 16
BANDS_MOST :: 256

// How much of each pitch everything that plays holds now: `count` numbers 0 to 100, from the
// lowest pitches to the highest, in steps of equal pitch; made with the frame's memory.
bands_all :: proc(count := BANDS_USUAL) -> []f64 {
	out := make([]f64, clamp(count, 1, BANDS_MOST), context.temp_allocator)
	audio.bands(the_mixer(), 0, out, everything = true)
	return out
}

// The same for one sound, or the microphone.
bands_of :: proc(s: Sound, count := BANDS_USUAL) -> []f64 {
	out := make([]f64, clamp(count, 1, BANDS_MOST), context.temp_allocator)
	audio.bands(the_mixer(), s, out)
	return out
}

bands :: proc{bands_all, bands_of}

// Opens the speakers the first time a sound plays in a sketch that has a window to show (never
// in a headless one or a test that refused graphics, which move their sounds on in `step`).
// A computer whose device cannot open says so once and the sketch goes on silent.
@(private)
open_speakers :: proc() {
	if speakers_tried || the.headless || graphics_refused {
		return
	}
	speakers_tried = true
	// the speakers' mix passes the limiter inside the mixer, so a recording of it is what is heard
	audio.set_limit(the_mixer(), true)
	speakers = platform.open_audio(audio.RATE, speakers_fill, the_mixer(), the.allocator if the.allocator.procedure != nil else context.allocator)
	if speakers.stream == nil {
		sound_problem = strings.clone(speakers.error, the.allocator if the.allocator.procedure != nil else context.allocator)
		platform.close_audio(speakers)
		speakers = nil
	}
}

// Why the speakers would not open, in SDL's words, for the language to say once; "" when they did.
@(thread_local) sound_problem: string

@(private)
speakers_fill :: proc(user: rawptr, out: []f32) {
	audio.mix((^audio.Mixer)(user), out)
}

// Moves the sounds of a sketch with no speakers on by a frame's time, as the speakers would
// have played them. Called by `step`.
@(private)
sounds_step :: proc(dt: f64) {
	if mixer == nil || speakers != nil || !(dt > 0) {
		return
	}
	headless_frames += dt * audio.RATE
	frames := int(headless_frames)
	headless_frames -= f64(frames)
	// mixed even when nothing plays, as the speakers do, so what `level` hears falls silent
	if frames == 0 {
		return
	}
	buffer := make([]f32, min(frames, audio.RATE) * audio.CHANNELS, context.temp_allocator)
	for frames > 0 {
		n := min(frames, len(buffer) / audio.CHANNELS)
		audio.mix(mixer, buffer[:n * audio.CHANNELS])
		frames -= n
	}
}

// Closes the speakers and lets go of every sound. Called by `shutdown`.
@(private)
sounds_stop :: proc() {
	platform.close_audio(speakers)
	speakers = nil
	speakers_tried = false
	platform.close_microphone(microphone)
	microphone = nil
	microphone_tried = false
	if mixer != nil {
		sounds_epoch += 1
	}
	audio.destroy_mixer(mixer)
	mixer = nil
	headless_frames = 0
	delete(sound_problem, the.allocator if the.allocator.procedure != nil else context.allocator)
	sound_problem = ""
}

// The decoder of a file that is read as it plays, in the form the mixer takes.
@(private)
stream_source :: proc(s: sound_files.Stream) -> audio.Source {
	read :: proc(handle: rawptr, out: []f32, frames: int) -> int {
		return sound_files.stream_read(sound_files.Stream{handle = handle, channels = audio.CHANNELS}, out, frames)
	}
	seek :: proc(handle: rawptr, frame: int) -> bool {
		return sound_files.stream_seek(sound_files.Stream{handle = handle, channels = audio.CHANNELS}, frame)
	}
	close :: proc(handle: rawptr) {
		sound_files.stream_close(sound_files.Stream{handle = handle, channels = audio.CHANNELS})
	}
	return audio.Source{handle = s.handle, read = read, seek = seek, close = close, length = s.length}
}

// Opens a file to be read as it plays when it is longer than `stream_threshold` seconds; false for a
// shorter one (decoded whole instead), and for one that is no sound or whose length is not known.
@(private)
open_long_sound :: proc(path: string) -> (audio.Source, bool) {
	opened, ok := sound_files.stream_open(path, audio.CHANNELS, audio.RATE)
	if !ok {
		return {}, false
	}
	seconds := stream_threshold.? or_else f64(STREAM_MIN_SECONDS)
	if f64(opened.length) <= seconds * audio.RATE {
		sound_files.stream_close(opened)
		return {}, false
	}
	return stream_source(opened), true
}

// Opens a sound file by its path and keeps it, stopped at its start: a long file (over 30 seconds) is
// read as it plays, keeping `buffer` seconds of it ready (from 1 to 60, 8 when not given), a short one
// decoded whole. False when the file cannot be read or is no sound.
add_sound_file :: proc(path: string, buffer := Maybe(f64){}) -> (Sound, bool) {
	if source, long := open_long_sound(path); long {
		return audio.add_stream(the_mixer(), source, buffer.? or_else audio.RING_SECONDS), true
	}
	bytes, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		return 0, false
	}
	return add_sound_whole(bytes)
}

// Puts a file saved again in the place of a sound, which goes on playing as it was.
replace_sound_file :: proc(s: Sound, path: string, buffer := Maybe(f64){}) -> bool {
	if source, long := open_long_sound(path); long {
		if !audio.replace_stream(the_mixer(), s, source, buffer.? or_else audio.RING_SECONDS) {
			return false
		}
		return true
	}
	bytes, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		return false
	}
	return replace_sound_whole(s, bytes)
}

// The same for the bytes of a file already held in memory: they are copied by the decoder, which
// reads the copy as the sound plays. False for a shorter one, and for bytes that are no sound.
@(private)
open_long_sound_memory :: proc(bytes: []u8) -> (audio.Source, bool) {
	opened, ok := sound_files.stream_open_memory(bytes, audio.CHANNELS, audio.RATE)
	if !ok {
		return {}, false
	}
	seconds := stream_threshold.? or_else f64(STREAM_MIN_SECONDS)
	if f64(opened.length) <= seconds * audio.RATE {
		sound_files.stream_close(opened)
		return {}, false
	}
	return stream_source(opened), true
}
