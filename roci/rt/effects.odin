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

@(thread_local) @(private) shaders: map[string]roci.Shader

// A shader by its name: one that comes with rocinante, or a file of the assets. 0 after saying why not.
@(private)
load_shader :: proc(name: string, fill: bool) -> roci.Shader {
	// a shader used to fill and one used as an effect are written for different preludes, so a file used both ways is two shaders
	key := strings.concatenate({name, "\x00fill"}, context.temp_allocator) if fill else name
	if known, ok := shaders[key]; ok {
		return known
	}
	if !fill {
		if source, _, builtin := roci.builtin_effect(name); builtin {
			id, message := roci.add_shader(source, name, false)
			if message != "" {
				say_once(key, fmt.tprintf("The effect `%s` is broken: %s", name, message))
			}
			return remember_shader(key, id, message == "")
		}
	}
	if !strings.contains(name, ".") {
		say_once(key, fmt.tprintf("I could not find an effect called `%s`: it is not one of the effects that come with rocinante (%s), and a shader of your own is a file with its extension, like `wave.hlsl`.", name, strings.join(roci.builtin_effect_names(), ", ", context.temp_allocator)))
		return 0
	}
	path := find_file(name, "shader")
	if path == "" {
		return 0
	}
	bytes, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		say_once(key, fmt.tprintf("I could not read the shader `%s`.", name))
		return 0
	}
	id, message := roci.add_shader(string(bytes), name, fill)
	if message != "" {
		say_once(key, fmt.tprintf("The shader `%s` is broken:\n%s", name, message))
	}
	return remember_shader(key, id, message == "")
}

@(private)
remember_shader :: proc(key: string, id: roci.Shader, good: bool) -> roci.Shader {
	if shaders == nil {
		shaders = make(map[string]roci.Shader)
	}
	shaders[strings.clone(key)] = id if good else 0
	return id if good else 0
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
