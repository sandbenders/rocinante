// SPDX-License-Identifier: 0BSD
//
// The interpreter: it runs the typed IR the checker made, calling the same
// procedures of package roci that an Odin sketch calls, so a sketch behaves the
// same written either way. `load` reads and checks a sketch, `start` runs its
// top-level statements (windows open, `draw` blocks are handed to the app loop),
// and the frames after that are run by the app loop through one trampoline.
//
// A sketch never stops on a mistake: a failing operation gives an empty value or
// 0, records a runtime error and carries on.
package interp

import "../"
import "../lang"
import "../registry"
import "core:fmt"
import "core:mem"
import "core:mem/virtual"
import "core:strings"
import "core:time"

// How many verbs may call each other before the sketch is stopped, and how long
// one block may run.
MAX_DEPTH :: 100
BLOCK_SECONDS :: 2.0

// A name that lives in a frame: a parameter, a loop name, `it`.
Slot :: struct {
	symbol: ^lang.Symbol,
	value:  Value,
}

// What a block or a taught verb sees of its own: its names, and what it gave back.
Frame :: struct {
	slots:  [dynamic]Slot,
	result: Value,
}

Flow :: enum u8 {
	Normal,
	Give,  // `give` ran: the value is in the frame
	Stop,  // `stop` ran
	Abort, // the block took too long
}

Runtime_Error :: struct {
	id:   lang.Message_Id,
	span: lang.Span,
	args: [4]string,
}

Interp :: struct {
	checked:   lang.Checked,
	src:       lang.Source,
	types:     ^lang.Types,
	arena:     virtual.Arena,
	long:      mem.Allocator, // the sketch's own memory, freed with it
	alloc:     mem.Allocator, // where new values go now: `long` while the sketch sets itself up, the frame's memory after
	globals:   map[^lang.Symbol]Value,
	frame:     ^Frame,
	items:     [dynamic]Value, // `it`, innermost last
	results:   [dynamic]Value, // `result`, innermost last
	draws:     map[roci.Window]^lang.IR_Block,
	handlers:  [dynamic]Handler,
	inbox:     [2][dynamic]Message, // [msg_now] is what arrives this frame, the other what is sent now
	msg_arenas: [2]virtual.Arena, // the memory of each inbox
	msg_now:   int,
	hook_frame: int,
	errors:    [dynamic]Runtime_Error,
	seen:      map[int]bool, // the errors said once: id and place
	printed:   [dynamic]string,
	echo:      bool, // `print` also writes to the console
	depth:     int,
	path:      string, // the file being watched, or ""
	mtime:     time.Time,
	notices:   [dynamic]string, // what reloads said
	problem_title: string, // the first error of a reload that failed, shown while the old sketch runs
	problem_lines: []string,
	reported:  int, // runtime errors already said on the console
	pending:   Flow, // a `stop` or `give` that ran inside a block a verb ran for its statement
	ops:       int,
	budget:    f64, // seconds one block may run
	started:   time.Tick, // when the block being run began
	has_errors: bool, // the sketch has check errors and does not run
}

// The interpreter the running frame belongs to. The app loop calls plain
// procedures, so the trampoline finds its sketch here; the sketch is thread-local
// like the rest of the app state.
@(thread_local)
current: ^Interp

// Reads and checks a sketch. Check errors are in `p.checked.diagnostics`, and the
// sketch does not run when there are any (`ok` is false). Free it with `destroy`.
load :: proc(name, text: string) -> (p: ^Interp, ok: bool) {
	p = new(Interp)
	if err := virtual.arena_init_growing(&p.arena); err != nil {
		return p, false
	}
	p.long = virtual.arena_allocator(&p.arena)
	for i in 0 ..< 2 {
		_ = virtual.arena_init_growing(&p.msg_arenas[i])
	}
	p.hook_frame = -1
	p.alloc = p.long
	p.src = lang.make_source(strings.clone(name, p.long), strings.clone(text, p.long), 0, p.long)
	p.checked = lang.check(p.src, registry.ALL_VERBS, nil, p.long)
	p.types = p.checked.program.types
	p.globals = make(map[^lang.Symbol]Value, 32, p.long)
	p.draws = make(map[roci.Window]^lang.IR_Block, 4, p.long)
	p.seen = make(map[int]bool, 8, p.long)
	p.budget = BLOCK_SECONDS
	p.has_errors = lang.has_errors(p.checked.diagnostics)
	return p, !p.has_errors
}

