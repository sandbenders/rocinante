#+build windows
// SPDX-License-Identifier: 0BSD
//
// Turns a shader written in HLSL into the code Direct3D 12 takes, while the program runs, with
// the shader compiler that is part of Windows itself (d3dcompiler_47.dll, the compiler known
// as FXC): DXBC of Shader Model 5.1, which SDL's Direct3D 12 back end takes as it takes DXIL.
// Windows draws with Direct3D 12 and nothing else, so nothing here needs a library or package
// of another graphics system, and nothing has to be installed or shipped beside the program.
//
// SDL binds a fragment shader's uniform buffers as `b0, space3`, `b1, space3`, and the
// preludes say so for rocinante's own block. A shader's own globals (`float amount;`) are
// put by the compiler in a block of their own, `$Globals`, on `b0, space0`, where SDL would
// not bind it, and the compiler cannot be told to put it elsewhere. So a shader with globals
// is compiled twice: the first time to learn from the compiled code which globals it has,
// the second with those declarations taken out of the text (blanked, so its lines keep their
// numbers) and declared again in a block on `b1, space3`.
//
// Like the other half, this is only ever called from the program's one thread, the first
// time a shader is used and each time its file changes.
package gfx

import "core:fmt"
import "core:strings"

import sdl "vendor:sdl3"
import d3dc "vendor:directx/d3d_compiler"
import d3d12 "vendor:directx/d3d12"

// The block a shader's own globals are moved into, named so no shader can mean it.
@(private)
OWN_BLOCK :: "rocinante_values_"

// The DXBC of a sketch's fragment shader (`ps_main`), with the layout of its own values.
translate_fragment :: proc(source: string, params: ^Shader_Params, file := "shader") -> (code: []u8, message: string, ok: bool) {
	if !strings.contains(source, "ps_main") {
		return nil, strings.clone("there is no function called ps_main in the shader"), false
	}
	first, first_message, first_ok := fxc_compile(source, "ps_main", "ps_5_1", file)
	if !first_ok {
		return nil, first_message, false
	}
	globals, globals_size, declarable, why := reflect_block(first, "$Globals")
	defer reflected_destroy(&globals)
	if globals_size == 0 {
		return first, "", true
	}
	delete(first)
	if !declarable {
		return nil, why, false
	}
	moved, missing := move_globals(source, globals[:])
	defer delete(moved)
	if missing != "" {
		return nil, fmt.aprintf("the value `%s` of the shader could not be found where it is written; write it on a line of its own at the top, such as `float %s;`", missing, missing), false
	}
	second, second_message, second_ok := fxc_compile(moved, "ps_main", "ps_5_1", file)
	if !second_ok {
		return nil, second_message, false
	}
	own, own_size, _, _ := reflect_block(second, OWN_BLOCK)
	defer reflected_destroy(&own)
	if params != nil {
		params.size = own_size
		for v in own {
			if v.floats > 0 {
				append(&params.list, Shader_Param{name = strings.clone(v.name), offset = v.offset, floats = v.floats})
			}
		}
	}
	return second, "", true
}

// Whether this renderer can run a sketch's shaders at all.
@(private)
can_run_effects :: proc(r: ^Renderer) -> bool {
	return .DXBC in sdl.GetGPUShaderFormats(r.device)
}

// The vertex and fragment code of a pipeline for a sketch's shader: DXBC for Direct3D 12, the
// vertex shader compiled the first time and kept. On failure the reason is said once through
// `effect_say`.
@(private)
user_shader_code :: proc(r: ^Renderer, data: ^Shader_Data, vertex_source: string, vertex: ^Vertex_Code, textures: bool) -> (out: User_Shader_Code, ok: bool) {
	if !can_run_effects(r) {
		effect_say(r, "this computer's graphics system does not take the shaders a sketch writes yet")
		return {}, false
	}
	if vertex.code == nil {
		code, message, compiled := fxc_compile(vertex_source, "vs_main", "vs_5_1", "shader")
		if !compiled {
			effect_say(r, message)
			delete(message)
			return {}, false
		}
		vertex.code = code
	}
	return {vertex.code, data.code, "vs_main", "ps_main", {.DXBC}}, true
}

