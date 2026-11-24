// SPDX-License-Identifier: 0BSD
//
// The release back end: turns the typed IR of a sketch into Odin source that calls the same procedures of
// package roci the interpreter calls, so a compiled sketch draws what the interpreted one does. Names keep
// the sketch's own, each statement says which line of the `.roci` it came from, every name the sketch
// assigns is declared once at the top, a record shape becomes a plain struct, a number a `f64`, a vector
// an array and a list a pointer to a dynamic array (lists are shared, as in the language). Taught verbs
// become one procedure for each tuple of argument types the checker found (`IR_Instance`).
//
// This is the first slice of the compiler: it covers the numbers, vectors, colours, text, lists and
// records, the control statements, taught verbs, `draw`, `every`, `on key` and `on mouse`, the shapes and
// the style verbs, and the maths. A sketch that uses anything else is refused with every line that does,
// said in plain words, never half compiled. What it leaves alone (memory is not freed while a sketch runs,
// there is no overlay for runtime errors, and a block that runs too long is not stopped) is listed in the
// design notes.
package codegen

import "../lang"
import "core:fmt"
import "core:strings"

// A line of the sketch the compiler cannot do yet, and what it is.
Problem :: struct {
	span: lang.Span,
	what: string,
}

Options :: struct {
	sketch:   string, // the sketch's name, for the header and the log
	source:   string, // the file it was written in, for the comments that say which line
	target:   string, // "ios" or "android" for a program an app runs, "macos", "linux", "freebsd", "openbsd" or "windows" for one that is packaged as an app; empty for this computer
	app_id:   string, // with target "macos", "linux", "freebsd", "openbsd" or "windows": the app's id, which names the folder it keeps what it writes in
	app_name: string, // with target "macos", "linux", "freebsd", "openbsd" or "windows": what people call the app, which volume controls and the like show (the program's name when empty)
}

// What a sketch asks the computer's devices for, known from the sketch itself. A packaged Mac app is given the permission for the
// microphone and the camera only when the sketch uses them, because macOS asks the player before it lets an app listen or look.
Uses :: struct {
	microphone: bool, // reads `mic` (which `level`, `bands` and `record` take as a source too)
	camera:     bool, // reads `webcam`, lists the cameras or picks one
}

Result :: struct {
	source:   string, // the Odin program; empty when there are problems
	problems: []Problem,
	uses:     Uses,
}

@(private)
Handler_Kind :: enum {
	Every,
	Event,
	Scene_Event, // `on enter` and `on leave`
	Receive,     // `on w receive message`
}

@(private)
Scene_Draw :: struct {
	scene:     int,
	proc_name: string,
}

@(private)
Handler :: struct {
	kind:    Handler_Kind,
	proc_name: string,
	scene:   int, // the scene it was written in, 0 for none
	event:   string, // for an event: the name `on` uses
	arg:     string, // for an event: the Odin text of the name it waits for ("" for any)
	message_type: string, // for a receiver: the Odin type of what it takes
	window:  string, // for an event: the Odin text of the window it is for ("" for any)
	frames:  bool,   // for `every`: counted in frames
	index:   int,
}

@(private)
Gen :: struct {
	program:  ^lang.IR_Program,
	types:    ^lang.Types,
	src:      lang.Source,
	options:  Options,
	problems: [dynamic]Problem,
	uses:     Uses, // the devices the program asks for, noted as the code that asks for them is written
	body:     strings.Builder, // the procedure being written
	procs:    strings.Builder, // everything written so far at package level
	indent:   int,
	names:    map[^lang.Symbol]string,
	taken:    map[string]bool,
	records:  map[int]string, // shape root -> type name
	verb_names: map[^lang.IR_Instance]string,
	markers:  map[string]string, // an element type's Odin text -> the procedure that marks an item of it, "nil" for items that hold nothing
	defs:     strings.Builder, // the record types
	handlers: [dynamic]Handler,
	next_id:  int,
	in_verb:  ^lang.IR_Instance,
	comment_line: int,
	dynamic_depth: int, // how deep in a block that is not the top level of the sketch
	uses_fmt: bool,
	uses_math: bool,
	uses_tweens: bool, // the frame hook steps the tweens
	uses_collide: bool,
	written:  map[^lang.IR]string,
	receiver_info: [dynamic]Receiver,
	receiver_next: int, // how many receivers have been written
	copiers:  map[string]string, // an Odin type -> the procedure that makes a deep copy of a value of it
	registering: int, // the scene whose statements are being written, 0 outside every scene
	has_scenes: bool,
	scenes:   [dynamic]string, // the names of the scenes, in the order they are met (the places `rt.scene_register` gives)
	draw_registered: bool,
	ui_registered: bool,
	scene_uis: [dynamic]Scene_Draw,
	scene_draws: [dynamic]Scene_Draw,
	uses_data: bool,
	lenient:  int, // above 0 while a record type the language hands out is made: a field of a type compiled sketches cannot hold is left out
	no_hoist: int, // above 0 while writing something that is evaluated more than once or not at all (a loop's test, the right side of `and`)
	unset_known: map[[2]int]bool, // the (record shape, field place) pairs that a `{ }` inside a taught verb leaves out somewhere in the sketch, found by an earlier pass: reading one of them is checked
	unset_found: map[[2]int]bool, // the same, found by this pass
	flagged:  map[^lang.Symbol]bool, // the constants that are made by a line that runs, and not before everything else: they carry a flag saying whether they have been made
	sites:    int, // how many places that can warn were written
}