destroy :: proc(p: ^Interp) {
	if current == p {
		current = nil
		roci.set_frame_hook(nil)
	}
	for i in 0 ..< 2 {
		delete(p.inbox[i])
		virtual.arena_destroy(&p.msg_arenas[i])
	}
	delete(p.handlers)
	delete(p.items)
	delete(p.notices)
	delete(p.results)
	delete(p.errors)
	delete(p.printed)
	virtual.arena_destroy(&p.arena)
	free(p)
}

// Runs the sketch's top-level statements once, in order. Windows open, set-up
// drawing is recorded and each `draw` block is handed to the app loop. Does
// nothing for a sketch with check errors.
start :: proc(p: ^Interp) {
	current = p
	roci.set_frame_hook(frame_hook)
	if p.has_errors {
		// It does not run, but the file is still watched, and the overlay says why.
		set_problem(p, p)
		update_overlay(p)
		return
	}
	p.alloc = p.long
	frame := Frame{}
	defer delete(frame.slots)
	p.frame = &frame
	begin_block(p)
	exec_stmts(p, p.checked.program.stmts)
	p.frame = nil
}

// The frame's hook: the app loop calls this for a window that has a `draw` block.
draw_trampoline :: proc() {
	p := current
	if p == nil {
		return
	}
	block, found := p.draws[roci.current_window()]
	if !found {
		return
	}
	run_block(p, block)
}

// Runs one block the app loop asked for (a `draw` block, later an event) with its
// own frame, its values in the frame's memory, and a time limit.
run_block :: proc(p: ^Interp, block: ^lang.IR_Block, bind: ^lang.Symbol = nil, value: Value = nil) {
	saved_alloc, saved_frame := p.alloc, p.frame
	p.alloc = context.temp_allocator
	frame := Frame{}
	frame.slots = make([dynamic]Slot, 0, 8, context.temp_allocator)
	p.frame = &frame
	p.depth = 0
	if bind != nil {
		append(&frame.slots, Slot{bind, value})
	}
	begin_block(p)
	exec_stmts(p, block.stmts)
	p.alloc, p.frame = saved_alloc, saved_frame
}

// Restarts the clock and the count that stop a block that runs too long.
begin_block :: proc(p: ^Interp) {
	p.started = time.tick_now()
	p.ops = 0
}

// Called for every statement run: now and then, checks the clock.
@(private)
tick :: proc(p: ^Interp, span: lang.Span) -> bool {
	p.ops += 1
	if p.ops & 4095 != 0 {
		return true
	}
	if time.duration_seconds(time.tick_since(p.started)) > p.budget {
		fail(p, .Runs_Too_Long, span, "", fmt.tprintf("%v", p.budget), "", fix_line(p, span, span, "repeat 100 [ ... ]"))
		return false
	}
	return true
}

// ---- runtime errors ----

// Says a runtime error once for each place it happens.
fail :: proc(p: ^Interp, id: lang.Message_Id, span: lang.Span, a, b, c, d: string) {
	key := span.start * 16 + int(id)
	if p.seen[key] {
		return
	}
	p.seen[key] = true
	append(&p.errors, Runtime_Error{id = id, span = span, args = {strings.clone(a, p.long), strings.clone(b, p.long), strings.clone(c, p.long), strings.clone(d, p.long)}})
}

// The writer's own line with `replacement` where `at` was; when it cannot be
// done the replacement alone.
@(private)
fix_line :: proc(p: ^Interp, line_of, at: lang.Span, replacement: string) -> string {
	return lang.line_replacing(p.src, at, replacement, context.temp_allocator)
}

// The runtime errors as people read them, in the order they happened.
report :: proc(p: ^Interp, allocator := context.allocator) -> string {
	diagnostics := make([]lang.Diagnostic, len(p.errors), context.temp_allocator)
	for e, i in p.errors {
		diagnostics[i] = lang.Diagnostic{id = e.id, span = e.span, args = e.args}
	}
	return lang.render_all(p.src, diagnostics, allocator)
}
