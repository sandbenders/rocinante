// SPDX-License-Identifier: 0BSD
//
// The progress of a long process (compiling a sketch, packaging an app, putting it on a phone), shown as a list of steps.
// On a terminal that shows colour the step that runs has its emoji, a spinner and its time ticking in place, and turns into
// a ✅ or ❌ with how long it took when it ends, so the finished steps stay on the screen as a checklist; a thread redraws the
// line about twelve times a second. Anywhere else (a pipe, a log, NO_COLOR) each step is a plain line when it starts and
// another when it ends, with no emoji and nothing redrawn, and the words are the same.
package term

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

// What a step does, which chooses its emoji.
Step_Kind :: enum {
	Compile,
	Bundle,
	Try,
	Phone,
	Install,
	Start,
	Fetch,
	Libraries,
	Sign,
	Check,
}

step_emoji :: proc(kind: Step_Kind) -> string {
	switch kind {
	case .Compile: return "🔨"
	case .Bundle: return "📦"
	case .Try: return "🧪"
	case .Phone: return "📱"
	case .Install: return "📲"
	case .Start: return "🚀"
	case .Fetch: return "🌐"
	case .Libraries: return "🧰"
	case .Sign: return "🔏"
	case .Check: return "🔍"
	}
	return "•"
}

SPINNER := [?]string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}

// The width the name of a step is padded to, so the times line up.
STEP_WIDTH :: 38

Progress :: struct {
	live:       bool, // the line of the running step is redrawn in place, with emojis and colour
	sink:       ^strings.Builder, // where it is written instead of standard output (the tests)
	started:    time.Tick,
	kind:       Step_Kind,
	text:       string,
	step_start: time.Tick,
	in_step:    bool,
	frame:      int,
	mutex:      sync.Mutex,
	stop:       bool,
	ticker:     ^thread.Thread,
}

// Starts a process called `title` (a sentence such as "Packaging Voyage 1.0.0 for Linux"), shown as live as standard output
// allows; `sink`, when given, is written to instead and nothing ticks, for the tests.
progress_begin :: proc(p: ^Progress, kind: Step_Kind, title: string, sink: ^strings.Builder = nil, live := false) {
	p^ = {}
	p.sink = sink
	p.live = live if sink != nil else out_colour
	p.started = time.tick_now()
	if p.live {
		write(p, fmt.tprintf("%s %s\n\n", step_emoji(kind), paint(title, .Bold, true)))
	} else {
		write(p, fmt.tprintf("%s\n", title))
	}
	if p.live && sink == nil {
		p.ticker = thread.create_and_start_with_poly_data(p, tick)
	}
}

// Ends the step that runs, if any, as done, and starts the next.
progress_step :: proc(p: ^Progress, kind: Step_Kind, text: string) {
	sync.mutex_lock(&p.mutex)
	defer sync.mutex_unlock(&p.mutex)
	end_step(p, true)
	p.kind = kind
	p.text = strings.clone(text, context.allocator)
	p.step_start = time.tick_now()
	p.in_step = true
	p.frame = 0
	if p.live {
		write(p, step_line(kind, p.text, 0, SPINNER[0], .Running, true))
	} else {
		write(p, fmt.tprintf("%s ...\n", p.text))
	}
}

// Ends the step that runs as failed, and the whole process with it; what went wrong is for the caller to say after.
progress_fail :: proc(p: ^Progress) {
	sync.mutex_lock(&p.mutex)
	end_step(p, false)
	sync.mutex_unlock(&p.mutex)
	stop_ticker(p)
	write(p, "\n" if p.live else "")
}

// Ends the step that runs as done and says the process is over, with its whole time: "Ready in 1 min 2 s". What it made is
// for the caller to list after, one `progress_result` a line.
progress_finish :: proc(p: ^Progress, word := "Ready") {
	sync.mutex_lock(&p.mutex)
	end_step(p, true)
	sync.mutex_unlock(&p.mutex)
	stop_ticker(p)
	total := fmt.tprintf("%s in %s", word, format_seconds(time.duration_seconds(time.tick_since(p.started))))
	if p.live {
		write(p, fmt.tprintf("\n  ✨ %s\n", paint(total, .Bold_Green, true)))
	} else {
		write(p, fmt.tprintf("%s\n", total))
	}
}

