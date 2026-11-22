// SPDX-License-Identifier: 0BSD
//
// The app's icons, for every system, made from one picture: `icons/icon.svg` or `icons/icon.png` in the sketch's folder
// (`roci package --icon file` puts one there). The drawing is painted at each size, so every icon is sharp; a PNG, which
// must be at least 1024 pixels, is scaled down. Each system gets its shape: the Mac's rounded square at 824 of 1024 in
// the middle (macOS puts any other icon in a grey frame), Android's round icon and the layers of its adaptive one, and
// the picture as it is for the iPhone (which rounds it itself, and wants it with nothing see-through), Windows and Linux.
//
// The icons are kept in `icons/`, laid out by system, beside the picture, and committed with the sketch:
//
//     icons/macos/<name>.iconset/icon_16x16.png ...      the ten pictures of a Mac icon
//     icons/ios/AppIcon-1024.png
//     icons/windows/<name>-16.png ... <name>.ico
//     icons/freedesktop/hicolor/16x16/apps/<name>.png ...  Linux and the BSDs; scalable/apps/<name>.svg from a drawing
//     icons/android/play-store-512.png, res/mipmap-*/ic_launcher*.png, res/mipmap-anydpi-v26/*.xml
//
// A file there that roci did not make, or that was changed after roci made it, is the person's own and is used as it is
// and never written over: `icons/.made` keeps the sum of every file roci made, and of the picture they were made from, so
// a new picture remakes only roci's own. A sketch with no picture gets the rocinante logo, made where the package is
// made and never in the sketch's folder.
package main

import "../roci/folder"
import "../roci/gfx"
import "../tools/term"
import "core:crypto/hash"
import "core:encoding/hex"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

// The pictures icons are made from, looked for in this order.
ICON_SOURCES :: [?]string{"icon.svg", "icon.png"}

// Where the sums of what roci made are kept, in the icons folder.
ICON_RECORD :: ".made"

// The smallest a PNG may be: the largest icon (the Mac's and the iPhone's) is 1024 pixels.
ICON_MIN_PNG :: 1024

// The corner of Apple's and Android's rounded squares, as a part of the side.
ICON_CORNER :: 0.2237

ICON_WINDOWS_SIZES :: [?]int{16, 20, 24, 32, 40, 48, 64, 96, 128, 256}
ICON_LINUX_SIZES :: [?]int{16, 22, 24, 32, 48, 64, 96, 128, 192, 256, 512}

// How an icon is made from the picture.
Icon_Kind :: enum u8 {
	Full,           // the picture, edge to edge
	Opaque,         // the same over white, with nothing see-through (the iPhone's)
	Mac,            // the picture in the Mac's rounded square, 824 of 1024 in the middle
	Rounded,        // the picture in a rounded square to the edges (Android's older icon)
	Round,          // the picture in a circle (Android's round icon)
	Adaptive_Back,  // Android's adaptive background: the picture in the middle 72 of 108, its edges going on to the border
	Adaptive_Front, // Android's adaptive foreground: nothing, as the background holds the whole picture
	Ico,            // Windows' icon file, of its PNGs
	Scalable,       // the drawing itself, for Linux
	Text,           // a file of text, `text`
}

Icon_File :: struct {
	path: string, // in the icons folder
	size: int,
	kind: Icon_Kind,
	text: string,
}

ICON_ADAPTIVE_XML :: `<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
`

