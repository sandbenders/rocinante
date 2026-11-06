// SPDX-License-Identifier: 0BSD
//
// Writes vendor/imgui/imgui.odin from the JSON that dear_bindings makes (the files
// `spikes/ui/setup.sh` and `odin run build -- ui-libs` leave in .cache/ui/generated).
// Only the procedures named in WANTED are bound, with every struct and enum of the
// headers, so the layouts are exact; a type it cannot translate stops the run
// instead of being guessed.
//
//     odin run tools/imgui -- [generated folder] [output file]
package imgui_bindings

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"

// The procedures rocinante uses, by their names in the C API.
WANTED := [?]string {
	// context, frame, io, style
	"ImGui_CreateContext", "ImGui_DestroyContext", "ImGui_GetIO", "ImGui_GetStyle",
	"ImGui_StyleColorsDark", "ImGui_StyleColorsLight", "ImGui_NewFrame", "ImGui_EndFrame",
	"ImGui_Render", "ImGui_GetDrawData",
	// windows and layout
	"ImGui_Begin", "ImGui_End", "ImGui_BeginChild", "ImGui_EndChild", "ImGui_SetNextWindowPos",
	"ImGui_SetNextWindowSize", "ImGui_SetNextWindowCollapsed", "ImGui_SameLine", "ImGui_Separator",
	"ImGui_Spacing", "ImGui_NewLine", "ImGui_SetNextItemWidth", "ImGui_PushItemWidth", "ImGui_PopItemWidth",
	"ImGui_PushID", "ImGui_PushIDInt", "ImGui_PopID", "ImGui_GetID",
	"ImGui_GetCursorScreenPos", "ImGui_SetCursorScreenPos", "ImGui_GetContentRegionAvail",
	"ImGui_BeginGroup", "ImGui_EndGroup", "ImGui_GetWindowDrawList", "ImGui_Dummy",
	// widgets
	"ImGui_TextUnformatted", "ImGui_Text", "ImGui_TextWrapped", "ImGui_Button", "ImGui_SmallButton",
	"ImGui_InvisibleButton", "ImGui_Checkbox", "ImGui_RadioButton",
	"ImGui_SliderFloat", "ImGui_SliderFloatEx", "ImGui_SliderInt", "ImGui_SliderIntEx",
	"ImGui_DragFloat", "ImGui_DragFloat2", "ImGui_DragFloatRange2Ex",
	"ImGui_InputFloat", "ImGui_InputInt", "ImGui_InputDouble", "ImGui_InputDoubleEx", "ImGui_InputTextMultilineEx",
	"ImGui_GetPlatformIO", "ImGui_TextDisabled", "ImGui_CollapsingHeader", "ImGui_Indent", "ImGui_Unindent", "ImGui_IsKeyPressed", "ImGui_ImageButton",
	"ImGui_InputText", "ImGui_InputTextWithHint", "ImGui_InputTextMultiline",
	"ImGui_ColorEdit4", "ImGui_ColorPicker4", "ImGui_ProgressBar",
	"ImGui_BeginCombo", "ImGui_EndCombo", "ImGui_Selectable", "ImGui_SelectableBoolPtr",
	"ImGui_BeginListBox", "ImGui_EndListBox",
	"ImGui_BeginTabBar", "ImGui_EndTabBar", "ImGui_BeginTabItem", "ImGui_EndTabItem",
	"ImGui_BeginMainMenuBar", "ImGui_EndMainMenuBar", "ImGui_BeginMenuBar", "ImGui_EndMenuBar",
	"ImGui_BeginMenu", "ImGui_EndMenu", "ImGui_MenuItem", "ImGui_MenuItemBoolPtr",
	"ImGui_SetTooltip", "ImGui_BeginTooltip", "ImGui_EndTooltip", "ImGui_SetItemTooltip",
	// items, focus, text
	"ImGui_IsItemHovered", "ImGui_IsItemFocused", "ImGui_IsItemActive", "ImGui_IsItemClicked",
	"ImGui_IsItemActivated", "ImGui_IsItemDeactivatedAfterEdit",
	"ImGui_GetItemID", "ImGui_GetItemRectMin", "ImGui_GetItemRectMax", "ImGui_GetItemRectSize",
	"ImGui_SetKeyboardFocusHere", "ImGui_SetKeyboardFocusHereEx", "ImGui_SetItemDefaultFocus",
	"ImGui_CalcTextSize", "ImGui_GetTextLineHeight", "ImGui_GetFrameHeight",
	"ImGui_IsWindowFocused", "ImGui_IsAnyItemActive", "ImGui_IsAnyItemFocused",
	"ImGui_PushStyleColor", "ImGui_PopStyleColor", "ImGui_PushStyleVar", "ImGui_PopStyleVar",
	"ImGui_PushStyleVarImVec2", "ImGui_BeginDisabled", "ImGui_EndDisabled",
	"ImGui_GetColorU32", "ImGui_GetColorU32ImU32", "ImGui_SetNextWindowBgAlpha",
	// draw lists, for the widgets Dear ImGui lacks
	"ImDrawList_AddLine", "ImDrawList_AddLineEx", "ImDrawList_AddRect", "ImDrawList_AddRectFilled",
	"ImDrawList_AddCircle", "ImDrawList_AddCircleFilled", "ImDrawList_AddCircleEx",
	"ImDrawList_AddTriangleFilled",
	"ImDrawList_AddText", "ImDrawList_PathArcTo", "ImDrawList_PathStroke", "ImDrawList_PathClear",
	// input, given as events so a window needs no backend to be driven
	"ImGui_SetCurrentContext", "ImGui_GetCurrentContext", "ImGuiIO_AddMousePosEvent",
	"ImGuiIO_AddMouseButtonEvent", "ImGuiIO_AddMouseWheelEvent", "ImGuiIO_AddKeyEvent",
	"ImGuiIO_AddInputCharactersUTF8", "ImGuiIO_AddFocusEvent", "ImGui_IsAnyItemHovered",
	"ImGuiStyle_ScaleAllSizes",
	// fonts
	"ImFontAtlas_AddFontFromMemoryTTF", "ImFontAtlas_AddFontFromFileTTF", "ImFontAtlas_AddFontDefault",
	"ImFontAtlas_Clear",
	// the SDL3 platform backend and the SDL_GPU renderer backend
	"cImGui_ImplSDL3_InitForSDLGPU", "cImGui_ImplSDL3_Shutdown", "cImGui_ImplSDL3_NewFrame",
	"cImGui_ImplSDL3_ProcessEvent",
	"cImGui_ImplSDLGPU3_Init", "cImGui_ImplSDLGPU3_Shutdown", "cImGui_ImplSDLGPU3_NewFrame",
	"cImGui_ImplSDLGPU3_PrepareDrawData", "cImGui_ImplSDLGPU3_RenderDrawData",
}

