// SPDX-License-Identifier: 0BSD
//
// The error overlay: a band across the top of every window that says what is
// wrong, drawn over the last good frame and taken off again, so a sketch that has
// an error keeps running underneath it. Real text comes later; until then it is set
// in the built-in overlay font, which has printable ASCII only.
package roci

import "core:strings"
import "gfx"

OVERLAY_LINE :: 11   // pixels from one line of body text to the next
OVERLAY_TITLE :: 20  // and of the title, which is drawn twice as big
OVERLAY_GLYPH :: 8   // the width of one character at scale 1

// Shows `title` and the `lines` under it over every window, or takes the overlay
// away when the title is empty. The text is copied.
set_overlay :: proc(title: string, lines: []string) {
	delete(the.overlay_title)
	for l in the.overlay_lines {
		delete(l)
	}
	clear(&the.overlay_lines)
	the.overlay_title = ""
	if title == "" {
		return
	}
	the.overlay_title = strings.clone(title)
	for l in lines {
		append(&the.overlay_lines, strings.clone(l))
	}
}

// Is an overlay showing, and what does it say?
overlay_text :: proc() -> (title: string, lines: []string) {
	return the.overlay_title, the.overlay_lines[:]
}

// Cuts `text` into pieces of at most `columns` characters, at spaces where it can.
wrap_text :: proc(text: string, columns: int, allocator := context.temp_allocator) -> []string {
	out := make([dynamic]string, allocator)
	width := max(columns, 8)
	rest := text
	for len(rest) > width {
		cut := width
		for i := width; i > width / 2; i -= 1 {
			if rest[i] == ' ' {
				cut = i
				break
			}
		}
		append(&out, strings.trim_right_space(rest[:cut]))
		rest = strings.trim_left_space(rest[cut:])
	}
	append(&out, rest)
	return out[:]
}

// Draws the overlay into the window's list; the caller takes it off again with a mark.
@(private)
draw_overlay :: proc(w: ^Win) {
	list := &w.list
	columns := max((w.width - 24) / OVERLAY_GLYPH, 8)
	title := wrap_text(the.overlay_title, columns / 2)
	body := make([dynamic]string, context.temp_allocator)
	for l in the.overlay_lines {
		append(&body, ..wrap_text(l, columns))
	}
	height := 16 + len(title) * OVERLAY_TITLE + len(body) * OVERLAY_LINE
	gfx.push(list, .Style_And_Transform)
	list.transform = gfx.IDENTITY
	list.look_changed = true
	gfx.no_stroke(list)
	gfx.set_alpha(list, 255)
	gfx.set_fill(list, {24, 12, 14, 240})
	gfx.rect(list, 0, 0, f32(w.width), f32(height))
	gfx.set_fill(list, {220, 60, 60, 255})
	gfx.rect(list, 0, 0, f32(w.width), 4)
	y := f32(12)
	gfx.set_fill(list, {255, 255, 255, 255})
	for l in title {
		gfx.debug_text(list, l, 12, y, 2)
		y += OVERLAY_TITLE
	}
	gfx.set_fill(list, {225, 215, 215, 255})
	for l in body {
		gfx.debug_text(list, l, 12, y, 1)
		y += OVERLAY_LINE
	}
	gfx.pop(list)
}
