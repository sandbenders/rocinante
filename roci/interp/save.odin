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
save_picture :: proc(it: ^Interp, e: ^lang.IR, name: string, in_sketch := false) {
	it.save_span = e.span
	example := "save \"shot.png\""
	if !roci.is_save_name(name) {
		fail(it, .Save_Failed, e.span, name, "I save PNG pictures, and SVG and PDF drawings, so the name has to end in `.png`, `.svg` or `.pdf`.", "", example)
		return
	}
	if !roci.save(save_path(it, name, in_sketch)) {
		fail(it, .Save_Failed, e.span, name, "There is no window to take a picture of.", "", example)
	}
}

// Where a name is saved: an absolute path as it is, anything else in the `output`
// folder of the sketch (beside the file for a lone one).
@(private)
save_path :: proc(it: ^Interp, name: string, in_sketch := false) -> string {
	if is_absolute_path(name) {
		return name
	}
	root, _ := assets_root(it)
	if in_sketch {
		// the sketch's own folder, which for a lone file is where it is run from
		return name if root == "" else strings.concatenate({root, "/", name}, context.temp_allocator)
	}
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

// `save picture "name.png"`: a picture or a canvas written as a PNG at its own size, at once, where a plain name goes in the
// `output` folder like the window's.
@(private)
save_image_file :: proc(it: ^Interp, e: ^lang.IR, picture: roci.Image, name: string, in_sketch := false) {
	example := "save (resize photo size 16 16) \"small.png\""
	if why := roci.save_image(picture, save_path(it, name, in_sketch)); why != "" {
		fail(it, .Save_Failed, e.span, name, strings.concatenate({"The picture could not be saved: ", why, "."}, context.temp_allocator), "", example)
	}
}