// Types written by hand: the same layout, a nicer Odin type.
OVERRIDES := [?][2]string{{"ImVec2", "[2]f32"}, {"ImVec4", "[4]f32"}}

Source :: struct {
	enums:    [dynamic]json.Object,
	typedefs: [dynamic]json.Object,
	structs:  [dynamic]json.Object,
	funcs:    [dynamic]json.Object,
	defines:  [dynamic]json.Object,
}

Generator :: struct {
	src:        Source,
	constants:  map[string]i64, // enum elements and numeric defines, for array bounds
	typedefs:   map[string]string, // typedef name -> Odin type
	structs:    map[string]bool, // struct name -> can be written
	opaque:     map[string]bool,
	out:        strings.Builder,
	problems:   [dynamic]string,
}

main :: proc() {
	dir := len(os.args) > 1 ? os.args[1] : ".cache/ui/generated"
	target := len(os.args) > 2 ? os.args[2] : "vendor/imgui/imgui.odin"
	g: Generator
	for name in ([?]string{"dcimgui.json", "backends/dcimgui_impl_sdl3.json", "backends/dcimgui_impl_sdlgpu3.json"}) {
		load(&g.src, fmt.tprintf("%s/%s", dir, name))
	}
	generate(&g)
	if len(g.problems) > 0 {
		for p in g.problems {
			fmt.eprintln("imgui bindings:", p)
		}
		os.exit(1)
	}
	if err := os.write_entire_file(target, transmute([]u8)strings.to_string(g.out)); err != nil {
		fmt.eprintln("imgui bindings: cannot write", target)
		os.exit(1)
	}
	fmt.println("wrote", target)
}

