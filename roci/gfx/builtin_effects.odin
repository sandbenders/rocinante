// SPDX-License-Identifier: 0BSD
//
// The effects that come with rocinante: ordinary effect shaders (shaders.odin) kept in the
// program as text, so `effect "blur"` needs no file. Each has the values it starts with, so
// `effect "blur"` does something without `by`; a name that has a file extension is always
// a file of the sketch's own.
package gfx

Builtin_Effect :: struct {
	name:     string,
	source:   string,
	defaults: []Builtin_Value, // the values it starts with, given again by the sketch's `by`
}

Builtin_Value :: struct {
	name:  string,
	value: f64,
}

@(private = "file")
BLUR_DEFAULTS := [?]Builtin_Value{{"amount", 6}}
@(private = "file")
GLOW_DEFAULTS := [?]Builtin_Value{{"amount", 14}, {"strength", 1}, {"threshold", 0.6}}
@(private = "file")
PIXELATE_DEFAULTS := [?]Builtin_Value{{"block", 8}}
@(private = "file")
VIGNETTE_DEFAULTS := [?]Builtin_Value{{"amount", 0.6}}
@(private = "file")
SPLIT_DEFAULTS := [?]Builtin_Value{{"amount", 4}}
@(private = "file")
GRAIN_DEFAULTS := [?]Builtin_Value{{"amount", 0.15}}
@(private = "file")
GRAY_DEFAULTS := [?]Builtin_Value{{"amount", 1}}
@(private = "file")
INVERT_DEFAULTS := [?]Builtin_Value{{"amount", 1}}

BUILTIN_EFFECTS := [?]Builtin_Effect {
	{"blur", #load("effects/blur.hlsl", string), BLUR_DEFAULTS[:]},
	{"glow", #load("effects/glow.hlsl", string), GLOW_DEFAULTS[:]},
	{"pixelate", #load("effects/pixelate.hlsl", string), PIXELATE_DEFAULTS[:]},
	{"vignette", #load("effects/vignette.hlsl", string), VIGNETTE_DEFAULTS[:]},
	{"split", #load("effects/split.hlsl", string), SPLIT_DEFAULTS[:]},
	{"grain", #load("effects/grain.hlsl", string), GRAIN_DEFAULTS[:]},
	{"gray", #load("effects/gray.hlsl", string), GRAY_DEFAULTS[:]},
	{"invert", #load("effects/invert.hlsl", string), INVERT_DEFAULTS[:]},
}

// The built-in effect of that name, or nil.
builtin_effect :: proc(name: string) -> ^Builtin_Effect {
	for &b in BUILTIN_EFFECTS {
		if b.name == name {
			return &b
		}
	}
	return nil
}