// Compiles `source`'s `entry` for `target` (`ps_5_1`, `vs_5_1`). On a mistake there is no
// code and `message` has what the compiler said, in the same form the other half gives.
@(private)
fxc_compile :: proc(source, entry, target, file: string) -> (code: []u8, message: string, ok: bool) {
	blob, errors: ^d3dc.ID3DBlob
	flags := transmute(u32)d3dc.D3DCOMPILE_OPTIMIZATION_LEVEL3
	result := d3dc.Compile(raw_data(source), len(source), strings.clone_to_cstring(file, context.temp_allocator), nil, nil, strings.clone_to_cstring(entry, context.temp_allocator), strings.clone_to_cstring(target, context.temp_allocator), flags, 0, &blob, &errors)
	defer if errors != nil {errors->Release()}
	if result < 0 || blob == nil {
		said := ""
		if errors != nil {
			// the buffer ends with the text's closing zero byte
			said = strings.trim_right_null(string(([^]u8)(errors->GetBufferPointer())[:errors->GetBufferSize()]))
		}
		if blob != nil {
			blob->Release()
		}
		message = compiler_message(said)
		if message == "" {
			delete(message)
			message = strings.clone("the shader compiler refused the shader")
		}
		return nil, message, false
	}
	defer blob->Release()
	bytes := ([^]u8)(blob->GetBufferPointer())[:blob->GetBufferSize()]
	code = make([]u8, len(bytes))
	copy(code, bytes)
	return code, "", true
}

// The compiler's lines (`broken.hlsl(1,12-15): error X3004: undeclared identifier 'oops'`) as
// the other half writes them (`broken.hlsl:1: error: undeclared identifier 'oops'`), so a
// message reads the same everywhere. The closing line saying no code was made is left out.
@(private)
compiler_message :: proc(said: string, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	rest := said
	for line in strings.split_lines_iterator(&rest) {
		text := strings.trim_space(line)
		if text == "" || strings.has_prefix(text, "compilation failed") || strings.has_prefix(text, "compilation object save succeeded") {
			continue
		}
		// every line ends with a line break, the last too, as shaderc's do
		strings.write_string(&b, plain_compiler_line(text))
		strings.write_byte(&b, '\n')
	}
	return strings.to_string(b)
}

@(private)
plain_compiler_line :: proc(text: string) -> string {
	// name(line,column...): kind Xnnnn: words
	close := strings.index(text, "): ")
	if close < 0 {
		return text
	}
	open := strings.last_index_byte(text[:close], '(')
	if open < 0 {
		return text
	}
	// The compiler writes a file's name as a full path from the folder the program runs in;
	// the name the sketch gave is the last part.
	name := text[:open]
	if slash := strings.last_index_any(name, "\\/"); slash >= 0 {
		name = name[slash + 1:]
	}
	place := text[open + 1:close]
	line := place
	if comma := strings.index_byte(place, ','); comma >= 0 {
		line = place[:comma]
	}
	after := text[close + 3:]
	kind := "error"
	if strings.has_prefix(after, "warning") {
		kind = "warning"
	}
	words := after
	if colon := strings.index(after, ": "); colon >= 0 {
		words = after[colon + 2:]
	}
	return fmt.tprintf("%s:%s: %s: %s", name, line, kind, words)
}

// A global as the compiled code describes it.
@(private)
Reflected :: struct {
	name:        string,
	declaration: string, // the type, written as HLSL (`float2`, `float4x4`, `int[3]`)
	offset:      int,    // bytes into its block
	floats:      int,    // 1 to 4 when it is a value a sketch can give (a float or a vector of them), else 0
}

@(private)
reflected_destroy :: proc(list: ^[dynamic]Reflected) {
	for v in list {
		delete(v.name)
		delete(v.declaration)
	}
	delete(list^)
}