load :: proc(src: ^Source, path: string) {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		fmt.eprintln("imgui bindings: cannot read", path, "(run odin run build -- ui-libs first)")
		os.exit(1)
	}
	value, jerr := json.parse(data)
	if jerr != nil {
		fmt.eprintln("imgui bindings: cannot parse", path)
		os.exit(1)
	}
	root := value.(json.Object)
	add :: proc(into: ^[dynamic]json.Object, from: json.Value) {
		for item in from.(json.Array) {
			append(into, item.(json.Object))
		}
	}
	add(&src.enums, root["enums"])
	add(&src.typedefs, root["typedefs"])
	add(&src.structs, root["structs"])
	add(&src.funcs, root["functions"])
	add(&src.defines, root["defines"])
}

str :: proc(o: json.Object, key: string) -> string {
	if v, ok := o[key]; ok {
		if s, is := v.(json.String); is {
			return s
		}
	}
	return ""
}

obj :: proc(o: json.Object, key: string) -> json.Object {
	if v, ok := o[key]; ok {
		if r, is := v.(json.Object); is {
			return r
		}
	}
	return nil
}

list :: proc(o: json.Object, key: string) -> json.Array {
	if v, ok := o[key]; ok {
		if r, is := v.(json.Array); is {
			return r
		}
	}
	return nil
}

// A whole number in the JSON (this parser reads numbers as floats unless told otherwise).
number :: proc(o: json.Object, key: string) -> (i64, bool) {
	if v, ok := o[key]; ok {
		#partial switch n in v {
		case json.Integer:
			return n, true
		case json.Float:
			return i64(n), true
		}
	}
	return 0, false
}

flag :: proc(o: json.Object, key: string) -> bool {
	if v, ok := o[key]; ok {
		if b, is := v.(json.Boolean); is {
			return b
		}
	}
	return false
}

problem :: proc(g: ^Generator, format: string, args: ..any) {
	append(&g.problems, fmt.aprintf(format, ..args))
}

// ---- names ----

// ImGuiCol_Text -> Col_Text, ImDrawFlags_Closed -> DrawFlags_Closed
strip_prefix :: proc(name: string) -> string {
	for prefix in ([?]string{"ImGui", "Im"}) {
		if strings.has_prefix(name, prefix) && len(name) > len(prefix) {
			rest := name[len(prefix):]
			if rest[0] >= 'A' && rest[0] <= 'Z' {
				return rest
			}
			if rest[0] == '_' && len(rest) > 1 { // ImGui_ImplSDLGPU3_InitInfo
				return rest[1:]
			}
		}
	}
	return name
}

// ImGuiCol_ (the enum) is not a name we use; its elements are.
type_name :: proc(name: string) -> string {
	n := strip_prefix(name)
	return strings.trim_right(n, "_")
}

snake :: proc(name: string) -> string {
	b: strings.Builder
	for i in 0 ..< len(name) {
		c := name[i]
		upper := c >= 'A' && c <= 'Z'
		if upper && i > 0 {
			prev := name[i - 1]
			prev_lower := (prev >= 'a' && prev <= 'z') || (prev >= '0' && prev <= '9')
			prev_upper := prev >= 'A' && prev <= 'Z'
			next_lower := i + 1 < len(name) && name[i + 1] >= 'a' && name[i + 1] <= 'z'
			if prev_lower || (prev_upper && next_lower) {
				strings.write_byte(&b, '_')
			}
		}
		strings.write_byte(&b, upper ? c + 32 : c)
	}
	return strings.to_string(b)
}

procedure_name :: proc(c_name: string) -> string {
	n := c_name
	for pair in ([?][2]string {
			{"cImGui_ImplSDLGPU3_", "gpu3_"},
			{"cImGui_ImplSDL3_", "sdl3_"},
			{"ImGuiIO_", "io_"},
			{"ImGuiStyle_", "style_"},
			{"ImDrawList_", "draw_list_"},
			{"ImFontAtlas_", "font_atlas_"},
			{"ImGui_", ""},
		}) {
		if strings.has_prefix(n, pair[0]) {
			return strings.concatenate({pair[1], snake(n[len(pair[0]):])})
		}
	}
	return snake(n)
}

// ---- numbers: array bounds like "32+1" or "ImGuiCol_COUNT" ----

Eval :: struct {
	text: string,
	at:   int,
	g:    ^Generator,
	ok:   bool,
}

eval_bound :: proc(g: ^Generator, text: string) -> (value: i64, ok: bool) {
	e := Eval{text = text, g = g, ok = true}
	value = eval_sum(&e)
	skip_space(&e)
	return value, e.ok && e.at == len(e.text)
}

