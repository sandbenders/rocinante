// SPDX-License-Identifier: 0BSD
//
// Coloured terminal output for the build script and `roci` (output is for people). Colour is on only when the stream is a terminal, the
// terminal can show it and NO_COLOR is not set (Odin's core:terminal decides
// the last two); piped output, files and pipelines stay plain text, and the
// words are the same either way, so nothing depends on colour to be understood.
package term

import "core:fmt"
import "core:os"
import "core:strings"
import "core:terminal"
import "core:terminal/ansi"

Style :: enum {
	Bold,
	Dim,
	Red,
	Green,
	Yellow,
	Blue,
	Cyan,
	Bold_Red,
	Bold_Green,
	Bold_Cyan,
}

// Set once by `setup`, before any other thread starts, and only read after.
out_colour: bool
err_colour: bool

// Decides colour for standard output and standard error separately, since one
// can be piped while the other is a terminal.
setup :: proc() {
	out_colour = colour_for(os.stdout)
	err_colour = colour_for(os.stderr)
}

colour_for :: proc(f: ^os.File) -> bool {
	return terminal.color_enabled && terminal.is_terminal(f)
}

code :: proc(style: Style) -> string {
	switch style {
	case .Bold: return "1"
	case .Dim: return "2"
	case .Red: return ansi.FG_RED
	case .Green: return ansi.FG_GREEN
	case .Yellow: return ansi.FG_YELLOW
	case .Blue: return ansi.FG_BLUE
	case .Cyan: return ansi.FG_CYAN
	case .Bold_Red: return "1;" + ansi.FG_RED
	case .Bold_Green: return "1;" + ansi.FG_GREEN
	case .Bold_Cyan: return "1;" + ansi.FG_CYAN
	}
	return ansi.RESET
}

// Wraps text in the style's escape codes when `on`, and returns it untouched
// otherwise. The result lives in the temp allocator.
paint :: proc(text: string, style: Style, on: bool) -> string {
	if !on || text == "" {
		return text
	}
	return fmt.tprintf(ansi.CSI + "%s" + ansi.SGR + "%s" + ansi.CSI + ansi.RESET + ansi.SGR, code(style), text)
}

// `paint` for text going to standard output and standard error.
out :: proc(text: string, style: Style) -> string {
	return paint(text, style, out_colour)
}

err :: proc(text: string, style: Style) -> string {
	return paint(text, style, err_colour)
}

// Pads to a width before painting, because escape codes would count as
// characters. Text longer than the width is not cut.
pad :: proc(text: string, width: int) -> string {
	n := len(text)
	if n >= width {
		return text
	}
	return fmt.tprintf("%s%*s", text, width - n, "")
}

// Emoji marks for results. They follow the colour switch: a terminal that shows
// colour shows them, and piped output and logs stay plain text.
Icon :: enum {
	Ok,
	Cannot,
	Missing,
}

// The icon and a space, or nothing when `on` is false.
icon :: proc(i: Icon, on: bool) -> string {
	if !on {
		return ""
	}
	switch i {
	case .Ok: return "✅ "
	case .Cannot: return "🚫 "
	case .Missing: return "❌ "
	}
	return ""
}

out_icon :: proc(i: Icon) -> string {
	return icon(i, out_colour)
}

err_icon :: proc(i: Icon) -> string {
	return icon(i, err_colour)
}

// Paints an error message as `roci` writes it (a title line of dashes, the source
// line with its carets, an explanation and an example) so the parts can be told
// apart: the title in bold red (yellow for a warning, cyan for a hint), the carets
// in red, the label of the example in green and the example itself in green. The
// words are the same with or without colour, which is how pipes and the pipelines
// see them.
message :: proc(text: string, on: bool) -> string {
	if !on {
		return text
	}
	b := strings.builder_make(context.temp_allocator)
	for line, i in strings.split_lines(text, context.temp_allocator) {
		if i > 0 {
			strings.write_string(&b, "\n")
		}
		trimmed := strings.trim_left_space(line)
		switch {
		case strings.has_prefix(line, "── "):
			style := Style.Bold_Red
			if strings.has_prefix(line, "── Warning:") {
				style = .Yellow
			} else if strings.has_prefix(line, "── Hint:") {
				style = .Cyan
			}
			strings.write_string(&b, paint(line, style, true))
		case is_caret_line(line):
			strings.write_string(&b, paint(line, .Red, true))
		case strings.has_prefix(line, "    ") && trimmed != "":
			strings.write_string(&b, paint(line, .Green, true))
		case strings.contains(line, ":  ") && !strings.contains(line, "│"):
			at := strings.index(line, ":  ")
			strings.write_string(&b, paint(line[:at + 1], .Bold_Green, true))
			strings.write_string(&b, paint(line[at + 1:], .Green, true))
		case:
			strings.write_string(&b, line)
		}
	}
	return strings.to_string(b)
}

// The line under the source line that points at it: `  │   ^^^^`.
@(private)
is_caret_line :: proc(line: string) -> bool {
	bar := strings.index(line, "│")
	return bar >= 0 && strings.has_prefix(strings.trim_left_space(line[bar + len("│"):]), "^")
}

// Whether standard input is a terminal, so a question has someone to ask.
in_terminal :: proc() -> bool {
	return terminal.is_terminal(os.stdin)
}
