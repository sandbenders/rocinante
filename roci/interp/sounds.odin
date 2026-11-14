// SPDX-License-Identifier: 0BSD
//
// Sounds a sketch loads: `load "rain.wav"` finds the file by name in the sketch's `assets/`
// (folder.find_asset), decodes it once (roci.add_sound) and gives a sound that `play` and
// `loop` play. While the sketch is watched (`roci run`) the file's time is looked at once a
// frame, and a file saved again is decoded into the same sound, which goes on playing; a
// reload finds the sound its file already has, so the music does not start again on every
// save. A name nothing answers, an ambiguous one and a file that is not a sound each give
// no sound, which plays nothing, and a message said once; a name that is not there is looked
// for again once a second.
package interp

import "../"
import "../folder"
import "../lang"
import "core:os"
import "core:strings"
import "core:time"

// What `load` remembers about a sound's name, on the heap (it lives as long as the interpreter).
Sound_Entry :: struct {
	state:   Picture_State,
	path:    string, // the file, from where the sketch runs
	id:      roci.Sound,
	epoch:   int,       // which set of sounds `id` belongs to (`roci.sound_epoch`)
	mtime:   time.Time, // the file's modification time when it was read
	tried:   time.Tick, // when a name that was not there was last looked for
	checked: int,       // the frame the file's time was last compared with `mtime`
	others:  string,    // for an ambiguous name, the files that share it, said in words
	suggest: string,    // and the first of them, as a name that is not ambiguous
}

// A file that has been decoded, whichever interpreter asked, by its path.
Decoded_Sound :: struct {
	id:    roci.Sound,
	mtime: time.Time,
	epoch: int,
}

@(thread_local) decoded_sounds: map[string]Decoded_Sound

// Forgets every decoded sound file (the sounds themselves are let go by `roci.shutdown`).
forget_decoded_sounds :: proc() {
	for path in decoded_sounds {
		delete(path)
	}
	delete(decoded_sounds)
	decoded_sounds = nil
}

// The sound the file `name` is, or the empty value. `span` is where to say what went wrong.
@(private)
load_sound :: proc(it: ^Interp, name: string, span: lang.Span) -> Value {
	entry, known := it.sounds[name]
	if known && entry.epoch == roci.sound_epoch() {
		if entry.state == .Loaded {
			frame := roci.frame_count()
			if it.path == "" || entry.checked == frame {
				return entry.id
			}
			entry.checked = frame
			info, err := os.stat(entry.path, context.temp_allocator)
			if err == nil && info.modification_time != entry.mtime {
				// saved again: the same sound, with what the file holds now
				if bytes, read_err := os.read_entire_file(entry.path, context.temp_allocator); read_err == nil && roci.replace_sound(entry.id, bytes) {
					entry.mtime = info.modification_time
					if done, found := &decoded_sounds[entry.path]; found {
						done.mtime = entry.mtime
					}
				}
			}
			it.sounds[name] = entry
			return entry.id
		} else if time.duration_seconds(time.tick_since(entry.tried)) < PICTURE_RETRY_SECONDS {
			say_sound_problem(it, name, entry, span)
			return nil
		}
	}
	fresh := read_sound(it, name)
	fresh.tried = time.tick_now()
	fresh.epoch = roci.sound_epoch()
	fresh.checked = roci.frame_count()
	store_sound(it, name, fresh)
	if fresh.state != .Loaded {
		say_sound_problem(it, name, fresh, span)
		return nil
	}
	return fresh.id
}

// Finds, reads and decodes the file called `name`.
@(private)
read_sound :: proc(it: ^Interp, name: string) -> (entry: Sound_Entry) {
	root, _ := assets_root(it)
	if root == "" {
		entry.state = .Missing
		return
	}
	path, status, candidates := folder.find_asset(root, name, context.temp_allocator)
	#partial switch status {
	case .Missing:
		entry.state = .Missing
		return
	case .Ambiguous:
		entry.state = .Ambiguous
		entry.others = strings.join(candidates, " and ")
		entry.suggest = strings.clone(strings.trim_prefix(candidates[0], "assets/"))
		return
	}
	entry.path = strings.concatenate({root, "/", path})
	if info, err := os.stat(entry.path, context.temp_allocator); err == nil {
		entry.mtime = info.modification_time
	}
	if done, found := decoded_sounds[entry.path]; found && done.epoch == roci.sound_epoch() {
		entry.id = done.id
		if done.mtime != entry.mtime {
			if bytes, err := os.read_entire_file(entry.path, context.temp_allocator); err == nil && roci.replace_sound(done.id, bytes) {
				decoded_sounds[entry.path] = Decoded_Sound{done.id, entry.mtime, done.epoch}
			}
		}
		return
	}
	bytes, read_err := os.read_entire_file(entry.path, context.temp_allocator)
	if read_err != nil {
		entry.state = .Unreadable
		return
	}
	id, ok := roci.add_sound(bytes)
	if !ok {
		entry.state = .Unreadable
		return
	}
	entry.id = id
	if decoded_sounds == nil {
		decoded_sounds = make(map[string]Decoded_Sound)
	}
	if _, found := decoded_sounds[entry.path]; found {
		decoded_sounds[entry.path] = Decoded_Sound{id, entry.mtime, roci.sound_epoch()}
	} else {
		decoded_sounds[strings.clone(entry.path)] = Decoded_Sound{id, entry.mtime, roci.sound_epoch()}
	}
	return
}