skip_space :: proc(e: ^Eval) {
	for e.at < len(e.text) && e.text[e.at] == ' ' {
		e.at += 1
	}
}

eval_sum :: proc(e: ^Eval) -> i64 {
	v := eval_product(e)
	for {
		skip_space(e)
		if e.at >= len(e.text) {
			return v
		}
		switch e.text[e.at] {
		case '+':
			e.at += 1
			v += eval_product(e)
		case '-':
			e.at += 1
			v -= eval_product(e)
		case:
			return v
		}
	}
}

eval_product :: proc(e: ^Eval) -> i64 {
	v := eval_atom(e)
	for {
		skip_space(e)
		if e.at >= len(e.text) {
			return v
		}
		switch e.text[e.at] {
		case '*':
			e.at += 1
			v *= eval_atom(e)
		case '/':
			e.at += 1
			d := eval_atom(e)
			if d == 0 {
				e.ok = false
				return 0
			}
			v /= d
		case:
			return v
		}
	}
}

eval_atom :: proc(e: ^Eval) -> i64 {
	skip_space(e)
	if e.at >= len(e.text) {
		e.ok = false
		return 0
	}
	if e.text[e.at] == '(' {
		e.at += 1
		v := eval_sum(e)
		skip_space(e)
		if e.at < len(e.text) && e.text[e.at] == ')' {
			e.at += 1
		} else {
			e.ok = false
		}
		return v
	}
	start := e.at
	for e.at < len(e.text) {
		c := e.text[e.at]
		if (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' {
			e.at += 1
		} else {
			break
		}
	}
	word := e.text[start:e.at]
	if n, ok := strconv.parse_i64(word); ok {
		return n
	}
	if v, ok := e.g.constants[word]; ok {
		return v
	}
	e.ok = false
	return 0
}

// ---- types ----

builtin :: proc(name: string) -> (string, bool) {
	switch name {
	case "bool": return "bool", true
	case "char": return "u8", true
	case "unsigned_char": return "u8", true
	case "short": return "i16", true
	case "unsigned_short": return "u16", true
	case "int": return "i32", true
	case "unsigned_int": return "u32", true
	case "long_long": return "i64", true
	case "unsigned_long_long": return "u64", true
	case "float": return "f32", true
	case "double": return "f64", true
	}
	return "", false
}

// The Odin spelling of a type description from the JSON.
odin_type :: proc(g: ^Generator, desc: json.Object, what: string) -> (string, bool) {
	switch str(desc, "kind") {
	case "Builtin":
		name := str(desc, "builtin_type")
		if name == "void" {
			return "", true
		}
		t, ok := builtin(name)
		if !ok {
			problem(g, "%s: unknown builtin %s", what, name)
		}
		return t, ok
	case "Pointer":
		inner := obj(desc, "inner_type")
		if str(inner, "kind") == "Builtin" {
			name := str(inner, "builtin_type")
			if name == "void" {
				return "rawptr", true
			}
			if name == "char" {
				return "cstring", true
			}
		}
		t, ok := odin_type(g, inner, what)
		if !ok {
			return "", false
		}
		if t == "" {
			return "rawptr", true
		}
		return strings.concatenate({"^", t}), true
	case "User":
		return user_type(g, str(desc, "name"), what)
	case "Array":
		t, ok := odin_type(g, obj(desc, "inner_type"), what)
		if !ok {
			return "", false
		}
		bound, bok := eval_bound(g, str(desc, "bounds"))
		if !bok {
			problem(g, "%s: cannot work out the array size %q", what, str(desc, "bounds"))
			return "", false
		}
		return fmt.aprintf("[%d]%s", bound, t), true
	}
	problem(g, "%s: unknown kind of type %q", what, str(desc, "kind"))
	return "", false
}

user_type :: proc(g: ^Generator, name, what: string) -> (string, bool) {
	for o in OVERRIDES {
		if o[0] == name {
			return o[1], true
		}
	}
	if strings.has_prefix(name, "SDL_") {
		return strings.concatenate({"sdl.", name[4:]}), true
	}
	switch name {
	case "size_t": return "uint", true
	case "va_list": return "rawptr", true
	}
	if name in g.typedefs {
		return type_name(name), true
	}
	if name in g.structs {
		return type_name(name), true
	}
	if name in g.opaque {
		return type_name(name), true
	}
	problem(g, "%s: unknown type %s", what, name)
	return "", false
}

