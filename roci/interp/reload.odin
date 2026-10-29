// SPDX-License-Identifier: 0BSD
//
// Live reload. When the sketch file changes it is read and checked first; if it
// has errors the old sketch keeps running under the error overlay. Otherwise it
// is loaded again and the old values are carried over where that is safe: a
// top-level line that did not change keeps its value, a changed one runs again,
// constants (names in capitals) always take the new text, and records that gained
// a field keep their values with the new field at zero. Anything that opens
// windows or draws while setting up cannot be re-run in place, so a change to such
// a line restarts the sketch from its first line; the windows stay open. Every
// reload says which of the two it was.
package interp

import "../"
import "../folder"
import "../lang"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import "../maths"
import "../../tools/term"

Outcome :: enum u8 {
	Unchanged, // nothing to do
	Reloaded,  // the new sketch runs with the values it could keep
	Restarted, // the new sketch runs again from its first line
	Failed,    // the new text has errors; the old sketch keeps running
}

// Interpreters that were replaced while one of their own blocks was running; freed
// at the next frame, when nothing refers to them.
@(thread_local)
retired: [dynamic]^Interp

// Remembers the file to watch, so changes to it are picked up. A `sketch.roci` stands
// for its whole folder: every .roci file there is watched, and so is the folder, for
// files that appear or go.
watch :: proc(p: ^Interp, path: string) {
	p.path = strings.clone(path, p.long)
	if t, err := os.modification_time_by_path(path); err == nil {
		p.mtime = t
	}
	if is_sketch_path(path) {
		p.program = true
		if program, problem := folder.read_program(path); problem == "" {
			remember_files(p, program.paths)
		}
	}
}

@(private)
is_sketch_path :: proc(path: string) -> bool {
	return path == "sketch.roci" || strings.has_suffix(path, "/sketch.roci")
}

// Remembers the files of the program and when each one last changed.
@(private)
remember_files :: proc(p: ^Interp, paths: []string) {
	p.watched = make([]string, len(paths), p.long)
	p.mtimes = make([]time.Time, len(paths), p.long)
	for path, i in paths {
		p.watched[i] = strings.clone(path, p.long)
		if t, err := os.modification_time_by_path(path); err == nil {
			p.mtimes[i] = t
		}
	}
	p.scanned = time.now()
}

// The interpreter that is running now: a reload makes a new one.
active :: proc() -> ^Interp {
	return current
}

// Frees what reloads have replaced.
free_retired :: proc() {
	for p in retired {
		if p != current {
			destroy(p)
		}
	}
	clear(&retired)
}

// Frees the running interpreter and every one a reload replaced.
shutdown :: proc() {
	running := current
	for p in retired {
		if p != running {
			destroy(p)
		}
	}
	delete(retired)
	retired = nil
	if running != nil {
		destroy(running)
	}
}

@(private)
notice :: proc(p: ^Interp, text: string) {
	append(&p.notices, strings.clone(text, p.long))
	if p.echo {
		style := term.Style.Green
		if strings.has_prefix(text, "restarted") {
			style = .Yellow
		}
		fmt.eprintfln("%s %s", term.err("rocinante:", .Bold_Cyan), term.err(text, style))
	}
}

// The text of a top-level statement, for telling which lines changed.
@(private)
statement_text :: proc(p: ^Interp, s: ^lang.IR_Stmt) -> string {
	return strings.trim_space(lang.span_text(p.src, s.span))
}

// Does setting this statement up open a window or draw, so that it cannot be run
// a second time on top of the first?
@(private)
is_effect :: proc(s: ^lang.IR_Stmt) -> bool {
	#partial switch k in s.kind {
	case lang.IR_Assign:
		return len(k.fields) > 0 || makes_window(k.value)
	case lang.IR_Draw, lang.IR_On, lang.IR_Every, lang.IR_Unchecked, lang.IR_Error_Stmt:
		return false
	}
	return true
}

@(private)
makes_window :: proc(e: ^lang.IR) -> bool {
	if call, ok := e.kind.(lang.IR_Call); ok && call.verb != nil {
		return call.verb.name == "window"
	}
	return false
}

// ---- carrying values across ----