// Every file of the icons for an app whose files are called `name`, in the order they are made (an `.ico` after the
// PNGs it holds).
icon_files :: proc(name: string, allocator := context.temp_allocator) -> []Icon_File {
	files := make([dynamic]Icon_File, allocator)
	for pair in ([?]struct {
		file: string,
		size: int,
	}{{"16x16", 16}, {"16x16@2x", 32}, {"32x32", 32}, {"32x32@2x", 64}, {"128x128", 128}, {"128x128@2x", 256}, {"256x256", 256}, {"256x256@2x", 512}, {"512x512", 512}, {"512x512@2x", 1024}}) {
		append(&files, Icon_File{path = fmt.aprintf("macos/%s.iconset/icon_%s.png", name, pair.file, allocator = allocator), size = pair.size, kind = .Mac})
	}
	append(&files, Icon_File{path = "ios/AppIcon-1024.png", size = 1024, kind = .Opaque})
	for s in ICON_WINDOWS_SIZES {
		append(&files, Icon_File{path = fmt.aprintf("windows/%s-%d.png", name, s, allocator = allocator), size = s, kind = .Full})
	}
	for s in ICON_LINUX_SIZES {
		append(&files, Icon_File{path = fmt.aprintf("freedesktop/hicolor/%dx%d/apps/%s.png", s, s, name, allocator = allocator), size = s, kind = .Full})
	}
	append(&files, Icon_File{path = "android/play-store-512.png", size = 512, kind = .Full})
	for density in ([?]struct {
		name:  string,
		scale: f64,
	}{{"mdpi", 1}, {"hdpi", 1.5}, {"xhdpi", 2}, {"xxhdpi", 3}, {"xxxhdpi", 4}}) {
		folder := fmt.aprintf("android/res/mipmap-%s/", density.name, allocator = allocator)
		layer, launcher := int(108 * density.scale), int(48 * density.scale)
		append(&files, Icon_File{path = strings.concatenate({folder, "ic_launcher_background.png"}, allocator), size = layer, kind = .Adaptive_Back})
		append(&files, Icon_File{path = strings.concatenate({folder, "ic_launcher_foreground.png"}, allocator), size = layer, kind = .Adaptive_Front})
		append(&files, Icon_File{path = strings.concatenate({folder, "ic_launcher.png"}, allocator), size = launcher, kind = .Rounded})
		append(&files, Icon_File{path = strings.concatenate({folder, "ic_launcher_round.png"}, allocator), size = launcher, kind = .Round})
	}
	append(&files, Icon_File{path = "android/res/mipmap-anydpi-v26/ic_launcher.xml", kind = .Text, text = ICON_ADAPTIVE_XML})
	append(&files, Icon_File{path = "android/res/mipmap-anydpi-v26/ic_launcher_round.xml", kind = .Text, text = ICON_ADAPTIVE_XML})
	append(&files, Icon_File{path = fmt.aprintf("windows/%s.ico", name, allocator = allocator), kind = .Ico})
	append(&files, Icon_File{path = fmt.aprintf("freedesktop/scalable/apps/%s.svg", name, allocator = allocator), kind = .Scalable})
	return files[:]
}

// ---- the record of what roci made ----

Icon_Record :: struct {
	source: string, // the sum of the picture the icons were made from
	files:  map[string]string, // each file roci made, and its sum
}

// Reads `icons/.made`: a `source <sum>` line, then `<sum>  <path>` a line. Lines it does not know are passed over.
read_icon_record :: proc(text: string, allocator := context.temp_allocator) -> Icon_Record {
	record := Icon_Record{files = make(map[string]string, 64, allocator)}
	for line in strings.split_lines(text, context.temp_allocator) {
		trimmed := strings.trim_space(line)
		switch {
		case trimmed == "" || strings.has_prefix(trimmed, "#"):
		case strings.has_prefix(trimmed, "source "):
			record.source = strings.clone(strings.trim_space(trimmed[len("source "):]), allocator)
		case:
			space := strings.index(trimmed, "  ")
			if space > 0 {
				record.files[strings.clone(trimmed[space + 2:], allocator)] = strings.clone(trimmed[:space], allocator)
			}
		}
	}
	return record
}

write_icon_record :: proc(record: Icon_Record, source_name: string, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	fmt.sbprintf(&b, "# The icons roci package made from %s, with their sums. A file whose sum no longer matches was changed by\n# hand and is never written over; delete it to have it made again.\n", source_name)
	fmt.sbprintf(&b, "source %s\n", record.source)
	paths := make([dynamic]string, context.temp_allocator)
	for path in record.files {
		append(&paths, path)
	}
	slice.sort(paths[:])
	for path in paths {
		fmt.sbprintf(&b, "%s  %s\n", record.files[path], path)
	}
	return strings.to_string(b)
}

