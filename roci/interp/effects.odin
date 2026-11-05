// SPDX-License-Identifier: 0BSD
//
// `effect "wave.hlsl" by { amount: 0.02 }`: a shader of the sketch's own run over the
// window's finished frame (roci/effects.odin). The file is found by its name in the
// sketch's `assets/` like a picture, translated the first time and again whenever its
// modification time changes, so a shader can be edited while the sketch runs; a mistake in
// it is said in the shader's own words and the frame shows without the effect until it is
// mended, when the message goes. The record after `by` gives the shader's globals their
// values by name: a number, a vector (two to four numbers) or a color (0 to 1 for the
// shader).
package interp

import "../"
import "../folder"
import "../lang"
import "../maths"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

Shader_State :: enum u8 {
	Good,
	Missing,
	Ambiguous,
	Broken,
	Unreadable,
}

// What `effect` remembers about a name, on the heap (it lives as long as the interpreter).
Shader_Entry :: struct {
	state:   Shader_State,
	path:    string,
	id:      roci.Shader,
	epoch:   int,
	mtime:   time.Time,
	tried:   time.Tick, // when a name that was not there was last looked for
	message: string,    // for a broken shader, what the translator said
	others:  string,    // for an ambiguous name, the files that share it
	suggest: string,
}

// How long a name that was not there waits before it is looked for again.
SHADER_RETRY_SECONDS :: 1.0

@(private)
effect_verb :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call) {
	name := as_text(eval(it, call.args[0]))
	id := load_shader(it, name, e.span)
	if id == 0 {
		_ = roci.effect(0) // still makes the window, as a drawing verb would
		return
	}
	if !roci.effect(id, shader_values(it, e, call, id, name)) {
		fail(it, .Shader_Window, e.span, name, "", "", "draw [\n  circle at mouse radius 40\n  effect \"wave.hlsl\"\n]")
	}
}

// `shade "spiral.hlsl" by { ... }`: shapes drawn from now on are filled by the shader, until
// another fill is chosen.
@(private)
shade_verb :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call) {
	name := as_text(eval(it, call.args[0]))
	id := load_shader(it, name, e.span, true)
	if id == 0 {
		return
	}
	_ = roci.fill_shader(id, shader_values(it, e, call, id, name))
}

// The values the record after `by` gives the shader's globals, by name: numbers, flags,
// vectors and colors (0 to 1 for the shader). A name the shader has not is said.
@(private)
shader_values :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call, id: roci.Shader, name: string) -> []roci.Effect_Value {
	given := make([dynamic]roci.Effect_Value, context.temp_allocator)
	record, ok := option_or_nil(it, call.options, "by").(^Record)
	if !ok || record == nil {
		return given[:]
	}
	known := roci.shader_value_names(id)
	for f, i in it.types.shapes[record.shape].fields {
		value := Value(nil)
		if i < len(record.fields) {
			value = record.fields[i]
		}
		item := roci.Effect_Value{name = f.name}
		#partial switch x in value {
		case f64:
			item.floats[0], item.count = x, 1
		case bool:
			item.floats[0], item.count = 1 if x else 0, 1
		case Vec:
			item.count = min(x.n, 4)
			for k in 0 ..< item.count {
				item.floats[k] = x.v[k]
			}
		case maths.Colour:
			for k in 0 ..< 4 {
				item.floats[k] = f64(x[k]) / 255
			}
			item.count = 4
		case:
			item.count = 0
		}
		if item.count == 0 || !roci.effect_value_ok(item) {
			continue
		}
		found := false
		for n in known {
			found ||= n == f.name
		}
		if !found {
			say_shader_value(it, e, name, f.name, known)
			continue
		}
		append(&given, item)
	}
	return given[:]
}

// The number of the shader the file `name` is, translating it first when it is new or has
// changed, or 0 (after saying why) when it cannot be had.
@(private)
load_shader :: proc(it: ^Interp, name: string, span: lang.Span, fill := false) -> roci.Shader {
	context.allocator = runtime.heap_allocator()
	// A shader used to fill and one used as an effect are written for different preludes, so a
	// file used both ways is two shaders.
	key := strings.concatenate({name, "\x00fill"}, context.temp_allocator) if fill else name
	entry, known := it.shaders[key]
	if known && entry.epoch == roci.shader_epoch() {
		if entry.state == .Good || entry.state == .Broken || entry.state == .Unreadable {
			info, err := os.stat(entry.path, context.temp_allocator)
			if err == nil && info.modification_time == entry.mtime {
				say_shader_problem(it, name, entry, span)
				return entry.id if entry.state == .Good else 0
			}
		} else if time.duration_seconds(time.tick_since(entry.tried)) < SHADER_RETRY_SECONDS {
			say_shader_problem(it, name, entry, span)
			return 0
		}
	}
	fresh := read_shader(it, name, entry if known && entry.epoch == roci.shader_epoch() else Shader_Entry{}, fill)
	fresh.tried = time.tick_now()
	fresh.epoch = roci.shader_epoch()
	store_shader(it, key, fresh)
	// A message for the file as it was before is not one for the file as it is.
	forget_error(it, .Shader_Broken, span)
	say_shader_problem(it, name, fresh, span)
	return fresh.id if fresh.state == .Good else 0
}