// Could a value that has the old type be kept as the new type? A record may have
// gained fields but not lost one or changed what one holds.
@(private)
compatible :: proc(old: ^Interp, ot: lang.Type_Id, fresh: ^Interp, nt: lang.Type_Id, depth := 0) -> bool {
	if depth > 8 {
		return false
	}
	o, n := lang.resolve(old.types, ot), lang.resolve(fresh.types, nt)
	a, b := old.types.items[o], fresh.types.items[n]
	loose := proc(k: lang.Type_Kind) -> bool {
		return k == .Boxed || k == .Variable || k == .Error
	}
	if loose(a.kind) || loose(b.kind) {
		return true
	}
	if a.kind != b.kind {
		return false
	}
	#partial switch a.kind {
	case .Vector:
		return a.a == b.a
	case .List:
		return compatible(old, lang.Type_Id(a.a), fresh, lang.Type_Id(b.a), depth + 1)
	case .Record:
		for f in old.types.shapes[a.a].fields {
			found := false
			for g in fresh.types.shapes[b.a].fields {
				if g.name == f.name {
					found = compatible(old, f.type, fresh, g.type, depth + 1)
					break
				}
			}
			if !found {
				return false
			}
		}
	}
	return true
}

// A copy of an old value in the new sketch's memory, shaped as the new type.
@(private)
convert :: proc(old, fresh: ^Interp, v: Value, nt: lang.Type_Id, depth := 0) -> Value {
	if depth > 16 {
		return nil
	}
	n := lang.resolve(fresh.types, nt)
	item := fresh.types.items[n]
	switch x in v {
	case string:
		return strings.clone(x, fresh.long)
	case ^roci.Gradient:
		if x == nil {
			return v
		}
		g := new(roci.Gradient, fresh.long)
		g^ = x^
		return g
	case ^List:
		if x == nil {
			return v
		}
		l := new(List, fresh.long)
		l.long = true
		l.items = make([dynamic]Value, 0, len(x.items), fresh.long)
		element := lang.T_BOXED
		if item.kind == .List {
			element = lang.Type_Id(item.a)
		}
		for e in x.items {
			append(&l.items, convert(old, fresh, e, element, depth + 1))
		}
		return l
	case ^Record:
		if x == nil || item.kind != .Record {
			return nil
		}
		r := new(Record, fresh.long)
		r.long = true
		r.shape = item.a
		fields := fresh.types.shapes[item.a].fields
		r.fields = make([]Value, len(fields), fresh.long)
		old_fields := old.types.shapes[x.shape].fields
		for f, i in fields {
			r.fields[i] = zero_value(fresh, f.type, 0)
			for g, j in old_fields {
				if g.name == f.name && j < len(x.fields) {
					r.fields[i] = convert(old, fresh, x.fields[j], f.type, depth + 1)
				}
			}
		}
		return r
	case f64, bool, Vec, maths.Colour, roci.Window:
	}
	return v
}

// ---- reloading ----

// Reads the new text of the sketch and makes it the running one. Gives the
// interpreter to use from now on (the same one when the text has errors, a new one
// otherwise) and what happened. `restart` runs the sketch from its first line
// even when its values could be kept (Ctrl+R).
reload :: proc(p: ^Interp, text: string, restart := false) -> (^Interp, Outcome) {
	return reload_files(p, {lang.File_Text{name = p.src.name, text = text}}, restart)
}