Icon_Action :: enum u8 {
	Make,  // missing, or roci's own made from another picture
	Keep,  // roci's own, made from this picture already
	Yours, // not made by roci, or changed since: used as it is
}

// What to do with one icon file.
plan_icon :: proc(exists: bool, current_sum: string, record: Icon_Record, path, source_sum: string) -> Icon_Action {
	if !exists {
		return .Make
	}
	recorded, known := record.files[path]
	if !known || recorded != current_sum {
		return .Yours
	}
	return .Keep if record.source == source_sum else .Make
}

sum_of :: proc(bytes: []byte) -> string {
	return string(hex.encode(hash.hash_bytes(.SHA256, bytes, context.temp_allocator), context.temp_allocator))
}

// ---- the picture ----

Icon_Source :: struct {
	name:    string, // as it is said: icons/icon.svg
	svg:     bool,
	bytes:   []byte,
	drawing: gfx.Svg_Drawing,
	picture: gfx.Image,
	contain: bool, // not square: drawn in the middle of a white square (the rocinante logo only)
}

icon_source_destroy :: proc(s: ^Icon_Source) {
	gfx.svg_destroy(&s.drawing)
	delete(s.picture.pixels)
	s^ = {}
}

// What the picture is said to leave out, in words: what an icon will not show of the drawing.
left_out_words :: proc(lost: bit_set[gfx.Svg_Lost]) -> []string {
	words := make([dynamic]string, context.temp_allocator)
	for kind in gfx.Svg_Lost {
		if kind not_in lost {
			continue
		}
		switch kind {
		case .Text:     append(&words, "text (turn it into paths)")
		case .Picture:  append(&words, "pictures inside it")
		case .Gradient: append(&words, "some gradients")
		case .Clip:     append(&words, "clips measured by their shape's box or clipped again")
		case .Mask:     append(&words, "masks")
		case .Filter:   append(&words, "filters")
		case .Pattern:  append(&words, "patterns")
		case .Marker:   append(&words, "markers")
		}
	}
	return words[:]
}

// Reads the picture icons are made from and says why it cannot be used, or what of it an icon leaves out. A PNG must be
// square and at least 1024 pixels; a drawing must be square (its view box, or its width and height).
read_icon_source :: proc(name: string, bytes: []byte, svg: bool) -> (source: Icon_Source, problem: string, left_out: []string) {
	source = Icon_Source{name = name, svg = svg, bytes = bytes}
	if svg {
		drawing, error := gfx.svg_read(bytes)
		if error != .None {
			return {}, fmt.tprintf("The icon `%s` cannot be used: %s.", name, gfx.svg_error_words(error)), nil
		}
		w, h := drawing.width, drawing.height
		if abs(w - h) > max(w, h) * 0.001 {
			gfx.svg_destroy(&drawing)
			return {}, fmt.tprintf("The icon `%s` is %v by %v (its view box), and an icon must be square: as tall as it is wide. Change its view box to a square, such as viewBox=\"0 0 1024 1024\", with the picture inside it.", name, w, h), nil
		}
		source.drawing = drawing
		return source, "", left_out_words(drawing.raster_lost)
	}
	data, ok := gfx.image_decode(bytes)
	if !ok {
		return {}, fmt.tprintf("The icon `%s` cannot be used: it is not a picture I can read. It should be a PNG, 1024 by 1024 pixels or more.", name), nil
	}
	if data.width != data.height {
		delete(data.pixels)
		return {}, fmt.tprintf("The icon `%s` is %d by %d pixels, and an icon must be square: as tall as it is wide. A PNG of 1024 by 1024 pixels or more is best, or an SVG drawing.", name, data.width, data.height), nil
	}
	if data.width < ICON_MIN_PNG {
		delete(data.pixels)
		return {}, fmt.tprintf("The icon `%s` is %d by %d pixels, and it must be at least %d by %d, so the largest icons (the Mac's and the iPhone's) are sharp. An SVG drawing is sharp at every size.", name, data.width, data.height, ICON_MIN_PNG, ICON_MIN_PNG), nil
	}
	source.picture = gfx.Image{width = data.width, height = data.height, pixels = data.pixels}
	return source, "", nil
}