proc_type :: proc(g: ^Generator, details: json.Object, what: string) -> (string, bool) {
	b: strings.Builder
	strings.write_string(&b, `proc "c" (`)
	first := true
	for a in list(details, "arguments") {
		arg := a.(json.Object)
		t, ok := odin_type(g, obj(obj(arg, "type"), "description"), what)
		if !ok {
			return "", false
		}
		if !first {
			strings.write_string(&b, ", ")
		}
		first = false
		fmt.sbprintf(&b, "%s: %s", odin_ident(str(arg, "name")), t)
	}
	strings.write_string(&b, ")")
	ret, ok := odin_type(g, obj(obj(details, "return_type"), "description"), what)
	if !ok {
		return "", false
	}
	if ret != "" {
		fmt.sbprintf(&b, " -> %s", ret)
	}
	return strings.to_string(b), true
}

KEYWORDS := [?]string{"context", "in", "map", "proc", "type", "matrix", "bit_set", "enum", "union", "struct", "using", "defer", "do", "if", "for", "else", "switch", "case", "return", "import", "package", "when", "transmute", "cast", "auto_cast", "distinct", "dynamic", "foreign", "typeid", "or_else", "or_return", "not_in", "where", "fallthrough", "break", "continue", "nil"}

odin_ident :: proc(name: string) -> string {
	n := snake(name)
	if n == "" {
		return "_"
	}
	if slice.contains(KEYWORDS[:], n) {
		return strings.concatenate({n, "_"})
	}
	return n
}

// The C++ default of an argument as Odin writes it, when it is one of the plain kinds:
// null, true and false, a number, a constant of an enum, or an ImVec2 or ImVec4 of numbers.
default_value :: proc(g: ^Generator, raw, odin: string) -> (string, bool) {
	text := strings.trim_space(raw)
	if text == "" {
		return "", false
	}
	pointer := odin == "cstring" || odin == "rawptr" || strings.has_prefix(odin, "^") || strings.has_prefix(odin, "[^]")
	if text == "NULL" || text == "nullptr" || (text == "0" && pointer) {
		return "nil", pointer
	}
	if pointer {
		return "", false
	}
	if text == "true" || text == "false" {
		return text, odin == "bool"
	}
	if number_text(text) {
		return strings.trim_right(text, "f"), true
	}
	if text in g.constants {
		return strip_prefix(text), true
	}
	for prefix in ([?]string{"ImVec2(", "ImVec4("}) {
		if strings.has_prefix(text, prefix) && strings.has_suffix(text, ")") {
			inner := text[len(prefix):len(text) - 1]
			parts, _ := strings.split(inner, ",", context.temp_allocator)
			out := strings.builder_make(context.temp_allocator)
			strings.write_string(&out, "{")
			for part, i in parts {
				p := strings.trim_space(part)
				if !number_text(p) {
					return "", false
				}
				if i > 0 {
					strings.write_string(&out, ", ")
				}
				strings.write_string(&out, strings.trim_right(p, "f"))
			}
			strings.write_string(&out, "}")
			return strings.to_string(out), true
		}
	}
	return "", false
}

number_text :: proc(text: string) -> bool {
	t := strings.trim_right(text, "f")
	if t == "" {
		return false
	}
	_, ok := strconv.parse_f64(t)
	return ok
}

// ---- the file ----

generate :: proc(g: ^Generator) {
	// every enum element and number is a constant first, because array sizes use them
	for e in g.src.enums {
		for el in list(e, "elements") {
			el_o := el.(json.Object)
			if n, ok := number(el_o, "value"); ok {
				g.constants[str(el_o, "name")] = n
			}
		}
	}
	for d in g.src.defines {
		if n, ok := strconv.parse_i64(str(d, "content")); ok {
			g.constants[str(d, "name")] = n
		}
	}
	// the one definition that depends on a compile setting: 16-bit characters (Dear ImGui's default)
	g.constants["IM_UNICODE_CODEPOINT_MAX"] = 0xFFFF

	w := &g.out
	strings.write_string(w, "// SPDX-License-Identifier: 0BSD\n//\n")
	strings.write_string(w, "// Dear ImGui v1.93.0 (MIT) and its SDL3 and SDL_GPU backends, as Odin. Made by tools/imgui from the\n")
	strings.write_string(w, "// JSON that dear_bindings v0.26 writes; do not edit it by hand.\n")
	strings.write_string(w, "package imgui\n\nimport sdl \"vendor:sdl3\"\n\n")
	strings.write_string(w, "when ODIN_OS == .Darwin || ODIN_OS == .FreeBSD {\n")
	strings.write_string(w, "\tforeign import lib {\"../../.cache/ui/libroci_ui.a\", \"system:c++\", \"system:SDL3\"}\n")
	strings.write_string(w, "} else when ODIN_OS == .Linux || ODIN_OS == .OpenBSD {\n")
	strings.write_string(w, "\tforeign import lib {\"../../.cache/ui/libroci_ui.a\", \"system:stdc++\", \"system:SDL3\"}\n")
	strings.write_string(w, "} else {\n\tforeign import lib \"../../.cache/ui/roci_ui.lib\"\n}\n\n")

	emit_typedefs(g)
	emit_enums(g)
	emit_structs(g)
	emit_procedures(g)
}