// What a compiled sketch cannot be (Odin keywords and the names the generated code uses itself).
@(private)
RESERVED := [?]string{
	"asm", "auto_cast", "bit_field", "bit_set", "break", "case", "cast", "context", "continue", "defer", "distinct",
	"do", "dynamic", "else", "enum", "fallthrough", "for", "foreign", "if", "import", "in", "map", "matrix",
	"nil", "not_in", "or_break", "or_continue", "or_else", "or_return", "package", "proc", "return", "struct",
	"switch", "transmute", "typeid", "union", "using", "when", "where", "string", "bool", "int", "f64", "f32",
	"u8", "u32", "u64", "i32", "i64", "len", "cap", "append", "make", "new", "delete", "free", "min", "max",
	"abs", "clamp", "copy", "swizzle", "real", "imag", "any", "rawptr", "true", "false", "type_of", "size_of",
	"roci", "rt", "maths", "fmt", "math", "main", "setup", "result__", "it_", "item",
	"runtime", "c", "sdl", "sketch_main", "sdl_main", "rocinante_main", "android_main",
}

// Makes the Odin source for a checked sketch, or says every place it cannot.
generate :: proc(program: ^lang.IR_Program, src: lang.Source, options: Options, allocator := context.allocator) -> Result {
	// A first pass finds the fields that a `{ }` inside a taught verb leaves out, which a read written before that `{ }` has to know about
	first, found := generate_pass(program, src, options, nil, allocator)
	if len(found) == 0 || len(first.problems) > 0 {
		return first
	}
	second, _ := generate_pass(program, src, options, found, allocator)
	return second
}

