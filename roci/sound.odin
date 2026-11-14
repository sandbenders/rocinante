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

import "core:strings"

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
}

@(thread_local) @(private) mixer: ^audio.Mixer
@(thread_local) @(private) speakers: ^platform.Audio_Out
@(thread_local) @(private) speakers_tried: bool
@(thread_local) @(private) microphone: ^platform.Audio_In
@(thread_local) @(private) microphone_tried: bool
@(thread_local) @(private) headless_frames: f64 // the fraction of a frame a headless step did not mix yet
@(thread_local) @(private) sounds_epoch: int     // raised each time every sound is let go

// Which sounds exist now: it changes when every sound is let go (`shutdown`), so a number kept
// from before no longer means what it did.
sound_epoch :: proc() -> int {
	return sounds_epoch
}

@(private)
the_mixer :: proc() -> ^audio.Mixer {
	if mixer == nil {
		mixer = audio.make_mixer(the.allocator if the.allocator.procedure != nil else context.allocator)
	}
	return mixer
}

// Decodes a sound file and keeps it, stopped at its start. False when the bytes are not a
// sound this reads (or have no sound in them).
add_sound :: proc(bytes: []u8) -> (Sound, bool) {
	m := the_mixer()
	samples, ok := sound_files.decode(bytes, audio.CHANNELS, audio.RATE, m.players.allocator)
	if !ok {
		return 0, false
	}
	return audio.add(m, samples), true
}

// Decodes a file saved again into the place of a sound, which goes on playing as it was.
replace_sound :: proc(s: Sound, bytes: []u8) -> bool {
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

// Plays a sound once, from where it is (from the start when it had come to its end).
play :: proc(s: Sound, volume := Maybe(f64){}, pan := Maybe(f64){}, speed := Maybe(f64){}) {
	sound_change(s, volume, pan, speed, nil)
	audio.play(the_mixer(), s, false)
	open_speakers()
}

// Plays a sound over and over, from where it is.
loop :: proc(s: Sound, volume := Maybe(f64){}, pan := Maybe(f64){}, speed := Maybe(f64){}) {
	sound_change(s, volume, pan, speed, nil)
	audio.play(the_mixer(), s, true)
	open_speakers()
}

// Holds a sound where it is; `play` or `loop` goes on from there.
pause :: proc(s: Sound) {
	audio.pause(the_mixer(), s)
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
set_sound :: proc(s: Sound, at := Maybe(f64){}, volume := Maybe(f64){}, pan := Maybe(f64){}, speed := Maybe(f64){}, looping := Maybe(bool){}) {
	sound_change(s, volume, pan, speed, looping)
	if seconds, ok := at.?; ok {
		audio.seek(the_mixer(), s, seconds)
	}
}

// What a sound is doing now; a number that is no sound gives every field 0. The microphone is
// playing while it is open.
sound_state :: proc(s: Sound) -> Sound_State {
	if s == MIC {
		m := the_mixer()
		return {playing = m.mic_open, volume = 100, speed = 1}
	}
	st := audio.state(the_mixer(), s)
	return {st.playing, st.looping, st.at, st.length, st.volume * 100, st.pan * 100, st.speed}
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