// ---- making the icons ----

// Paints the picture into a rectangle of the raster.
@(private = "file")
draw_art :: proc(r: ^gfx.Raster, source: ^Icon_Source, x, y, w, h: f64) {
	if source.contain {
		// a white square, and the drawing in its middle, four fifths of it at most
		mask := gfx.raster_contour_mask(gfx.raster_rounded_rect(x, y, w, h, 0, context.temp_allocator), {1, 1, 0, 0}, true, r.width, r.height, context.temp_allocator)
		for &p, i in r.pixels {
			p = [4]f32{1, 1, 1, 1} * mask[i] + p * (1 - mask[i])
		}
		dw, dh := f64(source.drawing.width), f64(source.drawing.height)
		scale := min(w / dw, h / dh) * 0.8
		gfx.raster_svg(r, &source.drawing, x + (w - dw * scale) / 2, y + (h - dh * scale) / 2, dw * scale, dh * scale)
		return
	}
	if source.svg {
		gfx.raster_svg(r, &source.drawing, x, y, w, h)
	} else {
		gfx.raster_image(r, source.picture, x, y, w, h)
	}
}

// One icon of the picture, `size` pixels square, in the shape its kind says.
render_icon :: proc(source: ^Icon_Source, kind: Icon_Kind, size: int, allocator := context.allocator) -> gfx.Image {
	r := gfx.raster_make(size, size, context.temp_allocator)
	s := f64(size)
	place := gfx.Raster_Place{1, 1, 0, 0}
	#partial switch kind {
	case .Full, .Opaque:
		draw_art(&r, source, 0, 0, s, s)
		if kind == .Opaque {
			gfx.raster_flatten(&r, {255, 255, 255, 255})
		}
	case .Mac:
		inset, side := s * 100 / 1024, s * 824 / 1024
		draw_art(&r, source, inset, inset, side, side)
		gfx.raster_apply_mask(&r, gfx.raster_contour_mask(gfx.raster_rounded_rect(inset, inset, side, side, side * ICON_CORNER, context.temp_allocator), place, true, size, size, context.temp_allocator))
	case .Rounded:
		draw_art(&r, source, 0, 0, s, s)
		gfx.raster_apply_mask(&r, gfx.raster_contour_mask(gfx.raster_rounded_rect(0, 0, s, s, s * ICON_CORNER, context.temp_allocator), place, true, size, size, context.temp_allocator))
	case .Round:
		draw_art(&r, source, 0, 0, s, s)
		gfx.raster_apply_mask(&r, gfx.raster_contour_mask(gfx.raster_circle(s / 2, s / 2, s / 2, context.temp_allocator), place, true, size, size, context.temp_allocator))
	case .Adaptive_Back:
		x0, x1 := int(s * 18 / 108 + 0.5), int(s * 90 / 108 + 0.5)
		draw_art(&r, source, f64(x0), f64(x0), f64(x1 - x0), f64(x1 - x0))
		gfx.raster_extend(&r, x0, x0, x1, x1)
	}
	return gfx.raster_to_image(r, allocator)
}

