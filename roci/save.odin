// SPDX-License-Identifier: 0BSD
//
// `save`: a picture of a window, written as a PNG file, or, for a name ending in `.svg` or
// `.pdf`, the shapes of its frame written as a vector file (gfx/svg.odin, gfx/pdf.odin; what
// a vector file cannot say is drawn as the nearest thing and told to the caller as an
// approximate save). The
// picture is the finished frame the call was made in (it is taken once the frame is
// drawn, before the error overlay goes on), at the window's pixel density, so a sharp
// screen saves a sharp picture. A name with a run of `#` (`frame-####.png`) has it
// replaced by the frame's number, so a `save` in `draw` makes a frame sequence. Where the
// file goes is the caller's business: the path is used as it is and its folders are
// made; the language puts a plain name in the sketch's `output` folder.
package roci

import "core:math"
import "core:os"
import "core:strings"
import "gfx"
import "platform"

// A file that could not be written, or was written with parts left out, and why, kept for
// the language to say.
Save_Problem :: struct {
	path:        string,
	why:         string,
	approximate: bool, // the file is there, but something in it is not what the window shows
}

// Asks for a picture of the current window, saved as `path` once the frame is drawn: a
// PNG, or, for a name ending in `.svg`, the shapes of the frame as a vector file
// (gfx/svg.odin). A run of `#` in the name is the frame number. Gives false, with
// `last_error` saying why, for a path that is neither or when there is no window.
save :: proc(path: string) -> bool {
	w := current_win()
	if w == nil {
		return false
	}
	if !is_save_name(path) {
		delete(the.error)
		the.error = strings.clone("only PNG, SVG and PDF files can be saved, so the name must end in .png, .svg or .pdf")
		return false
	}
	append(&w.saves, expand_frame_pattern(path, the.frame, context.allocator))
	return true
}

// The files that could not be written since the last call, for the language to say.
// They are valid until the temporary allocator is freed.
take_save_problems :: proc() -> []Save_Problem {
	out := make([]Save_Problem, len(the.save_problems), context.temp_allocator)
	for p, i in the.save_problems {
		out[i] = Save_Problem{strings.clone(p.path, context.temp_allocator), strings.clone(p.why, context.temp_allocator), p.approximate}
		delete(p.path)
		delete(p.why)
	}
	clear(&the.save_problems)
	return out
}

// Does the name end in `.png`, in any case?
is_png_name :: proc(path: string) -> bool {
	return len(path) > 4 && strings.equal_fold(path[len(path) - 4:], ".png")
}

// Does the name end in `.pdf`, in any case?
is_pdf_name :: proc(path: string) -> bool {
	return len(path) > 4 && strings.equal_fold(path[len(path) - 4:], ".pdf")
}

// Does the name end in `.svg`, in any case?
is_svg_name :: proc(path: string) -> bool {
	return len(path) > 4 && strings.equal_fold(path[len(path) - 4:], ".svg")
}

// A name `save` takes: a PNG, an SVG or a PDF.
is_save_name :: proc(path: string) -> bool {
	return is_png_name(path) || is_svg_name(path) || is_pdf_name(path)
}

// The name with its first run of `#` replaced by the frame's number, written with at
// least as many digits as the run has (`frame-####.png` and frame 42 give
// `frame-0042.png`). A name with no `#` stays as it is.
expand_frame_pattern :: proc(path: string, frame: int, allocator := context.allocator) -> string {
	first := strings.index_byte(path, '#')
	if first < 0 {
		return strings.clone(path, allocator)
	}
	last := first
	for last < len(path) && path[last] == '#' {
		last += 1
	}
	digits := last - first
	number := frame_digits(frame, digits)
	return strings.concatenate({path[:first], number, path[last:]}, allocator)
}

@(private = "file")
frame_digits :: proc(frame, width: int) -> string {
	text := make([dynamic]u8, context.temp_allocator)
	n := max(frame, 0)
	for {
		append(&text, u8('0' + n % 10))
		n /= 10
		if n == 0 {
			break
		}
	}
	for len(text) < width {
		append(&text, '0')
	}
	for i in 0 ..< len(text) / 2 {
		text[i], text[len(text) - 1 - i] = text[len(text) - 1 - i], text[i]
	}
	return string(text[:])
}

// Writes the pictures a window was asked for. Its batches are built already.
@(private)
write_saves :: proc(w: ^Win) {
	scale := 1
	if w.handle != nil {
		scale = max(1, int(math.round(platform.window_metrics(w.handle).density)))
	}
	picture_taken := false
	image: gfx.Image
	for path in w.saves {
		if is_svg_name(path) || is_pdf_name(path) {
			bytes: []u8
			left_out: []string
			if is_pdf_name(path) {
				bytes, left_out = gfx.pdf_write(&w.list, w.width, w.height, context.temp_allocator)
			} else {
				svg: string
				svg, left_out = gfx.svg_write(&w.list, w.width, w.height, context.temp_allocator)
				bytes = transmute([]u8)svg
			}
			if why := write_file(path, bytes); why != "" {
				note_save_problem(path, why)
			} else if len(left_out) > 0 {
				note_save_problem(path, left_out_text(left_out), approximate = true)
			}
			continue
		}
		if !picture_taken {
			ok: bool
			image, ok = picture(w.id, scale)
			if !ok {
				note_save_problem(path, the.error if the.error != "" else "the picture could not be drawn")
				continue
			}
			picture_taken = true
		}
		png, encoded := gfx.png_encode(image, context.temp_allocator)
		if !encoded {
			note_save_problem(path, "the picture could not be turned into a PNG")
			continue
		}
		if why := write_file(path, png); why != "" {
			note_save_problem(path, why)
		}
	}
	if picture_taken {
		delete(image.pixels)
	}
	for path in w.saves {
		delete(path)
	}
	clear(&w.saves)
}

// Writes a file, making its folders. Gives why it could not, or "" when it did.
@(private = "file")
write_file :: proc(path: string, bytes: []u8) -> string {
	if slash := strings.last_index_byte(path, '/'); slash > 0 {
		if err := os.make_directory_all(path[:slash]); err != nil && err != .Exist {
			return "its folder could not be made"
		}
	}
	if os.write_entire_file(path, bytes) != nil {
		return "the file could not be written"
	}
	return ""
}

// What an SVG file leaves out, as one sentence's worth: "a, b and c".
@(private)
left_out_text :: proc(parts: []string) -> string {
	switch len(parts) {
	case 1:
		return parts[0]
	case 2:
		return strings.concatenate({parts[0], " and ", parts[1]}, context.temp_allocator)
	}
	return strings.concatenate({strings.join(parts[:len(parts) - 1], ", ", context.temp_allocator), " and ", parts[len(parts) - 1]}, context.temp_allocator)
}

@(private = "file")
note_save_problem :: proc(path, why: string, approximate := false) {
	append(&the.save_problems, Save_Problem{strings.clone(path), strings.clone(why), approximate})
}