@(private)
generate_pass :: proc(program: ^lang.IR_Program, src: lang.Source, options: Options, known: map[[2]int]bool, allocator := context.allocator) -> (Result, map[[2]int]bool) {
	g := Gen{program = program, types = program.types, src = src, options = options, unset_known = known}
	g.unset_found = make(map[[2]int]bool, 4, context.temp_allocator)
	g.flagged = make(map[^lang.Symbol]bool, 4, context.temp_allocator)
	flag_constants(&g)
	g.problems = make([dynamic]Problem, allocator)
	g.names = make(map[^lang.Symbol]string, 16, context.temp_allocator)
	g.taken = make(map[string]bool, 16, context.temp_allocator)
	g.records = make(map[int]string, 4, context.temp_allocator)
	g.verb_names = make(map[^lang.IR_Instance]string, 4, context.temp_allocator)
	g.markers = make(map[string]string, 4, context.temp_allocator)
	g.written = make(map[^lang.IR]string, 64, context.temp_allocator)
	g.scenes = make([dynamic]string, context.temp_allocator)
	g.receiver_info = make([dynamic]Receiver, context.temp_allocator)
	g.copiers = make(map[string]string, 4, context.temp_allocator)
	g.scene_draws = make([dynamic]Scene_Draw, context.temp_allocator)
	g.scene_uis = make([dynamic]Scene_Draw, context.temp_allocator)
	for s in program.stmts {
		if _, is_scene := s.kind.(lang.IR_Scene); is_scene {
			g.has_scenes = true
		}
	}
	box_program(&g)
	g.handlers = make([dynamic]Handler, context.temp_allocator)
	for r in RESERVED {
		g.taken[r] = true
	}
	g.body = strings.builder_make(context.temp_allocator)
	g.procs = strings.builder_make(context.temp_allocator)
	g.defs = strings.builder_make(context.temp_allocator)

	// the sketch-wide names, each declared once with the type the checker settled on
	globals := strings.builder_make(context.temp_allocator)
	for sym in program.symbols {
		name := name_of(&g, sym)
		type, ok := odin_type(&g, sym.type, lang.Span{}, sym.name)
		if !ok {
			continue
		}
		fmt.sbprintf(&globals, "%s: %s\n", name, type)
		if sym in g.flagged {
			fmt.sbprintf(&globals, "%s_made__: bool\n", name)
		}
	}
	find_receivers(&g, program.stmts)
	// what the collector starts from: every name of the sketch that can hold a heap object
	roots := strings.builder_make(context.temp_allocator)
	for r in g.receiver_info {
		for inbox in ([]string{"now", "next"}) {
			element := r.message_type
			if statement := mark_statement_text(&g, element, "item"); statement != "" {
				fmt.sbprintf(&roots, "\tfor item in inbox_%d_%s {{ %s }}\n", r.id, inbox, statement)
			}
		}
	}
	for sym in program.symbols {
		if statement := mark_statement(&g, sym.type, name_of(&g, sym)); statement != "" {
			fmt.sbprintf(&roots, "\t%s\n", statement)
		}
	}
	// taught verbs
	for instance in program.instances {
		if !instance.unused {
			emit_instance(&g, instance)
		}
	}
	// the statements that run once, in order, and the blocks they register
	setup := strings.builder_make(context.temp_allocator)
	g.body = setup
	g.indent = 1
	if g.has_scenes {
		line(&g, "rt.scene_hooks = {{restart = scene_restart, event = scene_event, shift = scene_shift}}")
	}
	for s in program.stmts {
		emit_top_level(&g, s)
	}
	setup = g.body

	if len(g.problems) > 0 {
		return Result{problems = g.problems[:]}, g.unset_found
	}

	out := strings.builder_make(allocator)
	fmt.sbprintf(&out, "// Generated by roci from %s: the program of the sketch %s. Do not edit it by hand: the next compile makes it again.\n", options.source if options.source != "" else "the sketch", options.sketch)
	fmt.sbprintf(&out, "#+feature dynamic-literals\npackage sketch\n\nimport \"core:fmt\"\nimport \"core:math\"\nimport \"rocinante:roci\"\nimport \"rocinante:roci/collide\"\nimport \"rocinante:roci/data\"\nimport \"rocinante:roci/maths\"\nimport \"rocinante:roci/rt\"\n")
	switch options.target {
	case "":
	case "macos", "linux", "freebsd", "openbsd", "windows":
		fmt.sbprintf(&out, "import sdl \"vendor:sdl3\"\n")
	case:
		fmt.sbprintf(&out, "import \"base:runtime\"\nimport \"core:c\"\nimport sdl \"vendor:sdl3\"\n")
	}
	fmt.sbprintf(&out, "\n")
	fmt.sbprintf(&out, "// Keeps the imports used even when a sketch does not need them.\n_ :: fmt.println\n_ :: math.PI\n_ :: maths.grey\n_ :: collide.point\n_ :: data.format_of\n\n")
	strings.write_string(&out, strings.to_string(g.defs))
	fmt.sbprintf(&out, "%s\n", strings.to_string(globals))
	strings.write_string(&out, strings.to_string(g.procs))
	fmt.sbprintf(&out, "// What the names of the sketch hold, for the collector.\nroots :: proc() {{\n%s}}\n\n", strings.to_string(roots))
	fmt.sbprintf(&out, "inbox_frame := -1\n\n")
	emit_handlers(&g, &out)
	if g.has_scenes {
		emit_scene_procs(&g, &out)
	}
	source_declarations, source_call := source_lines(&g)
	fmt.sbprintf(&out, "%ssetup :: proc() {{\n%s%s%s%s}}\n\n", source_declarations, source_call, fullscreen_line(program), warm_line(program), strings.to_string(setup))
	hook := ", hook" if len(g.handlers) > 0 || g.uses_tweens else ""
	switch options.target {
	case "ios":
		// SDL starts UIKit's loop and calls `sdl_main` from it; the sketch's assets are in the app's own folder
		fmt.sbprintf(&out, "sketch_main :: proc() {{\n\trun := rt.read_run(%q, %q)\n\trt.execute(run, setup, roots%s)\n}}\n\n", options.sketch, ODIN_VERSION_PIN, hook)
		fmt.sbprintf(&out, "sdl_main :: proc \"c\" (argc: c.int, argv: [^]cstring) -> c.int {{\n\tcontext = runtime.default_context()\n\trt.use_home(string(sdl.GetBasePath()), string(cstring(sdl.GetPrefPath(\"rocinante\", %q))))\n\tsketch_main()\n\treturn 0\n}}\n\n", options.sketch)
		fmt.sbprintf(&out, "main :: proc() {{\n\tsdl.RunApp(0, nil, sdl_main, nil)\n}}\n")
	case "android":
		// SDL's Java activity finds `rocinante_main` by name in the library and calls it on its own thread; the
		// sketch's assets were put in the app's folder on the phone's storage
		fmt.sbprintf(&out, "sketch_main :: proc() {{\n\trun := rt.read_run(%q, %q)\n\trt.execute(run, setup, roots%s)\n}}\n\n", options.sketch, ODIN_VERSION_PIN, hook)
		fmt.sbprintf(&out, "@(export, link_name = \"rocinante_main\")\nrocinante_main :: proc \"c\" (argc: c.int, argv: [^]cstring) -> c.int {{\n\tcontext = runtime.default_context()\n\tfolder := string(sdl.GetAndroidInternalStoragePath())\n\trt.use_home(folder, folder)\n\tsketch_main()\n\treturn 0\n}}\n\n")
		fmt.sbprintf(&out, "// SDL's activity never goes through the NDK's native_app_glue, which wants this name defined.\n@(export, link_name = \"android_main\")\nandroid_main :: proc \"c\" (app: rawptr) {{}}\n")
	case "macos", "linux", "freebsd", "openbsd", "windows":
		// A packaged app starts with no folder of its own: the assets are beside the program (in the bundle of a Mac app), and what the sketch writes
		// goes in the app's folder (Application Support on a Mac, ~/.local/share on Linux), which is where the program works from.
		// The id and the name are given to SDL before it starts, so a Wayland or X11 desktop matches the window to the app's desktop file
		// and icon, and volume controls say the app's name (with neither, SDL uses the program's name for both)
		fmt.sbprintf(&out, "main :: proc() {{\n\t_ = sdl.SetAppMetadataProperty(sdl.PROP_APP_METADATA_IDENTIFIER_STRING, %q)\n", options.app_id)
		if options.app_name != "" {
			fmt.sbprintf(&out, "\t_ = sdl.SetAppMetadataProperty(sdl.PROP_APP_METADATA_NAME_STRING, %q)\n", options.app_name)
		}
		fmt.sbprintf(&out, "\trt.enter_app(string(sdl.GetBasePath()), string(cstring(sdl.GetPrefPath(\"\", %q))))\n\trun := rt.read_run(%q, %q)\n\trt.execute(run, setup, roots%s)\n}}\n", options.app_id, options.sketch, ODIN_VERSION_PIN, hook)
	case:
		fmt.sbprintf(&out, "main :: proc() {{\n\trun := rt.read_run(%q, %q)\n\trt.execute(run, setup, roots%s)\n}}\n", options.sketch, ODIN_VERSION_PIN, hook)
	}
	return Result{source = strings.to_string(out), problems = nil, uses = g.uses}, g.unset_found
}