// An `.ico` holding PNG pictures, as Windows reads them since Vista: a header, an entry for each picture, then the PNGs.
ico_encode :: proc(pngs: [][]byte, sizes: []int, allocator := context.temp_allocator) -> []byte {
	out := make([dynamic]byte, allocator)
	le16 :: proc(out: ^[dynamic]byte, v: int) {
		append(out, byte(v), byte(v >> 8))
	}
	le32 :: proc(out: ^[dynamic]byte, v: int) {
		append(out, byte(v), byte(v >> 8), byte(v >> 16), byte(v >> 24))
	}
	le16(&out, 0)
	le16(&out, 1) // an icon
	le16(&out, len(pngs))
	offset := 6 + 16 * len(pngs)
	for png, i in pngs {
		side := sizes[i]
		append(&out, byte(0 if side >= 256 else side), byte(0 if side >= 256 else side), 0, 0) // 256 is written as 0
		le16(&out, 1) // planes
		le16(&out, 32) // bits a pixel
		le32(&out, len(png))
		le32(&out, offset)
		offset += len(png)
	}
	for png in pngs {
		append(&out, ..png)
	}
	return out[:]
}

// What making the icons did, for the person to be told.
Icons :: struct {
	folder:   string, // where the package takes them from
	name:     string, // the files' name: the app's
	source:   string, // the picture they were made from, as it is said
	made:     int,
	kept:     [dynamic]string, // the person's own files, used as they are
	left_out: []string, // what the drawing has that the icons do not show
	logo:     bool, // there was no picture: the rocinante logo stood in
}