// Remembers an entry for a name, letting go of the one it replaces.
@(private)
store_sound :: proc(it: ^Interp, name: string, entry: Sound_Entry) {
	if it.sounds == nil {
		it.sounds = make(map[string]Sound_Entry)
	}
	if old, found := it.sounds[name]; found {
		delete(old.path)
		delete(old.others)
		delete(old.suggest)
		it.sounds[name] = entry
		return
	}
	it.sounds[strings.clone(name)] = entry
}

// Lets go of what `load` remembered of sounds.
@(private)
drop_sounds :: proc(it: ^Interp) {
	for name, entry in it.sounds {
		delete(entry.path)
		delete(entry.others)
		delete(entry.suggest)
		delete(name)
	}
	delete(it.sounds)
	it.sounds = nil
}

@(private)
say_sound_problem :: proc(it: ^Interp, name: string, entry: Sound_Entry, span: lang.Span) {
	example := strings.concatenate({"rain = load \"", name, "\""}, context.temp_allocator)
	switch entry.state {
	case .Loaded:
	case .Missing:
		fail(it, .Sound_Missing, span, name, "Sounds are found by their file name in your sketch's `assets` folder, and there is no file of that name there. `roci add` copies one in for you.", "", example)
	case .Ambiguous:
		fail(it, .Sound_Missing, span, name, strings.concatenate({"Two or more files have that name: ", entry.others, ". Say which one you mean with its folder."}, context.temp_allocator), "", strings.concatenate({"rain = load \"", entry.suggest, "\""}, context.temp_allocator))
	case .Unreadable:
		fail(it, .Sound_Unreadable, span, name, "", "", example)
	}
}

// What a sketch reads of a sound: `rain.playing`, `rain.at` and the rest.
@(private)
sound_field :: proc(s: roci.Sound, name: string) -> Value {
	st := roci.sound_state(s)
	switch name {
	case "playing": return st.playing
	case "at":      return st.at
	case "length":  return st.length
	case "volume":  return st.volume
	case "pan":     return st.pan
	case "speed":   return st.speed
	case "loop":    return st.looping
	case "pitch":   return st.pitch
	case "note":    return st.note
	}
	return nil
}

// `set rain at 30 volume 50 pan -50 speed 1.5 loop false`, and a sound's field assigned the same way.
@(private)
set_sound :: proc(it: ^Interp, target: Value, options: []lang.IR_Option) {
	s, is_sound := target.(roci.Sound)
	if !is_sound {
		return
	}
	at, volume, pan, speed, note, pitch: Maybe(f64)
	looping: Maybe(bool)
	for o in options {
		if len(o.args) == 0 {
			continue
		}
		v := eval(it, o.args[0])
		switch o.word {
		case "at":     at = as_number(v)
		case "volume": volume = as_number(v)
		case "pan":    pan = as_number(v)
		case "speed":  speed = as_number(v)
		case "loop":   looping = as_bool(v)
		case "note":   note = as_number(v)
		case "pitch":  pitch = as_number(v)
		}
	}
	roci.set_sound(s, at, volume, pan, speed, looping, note, pitch)
}

// The settings `play` and `loop` take, and the note, pitch and seconds of what they play.
@(private)
sound_options :: proc(it: ^Interp, options: []lang.IR_Option) -> (volume, pan, speed, note, pitch, seconds: Maybe(f64)) {
	if v, ok := option_value(it, options, "note"); ok {
		note = as_number(v)
	}
	if v, ok := option_value(it, options, "pitch"); ok {
		pitch = as_number(v)
	}
	if v, ok := option_value(it, options, "for"); ok {
		seconds = as_number(v)
	}
	if v, ok := option_value(it, options, "volume"); ok {
		volume = as_number(v)
	}
	if v, ok := option_value(it, options, "pan"); ok {
		pan = as_number(v)
	}
	if v, ok := option_value(it, options, "speed"); ok {
		speed = as_number(v)
	}
	return
}

// How many bands a sketch asked for, as a whole number; one that is not a number is the usual.
@(private)
band_count :: proc(v: f64) -> int {
	if !(v == v) {
		return roci.BANDS_USUAL
	}
	return int(clamp(v, 1, f64(roci.BANDS_MOST)))
}