// The release of Odin the sketch was generated for, said in the header of a build log.
@(private)
ODIN_VERSION_PIN :: ODIN_VERSION

// A problem to be reported: a place the compiler cannot do yet.
@(private)
refuse :: proc(g: ^Gen, span: lang.Span, what: string) {
	append(&g.problems, Problem{span = span, what = what})
}

// The Odin name of a symbol, made once: the sketch's own name, with a trailing underscore when Odin uses
// it, and a number when two symbols would otherwise share a name.
@(private)
name_of :: proc(g: ^Gen, sym: ^lang.Symbol) -> string {
	if found, ok := g.names[sym]; ok {
		return found
	}
	if sym.kind == .Item {
		return "it_" // the item a list verb's block is looking at; the procedure made for the call names it so
	}
	if sym.kind == .Result {
		return "result_" // the running value of `combine`
	}
	base := clean(sym.name)
	name := base
	if g.taken[name] {
		name = fmt.aprintf("%s_", base, allocator = context.temp_allocator)
		for n := 2; g.taken[name]; n += 1 {
			name = fmt.aprintf("%s_%d", base, n, allocator = context.temp_allocator)
		}
	}
	g.taken[name] = true
	g.names[sym] = name
	return name
}

// A name Odin will take: letters, digits and underscores, not starting with a digit.
@(private)
clean :: proc(name: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	for r, i in name {
		ok := r == '_' || (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r > 127
		if i == 0 && r >= '0' && r <= '9' {
			strings.write_byte(&b, '_')
		}
		strings.write_rune(&b, r if ok else '_')
	}
	return strings.to_string(b)
}

// A field name as Odin wants it (records keep the sketch's names, so only the odd one is changed).
@(private)
field_name :: proc(name: string) -> string {
	c := clean(name)
	for r in RESERVED {
		if r == c {
			return strings.concatenate({c, "_"}, context.temp_allocator)
		}
	}
	return c
}

// The Odin type of a checked type. Says what is not supported (a mix of values the checker could not
// settle, windows, pictures, sounds and the like) when it has a place to say it at.
@(private)
odin_type :: proc(g: ^Gen, t: lang.Type_Id, span: lang.Span, what: string) -> (name: string, ok: bool) {
	resolved := lang.resolve(g.types, t)
	item := g.types.items[resolved]
	#partial switch item.kind {
	case .Number:  return "f64", true
	case .Boolean: return "bool", true
	case .Text:    return "string", true
	case .Colour:  return "maths.Colour", true
	case .Image:   return "roci.Image", true
	case .Sound:   return "roci.Sound", true
	case .Window:  return "roci.Window", true
	case .Gradient: return "^rt.Gradient_Box", true
	case .Boxed:   return "rt.Box", true
	case .Table:
		value, value_ok := odin_type(g, lang.Type_Id(item.a), span, what)
		if !value_ok {
			return "", false
		}
		return fmt.aprintf("^rt.Table(%s)", value, allocator = context.temp_allocator), true
	case .Vector:  return fmt.aprintf("[%d]f64", item.a, allocator = context.temp_allocator), true
	case .List:
		element, element_ok := odin_type(g, lang.Type_Id(item.a), span, what)
		if !element_ok {
			return "", false
		}
		return fmt.aprintf("^rt.List(%s)", element, allocator = context.temp_allocator), true
	case .Record:
		return record_type(g, resolved, span, what)
	case .None:
		return "", true
	}
	refuse(g, span, fmt.tprintf("`%s` holds %s, which compiled sketches cannot hold yet", what, describe_type(g, resolved)))
	return "", false
}