// Finds and translates the file called `name`. `before` is what was known of it, so a
// shader that is only being changed keeps its number.
@(private)
read_shader :: proc(it: ^Interp, name: string, before: Shader_Entry, fill: bool) -> (entry: Shader_Entry) {
	root, _ := assets_root(it)
	entry.id = before.id
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
		entry.others = strings.join(candidates, " and ", runtime.heap_allocator())
		entry.suggest = strings.clone(strings.trim_prefix(candidates[0], "assets/"), runtime.heap_allocator())
		return
	}
	entry.path = strings.concatenate({root, "/", path}, runtime.heap_allocator())
	if info, err := os.stat(entry.path, context.temp_allocator); err == nil {
		entry.mtime = info.modification_time
	}
	bytes, read_err := os.read_entire_file(entry.path, context.temp_allocator)
	if read_err != nil {
		entry.state = .Unreadable
		return
	}
	source := string(bytes)
	message: string
	if entry.id == 0 {
		entry.id, message = roci.add_shader(source, name, fill)
	} else {
		message = roci.update_shader(entry.id, source, name)
	}
	if message != "" {
		entry.state = .Broken
		entry.message = strings.clone(message, runtime.heap_allocator())
	}
	return
}

@(private)
store_shader :: proc(it: ^Interp, name: string, entry: Shader_Entry) {
	context.allocator = runtime.heap_allocator()
	if it.shaders == nil {
		it.shaders = make(map[string]Shader_Entry)
	}
	if old, found := it.shaders[name]; found {
		release_shader_entry(old)
		it.shaders[name] = entry
		return
	}
	it.shaders[strings.clone(name)] = entry
}

@(private)
release_shader_entry :: proc(entry: Shader_Entry) {
	delete(entry.path)
	delete(entry.message)
	delete(entry.others)
	delete(entry.suggest)
}

// Lets go of what `effect` remembered.
@(private)
drop_shaders :: proc(it: ^Interp) {
	context.allocator = runtime.heap_allocator()
	for name, entry in it.shaders {
		release_shader_entry(entry)
		delete(name)
	}
	delete(it.shaders)
	it.shaders = nil
}

@(private)
say_shader_problem :: proc(it: ^Interp, name: string, entry: Shader_Entry, span: lang.Span) {
	example := strings.concatenate({"effect \"", name, "\""}, context.temp_allocator)
	switch entry.state {
	case .Good:
	case .Missing:
		fail(it, .Shader_Missing, span, name, "Shaders are found by their file name in your sketch's `assets` folder, and there is no file of that name there.", "", "effect \"wave.hlsl\"")
	case .Ambiguous:
		fail(it, .Shader_Missing, span, name, strings.concatenate({"Two or more files have that name: ", entry.others, ". Say which one you mean with its folder."}, context.temp_allocator), "", strings.concatenate({"effect \"", entry.suggest, "\""}, context.temp_allocator))
	case .Unreadable:
		fail(it, .Shader_Missing, span, name, "The file could not be read.", "", example)
	case .Broken:
		fail(it, .Shader_Broken, span, name, entry.message, "", "")
	}
}

@(private)
say_shader_value :: proc(it: ^Interp, e: ^lang.IR, shader, value: string, known: []string) {
	have := "It reads no values: write `float amount;` at the top of the shader to give it one."
	example := "effect \"wave.hlsl\" by { amount: 0.02 }"
	if len(known) > 0 {
		have = fmt.tprintf("The values it reads are: %s.", strings.join(known, ", ", context.temp_allocator))
		example = fmt.tprintf("effect \"%s\" by { %s: 1 }", shader, known[0])
	} else {
		example = fmt.tprintf("effect \"%s\" by { amount: 0.02 }", shader)
	}
	fail(it, .Shader_Value, e.span, shader, value, have, example)
}