// The variables of the constant block `name` of compiled code and the block's size (0 when it
// has no such block). `declarable` is false, with `why`, when one of them is of a kind that
// cannot be declared again by its type's name (a structure).
@(private)
reflect_block :: proc(code: []u8, name: cstring) -> (vars: [dynamic]Reflected, size: int, declarable: bool, why: string) {
	declarable = true
	reflector: ^d3d12.IShaderReflection
	if d3dc.Reflect(raw_data(code), len(code), d3d12.IShaderReflection_UUID, (^rawptr)(&reflector)) < 0 || reflector == nil {
		return
	}
	defer reflector->Release()
	block := reflector->GetConstantBufferByName(name)
	desc: d3d12.SHADER_BUFFER_DESC
	// An unknown name gives an object whose GetDesc fails, not nil.
	if block == nil || block->GetDesc(&desc) < 0 {
		return
	}
	size = int(desc.Size)
	for i in 0 ..< desc.Variables {
		variable := block->GetVariableByIndex(i)
		vdesc: d3d12.SHADER_VARIABLE_DESC
		tdesc: d3d12.SHADER_TYPE_DESC
		if variable == nil || variable->GetDesc(&vdesc) < 0 {
			continue
		}
		type := variable->GetType()
		if type == nil || type->GetDesc(&tdesc) < 0 {
			continue
		}
		v := Reflected{name = strings.clone(string(vdesc.Name)), offset = int(vdesc.StartOffset)}
		#partial switch tdesc.Class {
		case .SCALAR, .VECTOR, .MATRIX_ROWS, .MATRIX_COLUMNS:
			if tdesc.Elements > 0 {
				v.declaration = fmt.aprintf("%s[%d]", tdesc.Name, tdesc.Elements)
			} else {
				v.declaration = strings.clone(string(tdesc.Name))
			}
			if tdesc.Type == .FLOAT && tdesc.Elements == 0 && (tdesc.Class == .SCALAR || tdesc.Class == .VECTOR) && tdesc.Columns >= 1 && tdesc.Columns <= 4 {
				v.floats = int(tdesc.Columns)
			}
		case:
			if declarable {
				why = fmt.aprintf("the value `%s` of the shader is a structure; a value of the shader is a number or a vector of numbers, such as `float %s;`", v.name, v.name)
			}
			declarable = false
		}
		append(&vars, v)
	}
	return
}

// `source` with the declarations of `globals` blanked out (each character but a line break made
// a space, so every line keeps its number) and declared again, first, in the block the effect
// pass binds on `b1, space3`. `missing` names a global whose declaration was not found.
@(private)
move_globals :: proc(source: string, globals: []Reflected) -> (moved: string, missing: string) {
	clean := code_only(source)
	defer delete(clean)
	out := transmute([]u8)strings.clone(source)
	defer delete(out)
	found := make([]bool, len(globals), context.temp_allocator)

	depth := 0
	start := -1
	block := false  // the statement holds a body (a function, a structure, a block)
	equals := false // an `=` at the top of the statement: a brace after it is a value
	for i := 0; i < len(clean); i += 1 {
		c := clean[i]
		if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
			continue
		}
		if depth == 0 && start < 0 {
			start, block, equals = i, false, false
		}
		switch c {
		case '=':
			if depth == 0 {
				equals = true
			}
		case '{':
			if depth == 0 && !equals {
				block = true
			}
			depth += 1
		case '(', '[':
			depth += 1
		case ')', ']':
			depth = max(depth - 1, 0)
		case '}':
			depth = max(depth - 1, 0)
			if depth == 0 && block {
				start = -1
			}
		case ';':
			if depth == 0 {
				if !block && declares_globals(string(clean[start:i]), globals, found) {
					for j in start ..= i {
						if out[j] != '\n' && out[j] != '\r' {
							out[j] = ' '
						}
					}
				}
				start = -1
			}
		}
	}
	for f, i in found {
		if !f {
			return "", globals[i].name
		}
	}
	b := strings.builder_make()
	fmt.sbprintf(&b, "cbuffer %s : register(b1, space3)\n", OWN_BLOCK)
	strings.write_string(&b, "{\n")
	for g in globals {
		// `float4x4 m` takes its brackets after the name: `float m[3]`.
		bracket := strings.index_byte(g.declaration, '[')
		if bracket >= 0 {
			fmt.sbprintf(&b, "    %s %s%s;\n", g.declaration[:bracket], g.name, g.declaration[bracket:])
		} else {
			fmt.sbprintf(&b, "    %s %s;\n", g.declaration, g.name)
		}
	}
	strings.write_string(&b, "};\n")
	strings.write_string(&b, string(out))
	return strings.to_string(b), ""
}