@(private)
describe_type :: proc(g: ^Gen, t: lang.Type_Id) -> string {
	return lang.describe(g.types, t)
}

// The struct of a record shape, written the first time it is needed, with the header the collector needs as
// its first field and a procedure that marks the heap objects its fields hold.
@(private)
record_type :: proc(g: ^Gen, t: lang.Type_Id, span: lang.Span, what: string) -> (string, bool) {
	shape_index := g.types.items[t].a
	if known, ok := g.records[shape_index]; ok {
		return fmt.aprintf("^%s", known, allocator = context.temp_allocator), true
	}
	name := fmt.aprintf("Record_%d", len(g.records) + 1, allocator = context.temp_allocator)
	g.records[shape_index] = name
	fields := strings.builder_make(context.temp_allocator)
	marks := strings.builder_make(context.temp_allocator)
	ok := true
	for f in g.types.shapes[shape_index].fields {
		if g.lenient > 0 {
			before := len(g.problems)
			_, can_hold := odin_type(g, f.type, span, f.name)
			if !can_hold {
				resize(&g.problems, before)
				continue // `osc.args` is a list of mixed values, which is left out; reading it is refused
			}
		}
		type, field_ok := odin_type(g, f.type, span, f.name)
		if !field_ok {
			ok = false
			continue
		}
		fmt.sbprintf(&fields, "\t%s: %s,\n", field_name(f.name), type)
		if statement := mark_statement(g, f.type, fmt.tprintf("r.%s", field_name(f.name))); statement != "" {
			fmt.sbprintf(&marks, "\t%s\n", statement)
		}
	}
	// `class__` is what shape the record was written as (`lang.Shape_Class`), for a list that mixes lines, circles and rectangles
	fmt.sbprintf(&g.defs, "%s :: struct {{\n\tusing gc__: rt.Header,\n\tclass__: u8,\n\tunset__: u64,\n%s}}\n\n", name, strings.to_string(fields))
	if strings.to_string(marks) != "" {
		fmt.sbprintf(&g.defs, "trace_%s :: proc(h: ^rt.Header) {{\n\tr := (^%s)(h)\n%s}}\n\n", name, name, strings.to_string(marks))
	}
	return fmt.aprintf("^%s", name, allocator = context.temp_allocator), ok
}

