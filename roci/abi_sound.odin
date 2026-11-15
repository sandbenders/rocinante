// SPDX-License-Identifier: 0BSD
//
// Sounds in C: a sound is a roci_sound_id made by roci_load_sound (the bytes of a file) or
// roci_load_sound_file (a path), played with roci_play and roci_loop, and changed and read by the
// functions below, which are the language's `set` and fields of a sound. Volume is 0 to 100, pan
// -100 to 100, times in seconds, as in the language.
package roci

import "core:c"
import "core:os"

@(export, link_name = "roci_load_sound")
abi_load_sound :: proc "c" (bytes: [^]u8, length: c.int) -> c.int {
	context = abi_context()
	if bytes == nil || length <= 0 {
		return 0
	}
	s, ok := add_sound(bytes[:length])
	return c.int(s) if ok else 0
}

@(export, link_name = "roci_load_sound_file")
abi_load_sound_file :: proc "c" (path: cstring) -> c.int {
	context = abi_context()
	bytes, err := os.read_entire_file(text_from_abi(path), context.temp_allocator)
	if err != nil {
		return 0
	}
	s, ok := add_sound(bytes)
	return c.int(s) if ok else 0
}

@(export, link_name = "roci_play")
abi_play :: proc "c" (sound: c.int) {
	context = abi_context()
	play(Sound(sound))
}

@(export, link_name = "roci_loop")
abi_loop :: proc "c" (sound: c.int) {
	context = abi_context()
	loop(Sound(sound))
}

@(export, link_name = "roci_pause")
abi_pause :: proc "c" (sound: c.int) {
	context = abi_context()
	pause(Sound(sound))
}

@(export, link_name = "roci_rewind")
abi_rewind :: proc "c" (sound: c.int) {
	context = abi_context()
	rewind(Sound(sound))
}

@(export, link_name = "roci_rewind_by")
abi_rewind_by :: proc "c" (sound: c.int, seconds: f64) {
	context = abi_context()
	rewind(Sound(sound), seconds)
}

@(export, link_name = "roci_forward_sound")
abi_forward_sound :: proc "c" (sound: c.int, seconds: f64) {
	context = abi_context()
	forward_sound(Sound(sound), seconds)
}

@(export, link_name = "roci_set_sound_at")
abi_set_sound_at :: proc "c" (sound: c.int, seconds: f64) {
	context = abi_context()
	set_sound(Sound(sound), at = seconds)
}

@(export, link_name = "roci_set_sound_volume")
abi_set_sound_volume :: proc "c" (sound: c.int, volume: f64) {
	context = abi_context()
	set_sound(Sound(sound), volume = volume)
}

@(export, link_name = "roci_set_sound_pan")
abi_set_sound_pan :: proc "c" (sound: c.int, pan: f64) {
	context = abi_context()
	set_sound(Sound(sound), pan = pan)
}

@(export, link_name = "roci_set_sound_speed")
abi_set_sound_speed :: proc "c" (sound: c.int, speed: f64) {
	context = abi_context()
	set_sound(Sound(sound), speed = speed)
}

@(export, link_name = "roci_set_sound_loop")
abi_set_sound_loop :: proc "c" (sound: c.int, on: c.int) {
	context = abi_context()
	set_sound(Sound(sound), looping = on != 0)
}

@(export, link_name = "roci_sound_playing")
abi_sound_playing :: proc "c" (sound: c.int) -> c.int {
	context = abi_context()
	return 1 if sound_state(Sound(sound)).playing else 0
}

@(export, link_name = "roci_sound_loops")
abi_sound_loops :: proc "c" (sound: c.int) -> c.int {
	context = abi_context()
	return 1 if sound_state(Sound(sound)).looping else 0
}

@(export, link_name = "roci_sound_at")
abi_sound_at :: proc "c" (sound: c.int) -> f64 {
	context = abi_context()
	return sound_state(Sound(sound)).at
}

@(export, link_name = "roci_sound_length")
abi_sound_length :: proc "c" (sound: c.int) -> f64 {
	context = abi_context()
	return sound_state(Sound(sound)).length
}

@(export, link_name = "roci_sound_volume")
abi_sound_volume :: proc "c" (sound: c.int) -> f64 {
	context = abi_context()
	return sound_state(Sound(sound)).volume
}

@(export, link_name = "roci_sound_pan")
abi_sound_pan :: proc "c" (sound: c.int) -> f64 {
	context = abi_context()
	return sound_state(Sound(sound)).pan
}

