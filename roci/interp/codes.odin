// SPDX-License-Identifier: 0BSD
//
// Every registry verb the interpreter runs, as a number. A call switches on its
// verb's code rather than its name: a string switch compares the name with each case
// in turn, which cost a fifth of the time of a frame of 100,000 circles. The code of
// a verb is looked up once, by its place in `registry.ALL_VERBS`.
package interp

import "../registry"
import "base:runtime"

Verb_Code :: enum u8 {
	None,
	Window,
	Title,
	Fullscreen,
	Quit,
	Background,
	Clear,
	Circle,
	Ellipse,
	Rect,
	Square,
	Line,
	Point,
	Triangle,
	Quad,
	Arc,
	Fill,
	No_Fill,
	Stroke,
	No_Stroke,
	Thickness,
	Alpha,
	Caps,
	Joins,
	Rgb,
	Hsb,
	Oklch,
	Gradient,
	Mix,
	Move,
	Turn,
	Grow,
	Shear,
	Push,
	Forward,
	Back,
	Left,
	Right,
	Pen_Up,
	Pen_Down,
	Home,
	Map,
	Clamp,
	Dist,
	Abs,
	Sqrt,
	Floor,
	Round,
	Ceil,
	Sin,
	Cos,
	Ease,
	Random,
	Pick,
	Gaussian,
	Seed,
	Noise,
	Fbm,
	// The verbs only the language has, from here on: `is_language_code` tells them apart.
	Add,
	Remove,
	Count,
	Item,
	Set,
	Send,
	Print,
	Copy,
	Keep,
	Skip,
	Collect,
	Combine,
	Find,
	Held,
	Shuffle,
	Sort,
	Tween,
	Table,
	Put,
	Get,
	Keys,
	Touching,
	Contact,
	Hits,
	Inside,
	Cast,
}

// The registry's name of each code. A test fails when the registry gains a verb
// that has no code here.
VERB_CODE_NAMES := [Verb_Code]string{
	.None = "",
	.Window = "window",
	.Title = "title",
	.Fullscreen = "fullscreen",
	.Quit = "quit",
	.Background = "background",
	.Clear = "clear",
	.Circle = "circle",
	.Ellipse = "ellipse",
	.Rect = "rect",
	.Square = "square",
	.Line = "line",
	.Point = "point",
	.Triangle = "triangle",
	.Quad = "quad",
	.Arc = "arc",
	.Fill = "fill",
	.No_Fill = "no fill",
	.Stroke = "stroke",
	.No_Stroke = "no stroke",
	.Thickness = "thickness",
	.Alpha = "alpha",
	.Caps = "caps",
	.Joins = "joins",
	.Rgb = "rgb",
	.Hsb = "hsb",
	.Oklch = "oklch",
	.Gradient = "gradient",
	.Mix = "mix",
	.Move = "move",
	.Turn = "turn",
	.Grow = "grow",
	.Shear = "shear",
	.Push = "push",
	.Forward = "forward",
	.Back = "back",
	.Left = "left",
	.Right = "right",
	.Pen_Up = "pen up",
	.Pen_Down = "pen down",
	.Home = "home",
	.Map = "map",
	.Clamp = "clamp",
	.Dist = "dist",
	.Abs = "abs",
	.Sqrt = "sqrt",
	.Floor = "floor",
	.Round = "round",
	.Ceil = "ceil",
	.Sin = "sin",
	.Cos = "cos",
	.Ease = "ease",
	.Random = "random",
	.Pick = "pick",
	.Gaussian = "gaussian",
	.Seed = "seed",
	.Noise = "noise",
	.Fbm = "fbm",
	.Add = "add",
	.Remove = "remove",
	.Count = "count",
	.Item = "item",
	.Set = "set",
	.Send = "send",
	.Print = "print",
	.Copy = "copy",
	.Keep = "keep",
	.Skip = "skip",
	.Collect = "collect",
	.Combine = "combine",
	.Find = "find",
	.Held = "held",
	.Shuffle = "shuffle",
	.Sort = "sort",
	.Tween = "tween",
	.Table = "table",
	.Put = "put",
	.Get = "get",
	.Keys = "keys",
	.Touching = "touching",
	.Contact = "contact",
	.Hits = "hits",
	.Inside = "inside",
	.Cast = "cast",
}

// The code of each verb of `registry.ALL_VERBS`, by its place there.
@(private)
verb_codes: []Verb_Code

@(init, private)
verb_codes_init :: proc "contextless" () {
	context = runtime.default_context()
	verb_codes = make([]Verb_Code, len(registry.ALL_VERBS))
	for verb, i in registry.ALL_VERBS {
		verb_codes[i] = code_for_name(verb.name)
	}
}

code_for_name :: proc "contextless" (name: string) -> Verb_Code {
	for n, code in VERB_CODE_NAMES {
		if code != .None && n == name {
			return code
		}
	}
	return .None
}

// The code of a verb the checker found, which is always one of `registry.ALL_VERBS`.
verb_code :: proc "contextless" (verb: ^registry.Verb) -> Verb_Code {
	if verb == nil || len(registry.ALL_VERBS) == 0 {
		return .None
	}
	at := (uintptr(verb) - uintptr(&registry.ALL_VERBS[0])) / size_of(registry.Verb)
	if uintptr(verb) < uintptr(&registry.ALL_VERBS[0]) || at >= uintptr(len(verb_codes)) {
		return .None
	}
	return verb_codes[at]
}

// Whether the verb is one only the language has (lists, tables, messages, collision),
// as opposed to one of the Odin API.
is_language_code :: proc "contextless" (code: Verb_Code) -> bool {
	return code >= .Add
}
