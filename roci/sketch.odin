// SPDX-License-Identifier: 0BSD
//
// The state of a running sketch (the public API sits on top of platform, gfx and maths). A sketch is one program with some windows. The
// verbs in this package act on the *current window*: the default window while
// the program sets itself up, and the window whose `draw` block is running while a
// frame is drawn. Style and transform state live on each window's command list
// and reset at the start of every frame.
//
// Everything runs on the thread that started the sketch, which is where SDL wants
// its video calls. The state is thread-local, so tests that run
// in parallel threads each have their own sketch. A sketch can also run
// headless, with no SDL and no window, drawing nothing to the screen but
// recording everything: that is how the tests, the golden scenes and the
// benchmark step it.
package roci

import "core:fmt"
import "core:strings"
import "core:time"
import "gfx"
import "maths"
import "platform"

// The size a sketch gets when it never calls `window`.
DEFAULT_WIDTH :: 800
DEFAULT_HEIGHT :: 600

// A window, by the number the program was given when it made it. 0 is no window.
Window :: distinct int

// What a window needs, besides the operating system's window.
Win :: struct {
	id:           Window,
	handle:       ^platform.Window, // nil when headless
	list:         gfx.Command_List,
	batcher:      gfx.Batcher,
	draw:         proc(),           // runs every frame, when set; otherwise the list drawn at set-up is shown as it is
	on_receive:   proc(value: Value),
	inbox:        [dynamic]Value,   // messages sent to this window, delivered on the next frame
	width:        int,              // logical size, as sketches see it
	height:       int,
	title:        string,
	explicit:     bool,             // made by a `window` call, as opposed to the default window
	alive:        bool,
	mouse:        [2]f64,           // where the mouse is in this window, and where it was a frame ago
	previous:     [2]f64,
	buttons:      bit_set[platform.Mouse_Button], // the mouse buttons held down that went down in this window
	fullscreen:   bool,
	fixed:        bool,             // its size cannot be changed by dragging its edges
	borderless:   bool,             // no title bar or frame
	topmost:      bool,
	hidden:       bool,
	unfocusable:  bool,
	grabbed:      bool,             // the mouse is kept inside it
	modal:        bool,
	alpha:        f64,              // how solid the whole window is, 0 to 255
	parent:       Window,
	smallest:     [2]int,           // size limits; 0 for none
	largest:      [2]int,
	ratio:        f64,              // the shape it keeps when resized; 0 for any
	position:     [2]int,           // where it was asked to be (a headless window has no screen)
	cursor:       Cursor,           // the mouse cursor while the mouse is over it
	fingers:      [dynamic]Finger,  // the fingers down that went down in this window, in that order
}

Sketch :: struct {
	started:      bool,
	headless:     bool,
	failed:       bool,    // the graphics could not be started; the sketch runs headless
	error:        string,
	render_reported: bool, // a drawing failure has been said once
	app:          platform.App,
	renderer:     gfx.Renderer,
	windows:      [dynamic]^Win,
	closed:       [dynamic]^Win, // closed windows, freed with the sketch
	next_id:      int,
	next_finger:  int,     // the number the last finger to go down was given
	current:      ^Win,    // the window verbs draw into
	default:      ^Win,    // the window made when a verb needed one and there was none
	newest:       ^Win,    // the window the last `window` call made: verbs outside any block act on it
	focused:      ^Win,    // the window the mouse and keys are in
	quit:         bool,
	frame:        int,
	clock:        f64,     // seconds since the sketch began
	previous:     f64,
	delta:        f64,
	started_at:   time.Tick,
	stepped:      bool,    // the clock is driven by `step`, not by the wall
	rng:          maths.Rng,
	noise:        maths.Noise,
	seed:         u64,
	seed_chosen:  bool,    // by `seed`, or by the start-up when the program did not choose
	keys:         [512]bool, // by SDL scancode
	wheel:        [2]f64,   // scrolled during the last frame
	log:          [dynamic]Happened, // what happened in the frame in progress
	last_key:     string,
	hook:         proc(w: Window), // run for each window in each frame
	overlay_title: string, // what the error overlay says, or "" for none
	overlay_lines: [dynamic]string,
	reuse:        [dynamic]^Win, // windows of the last run a restart gives to the first `window` calls
	shot_app:     platform.App, // the graphics a headless sketch starts for its first picture
	shot_renderer: gfx.Renderer,
	shot_ready:   bool,
	cursor_shown: Cursor, // what the one cursor of the program is now
}

@(thread_local)
the: Sketch

// ---- starting and stopping ----

// Starts a sketch with no windows and no graphics: verbs record, nothing is shown.
// Used by tests, by the golden scenes and by the benchmark; `step` runs a frame.
start_headless :: proc(seed: u64 = 0) {
	shutdown()
	the.started, the.headless, the.stepped = true, true, true
	set_seed(seed)
}

