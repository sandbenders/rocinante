// SPDX-License-Identifier: 0BSD
//
// Effects over the window's finished frame, shaders that fill shapes, and the effects of sounds, as the
// interpreter does them: the shaders that come with rocinante by their names, a shader of the sketch's own
// from a file of the assets (translated the first time it is used), and what a shader or a sound reads by name
// from the record after `by`. A message about a shader is said once, in the shader translator's own words.
package rt

import "core:fmt"
import "core:os"
import "core:strings"
import "../"
import "../folder"

// What became of a shader's name: its number (0 when it cannot be drawn with) and, when it cannot, why,
// which is said the first time a line uses it.
@(private)
Loaded_Shader :: struct {
	id:      roci.Shader,
	problem: string,
}

@(thread_local) @(private) shaders: map[string]Loaded_Shader

// A shader the program names in an `effect` or `shade` line by its own text, translated before the first frame.
Named_Shader :: struct {
	name: string,
	fill: bool,
}

// Translates the shaders the program names before its first frame, so no frame waits for one. A file
// that is not in the assets is left to the line that uses it, which says so; a problem with one that is
// is kept and said when its line first runs, as it would have been.
warm_shaders :: proc(named: []Named_Shader) {
	for n in named {
		key := shader_key(n.name, n.fill)
		if _, known := shaders[key]; known {
			continue
		}
		if loaded, found := translate_shader(n.name, n.fill, quiet = true); found {
			remember_shader(key, loaded)
		}
	}
}

@(private)
shader_key :: proc(name: string, fill: bool) -> string {
	// a shader used to fill and one used as an effect are written for different preludes, so a file used both ways is two shaders
	return strings.concatenate({name, "\x00fill"}, context.temp_allocator) if fill else name
}

// A shader by its name: one that comes with rocinante, or a file of the assets. 0 after saying why not.
@(private)
load_shader :: proc(name: string, fill: bool) -> roci.Shader {
	key := shader_key(name, fill)
	loaded, known := shaders[key]
	if !known {
		found: bool
		loaded, found = translate_shader(name, fill, quiet = false)
		if !found {
			return 0 // said; looked for again next time, as a picture is
		}
		remember_shader(key, loaded)
	}
	if loaded.problem != "" {
		say_once(key, loaded.problem)
	}
	return loaded.id
}

// Finds and translates a shader. `found` is false for a file that is not in the assets (said unless `quiet`,
// and not to be remembered, so a file put there later is found); otherwise `problem` says why it cannot be
// drawn with, and `id` is 0 then.
@(private)
translate_shader :: proc(name: string, fill, quiet: bool) -> (loaded: Loaded_Shader, found: bool) {
	if !fill {
		if source, _, builtin := roci.builtin_effect(name); builtin {
			id, message := roci.add_shader(source, name, false)
			if message != "" {
				return {problem = fmt.aprintf("The effect `%s` is broken: %s", name, message)}, true
			}
			return {id = id}, true
		}
	}
	if !strings.contains(name, ".") {
		return {problem = fmt.aprintf("I could not find an effect called `%s`: it is not one of the effects that come with rocinante (%s), and a shader of your own is a file with its extension, like `wave.hlsl`.", name, strings.join(roci.builtin_effect_names(), ", ", context.temp_allocator))}, true
	}
	path: string
	if quiet {
		if found_at, status, _ := folder.find_asset(ASSETS_ROOT, name, context.temp_allocator); status == .Found {
			path = strings.concatenate({ASSETS_ROOT, "/", found_at}, context.temp_allocator)
		}
	} else {
		path = find_file(name, "shader")
	}
	if path == "" {
		return {}, false
	}
	bytes, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		return {problem = fmt.aprintf("I could not read the shader `%s`.", name)}, true
	}
	id, message := roci.add_shader(string(bytes), name, fill)
	if message != "" {
		return {problem = fmt.aprintf("The shader `%s` is broken:\n%s", name, message)}, true
	}
	return {id = id}, true
}