@(export, link_name = "roci_sound_speed")
abi_sound_speed :: proc "c" (sound: c.int) -> f64 {
	context = abi_context()
	return sound_state(Sound(sound)).speed
}

@(export, link_name = "roci_level")
abi_level :: proc "c" () -> f64 {
	context = abi_context()
	return level_all()
}

@(export, link_name = "roci_level_of")
abi_level_of :: proc "c" (sound: c.int) -> f64 {
	context = abi_context()
	return level_of(Sound(u32(sound)))
}

@(export, link_name = "roci_mic")
abi_mic :: proc "c" () -> c.int {
	context = abi_context()
	return c.int(u32(mic()))
}

// Writes `count` bands (at most 256) into `out` and gives how many it wrote.
@(private)
abi_write_bands :: proc(values: []f64, out: [^]f64) -> c.int {
	if out == nil {
		return 0
	}
	copy(out[:len(values)], values)
	return c.int(len(values))
}

@(export, link_name = "roci_bands")
abi_bands :: proc "c" (count: c.int, out: [^]f64) -> c.int {
	context = abi_context()
	if count <= 0 {
		return 0
	}
	return abi_write_bands(bands_all(int(count)), out)
}

@(export, link_name = "roci_bands_of")
abi_bands_of :: proc "c" (sound: c.int, count: c.int, out: [^]f64) -> c.int {
	context = abi_context()
	if count <= 0 {
		return 0
	}
	return abi_write_bands(bands_of(Sound(u32(sound)), int(count)), out)
}

@(export, link_name = "roci_synth")
abi_synth :: proc "c" (wave: cstring) -> c.int {
	context = abi_context()
	return c.int(synth(text_from_abi(wave)))
}

@(export, link_name = "roci_play_note")
abi_play_note :: proc "c" (sound: c.int, note: f64, seconds: f64) {
	context = abi_context()
	play(Sound(sound), note = note, seconds = seconds)
}

@(export, link_name = "roci_pause_note")
abi_pause_note :: proc "c" (sound: c.int, note: f64) {
	context = abi_context()
	pause(Sound(sound), note)
}

@(export, link_name = "roci_set_sound_pitch")
abi_set_sound_pitch :: proc "c" (sound: c.int, hertz: f64) {
	context = abi_context()
	set_sound(Sound(sound), pitch = hertz)
}

@(export, link_name = "roci_sound_pitch")
abi_sound_pitch :: proc "c" (sound: c.int) -> f64 {
	context = abi_context()
	return sound_state(Sound(sound)).pitch
}

@(export, link_name = "roci_midi_control")
abi_midi_control :: proc "c" (number: f64) -> f64 {
	context = abi_context()
	return midi_control(number)
}

@(export, link_name = "roci_soundfont")
abi_soundfont :: proc "c" (path: cstring, preset: c.int) -> c.int {
	context = abi_context()
	bytes, err := os.read_entire_file(text_from_abi(path), context.temp_allocator)
	if err != nil {
		return 0
	}
	s, _, ok := add_soundfont(bytes, int(preset))
	return c.int(s) if ok else 0
}

@(export, link_name = "roci_soundfont_named")
abi_soundfont_named :: proc "c" (path: cstring, preset: cstring) -> c.int {
	context = abi_context()
	bytes, err := os.read_entire_file(text_from_abi(path), context.temp_allocator)
	if err != nil {
		return 0
	}
	s, _, ok := add_soundfont(bytes, name = text_from_abi(preset))
	return c.int(s) if ok else 0
}

@(export, link_name = "roci_speakers")
abi_speakers :: proc "c" () -> c.int {
	context = abi_context()
	return c.int(u32(the_speakers()))
}

@(export, link_name = "roci_sound_effect")
abi_sound_effect :: proc "c" (sound: c.int, name: cstring) -> c.int {
	context = abi_context()
	_, problem := sound_effect(Sound(u32(sound)), text_from_abi(name))
	return 1 if problem == .None else 0
}

@(export, link_name = "roci_sound_effect_set")
abi_sound_effect_set :: proc "c" (sound: c.int, name: cstring, setting: cstring, value: f64) -> c.int {
	context = abi_context()
	settings := []Sound_Setting{{name = text_from_abi(setting), number = value}}
	unknown, problem := sound_effect(Sound(u32(sound)), text_from_abi(name), settings)
	return 1 if problem == .None && len(unknown) == 0 else 0
}