// The same for a program of several files, given in the order they are joined.
reload_files :: proc(p: ^Interp, files: []lang.File_Text, restart := false) -> (^Interp, Outcome) {
	n, ok := load_files(files)
	if !ok {
		set_problem(p, n)
		destroy(n)
		update_overlay(p)
		return p, .Failed
	}
	n.echo, n.budget, n.hook_frame = p.echo, p.budget, p.hook_frame
	n.path, n.mtime = strings.clone(p.path, n.long), p.mtime
	n.program, n.scanned = p.program, p.scanned
	n.watched, n.mtimes = make([]string, len(p.watched), n.long), make([]time.Time, len(p.mtimes), n.long)
	for path, i in p.watched {
		n.watched[i] = strings.clone(path, n.long)
	}
	copy(n.mtimes, p.mtimes)

	old_stmts, new_stmts := p.checked.program.stmts, n.checked.program.stmts
	carry := make([]int, len(new_stmts), context.temp_allocator)
	used := make([]bool, len(old_stmts), context.temp_allocator)
	// A sketch that never ran (it had errors when it was opened) has nothing to carry over.
	need_restart := restart || p.has_errors
	for s, i in new_stmts {
		carry[i] = -1
		written := statement_text(n, s)
		for o, j in old_stmts {
			if !used[j] && statement_text(p, o) == written {
				carry[i], used[j] = j, true
				break
			}
		}
		if carry[i] < 0 && is_effect(s) {
			need_restart = true
		}
	}
	for o, j in old_stmts {
		if !used[j] && is_effect(o) {
			need_restart = true
		}
	}

	if need_restart {
		roci.begin_restart()
		start(n)
		roci.end_restart()
		notice(n, "the errors are fixed: the sketch runs from its first line" if p.has_errors else "restarted: the sketch runs again from its first line" if restart else "restarted: a line that opens a window or draws changed, so the sketch runs again from its first line")
		append(&retired, p)
		update_overlay(n)
		return n, .Restarted
	}

	current = n
	n.alloc = n.long
	frame := Frame{}
	defer delete(frame.slots)
	n.frame = &frame
	begin_block(n)
	kept, again, lost := 0, make([dynamic]string, context.temp_allocator), make([dynamic]string, context.temp_allocator)
	for s, i in new_stmts {
		j := carry[i]
		assign, is_assign := s.kind.(lang.IR_Assign)
		if is_assign && j >= 0 && len(assign.fields) == 0 {
			if old_assign, was_assign := old_stmts[j].kind.(lang.IR_Assign); was_assign && assign.target.kind != .Constant {
				if v, has := p.globals[old_assign.target]; has && compatible(p, old_assign.target.type, n, assign.target.type) {
					n.globals[assign.target] = convert(p, n, v, assign.target.type)
					kept += 1
					continue
				}
			}
			append(&again, assign.target.name)
		} else if is_assign && len(assign.fields) == 0 {
			append(&again, assign.target.name) // a line that changed or is new runs
		} else if j >= 0 && is_effect(s) {
			continue
		}
		exec_stmt(n, s)
	}
	// Names the sketch gives only inside blocks (or assigns in a way no line above carried): by name.
	for old_symbol, v in p.globals {
		for new_symbol in n.checked.program.symbols {
			if new_symbol.name != old_symbol.name {
				continue
			}
			if _, has := n.globals[new_symbol]; has || new_symbol.kind == .Constant {
				break
			}
			if compatible(p, old_symbol.type, n, new_symbol.type) {
				n.globals[new_symbol] = convert(p, n, v, new_symbol.type)
				kept += 1
			} else {
				append(&lost, old_symbol.name)
			}
			break
		}
	}
	n.frame = nil
	message := fmt.tprintf("reloaded: %d values kept", kept)
	if len(again) > 0 {
		message = fmt.tprintf("%s, started again from their lines: %s", message, strings.join(again[:], ", ", context.temp_allocator))
	}
	if len(lost) > 0 {
		message = fmt.tprintf("%s, lost: %s", message, strings.join(lost[:], ", ", context.temp_allocator))
	}
	notice(n, message)
	append(&retired, p)
	update_overlay(n)
	return n, .Reloaded
}

// Remembers the first error of `bad` (a sketch that did not check) to show over the
// running one, and says so on the console, once for each message.
set_problem :: proc(p, bad: ^Interp) {
	first := bad.checked.diagnostics[0]
	for d in bad.checked.diagnostics {
		if lang.severity_of(d) == .Error {
			first = d
			break
		}
	}
	title, lines := lang.plain_message(bad.src, first)
	if title == p.problem_title {
		return
	}
	p.problem_title = strings.clone(title, p.long)
	p.problem_lines = make([]string, len(lines), p.long)
	for l, i in lines {
		p.problem_lines[i] = strings.clone(l, p.long)
	}
	if p.echo {
		what := "the sketch has errors, so nothing runs until they are fixed" if p.has_errors else "the sketch has errors, so the last good version keeps running"
		fmt.eprintfln("%s %s\n\n%s", term.err("rocinante:", .Bold_Cyan), term.err(what, .Yellow), term.message(lang.render_all(bad.src, bad.checked.diagnostics, context.temp_allocator), term.err_colour))
	}
}