// The statement that marks a value of a type for the collector, or "" for a type that holds nothing on the
// heap (numbers, vectors, colors, true and false).
@(private)
mark_statement :: proc(g: ^Gen, t: lang.Type_Id, value: string) -> string {
	resolved := lang.resolve(g.types, t)
	#partial switch g.types.items[resolved].kind {
	case .Text:
		return fmt.aprintf("rt.mark_text(%s)", value, allocator = context.temp_allocator)
	case .Record, .List, .Table, .Gradient:
		return fmt.aprintf("if %s != nil {{ rt.mark(&%s.gc__) }}", value, value, allocator = context.temp_allocator)
	case .Boxed:
		return fmt.aprintf("rt.mark_box(%s)", value, allocator = context.temp_allocator)
	}
	return ""
}

// The statement that marks a value of a type given by its Odin text (a message): a pointer to a record or a list, or a text.
@(private)
mark_statement_text :: proc(g: ^Gen, odin: string, value: string) -> string {
	switch {
	case odin == "string":
		return fmt.aprintf("rt.mark_text(%s)", value, allocator = context.temp_allocator)
	case odin == "rt.Box":
		return fmt.aprintf("rt.mark_box(%s)", value, allocator = context.temp_allocator)
	case strings.has_prefix(odin, "^"):
		return fmt.aprintf("if %s != nil {{ rt.mark(&%s.gc__) }}", value, value, allocator = context.temp_allocator)
	}
	return ""
}

// The procedure that marks one item of a list whose items are of this type, or "nil" for items that hold nothing.
@(private)
item_marker :: proc(g: ^Gen, element: lang.Type_Id, element_odin: string) -> string {
	if known, ok := g.markers[element_odin]; ok {
		return known
	}
	statement := mark_statement(g, element, "item")
	if statement == "" {
		g.markers[element_odin] = "nil"
		return "nil"
	}
	name := fmt.aprintf("mark_item_%d", len(g.markers) + 1, allocator = context.temp_allocator)
	g.markers[element_odin] = name
	fmt.sbprintf(&g.defs, "%s :: proc(item: %s) {{\n\t%s\n}}\n\n", name, element_odin, statement)
	return name
}

// The record struct's own name (without the pointer), for building one.
@(private)
record_name :: proc(g: ^Gen, t: lang.Type_Id, span: lang.Span) -> string {
	resolved := lang.resolve(g.types, t)
	odin_type(g, resolved, span, "a record")
	return g.records[g.types.items[resolved].a]
}

// ---- output ----

@(private)
line :: proc(g: ^Gen, format: string, args: ..any) {
	for _ in 0 ..< g.indent {
		strings.write_byte(&g.body, '\t')
	}
	fmt.sbprintf(&g.body, format, ..args)
	strings.write_byte(&g.body, '\n')
}

// A comment naming the line of the sketch a statement comes from, once for each new line.
@(private)
comment :: proc(g: ^Gen, span: lang.Span) {
	if span.end <= span.start && span.start == 0 {
		return
	}
	at := lang.position_of(g.src, span.start).line
	if at == g.comment_line {
		return
	}
	g.comment_line = at
	text := strings.trim_space(lang.line_text(g.src, at))
	text, _ = strings.replace_all(text, "\n", " ", context.temp_allocator)
	line(g, "// line %d: %s", at, text)
}

// A line number and column for a problem.
position :: proc(src: lang.Source, span: lang.Span) -> (line, column: int) {
	p := lang.position_of(src, span.start)
	return p.line, p.column
}