@(export, link_name = "roci_sound_effect_word")
abi_sound_effect_word :: proc "c" (sound: c.int, name: cstring, setting: cstring, word: cstring) -> c.int {
	context = abi_context()
	settings := []Sound_Setting{{name = text_from_abi(setting), word = text_from_abi(word)}}
	unknown, problem := sound_effect(Sound(u32(sound)), text_from_abi(name), settings)
	return 1 if problem == .None && len(unknown) == 0 else 0
}

@(export, link_name = "roci_no_sound_effect")
abi_no_sound_effect :: proc "c" (sound: c.int, name: cstring) -> c.int {
	context = abi_context()
	return 1 if no_sound_effect(Sound(u32(sound)), text_from_abi(name)) else 0
}

// The table rows of the functions above that are not a registry shape.
abi_sound_group :: proc(all: ^[dynamic]Abi_Entry) {
	append(all, abi_entry("roci_load_sound", typeid_of(type_of(abi_load_sound)), "roci_sound_id roci_load_sound(const unsigned char *bytes, int length)", "Decodes the bytes of a sound file (WAV, FLAC, MP3 or Ogg Vorbis) and gives its number, or 0 when they are not a sound. A sound is stopped at its start, at volume 100, in the middle and at speed 1."))
	append(all, abi_entry("roci_load_sound_file", typeid_of(type_of(abi_load_sound_file)), "roci_sound_id roci_load_sound_file(const char *path)", "Reads a sound file (WAV, FLAC, MP3 or Ogg Vorbis) and gives its number, or 0 when it cannot be read."))
	append(all, abi_entry("roci_rewind_by", typeid_of(type_of(abi_rewind_by)), "void roci_rewind_by(roci_sound_id sound, double seconds)", "Moves a sound some seconds back, no further than its start."))
	append(all, abi_entry("roci_forward_sound", typeid_of(type_of(abi_forward_sound)), "void roci_forward_sound(roci_sound_id sound, double seconds)", "Moves a sound some seconds ahead; past its end, a sound that does not loop has ended and one that loops goes on from its start."))
	append(all, abi_entry("roci_set_sound_at", typeid_of(type_of(abi_set_sound_at)), "void roci_set_sound_at(roci_sound_id sound, double seconds)", "Puts a sound that many seconds from its start, kept between its start and its end."))
	append(all, abi_entry("roci_set_sound_volume", typeid_of(type_of(abi_set_sound_volume)), "void roci_set_sound_volume(roci_sound_id sound, double volume)", "How loud a sound plays, 0 to 100."))
	append(all, abi_entry("roci_set_sound_pan", typeid_of(type_of(abi_set_sound_pan)), "void roci_set_sound_pan(roci_sound_id sound, double pan)", "Where a sound is between the speakers, -100 (left) to 100 (right): in the middle both play it at full volume, towards one side the other fades."))
	append(all, abi_entry("roci_set_sound_speed", typeid_of(type_of(abi_set_sound_speed)), "void roci_set_sound_speed(roci_sound_id sound, double speed)", "How fast a sound plays, 1 as recorded, 0 (held still) to 8; faster is higher, as on a record player."))
	append(all, abi_entry("roci_set_sound_loop", typeid_of(type_of(abi_set_sound_loop)), "void roci_set_sound_loop(roci_sound_id sound, int on)", "Whether a sound starts again at its end: 0 lets a looping sound finish where it is."))
	append(all, abi_entry("roci_sound_playing", typeid_of(type_of(abi_sound_playing)), "int roci_sound_playing(roci_sound_id sound)", "1 while a sound is playing."))
	append(all, abi_entry("roci_sound_loops", typeid_of(type_of(abi_sound_loops)), "int roci_sound_loops(roci_sound_id sound)", "1 when a sound starts again at its end."))
	append(all, abi_entry("roci_sound_at", typeid_of(type_of(abi_sound_at)), "double roci_sound_at(roci_sound_id sound)", "Where a sound is, in seconds from its start."))
	append(all, abi_entry("roci_sound_length", typeid_of(type_of(abi_sound_length)), "double roci_sound_length(roci_sound_id sound)", "How long a sound is, in seconds (0 for no sound)."))
	append(all, abi_entry("roci_sound_volume", typeid_of(type_of(abi_sound_volume)), "double roci_sound_volume(roci_sound_id sound)", "How loud a sound plays, 0 to 100."))
	append(all, abi_entry("roci_sound_pan", typeid_of(type_of(abi_sound_pan)), "double roci_sound_pan(roci_sound_id sound)", "Where a sound is between the speakers, -100 to 100."))
	append(all, abi_entry("roci_play_note", typeid_of(type_of(abi_play_note)), "void roci_play_note(roci_sound_id sound, double note, double seconds)", "Plays a note (60 is middle C, each step a semitone) for some seconds, or held until roci_pause_note when `seconds` is 0. An instrument's notes sound together; a sound from a file plays as if it were middle C, faster for a higher note."))
	append(all, abi_entry("roci_pause_note", typeid_of(type_of(abi_pause_note)), "void roci_pause_note(roci_sound_id sound, double note)", "Lets an instrument's notes of that number go; they fade out. roci_pause lets all of them go."))
	append(all, abi_entry("roci_set_sound_pitch", typeid_of(type_of(abi_set_sound_pitch)), "void roci_set_sound_pitch(roci_sound_id sound, double hertz)", "Sets an instrument's pitch: its sounding notes slide there, and a note played with none takes it. A sound from a file plays at the speed that makes it that pitch, taking it to be middle C."))
	append(all, abi_entry("roci_sound_pitch", typeid_of(type_of(abi_sound_pitch)), "double roci_sound_pitch(roci_sound_id sound)", "An instrument's pitch in hertz, or middle C at the speed of a sound from a file."))
	append(all, abi_entry("roci_soundfont", typeid_of(type_of(abi_soundfont)), "roci_sound_id roci_soundfont(const char *path, int preset)", "Reads a SoundFont (.sf2) and makes an instrument of one of its presets, by number (General MIDI's 0 is a piano), or the first one for -1 or a number it does not have; 0 when the file cannot be read. Its notes are played with roci_play_note."))
	append(all, abi_entry("roci_soundfont_named", typeid_of(type_of(abi_soundfont_named)), "roci_sound_id roci_soundfont_named(const char *path, const char *preset)", "The same, the preset found by its name in any case (the first one when no preset has it)."))
	append(all, abi_entry("roci_speakers", typeid_of(type_of(abi_speakers)), "roci_sound_id roci_speakers(void)", "The whole mix, as a sound for roci_sound_effect (its effects run over everything that plays, last) and roci_level_of."))
	append(all, abi_entry("roci_sound_effect", typeid_of(type_of(abi_sound_effect)), "int roci_sound_effect(roci_sound_id sound, const char *name)", "Puts a sound effect on a sound or the speakers (\"overdrive\", \"fuzz\", \"delay\", \"reverb\", \"chorus\", \"flanger\", \"phaser\", \"tremolo\", \"compressor\", \"eq\", \"rotary\", \"filter\", \"bitcrush\", \"ring\", \"wah\" or \"limiter\"), at the end of its effects, with its start values; 1 when it is on, 0 for a name no effect has or no sound."))
	append(all, abi_entry("roci_sound_effect_set", typeid_of(type_of(abi_sound_effect_set)), "int roci_sound_effect_set(roci_sound_id sound, const char *name, const char *setting, double value)", "Sets a setting of a sound's effect, putting the effect on first if it has none: amounts 0 to 100, times in seconds, rates in times a second, pitches in hertz, eq bands -100 to 100. 0 for a setting the effect has not."))
	append(all, abi_entry("roci_sound_effect_word", typeid_of(type_of(abi_sound_effect_word)), "int roci_sound_effect_word(roci_sound_id sound, const char *name, const char *setting, const char *word)", "The same for a setting that is a word: the filter's kind, \"low\", \"high\" or \"band\"."))
	append(all, abi_entry("roci_no_sound_effect", typeid_of(type_of(abi_no_sound_effect)), "int roci_no_sound_effect(roci_sound_id sound, const char *name)", "Takes a sound effect off a sound or the speakers; 0 when it had none of that name."))
	append(all, abi_entry("roci_mic", typeid_of(type_of(abi_mic)), "roci_sound_id roci_mic(void)", "The microphone, as a sound for roci_level_of and roci_bands_of. The first call in a program with a window opens the computer's default recording device (the system may ask first). Playing it does nothing."))
	append(all, abi_entry("roci_bands", typeid_of(type_of(abi_bands)), "int roci_bands(int count, double *out)", "How much of each pitch everything that plays holds now: writes `count` numbers 0 to 100 (at most 256), the lowest pitches first, into `out`, and gives how many it wrote."))
	append(all, abi_entry("roci_bands_of", typeid_of(type_of(abi_bands_of)), "int roci_bands_of(roci_sound_id sound, int count, double *out)", "The same for one sound, or the microphone (roci_mic)."))
	append(all, abi_entry("roci_sound_speed", typeid_of(type_of(abi_sound_speed)), "double roci_sound_speed(roci_sound_id sound)", "How fast a sound plays, 1 as recorded."))
}