// Finds the picture (putting `flag`'s there first when it is given), makes the icons it lacks or that are out of date,
// and says where the package should take them from. False, with what is wrong said in `err`, when the picture cannot
// be used.
prepare_icons :: proc(sketch_folder, root, name, work, flag: string, err: ^strings.Builder) -> (icons: Icons, ok: bool) {
	icons.name = name
	icons.kept = make([dynamic]string, context.temp_allocator)
	own := strings.concatenate({sketch_folder, "/", folder.ICONS_FOLDER}, context.temp_allocator)
	if flag != "" && !put_icon_source(sketch_folder, own, flag, err) {
		return icons, false
	}
	source: Icon_Source
	defer icon_source_destroy(&source)
	for candidate in ICON_SOURCES {
		path := strings.concatenate({own, "/", candidate}, context.temp_allocator)
		bytes, read_err := os.read_entire_file(path, context.temp_allocator)
		if read_err != nil {
			continue
		}
		said := strings.concatenate({folder.ICONS_FOLDER, "/", candidate}, context.temp_allocator)
		problem: string
		source, problem, icons.left_out = read_icon_source(said, bytes, strings.has_suffix(candidate, ".svg"))
		if problem != "" {
			fmt.sbprintf(err, "%s\n", problem)
			return icons, false
		}
		icons.source = said
		break
	}
	icons.folder = own
	if icons.source == "" {
		// no picture: the rocinante logo, in a copy of the icons the sketch has, where the package is made
		logo, read_err := os.read_entire_file(strings.concatenate({root, "/docs/logo/rocinante-logo.svg"}, context.temp_allocator), context.temp_allocator)
		drawing, error := gfx.svg_read(logo)
		if read_err != nil || error != .None {
			fmt.sbprintf(err, "I cannot read rocinante's logo, which stands in for an icon the sketch does not have. Put a picture in %s/icon.svg or icon.png.\n", own)
			return icons, false
		}
		source = Icon_Source{name = "the rocinante logo", svg = true, bytes = logo, drawing = drawing, contain = true}
		icons.logo = true
		icons.folder = strings.concatenate({work, "/icons"}, context.temp_allocator)
		_ = os.remove_all(icons.folder)
		if os.is_directory(own) && !copy_files(own, icons.folder) {
			fmt.sbprintf(err, "I cannot copy the icons of %s into %s.\n", own, icons.folder)
			return icons, false
		}
	}
	record_path := strings.concatenate({icons.folder, "/", ICON_RECORD}, context.temp_allocator)
	record := Icon_Record{files = make(map[string]string, 64, context.temp_allocator)}
	if !icons.logo {
		if text, read_err := os.read_entire_file(record_path, context.temp_allocator); read_err == nil {
			record = read_icon_record(string(text))
		}
	}
	source_sum := sum_of(source.bytes)
	next := Icon_Record{source = source_sum, files = make(map[string]string, 64, context.temp_allocator)}
	for file in icon_files(name) {
		path := strings.concatenate({icons.folder, "/", file.path}, context.temp_allocator)
		current, read_err := os.read_entire_file(path, context.temp_allocator)
		exists := read_err == nil
		current_sum := sum_of(current) if exists else ""
		action := plan_icon(exists, current_sum, record, file.path, source_sum)
		if icons.logo && exists {
			action = .Yours // the logo never replaces what the sketch has
		}
		switch action {
		case .Yours:
			if !icons.logo || !strings.has_suffix(file.path, ".xml") {
				append(&icons.kept, file.path)
			}
			continue
		case .Keep:
			next.files[file.path] = current_sum
			continue
		case .Make:
		}
		bytes: []byte
		switch file.kind {
		case .Text:
			bytes = transmute([]byte)file.text
		case .Scalable:
			if !source.svg || source.contain {
				// no drawing to put there; one roci put there from an earlier drawing goes
				if exists {
					_ = os.remove(path)
				}
				continue
			}
			bytes = source.bytes
		case .Ico:
			pngs := make([dynamic][]byte, context.temp_allocator)
			sizes := make([dynamic]int, context.temp_allocator)
			for s in ICON_WINDOWS_SIZES {
				png, png_err := os.read_entire_file(fmt.tprintf("%s/windows/%s-%d.png", icons.folder, name, s), context.temp_allocator)
				if png_err == nil {
					append(&pngs, png)
					append(&sizes, s)
				}
			}
			bytes = ico_encode(pngs[:], sizes[:])
		case .Full, .Opaque, .Mac, .Rounded, .Round, .Adaptive_Back, .Adaptive_Front:
			img := render_icon(&source, file.kind, file.size, context.temp_allocator)
			png, encoded := gfx.png_encode(img, context.temp_allocator, .Adaptive)
			if !encoded {
				fmt.sbprintf(err, "I could not make the icon `%s`.\n", file.path)
				return icons, false
			}
			bytes = png
		}
		if os.make_directory_all(parent_of(path)) != nil && !os.is_directory(parent_of(path)) {
			fmt.sbprintf(err, "I cannot make the folder `%s`.\n", parent_of(path))
			return icons, false
		}
		if os.write_entire_file(path, bytes) != nil {
			fmt.sbprintf(err, "I cannot write the icon `%s`.\n", path)
			return icons, false
		}
		next.files[file.path] = sum_of(bytes)
		icons.made += 1
	}
	if !icons.logo && os.write_entire_file(record_path, transmute([]byte)write_icon_record(next, icons.source)) != nil {
		fmt.sbprintf(err, "I cannot write `%s`.\n", record_path)
		return icons, false
	}
	return icons, true
}

// Copies the files of a folder and of the folders in it into another, made as needed; links and the rest are passed over.
copy_files :: proc(from, to: string) -> bool {
	if os.make_directory_all(to) != nil && !os.is_directory(to) {
		return false
	}
	entries, read_err := os.read_all_directory_by_path(from, context.temp_allocator)
	if read_err != nil {
		return false
	}
	for entry in entries {
		source := strings.concatenate({from, "/", entry.name}, context.temp_allocator)
		target := strings.concatenate({to, "/", entry.name}, context.temp_allocator)
		#partial switch entry.type {
		case .Directory:
			if !copy_files(source, target) {
				return false
			}
		case .Regular:
			bytes, file_err := os.read_entire_file(source, context.temp_allocator)
			if file_err != nil || os.write_entire_file(target, bytes) != nil {
				return false
			}
		}
	}
	return true
}

// The folder a path is in.
parent_of :: proc(path: string) -> string {
	slash := strings.last_index_byte(path, '/')
	return path[:slash] if slash > 0 else "."
}