@(private)
remember_shader :: proc(key: string, loaded: Loaded_Shader) {
	if shaders == nil {
		shaders = make(map[string]Loaded_Shader)
	}
	shaders[strings.clone(key)] = loaded
}

// Forgets every shader's name and what became of it, so a test leaves nothing behind (the shaders themselves
// go with `roci.shutdown`).
forget_shaders :: proc() {
	for key, loaded in shaders {
		delete(key)
		delete(loaded.problem)
	}
	delete(shaders)
	shaders = nil
}

// The values a shader reads that the record after `by` named, and that the shader has.
@(private)
known_values :: proc(id: roci.Shader, shader, verb: string, values: []roci.Effect_Value) -> []roci.Effect_Value {
	known := roci.shader_value_names(id)
	given := make([dynamic]roci.Effect_Value, context.temp_allocator)
	for item in values {
		if item.count == 0 || !roci.effect_value_ok(item) {
			continue
		}
		found := false
		for n in known {
			found ||= n == item.name
		}
		if !found {
			have := "It reads no values: write `float amount;` at the top of the shader to give it one."
			if len(known) > 0 {
				have = fmt.tprintf("The values it reads are: %s.", strings.join(known, ", ", context.temp_allocator))
			}
			say_once(strings.concatenate({verb, shader, item.name}, context.temp_allocator), fmt.tprintf("`%s` is not a value the shader `%s` reads. %s", item.name, shader, have))
			continue
		}
		append(&given, item)
	}
	return given[:]
}

// `effect "wave.hlsl" by { amount: 0.02 }`.
effect :: proc(name: string, values: []roci.Effect_Value = nil) {
	id := load_shader(name, false)
	if id == 0 {
		_ = roci.effect(0) // still makes the window, as a drawing verb would
		return
	}
	given := known_values(id, name, "effect", values)
	if _, defaults, builtin := roci.builtin_effect(name); builtin {
		joined := make([]roci.Effect_Value, len(defaults) + len(given), context.temp_allocator)
		copy(joined, defaults)
		copy(joined[len(defaults):], given)
		given = joined
	}
	_ = roci.effect(id, given)
}

// `shade "spiral.hlsl" by { ... }`.
shade :: proc(name: string, values: []roci.Effect_Value = nil) {
	id := load_shader(name, true)
	if id == 0 {
		return
	}
	_ = roci.fill_shader(id, known_values(id, name, "shade", values))
}

// The values of a shader, one at a time.
effect_number :: proc(name: string, x: f64) -> roci.Effect_Value {
	return {name = name, floats = {x, 0, 0, 0}, count = 1}
}

effect_vector :: proc(name: string, v: [$N]f64) -> roci.Effect_Value {
	item := roci.Effect_Value{name = name, count = min(N, 4)}
	for i in 0 ..< item.count {
		item.floats[i] = v[i]
	}
	return item
}

effect_colour :: proc(name: string, c: roci.Colour) -> roci.Effect_Value {
	return {name = name, floats = {f64(c[0]) / 255, f64(c[1]) / 255, f64(c[2]) / 255, f64(c[3]) / 255}, count = 4}
}

// `effect guitar "delay" by { time: 0.3 }`.
sound_effect :: proc(s: roci.Sound, name: string, settings: []roci.Sound_Setting) {
	unknown, problem := roci.sound_effect(s, name, settings)
	#partial switch problem {
	case .Unknown_Effect:
		say_once(strings.concatenate({"sound effect ", name}, context.temp_allocator), fmt.tprintf("I could not find a sound effect called `%s`. They are %s.", name, strings.join(roci.sound_effect_names(), ", ", context.temp_allocator)))
	}
	if len(unknown) > 0 {
		say_once(strings.concatenate({"effect setting ", name, unknown[0]}, context.temp_allocator), fmt.tprintf("`%s` is not a setting of the effect `%s`. Its settings are %s.", unknown[0], name, strings.join(roci.sound_effect_settings(name), ", ", context.temp_allocator)))
	}
}