// Checks the sketch file for a change and reloads it. Gives the interpreter to use.
poll :: proc(p: ^Interp) -> ^Interp {
	if p.path == "" {
		return p
	}
	if p.program {
		return poll_program(p)
	}
	t, err := os.modification_time_by_path(p.path)
	if err != nil || t == p.mtime {
		return p
	}
	p.mtime = t
	data, read_err := os.read_entire_file(p.path, context.temp_allocator)
	if read_err != nil {
		return p
	}
	if string(data) == p.src.text {
		// Saved back to the text that is running: the errors of the last save are gone.
		if p.problem_title != "" {
			p.problem_title, p.problem_lines = "", nil
			update_overlay(p)
			notice(p, "the errors are fixed")
		}
		return p
	}
	next, _ := reload(p, string(data))
	return next
}

// Runs the sketch again from its first line, reading the file again when it is watched.
restart :: proc(p: ^Interp) -> ^Interp {
	if p.program {
		if files, ok := read_watched_program(p); ok {
			next, _ := reload_files(p, files, true)
			return next
		}
	}
	text := p.src.text
	if p.path != "" {
		if data, err := os.read_entire_file(p.path, context.temp_allocator); err == nil {
			text = string(data)
			if t, terr := os.modification_time_by_path(p.path); terr == nil {
				p.mtime = t
			}
		}
	}
	next, _ := reload(p, text, true)
	return next
}

// ---- what the overlay says ----

// Shows the first thing that is wrong, if anything is: the text that failed to
// check, else the first runtime error. Done only when the message changes.
update_overlay :: proc(p: ^Interp) {
	title: string
	lines: []string
	switch {
	case p.problem_title != "":
		title, lines = p.problem_title, p.problem_lines
	case len(p.errors) > 0:
		e := p.errors[0]
		title, lines = lang.plain_message(p.src, lang.Diagnostic{id = e.id, span = e.span, args = e.args})
	}
	if shown, _ := roci.overlay_text(); title == shown {
		return
	}
	roci.set_overlay(title, lines)
}

// Says each runtime error on the console as it first happens.
report_new_errors :: proc(p: ^Interp) {
	for p.reported < len(p.errors) {
		e := p.errors[p.reported]
		p.reported += 1
		if p.echo {
			fmt.eprintfln("%s", term.message(lang.render(p.src, lang.Diagnostic{id = e.id, span = e.span, args = e.args}, context.temp_allocator), term.err_colour))
		}
	}
}

// How often the folder of a program is listed for files that came or went.
SCAN_EVERY :: 500 * time.Millisecond

// The program as it is on disk now, or nothing when it cannot be read or has no sketch.roci.
@(private)
read_watched_program :: proc(p: ^Interp) -> (files: []lang.File_Text, ok: bool) {
	program, problem := folder.read_program(p.path)
	if problem != "" || len(program.files) == 0 || !is_sketch_path(program.files[len(program.files) - 1].name) {
		return nil, false
	}
	remember_files(p, program.paths)
	return program.files, true
}

// `poll` for a program: any of its files changing, or a file coming or going, reloads it.
@(private)
poll_program :: proc(p: ^Interp) -> ^Interp {
	changed := false
	for path, i in p.watched {
		t, err := os.modification_time_by_path(path)
		if err != nil || t != p.mtimes[i] {
			changed = true
		}
	}
	if !changed && time.diff(p.scanned, time.now()) >= SCAN_EVERY {
		p.scanned = time.now()
		// The program as it is now, libraries it asks for included: any file that came or went.
		listed, problem := folder.read_program(p.path)
		if problem == "" {
			changed = len(listed.paths) != len(p.watched)
			for path in listed.paths {
				known := false
				for w in p.watched {
					known ||= w == path
				}
				changed ||= !known
			}
		}
	}
	if !changed {
		return p
	}
	files, ok := read_watched_program(p)
	if !ok {
		return p
	}
	if lang.join_sources(files, context.temp_allocator).text == p.src.text {
		// Saved back to the text that is running: the errors of the last save are gone.
		if p.problem_title != "" {
			p.problem_title, p.problem_lines = "", nil
			update_overlay(p)
			notice(p, "the errors are fixed")
		}
		return p
	}
	next, _ := reload_files(p, files)
	return next
}