emit_typedefs :: proc(g: ^Generator) {
	seen: map[string]bool
	for t in g.src.typedefs {
		name := str(t, "name")
		if name in seen {
			continue
		}
		seen[name] = true
		type_o := obj(t, "type")
		desc := obj(type_o, "description")
		// ImWchar is 16 bits unless IMGUI_USE_WCHAR32 is set
		if name == "ImWchar" {
			g.typedefs[name] = "u16"
			fmt.sbprintf(&g.out, "%s :: u16\n", type_name(name))
			continue
		}
		if name == "ImDrawIdx" {
			g.typedefs[name] = "u16"
			fmt.sbprintf(&g.out, "%s :: u16\n", type_name(name))
			continue
		}
		if details := obj(type_o, "type_details"); details != nil && str(details, "flavour") == "function_pointer" {
			// written after the structs it names are known (see below)
			continue
		}
		t_str, ok := "", false
		switch str(desc, "kind") {
		case "Builtin":
			t_str, ok = builtin(str(desc, "builtin_type"))
		case "User":
			// an alias of another typedef; fine if that one is already written, else retried
			t_str, ok = user_type(g, str(desc, "name"), name)
			if !ok && len(g.problems) > 0 {
				pop(&g.problems)
			}
		}
		if !ok {
			// retried after the scalars
			continue
		}
		g.typedefs[name] = t_str
		fmt.sbprintf(&g.out, "%s :: %s\n", type_name(name), t_str)
	}
	// aliases that named a typedef written later
	for t in g.src.typedefs {
		name := str(t, "name")
		if name in g.typedefs {
			continue
		}
		type_o := obj(t, "type")
		if str(obj(type_o, "description"), "kind") == "User" {
			if s, ok := user_type(g, str(obj(type_o, "description"), "name"), name); ok {
				g.typedefs[name] = s
				fmt.sbprintf(&g.out, "%s :: %s\n", type_name(name), s)
			} else if len(g.problems) > 0 {
				pop(&g.problems)
			}
		}
	}
	strings.write_string(&g.out, "\n")
}

emit_enums :: proc(g: ^Generator) {
	seen: map[string]bool
	for e in g.src.enums {
		for el in list(e, "elements") {
			el_o := el.(json.Object)
			name := str(el_o, "name")
			if name in seen {
				continue
			}
			seen[name] = true
			n, ok := number(el_o, "value")
			if !ok {
				continue
			}
			fmt.sbprintf(&g.out, "%s :: %d\n", strip_prefix(name), n)
		}
		// the enum's own name is a plain int in the C API (a typedef), so nothing more
	}
	strings.write_string(&g.out, "\n")
}

