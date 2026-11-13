// SPDX-License-Identifier: 0BSD
//
// Drawings a sketch shows: `svg "logo.svg" at 20 20 size 200 100` finds the file by name in the sketch's
// `assets/` (folder.find_asset), reads it once (gfx.svg_read) and draws its shapes as paths. Like a picture or a
// model, a drawing is kept while its file is unchanged, so an `svg` in `draw` costs one look at the file's time a
// frame while the sketch is watched, and a file saved again is read again at once. A name nothing answers, an
// ambiguous one, and a file that is not an SVG each draw nothing and are said once; what a drawing has that
// cannot be drawn (text, pictures, clips, masks, filters, patterns) is said once as a warning.
package interp

import "../"
import "../folder"
import "../gfx"
import "../lang"
import "core:os"
import "core:strings"
import "core:time"

Svg_State :: enum u8 {
	Loaded,
	Missing,
	Ambiguous,
	Unreadable,
}

// What `svg` remembers about a name, on the heap.
Svg_Entry :: struct {
	state:   Svg_State,
	path:    string,
	drawing: ^gfx.Svg_Drawing,
	mtime:   time.Time,
	tried:   time.Tick,
	checked: int, // the frame the file's time was last compared with `mtime`
	others:  string,
	suggest: string,
	reason:  string,
	lost:    bit_set[gfx.Svg_Lost],
}

// The drawing the file `name` is, or nil. `span` is where to say what went wrong.
@(private)
load_svg :: proc(it: ^Interp, name: string, span: lang.Span) -> ^gfx.Svg_Drawing {
	entry, known := it.svgs[name]
	if known {
		if entry.state == .Loaded {
			frame := roci.frame_count()
			if it.path == "" || entry.checked == frame {
				return entry.drawing
			}
			info, err := os.stat(entry.path, context.temp_allocator)
			if err == nil && info.modification_time == entry.mtime {
				entry.checked = frame
				it.svgs[name] = entry
				return entry.drawing
			}
		} else if time.duration_seconds(time.tick_since(entry.tried)) < PICTURE_RETRY_SECONDS {
			say_svg_problem(it, name, entry, span)
			return nil
		}
	}
	fresh := read_svg(it, name)
	fresh.tried = time.tick_now()
	fresh.checked = roci.frame_count()
	store_svg(it, name, fresh)
	if fresh.state != .Loaded {
		say_svg_problem(it, name, fresh, span)
		return nil
	}
	if fresh.lost != {} {
		say_svg_lost(it, name, fresh, span)
	}
	return fresh.drawing
}

@(private)
read_svg :: proc(it: ^Interp, name: string) -> (entry: Svg_Entry) {
	root, _ := assets_root(it)
	if root == "" {
		entry.state = .Missing
		return
	}
	path, status, candidates := folder.find_asset(root, name, context.temp_allocator)
	#partial switch status {
	case .Missing:
		entry.state = .Missing
		return
	case .Ambiguous:
		entry.state = .Ambiguous
		entry.others = strings.join(candidates, " and ")
		entry.suggest = strings.clone(strings.trim_prefix(candidates[0], "assets/"))
		return
	}
	entry.path = strings.concatenate({root, "/", path})
	if info, err := os.stat(entry.path, context.temp_allocator); err == nil {
		entry.mtime = info.modification_time
	}
	bytes, read_err := os.read_entire_file(entry.path, context.temp_allocator)
	if read_err != nil {
		entry.state = .Unreadable
		entry.reason = strings.clone("the file cannot be read")
		return
	}
	drawing, error := gfx.svg_read(bytes)
	if error != .None {
		entry.state = .Unreadable
		entry.reason = strings.clone(gfx.svg_error_words(error))
		return
	}
	entry.drawing = new(gfx.Svg_Drawing)
	entry.drawing^ = drawing
	entry.lost = drawing.lost
	return
}

@(private)
store_svg :: proc(it: ^Interp, name: string, entry: Svg_Entry) {
	if it.svgs == nil {
		it.svgs = make(map[string]Svg_Entry)
	}
	if old, found := it.svgs[name]; found {
		free_svg_entry(old)
		it.svgs[name] = entry
		return
	}
	it.svgs[strings.clone(name)] = entry
}

@(private)
free_svg_entry :: proc(entry: Svg_Entry) {
	if entry.drawing != nil {
		drawing := entry.drawing
		gfx.svg_destroy(drawing)
		free(drawing)
	}
	delete(entry.path)
	delete(entry.others)
	delete(entry.suggest)
	delete(entry.reason)
}

@(private)
drop_svgs :: proc(it: ^Interp) {
	for name, entry in it.svgs {
		free_svg_entry(entry)
		delete(name)
	}
	delete(it.svgs)
	it.svgs = nil
}

@(private)
svg_example :: proc(name: string) -> string {
	return strings.concatenate({"svg \"", name, "\" at 0 0"}, context.temp_allocator)
}

@(private)
say_svg_problem :: proc(it: ^Interp, name: string, entry: Svg_Entry, span: lang.Span) {
	switch entry.state {
	case .Loaded:
	case .Missing:
		fail(it, .Svg_Missing, span, name, "Drawings are found by their file name in your sketch's `assets` folder, and there is no file of that name there. `roci add` copies one in for you.", "", svg_example(name))
	case .Ambiguous:
		fail(it, .Svg_Missing, span, name, strings.concatenate({"Two or more files have that name: ", entry.others, ". Say which one you mean with its folder."}, context.temp_allocator), "", svg_example(entry.suggest))
	case .Unreadable:
		fail(it, .Svg_Unreadable, span, name, entry.reason, "", svg_example(name))
	}
}

@(private)
say_svg_lost :: proc(it: ^Interp, name: string, entry: Svg_Entry, span: lang.Span) {
	parts := make([dynamic]string, context.temp_allocator)
	for part in entry.lost {
		switch part {
		case .Text:     append(&parts, "text")
		case .Picture:  append(&parts, "pictures")
		case .Gradient: append(&parts, "gradients (each is drawn in the first color of its stops)")
		case .Clip:     append(&parts, "clips")
		case .Mask:     append(&parts, "masks")
		case .Filter:   append(&parts, "filters")
		case .Pattern:  append(&parts, "patterns")
		case .Marker:   append(&parts, "markers")
		}
	}
	words := strings.concatenate({"The file has ", strings.join(parts[:], ", ", context.temp_allocator), ", which I cannot draw."}, context.temp_allocator)
	fail(it, .Svg_Lost, span, name, words, "", svg_example(name))
}

@(private)
svg_verb :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call) {
	name := as_text(eval(it, call.args[0]))
	drawing := load_svg(it, name, e.span)
	if drawing == nil {
		return
	}
	at: [2]f64
	size := [2]f64{f64(drawing.width), f64(drawing.height)}
	switch call.shape {
	case 0:
		at = {as_number(eval(it, call.args[1])), as_number(eval(it, call.args[2]))}
	case 1:
		at = as_pair(eval(it, call.args[1]))
	case 2:
		at = {as_number(eval(it, call.args[1])), as_number(eval(it, call.args[2]))}
		size = {as_number(eval(it, call.args[3])), as_number(eval(it, call.args[4]))}
	case 3:
		at = as_pair(eval(it, call.args[1]))
		size = as_pair(eval(it, call.args[2]))
	}
	roci.draw_svg(drawing, at.x, at.y, size.x, size.y)
}