// Whether a statement of the top of a shader (without its `;`) declares globals of the list:
// each of its declarators (split at the commas between them) is cut at its `=`, `:` or `[`,
// and the last word before the cut is the name. A statement with a `(` before a cut is a
// function's declaration. When it declares one of them, every name it declares is marked found.
@(private)
declares_globals :: proc(statement: string, globals: []Reflected, found: []bool) -> bool {
	parts := make([dynamic]string, context.temp_allocator)
	depth, from := 0, 0
	for i in 0 ..< len(statement) {
		switch statement[i] {
		case '(', '[', '{':
			depth += 1
		case ')', ']', '}':
			depth = max(depth - 1, 0)
		case ',':
			if depth == 0 {
				append(&parts, statement[from:i])
				from = i + 1
			}
		}
	}
	append(&parts, statement[from:])
	names := make([dynamic]int, context.temp_allocator)
	for part in parts {
		cut := len(part)
		for j in 0 ..< len(part) {
			c := part[j]
			if c == '(' {
				return false
			}
			if c == '=' || c == ':' || c == '[' {
				cut = j
				break
			}
		}
		name := last_word(part[:cut])
		for g, k in globals {
			if g.name == name {
				append(&names, k)
			}
		}
	}
	for k in names {
		found[k] = true
	}
	return len(names) > 0
}

@(private)
last_word :: proc(text: string) -> string {
	end := len(text)
	for end > 0 && !is_word_byte(text[end - 1]) {
		end -= 1
	}
	begin := end
	for begin > 0 && is_word_byte(text[begin - 1]) {
		begin -= 1
	}
	return text[begin:end]
}

@(private)
is_word_byte :: proc(c: u8) -> bool {
	return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c >= 0x80
}

// `source` with its comments, strings and preprocessor lines made spaces (line breaks kept), so
// what is left is code, at the same places.
@(private)
code_only :: proc(source: string) -> []u8 {
	out := transmute([]u8)strings.clone(source)
	blank :: proc(out: []u8, from, to: int) {
		for j in from ..< to {
			if out[j] != '\n' {
				out[j] = ' '
			}
		}
	}
	line_start := true
	i := 0
	for i < len(out) {
		c := out[i]
		switch {
		case c == '/' && i + 1 < len(out) && out[i + 1] == '/':
			end := i
			for end < len(out) && out[end] != '\n' {
				end += 1
			}
			blank(out, i, end)
			i = end
			continue
		case c == '/' && i + 1 < len(out) && out[i + 1] == '*':
			end := i + 2
			for end + 1 < len(out) && !(out[end] == '*' && out[end + 1] == '/') {
				end += 1
			}
			end = min(end + 2, len(out))
			blank(out, i, end)
			i = end
			continue
		case c == '"':
			end := i + 1
			for end < len(out) && out[end] != '"' && out[end] != '\n' {
				if out[end] == '\\' {
					end += 1
				}
				end += 1
			}
			end = min(end + 1, len(out))
			blank(out, i, end)
			i = end
			continue
		case c == '#' && line_start:
			end := i
			for end < len(out) && out[end] != '\n' {
				if out[end] == '\\' && end + 1 < len(out) && out[end + 1] == '\n' {
					end += 1
				}
				end += 1
			}
			blank(out, i, end)
			i = end
			continue
		case c == '\n':
			line_start = true
		case c != ' ' && c != '\t' && c != '\r':
			line_start = false
		}
		i += 1
	}
	return out
}