// A line under the end: what was made and a detail about it (a path and its size).
progress_result :: proc(p: ^Progress, name, detail: string) {
	if p.live {
		write(p, fmt.tprintf("     %s  %s\n", pad(name, 10), paint(detail, .Cyan, true)))
	} else {
		write(p, fmt.tprintf("%s  %s\n", pad(name, 10), detail))
	}
}

Step_State :: enum {
	Running,
	Done,
	Failed,
}

// One line of the list: the step's emoji (✅ or ❌ when it has ended), its name and its time, and the spinner while it runs.
step_line :: proc(kind: Step_Kind, text: string, seconds: f64, spinner: string, state: Step_State, colour: bool) -> string {
	mark := step_emoji(kind)
	switch state {
	case .Running:
	case .Done: mark = "✅"
	case .Failed: mark = "❌"
	}
	name := pad(text, STEP_WIDTH)
	when_ := fmt.tprintf("%8s", format_seconds(seconds))
	switch state {
	case .Running:
		return fmt.tprintf("  %s %s %s %s", mark, paint(name, .Bold, colour), paint(when_, .Dim, colour), paint(spinner, .Cyan, colour))
	case .Done:
		return fmt.tprintf("  %s %s %s", mark, name, paint(when_, .Dim, colour))
	case .Failed:
		return fmt.tprintf("  %s %s %s", mark, paint(name, .Red, colour), paint(when_, .Dim, colour))
	}
	return ""
}

// A time as people read it: "0.05 s", "48.2 s", "1 min 2 s"; under a second with two decimals, so a short step does not read
// as if it took nothing.
format_seconds :: proc(seconds: f64) -> string {
	s := max(seconds, 0)
	if s < 1 {
		return fmt.tprintf("%.2f s", s)
	}
	if s < 60 {
		return fmt.tprintf("%.1f s", s)
	}
	whole := int(s)
	return fmt.tprintf("%d min %d s", whole / 60, whole % 60)
}

// Draws the running step again with the next spinner frame and its time so far; the ticker calls it, and the tests do.
redraw :: proc(p: ^Progress) {
	sync.mutex_lock(&p.mutex)
	defer sync.mutex_unlock(&p.mutex)
	if !p.in_step || !p.live {
		return
	}
	p.frame += 1
	seconds := time.duration_seconds(time.tick_since(p.step_start))
	write(p, fmt.tprintf("\r\x1b[2K%s", step_line(p.kind, p.text, seconds, SPINNER[p.frame % len(SPINNER)], .Running, true)))
}

@(private)
end_step :: proc(p: ^Progress, ok: bool) {
	if !p.in_step {
		return
	}
	p.in_step = false
	seconds := time.duration_seconds(time.tick_since(p.step_start))
	if p.live {
		write(p, fmt.tprintf("\r\x1b[2K%s\n", step_line(p.kind, p.text, seconds, "", .Done if ok else .Failed, true)))
	} else if ok {
		write(p, fmt.tprintf("%s: done in %s\n", p.text, format_seconds(seconds)))
	} else {
		write(p, fmt.tprintf("%s: failed after %s\n", p.text, format_seconds(seconds)))
	}
	delete(p.text)
	p.text = ""
}

@(private)
tick :: proc(p: ^Progress) {
	for !sync.atomic_load(&p.stop) {
		time.sleep(80 * time.Millisecond)
		redraw(p)
	}
}

@(private)
stop_ticker :: proc(p: ^Progress) {
	if p.ticker == nil {
		return
	}
	sync.atomic_store(&p.stop, true)
	thread.join(p.ticker)
	thread.destroy(p.ticker)
	p.ticker = nil
}

@(private)
write :: proc(p: ^Progress, text: string) {
	if p.sink != nil {
		strings.write_string(p.sink, text)
		return
	}
	_, _ = os.write_string(os.stdout, text)
}
