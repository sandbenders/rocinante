// SPDX-License-Identifier: 0BSD
//
// `save "name.png"` and `save "name.svg"`: a picture of the window, or its shapes as a
// vector file, written once the frame is drawn (roci/save.odin). A plain name goes into
// the sketch's `output` folder, so renders never clutter the sketch, and an absolute path
// is used as it is. A file that could not be written is said on the next frame, because
// it is written after the frame.
package interp

import "../"
import "../lang"
import "core:strings"

@(private)
save_picture :: proc(it: ^Interp, e: ^lang.IR, name: string) {
	it.save_span = e.span
	example := "save \"shot.png\""
	if !roci.is_save_name(name) {
		fail(it, .Save_Failed, e.span, name, "I save PNG pictures and SVG drawings, so the name has to end in `.png` or `.svg`.", "", example)
		return
	}
	if !roci.save(save_path(it, name)) {
		fail(it, .Save_Failed, e.span, name, "There is no window to take a picture of.", "", example)
	}
}

// Where a name is saved: an absolute path as it is, anything else in the `output`
// folder of the sketch (beside the file for a lone one).
@(private)
save_path :: proc(it: ^Interp, name: string) -> string {
	if is_absolute_path(name) {
		return name
	}
	root, _ := assets_root(it)
	if root == "" {
		return strings.concatenate({"output/", name}, context.temp_allocator)
	}
	return strings.concatenate({root, "/output/", name}, context.temp_allocator)
}

@(private)
is_absolute_path :: proc(name: string) -> bool {
	if strings.has_prefix(name, "/") || strings.has_prefix(name, "\\") {
		return true
	}
	return len(name) > 2 && name[1] == ':' && (name[2] == '/' || name[2] == '\\') // C:\ on Windows
}

// Says what went wrong with the files the last frame asked for.
@(private)
say_save_problems :: proc(it: ^Interp) {
	for problem in roci.take_save_problems() {
		if problem.approximate {
			fail(it, .Save_Approximate, it.save_span, problem.path, problem.why, "", "save \"shot.png\"")
			continue
		}
		fail(it, .Save_Failed, it.save_span, problem.path, strings.concatenate({"The picture could not be saved: ", problem.why, "."}, context.temp_allocator), "", "save \"shot.png\"")
	}
}
