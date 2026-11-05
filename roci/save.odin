// SPDX-License-Identifier: 0BSD
//
// `save`: a picture of a window, written as a PNG file. The picture is the finished
// frame the call was made in (it is taken once the frame is drawn, before the error
// overlay goes on), at the window's pixel density, so a sharp screen saves a sharp
// picture. A name with a run of `#` (`frame-####.png`) has it replaced by the frame's
// number, so a `save` in `draw` makes a frame sequence. Where the file goes is the
// caller's business: the path is used as it is and its folders are made; the language
// puts a plain name in the sketch's `output` folder.
package roci

import "core:math"
import "core:os"
import "core:strings"
import "gfx"
import "platform"

// A file that could not be written, and why, kept for the language to say.
Save_Problem :: struct {
	path: string,
	why:  string,
}

// Asks for a picture of the current window, saved as `path` once the frame is drawn.
// A run of `#` in the name is the frame number. Gives false, with `last_error` saying
// why, for a path that is not a PNG name or when there is no window.
save :: proc(path: string) -> bool {
	w := current_win()
	if w == nil {
		return false
	}
	if !is_png_name(path) {
		delete(the.error)
		the.error = strings.clone("only PNG files can be saved, so the name must end in .png")
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
		out[i] = Save_Problem{strings.clone(p.path, context.temp_allocator), strings.clone(p.why, context.temp_allocator)}
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
		if slash := strings.last_index_byte(path, '/'); slash > 0 {
			if err := os.make_directory_all(path[:slash]); err != nil && err != .Exist {
				note_save_problem(path, "its folder could not be made")
				continue
			}
		}
		if os.write_entire_file(path, png) != nil {
			note_save_problem(path, "the file could not be written")
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

@(private = "file")
note_save_problem :: proc(path, why: string) {
	append(&the.save_problems, Save_Problem{strings.clone(path), strings.clone(why)})
}