// The constants made by a line that runs in its turn: the ones whose value is not only written down. A constant of numbers, text and
// colours is made before everything else, so nothing reads it early; one that uses a name, a verb or the clock is made where it is
// written, and a verb called before that reads it empty. Each of those carries a flag, and a read inside a verb checks it.
@(private)
flag_constants :: proc(g: ^Gen) {
	for s in g.program.stmts {
		assign, is_assign := s.kind.(lang.IR_Assign)
		if is_assign && assign.target.kind == .Constant && len(assign.fields) == 0 && !written_down(assign.value) {
			g.flagged[assign.target] = true
		}
	}
}

// Whether an expression is only written down: numbers, text, colours, words, and vectors, lists, records and sums of those.
@(private)
written_down :: proc(e: ^lang.IR) -> bool {
	if e == nil {
		return true
	}
	switch k in e.kind {
	case lang.IR_Number, lang.IR_Text, lang.IR_Colour, lang.IR_Boolean, lang.IR_Word:
		return true
	case lang.IR_Vector:
		for item in k.items {
			if !written_down(item) {
				return false
			}
		}
		return true
	case lang.IR_List:
		for item in k.items {
			if !written_down(item) {
				return false
			}
		}
		return true
	case lang.IR_Record:
		for value in k.values {
			if !written_down(value) {
				return false
			}
		}
		return true
	case lang.IR_Unary:
		return written_down(k.operand)
	case lang.IR_Binary:
		return written_down(k.lhs) && written_down(k.rhs)
	case lang.IR_Convert:
		return written_down(k.value)
	case lang.IR_Load, lang.IR_Builtin, lang.IR_Swizzle, lang.IR_Field, lang.IR_Call, lang.IR_Block_Value, lang.IR_Error:
		return false
	}
	return false
}

// A place that can warn, written once at package level: `rt.Site`. Gives its name.
@(private)
new_site :: proc(g: ^Gen, span: lang.Span, name, fields: string) -> string {
	g.sites += 1
	id := fmt.aprintf("site_%d", g.sites, allocator = context.temp_allocator)
	fmt.sbprintf(&g.procs, "%s := rt.Site{{start = %d, end = %d, name = %q, fields = %q}}\n\n", id, span.start, span.end, name, fields)
	return id
}

// What gives the program the text of its sketch, when it has a place that can warn, and nothing when it has none: the text and
// its parts as declarations of the package, and the line of `setup` that hands them over. The parts are a variable of the package
// because `use_source` keeps them, and a literal in `setup` would be gone once it returns (Odin warns that it escapes, and printing
// that warning under a line holding the whole sketch took all the memory of the computer); the text is a constant on a line of its own.
@(private)
source_lines :: proc(g: ^Gen) -> (declarations, call: string) {
	if g.sites == 0 {
		return "", ""
	}
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "// The text of the sketch and its files, for the line under a warning.\nsource_text__ :: %q\n\nsource_parts__ := [?]rt.Part{{\n", g.src.text)
	for part in g.src.parts {
		fmt.sbprintf(&b, "\t{{name = %q, library = %q, start = %d, first_line = %d}},\n", part.name, part.library, part.start, part.first_line)
	}
	strings.write_string(&b, "}\n\n")
	return strings.to_string(b), fmt.tprintf("\trt.use_source(source_text__, %q, source_parts__[:])\n", g.src.name)
}

// The line that starts `setup` by translating the shaders the sketch names, so no frame waits for one,
// as the interpreter does before it runs; nothing when it names none.
warm_line :: proc(program: ^lang.IR_Program) -> string {
	if len(program.shaders) == 0 {
		return ""
	}
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, "\trt.warm_shaders({")
	for named, i in program.shaders {
		if i > 0 {
			strings.write_string(&b, ", ")
		}
		fmt.sbprintf(&b, "{{%q, %v}}", named.name, named.fill)
	}
	strings.write_string(&b, "})\n")
	return strings.to_string(b)
}

// The line that starts `setup` for a sketch that asks for fullscreen in its own text, so a Mac fills the
// screen at once instead of sliding into a Space, as the interpreter does; it must come before the first
// window. Nothing for any other sketch.
fullscreen_line :: proc(program: ^lang.IR_Program) -> string {
	return "\troci.fullscreen_spaces(false)\n" if program.fullscreen else ""
}

