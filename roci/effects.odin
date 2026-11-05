// SPDX-License-Identifier: 0BSD
//
// Effects: a shader of the sketch's own, written in HLSL, that runs over a window's
// finished frame (roci/gfx/shaders.odin has what a shader looks like). `add_shader`
// translates the source and keeps it; `update_shader` does it again when the file
// changes; `effect` asks for it to run over the frame being drawn, with the values the
// sketch gives its globals by name, and the time, the frame and the mouse the shader
// reads as `time`, `frame` and `mouse`. Effects run in the order they were asked for.
package roci

import "core:math"
import "core:strings"
import "gfx"

// A shader that was added, from 1; 0 is none.
Shader :: gfx.Shader_Id

// One value a sketch gives a shader: the name of one of its globals and up to four numbers.
Effect_Value :: struct {
	name:   string,
	floats: [4]f64,
	count:  int, // how many of `floats` are given (1 to 4)
}

// Translates `source` and keeps it. Gives what the translator said when it is not a good
// shader (the shader is kept, and draws nothing until `update_shader` mends it).
add_shader :: proc(source: string, file := "shader") -> (shader: Shader, message: string) {
	return gfx.shader_add(source, file)
}

// Translates a changed `source` into `shader`. Gives what the translator said, "" when good.
update_shader :: proc(shader: Shader, source: string, file := "shader") -> (message: string) {
	return gfx.shader_update(shader, source, file)
}

// Which set of shaders a number belongs to; a number kept from before a `shutdown` is stale.
shader_epoch :: proc() -> int {
	return gfx.shaders_epoch
}

// The names of the globals a shader reads from the sketch, in the order it declares them.
shader_value_names :: proc(shader: Shader, allocator := context.temp_allocator) -> []string {
	data := gfx.shader_data(shader)
	if data == nil {
		return nil
	}
	names := make([]string, len(data.params.list), allocator)
	for p, i in data.params.list {
		names[i] = p.name
	}
	return names
}

// Runs `shader` over the current window's frame once it is drawn. The values that name no
// global of the shader are ignored (`shader_value_names` says which there are); a global
// given fewer numbers than it has keeps the rest at 0. Gives false when there is no window,
// or the shader is not good, or a canvas is being drawn into (an effect runs over a window).
effect :: proc(shader: Shader, values: []Effect_Value = nil) -> bool {
	w := current_win()
	if w == nil || into_list() != nil {
		return false
	}
	data := gfx.shader_data(shader)
	if data == nil || len(data.spirv) == 0 {
		return false
	}
	block := make([]u8, data.params.size, context.temp_allocator)
	for v in values {
		for p in data.params.list {
			if p.name != v.name {
				continue
			}
			floats := (cast([^]f32)raw_data(block[p.offset:]))[:p.floats]
			for i in 0 ..< min(p.floats, v.count, 4) {
				floats[i] = f32(v.floats[i])
			}
			break
		}
	}
	mouse := w.mouse
	gfx.effect(&w.list, shader, f32(time_now()), f32(the.frame), {f32(mouse.x), f32(mouse.y)}, block)
	return true
}

// Whether `finite` numbers only: a value with a NaN or an infinity is not given.
effect_value_ok :: proc(v: Effect_Value) -> bool {
	for i in 0 ..< min(v.count, 4) {
		if math.is_nan(v.floats[i]) || math.is_inf(v.floats[i]) {
			return false
		}
	}
	return v.count >= 1 && v.count <= 4 && strings.trim_space(v.name) != ""
}