emit_structs :: proc(g: ^Generator) {
	for e in g.src.enums {
		name := strings.trim_right(str(e, "name"), "_")
		if name not_in g.typedefs {
			g.typedefs[name] = "i32"
			fmt.sbprintf(&g.out, "%s :: i32\n", type_name(name))
		}
	}
	// pass 1: every struct name exists; function pointer typedefs are written once the names are known
	seen: map[string]bool
	all: [dynamic]json.Object
	for s in g.src.structs {
		name := str(s, "name")
		if name in seen || flag(s, "forward_declaration") && false {
			continue
		}
		seen[name] = true
		append(&all, s)
		g.structs[name] = true
	}
	for t in g.src.typedefs {
		type_o := obj(t, "type")
		details := obj(type_o, "type_details")
		if details != nil && str(details, "flavour") == "function_pointer" {
			name := str(t, "name")
			s, ok := proc_type(g, details, name)
			if !ok {
				s = "rawptr"
				if len(g.problems) > 0 {
					pop(&g.problems)
				}
			}
			g.typedefs[name] = s
			fmt.sbprintf(&g.out, "%s :: %s\n", type_name(name), s)
		}
	}
	strings.write_string(&g.out, "\n")

	for s in all {
		name := str(s, "name")
		for o in OVERRIDES {
			if o[0] == name {
				fmt.sbprintf(&g.out, "%s :: %s\n\n", type_name(name), o[1])
			}
		}
		is_override := false
		for o in OVERRIDES {
			is_override ||= o[0] == name
		}
		if is_override {
			continue
		}
		fields := list(s, "fields")
		if len(fields) == 0 {
			fmt.sbprintf(&g.out, "%s :: struct {{}}\n\n", type_name(name))
			continue
		}
		b: strings.Builder
		union_ := str(s, "kind") == "union"
		fmt.sbprintf(&b, "%s :: struct%s {{\n", type_name(name), union_ ? " #raw_union" : "")
		ok := true
		for f in fields {
			fo := f.(json.Object)
			type_o := obj(fo, "type")
			ft := ""
			if details := obj(type_o, "type_details"); details != nil && str(details, "flavour") == "function_pointer" {
				ft, ok = proc_type(g, details, name)
			} else {
				ft, ok = odin_type(g, obj(type_o, "description"), fmt.tprintf("%s.%s", name, str(fo, "name")))
			}
			if !ok {
				break
			}
			if ft == "" {
				ft = "rawptr"
			}
			fmt.sbprintf(&b, "\t%s: %s,\n", odin_ident(str(fo, "name")), ft)
		}
		if !ok {
			continue
		}
		strings.write_string(&b, "}\n\n")
		strings.write_string(&g.out, strings.to_string(b))
	}
}

emit_procedures :: proc(g: ^Generator) {
	strings.write_string(&g.out, "@(default_calling_convention = \"c\")\nforeign lib {\n")
	found: map[string]bool
	names: map[string]string // Odin name -> C name, to catch two procedures with one name
	for f in g.src.funcs {
		c_name := str(f, "name")
		if !slice.contains(WANTED[:], c_name) || c_name in found {
			continue
		}
		found[c_name] = true
		odin_name := procedure_name(c_name)
		if other, dup := names[odin_name]; dup {
			problem(g, "%s and %s are both %s", c_name, other, odin_name)
			continue
		}
		names[odin_name] = c_name
		b: strings.Builder
		fmt.sbprintf(&b, "\t@(link_name = %q) %s :: proc(", c_name, odin_name)
		first := true
		ok := true
		for a in list(f, "arguments") {
			arg := a.(json.Object)
			if !first {
				strings.write_string(&b, ", ")
			}
			first = false
			if flag(arg, "is_varargs") {
				strings.write_string(&b, "#c_vararg args: ..any")
				continue
			}
			desc := obj(obj(arg, "type"), "description")
			t := ""
			if flag(arg, "is_array") {
				inner, iok := odin_type(g, desc, c_name)
				if !iok {
					ok = false
					break
				}
				bounds := str(arg, "array_bounds")
				if bounds == "" {
					t = strings.concatenate({"[^]", inner})
				} else {
					n, bok := eval_bound(g, bounds)
					if !bok {
						problem(g, "%s: array size %q", c_name, bounds)
						ok = false
						break
					}
					t = fmt.aprintf("^[%d]%s", n, inner)
				}
			} else {
				tt, tok := odin_type(g, desc, c_name)
				if !tok {
					ok = false
					break
				}
				t = tt
			}
			if t == "" {
				t = "rawptr"
			}
			fmt.sbprintf(&b, "%s: %s", odin_ident(str(arg, "name")), t)
			if def, has := default_value(g, str(arg, "default_value"), t); has {
				fmt.sbprintf(&b, " = %s", def)
			}
		}
		if !ok {
			continue
		}
		strings.write_string(&b, ")")
		ret, rok := odin_type(g, obj(obj(f, "return_type"), "description"), c_name)
		if !rok {
			continue
		}
		if ret != "" {
			fmt.sbprintf(&b, " -> %s", ret)
		}
		strings.write_string(&b, " ---\n")
		strings.write_string(&g.out, strings.to_string(b))
	}
	strings.write_string(&g.out, "}\n")
	for want in WANTED {
		if want not_in found {
			problem(g, "the C API has no %s", want)
		}
	}
}