// Puts the picture `--icon` names into the icons folder as icon.svg or icon.png, after checking it, so the next package
// finds it there without being told; the other picture, if there was one, goes.
put_icon_source :: proc(sketch_folder, own, flag: string, err: ^strings.Builder) -> bool {
	path := flag
	if !strings.has_prefix(flag, "/") {
		path = strings.concatenate({sketch_folder, "/", flag}, context.temp_allocator)
		if !os.is_file(path) && os.is_file(flag) {
			path = flag // from where `roci package` was run
		}
	}
	lower := strings.to_lower(flag, context.temp_allocator)
	svg := strings.has_suffix(lower, ".svg")
	if !svg && !strings.has_suffix(lower, ".png") {
		fmt.sbprintf(err, "The icon `%s` should be an SVG drawing or a PNG picture (1024 by 1024 pixels or more).\n", flag)
		return false
	}
	bytes, read_err := os.read_entire_file(path, context.temp_allocator)
	if read_err != nil {
		fmt.sbprintf(err, "I cannot find the icon `%s`. It is looked for from the sketch's folder.\n", flag)
		return false
	}
	source, problem, _ := read_icon_source(flag, bytes, svg)
	icon_source_destroy(&source)
	if problem != "" {
		fmt.sbprintf(err, "%s\n", problem)
		return false
	}
	if os.make_directory_all(own) != nil && !os.is_directory(own) {
		fmt.sbprintf(err, "I cannot make the folder `%s`.\n", own)
		return false
	}
	target := strings.concatenate({own, "/", "icon.svg" if svg else "icon.png"}, context.temp_allocator)
	other := strings.concatenate({own, "/", "icon.png" if svg else "icon.svg"}, context.temp_allocator)
	if os.write_entire_file(target, bytes) != nil {
		fmt.sbprintf(err, "I cannot write `%s`.\n", target)
		return false
	}
	_ = os.remove(other)
	return true
}

// Tells what making the icons did, after the package is made: nothing when they were all there already.
say_icons :: proc(icons: Icons) {
	if icons.logo {
		picture := fmt.tprintf("a square SVG drawing, or a PNG of 1024 by 1024 pixels or more, in %s/icon.svg or icon.png (or give it with --icon)", folder.ICONS_FOLDER)
		switch {
		case len(icons.kept) == 0:
			fmt.println(term.out(fmt.tprintf("The app has rocinante's logo for an icon: put %s and package again.", picture), .Yellow))
		case icons.made > 0:
			fmt.println(term.out(fmt.tprintf("Used the %d icon files in %s/ as they are; the %d it lacks have rocinante's logo, in this package only. Put %s to have them made.", len(icons.kept), folder.ICONS_FOLDER, icons.made, picture), .Yellow))
		case:
			fmt.println(term.out(fmt.tprintf("Used the %d icon files in %s/ as they are.", len(icons.kept), folder.ICONS_FOLDER), .Dim))
		}
		return
	}
	if icons.made > 0 {
		fmt.println(term.out(fmt.tprintf("Made %d icon files from %s, in %s/ (commit them with the sketch).", icons.made, icons.source, folder.ICONS_FOLDER), .Dim))
	}
	if len(icons.kept) > 0 {
		fmt.println(term.out(fmt.tprintf("Kept %d icon files of your own, used as they are; delete one to have it made again:", len(icons.kept)), .Dim))
		for path, i in icons.kept {
			if i == 6 {
				fmt.println(term.out(fmt.tprintf("  and %d more", len(icons.kept) - 6), .Dim))
				break
			}
			fmt.println(term.out(fmt.tprintf("  %s/%s", folder.ICONS_FOLDER, path), .Dim))
		}
	}
	if len(icons.left_out) > 0 {
		fmt.println(term.out(fmt.tprintf("%s has things the icons cannot show, which are left out: %s.", icons.source, strings.join(icons.left_out, ", ", context.temp_allocator)), .Yellow))
	}
}
