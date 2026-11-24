// SPDX-License-Identifier: 0BSD
//
// The shaders a program names: every `effect` and `shade` whose shader is written as text in the line
// (`effect "melt.hlsl"`, `shade "spiral.hlsl"`, `effect "glow"`), so both back ends can translate them
// before the first frame and no frame waits for one. A name made while the sketch runs (with a text hole
// or from a value) is not known before it runs, and is translated when its line first runs, as before.
package lang

import "../registry"

// A shader an `effect` or `shade` line names by its own text, and whether it fills shapes (`shade`) or
// runs over the frame (`effect`), since the two are translated with different preludes.
Named_Shader :: struct {
	name: string,
	fill: bool,
}

// Notes the shader of an `effect` (its shader shape, not a sound's) or a `shade` call, once for each
// name and use.
@(private)
shader_use :: proc(c: ^Checker, verb: ^registry.Verb, shape: int, args: []^IR) {
	fill: bool
	switch verb.name {
	case "effect":
		if shape != 0 {
			return // a sound's effect
		}
	case "shade":
		fill = true
	case:
		return
	}
	if len(args) == 0 || args[0] == nil {
		return
	}
	text, is_text := args[0].kind.(IR_Text)
	if !is_text || text.value == "" {
		return
	}
	for known in c.shaders {
		if known.name == text.value && known.fill == fill {
			return
		}
	}
	append(&c.shaders, Named_Shader{name = text.value, fill = fill})
}