// Starts the graphics, once. The first verb that needs a window calls this, so a
// sketch of one line works with nothing set up. When the
// graphics cannot start, the sketch carries on headless and `last_error` says why:
// a sketch never crashes.
start :: proc() -> bool {
	if the.started {
		return !the.failed
	}
	the.started = true
	the.started_at = time.tick_now()
	if !the.seed_chosen {
		set_seed(u64(time.to_unix_nanoseconds(time.now())))
	}
	if !platform.init(&the.app) {
		the.failed, the.headless = true, true
		the.error = strings.clone(the.app.error)
		fmt.eprintfln("rocinante: could not start the graphics: %s", the.app.error)
		delete(the.app.error)
		the.app.error = ""
		return false
	}
	gfx.renderer_init(&the.renderer, the.app.device)
	return true
}

// What went wrong when the sketch could not start its graphics, or "".
last_error :: proc() -> string {
	return the.error
}

// Closes every window and gives everything back. The sketch can be started again.
shutdown :: proc() {
	for w in the.windows {
		destroy_win(w)
	}
	delete(the.windows)
	for w in the.closed {
		destroy_win(w)
	}
	delete(the.closed)
	if the.started && !the.headless {
		gfx.renderer_destroy(&the.renderer)
		platform.shutdown(&the.app)
	}
	if the.shot_ready {
		gfx.renderer_destroy(&the.shot_renderer)
		platform.shutdown(&the.shot_app)
	}
	delete(the.log)
	set_overlay("", nil)
	delete(the.overlay_lines)
	delete(the.reuse)
	delete(the.error)
	the = {}
}

@(private)
destroy_win :: proc(w: ^Win) {
	gfx.destroy(&w.list)
	gfx.batcher_destroy(&w.batcher)
	delete(w.inbox)
	delete(w.title)
	delete(w.fingers)
	if w.handle != nil {
		platform.destroy_window(&the.app, w.handle)
	}
	free(w)
}

// ---- windows ----

// Makes a window of the given logical size, on screen unless headless.
@(private)
make_win :: proc(width, height: int, position: Maybe([2]int), title: string, flags := Window_Flags{}) -> ^Win {
	w := new(Win)
	w.alpha = 255
	w.hidden = flags.hidden
	the.next_id += 1
	w.id = Window(the.next_id)
	w.width, w.height = width if width > 0 else DEFAULT_WIDTH, height if height > 0 else DEFAULT_HEIGHT
	w.title = strings.clone(title)
	w.alive = true
	if p, has := position.?; has {
		w.position = p
	}
	if !the.headless {
		handle, ok := platform.create_window(&the.app, {title = title, width = w.width, height = w.height, position = position, resizable = true, hidden = flags.hidden})
		if !ok {
			the.error = strings.clone(the.app.error)
			fmt.eprintfln("rocinante: could not open a window: %s", the.app.error)
			delete(the.app.error)
			the.app.error = ""
			the.failed, the.headless = true, true
		}
		w.handle = handle
	}
	gfx.begin_frame(&w.list)
	append(&the.windows, w)
	return w
}

// The window verbs act on: the one whose block is running, else the one the last
// `window` call made (so `title` after `window` names that window, in reading
// order), else the default window, made now if there is none (a program of one
// line needs nothing else).
@(private)
current_win :: proc() -> ^Win {
	if the.current != nil {
		return the.current
	}
	if the.newest != nil {
		return the.newest
	}
	if the.default == nil && len(the.windows) > 0 {
		the.default = the.windows[0] // the default window closed; the first one left takes over
	}
	if the.default == nil {
		start()
		the.default = make_win(DEFAULT_WIDTH, DEFAULT_HEIGHT, nil, "rocinante")
	}
	return the.default
}

@(private)
win_for :: proc(id: Window) -> ^Win {
	for w in the.windows {
		if w.id == id {
			return w
		}
	}
	return nil
}

@(private)
win_for_platform :: proc(id: platform.Window_Id) -> ^Win {
	for w in the.windows {
		// A headless window has no operating-system window, and takes its own number
		// as the id of the events sent to it.
		if (w.handle != nil && w.handle.id == id) || (w.handle == nil && platform.Window_Id(w.id) == id) {
			return w
		}
	}
	return nil
}

// The list the drawing verbs record into.
@(private)
current_list :: proc() -> ^gfx.Command_List {
	return &current_win().list
}

// ---- the clock ----

// Seconds since the sketch began.
time_now :: proc() -> f64 {
	return the.clock
}

// How many frames have been drawn.
frame_count :: proc() -> int {
	return the.frame
}

// Frames per second, from the time the last frame took.
frame_rate :: proc() -> f64 {
	return 1 / the.delta if the.delta > 0 else 0
}

@(private)
set_seed :: proc(seed: u64) {
	the.seed, the.seed_chosen = seed, true
	the.rng = maths.rng_make(seed)
	the.noise = maths.noise_make(seed)
}
