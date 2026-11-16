// SPDX-License-Identifier: 0BSD
//
// Sounds in C: a sound is a roci_sound_id made by roci_load_sound (the bytes of a file) or
// roci_load_sound_file (a path), played with roci_play and roci_loop, and changed and read by the
// functions below, which are the language's `set` and fields of a sound. Volume is 0 to 100, pan
// -100 to 100, times in seconds, as in the language.
package roci

import "core:c"
import "core:math"
import "core:os"

import oscp "osc"

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
	s, ok := add_sound_file(text_from_abi(path))
	return c.int(s) if ok else 0
}

@(export, link_name = "roci_load_sound_buffered")
abi_load_sound_buffered :: proc "c" (bytes: [^]u8, length: c.int, seconds: f64) -> c.int {
	context = abi_context()
	if bytes == nil || length <= 0 {
		return 0
	}
	s, ok := add_sound(bytes[:length], seconds)
	return c.int(s) if ok else 0
}

@(export, link_name = "roci_load_sound_file_buffered")
abi_load_sound_file_buffered :: proc "c" (path: cstring, seconds: f64) -> c.int {
	context = abi_context()
	s, ok := add_sound_file(text_from_abi(path), seconds)
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

@(export, link_name = "roci_set_sound_envelope")
abi_set_sound_envelope :: proc "c" (sound: c.int, attack, decay, sustain, release: f64) {
	context = abi_context()
	pick :: proc(v: f64) -> Maybe(f64) {
		return v if v >= 0 else nil
	}
	set_envelope(Sound(sound), pick(attack), pick(decay), pick(sustain), pick(release))
}

@(export, link_name = "roci_set_sound_wheels")
abi_set_sound_wheels :: proc "c" (sound: c.int, bend, vibrato: f64) {
	context = abi_context()
	// a number that is not 0 to 100 (or -100 to 100 for the bend) is left out, as the envelope's are: NaN
	pick :: proc(v: f64) -> Maybe(f64) {
		return v if v == v else nil
	}
	set_wheels(Sound(sound), pick(bend), pick(vibrato))
}

// ---- MIDI out ----

@(private)
midi_result_c :: proc(r: Midi_Out_Result) -> c.int {
	return 1 if r == .Sent else 0
}

@(private)
midi_maybe :: proc(v: f64, off: f64) -> Maybe(f64) {
	return v if v > off else nil
}

@(export, link_name = "roci_midi_note")
abi_midi_note :: proc "c" (note, velocity, channel, seconds: f64) -> c.int {
	context = abi_context()
	return midi_result_c(midi_note(note, velocity if velocity >= 0 else nil, channel if channel > 0 else nil, midi_maybe(seconds, 0)))
}

@(export, link_name = "roci_midi_release")
abi_midi_release :: proc "c" (note, channel: f64) -> c.int {
	context = abi_context()
	return midi_result_c(midi_release(note if note >= 0 else nil, channel if channel > 0 else nil))
}

@(export, link_name = "roci_midi_set")
abi_midi_set :: proc "c" (controller, value, channel: f64) -> c.int {
	context = abi_context()
	return midi_result_c(midi_set(controller, value, channel if channel > 0 else nil))
}

@(export, link_name = "roci_midi_bend")
abi_midi_bend :: proc "c" (amount, channel: f64) -> c.int {
	context = abi_context()
	return midi_result_c(midi_bend(amount, channel if channel > 0 else nil))
}

@(export, link_name = "roci_midi_program")
abi_midi_program :: proc "c" (number, channel: f64) -> c.int {
	context = abi_context()
	return midi_result_c(midi_program(number, channel if channel > 0 else nil))
}

@(export, link_name = "roci_midi_to")
abi_midi_to :: proc "c" (name: cstring) {
	context = abi_context()
	midi_to(text_from_abi(name))
}

@(export, link_name = "roci_midi_output_count")
abi_midi_output_count :: proc "c" () -> c.int {
	context = abi_context()
	names := midi_outputs(context.temp_allocator)
	return c.int(len(names))
}

@(export, link_name = "roci_midi_output_name")
abi_midi_output_name :: proc "c" (index: c.int, out: [^]u8, capacity: c.int) -> c.int {
	context = abi_context()
	names := midi_outputs(context.temp_allocator)
	if index < 0 || int(index) >= len(names) || out == nil || capacity <= 0 {
		return 0
	}
	name := names[index]
	n := min(len(name), int(capacity) - 1)
	copy(out[:n], name[:n])
	out[n] = 0
	return c.int(n)
}

@(export, link_name = "roci_midi_clock")
abi_midi_clock :: proc "c" (tempo: f64) -> c.int {
	context = abi_context()
	return midi_result_c(midi_clock(tempo))
}

@(export, link_name = "roci_midi_stop")
abi_midi_stop :: proc "c" () {
	context = abi_context()
	midi_clock_stop()
}

@(export, link_name = "roci_midi_tempo")
abi_midi_tempo :: proc "c" () -> f64 {
	context = abi_context()
	return midi_tempo()
}

@(export, link_name = "roci_record_sound")
abi_record_sound :: proc "c" (sound: c.int, path: cstring) -> c.int {
	context = abi_context()
	ok, _ := record_sound(Sound(sound), text_from_abi(path))
	return 1 if ok else 0
}

@(export, link_name = "roci_no_record_sound")
abi_no_record_sound :: proc "c" (sound: c.int) {
	context = abi_context()
	no_record_sound(Sound(sound))
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
	append(all, abi_entry("roci_set_sound_envelope", typeid_of(type_of(abi_set_sound_envelope)), "void roci_set_sound_envelope(roci_sound_id sound, double attack, double decay, double sustain, double release)", "Shapes an instrument's notes: seconds to come in, seconds to fall to the sustain, the level the note sits at while held (0 to 100) and seconds to fade out after it is let go. A negative number leaves that one as it was; a SoundFont instrument's own envelope is the least these can make it."))
	append(all, abi_entry("roci_set_sound_wheels", typeid_of(type_of(abi_set_sound_wheels)), "void roci_set_sound_wheels(roci_sound_id sound, double bend, double vibrato)", "Moves an instrument's wheels: the pitch wheel from -100 (two semitones down) to 100 (two up) and the modulation wheel from 0 to 100, which swells a SoundFont's vibrato. The notes sounding follow them. A number that is NaN leaves that wheel as it was."))
	append(all, abi_entry("roci_osc_send", typeid_of(type_of(abi_osc_send)), "int roci_osc_send(const char *address, const roci_value *args, int count, const char *host, int port)", "Sends an OSC message to another program, a phone or another sketch: `args` holds `count` values, each a number (a whole number goes as an integer, any other as a float), text, a boolean, or a list of numbers, which goes as a blob of bytes. `host` is a name or an address (NULL for this computer) and `port` the port (0 for 9000). Gives 1 when it was sent, and 0 when the address does not begin with a slash, the host is unknown or the system would not send it."))
	append(all, abi_entry("roci_record_sound", typeid_of(type_of(abi_record_sound)), "int roci_record_sound(roci_sound_id sound, const char *path)", "Records what plays into a sound file as it plays: a sound, the sound roci_speakers gives for the whole mix (what is heard) or the one roci_mic gives for the microphone. The name ends in .wav (written here: 16-bit, two channels at 48,000) or .mp3, .ogg, .flac or .m4a (made by ffmpeg, which must be installed). The path is used as it is, and its folders are made. Gives 1 when it started and 0 when the name is not one of those, the sound is not there, there is no ffmpeg for the kind or the file cannot be made. The recording ends with roci_no_record_sound or when the program ends."))
	append(all, abi_entry("roci_no_record_sound", typeid_of(type_of(abi_no_record_sound)), "void roci_no_record_sound(roci_sound_id sound)", "Ends the recording of a sound (or of the speakers or the microphone) and finishes the file; nothing when it is not being recorded."))
	append(all, abi_entry("roci_midi_note", typeid_of(type_of(abi_midi_note)), "int roci_midi_note(double note, double velocity, double channel, double seconds)", "Plays a note through MIDI out: 60 is middle C, `velocity` 0 to 100 (negative for the usual 80), `channel` 1 to 16 (0 for 1) and `seconds` above 0 lets it go after that long (0 holds it until roci_midi_release). Goes to the first MIDI output, or the one roci_midi_to chose. Gives 1 when it was sent and 0 when there is no output or it would not take it. A note still sounding when the program ends is let go."))
	append(all, abi_entry("roci_midi_release", typeid_of(type_of(abi_midi_release)), "int roci_midi_release(double note, double channel)", "Lets a note go on a channel (0 for 1); a negative note lets every note go that is sounding on it. Gives 1 when it was sent."))
	append(all, abi_entry("roci_midi_set", typeid_of(type_of(abi_midi_set)), "int roci_midi_set(double controller, double value, double channel)", "Moves a controller (7 is volume, 1 the mod wheel) to a value, 0 to 100, on a channel (0 for 1). Gives 1 when it was sent."))
	append(all, abi_entry("roci_midi_bend", typeid_of(type_of(abi_midi_bend)), "int roci_midi_bend(double amount, double channel)", "Moves the pitch wheel, -100 to 100, 0 in the middle, on a channel (0 for 1). Gives 1 when it was sent."))
	append(all, abi_entry("roci_midi_program", typeid_of(type_of(abi_midi_program)), "int roci_midi_program(double number, double channel)", "Chooses an instrument, 0 to 127, on a channel (0 for 1). Gives 1 when it was sent."))
	append(all, abi_entry("roci_midi_to", typeid_of(type_of(abi_midi_to)), "void roci_midi_to(const char *name)", "Chooses the MIDI output the messages go to by part of its name, in any case; an empty name or NULL is the first output."))
	append(all, abi_entry("roci_midi_output_count", typeid_of(type_of(abi_midi_output_count)), "int roci_midi_output_count(void)", "How many MIDI outputs there are."))
	append(all, abi_entry("roci_midi_output_name", typeid_of(type_of(abi_midi_output_name)), "int roci_midi_output_name(int index, char *out, int capacity)", "Copies the name of a MIDI output (counting from 0) into `out`, which holds `capacity` bytes, and gives its length; 0 for an output that is not there."))
	append(all, abi_entry("roci_midi_clock", typeid_of(type_of(abi_midi_clock)), "int roci_midi_clock(double tempo)", "Starts a steady MIDI clock at some beats a minute (20 to 300): Start, and then 24 ticks a beat from a thread of its own. Called again it changes the tempo. Gives 1 when it started."))
	append(all, abi_entry("roci_midi_stop", typeid_of(type_of(abi_midi_stop)), "void roci_midi_stop(void)", "Stops the clock roci_midi_clock started, sending Stop."))
	append(all, abi_entry("roci_osc_send_bundle", typeid_of(type_of(abi_osc_send_bundle)), "int roci_osc_send_bundle(const roci_value *messages, int count, const char *host, int port)", "Sends several OSC messages together as one bundle, which the receiver reads as a group: `messages` holds `count` values of kind ROCI_LIST, each a message whose first item is its address (text) and whose other items are its arguments, as for roci_osc_send. Gives 1 when it was sent, and 0 when an address does not begin with a slash, the host is unknown or the system would not send it."))
	append(all, abi_entry("roci_load_sound", typeid_of(type_of(abi_load_sound)), "roci_sound_id roci_load_sound(const unsigned char *bytes, int length)", "Takes the bytes of a sound file (WAV, FLAC, MP3 or Ogg Vorbis) and gives its number, or 0 when they are not a sound. A file shorter than 30 seconds is decoded whole; a longer one is read as it plays from a copy of the bytes, so they may be let go of at once. A sound is stopped at its start, at volume 100, in the middle and at speed 1."))
	append(all, abi_entry("roci_load_sound_buffered", typeid_of(type_of(abi_load_sound_buffered)), "roci_sound_id roci_load_sound_buffered(const unsigned char *bytes, int length, double seconds)", "The same as roci_load_sound, with `seconds` of a long file kept ready as it plays (from 1 to 60; 8 for roci_load_sound). More rides out a slow disk or a high speed and costs about 400 kilobytes a second."))
	append(all, abi_entry("roci_load_sound_file_buffered", typeid_of(type_of(abi_load_sound_file_buffered)), "roci_sound_id roci_load_sound_file_buffered(const char *path, double seconds)", "The same as roci_load_sound_file, with `seconds` of a long file kept ready as it plays (from 1 to 60; 8 for roci_load_sound_file)."))
	append(all, abi_entry("roci_load_sound_file", typeid_of(type_of(abi_load_sound_file)), "roci_sound_id roci_load_sound_file(const char *path)", "Opens a sound file (WAV, FLAC, MP3 or Ogg Vorbis) and gives its number, or 0 when it cannot be read. A file longer than 30 seconds is not decoded whole: it is read from the disk as it plays, so a long song costs little memory (roci_load_sound, from the bytes of a file, does the same from a copy of the bytes, which it makes, so they may be let go of at once)."))
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

// ---- OSC ----

@(export, link_name = "roci_osc_listen")
abi_osc_listen :: proc "c" (port: f64) {
	context = abi_context()
	osc_listen(port)
}

@(export, link_name = "roci_osc_value")
abi_osc_value :: proc "c" (address: cstring) -> f64 {
	context = abi_context()
	return osc_value(text_from_abi(address))
}

// The arguments of an OSC message made from C values: numbers, text and booleans, and a list of numbers is
// a blob of bytes (each number rounded and kept from 0 to 255). Any other kind is left out.
@(private)
osc_args_from_abi :: proc(args: [^]Abi_Value, count: c.int) -> []oscp.Arg {
	values := make([dynamic]oscp.Arg, context.temp_allocator)
	for i in 0 ..< int(max(count, 0)) {
		a := args[i]
		#partial switch a.kind {
		case .Number:
			append(&values, a.number)
		case .Text:
			append(&values, text_from_abi(a.text))
		case .Boolean:
			append(&values, a.number != 0)
		case .List:
			bytes := make([]byte, int(max(a.count, 0)), context.temp_allocator)
			for j in 0 ..< len(bytes) {
				bytes[j] = byte(clamp(math.round(a.items[j].number), 0, 255))
			}
			append(&values, oscp.Blob(bytes))
		}
	}
	return values[:]
}

// Sends an OSC message: `count` values of kind number, text, boolean or list (a list of numbers is a blob of
// bytes; any other kind is left out), to a host (NULL or "" for this computer) and a port (0 or less for
// 9000). Gives 1 when it was sent and 0 when the address does not begin with a slash, the host is unknown or
// the system would not send it.
@(export, link_name = "roci_osc_send")
abi_osc_send :: proc "c" (address: cstring, args: [^]Abi_Value, count: c.int, host: cstring, port: c.int) -> c.int {
	context = abi_context()
	values := osc_args_from_abi(args, count)
	target := text_from_abi(host)
	result := osc_send(text_from_abi(address), values[:], target if target != "" else "127.0.0.1", int(port) if port > 0 else DEFAULT_OSC_PORT)
	return 1 if result == .Sent else 0
}

// Sends several OSC messages together as one bundle, which the receiver reads as a group: `messages` holds
// `count` values of kind list, each a message whose first item is its address (text) and the others its
// arguments, as for roci_osc_send. Gives 1 when it was sent and 0 when an address does not begin with a slash,
// the host is unknown or the system would not send it.
@(export, link_name = "roci_osc_send_bundle")
abi_osc_send_bundle :: proc "c" (messages: [^]Abi_Value, count: c.int, host: cstring, port: c.int) -> c.int {
	context = abi_context()
	out := make([dynamic]oscp.Out_Message, context.temp_allocator)
	for i in 0 ..< int(max(count, 0)) {
		m := messages[i]
		if m.kind != .List || m.count < 1 || m.items[0].kind != .Text {
			return 0
		}
		append(&out, oscp.Out_Message{address = text_from_abi(m.items[0].text), args = osc_args_from_abi(&m.items[1], m.count - 1)})
	}
	target := text_from_abi(host)
	result := osc_send_bundle(out[:], target if target != "" else "127.0.0.1", int(port) if port > 0 else DEFAULT_OSC_PORT)
	return 1 if result == .Sent else 0
}
