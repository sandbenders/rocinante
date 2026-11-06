// SPDX-License-Identifier: 0BSD
//
// Fonts for real text. Faces are loaded once and shared; a face at a size (and a
// line alignment) is one SDL_ttf font, opened the first time it is asked for. The
// two faces every sketch has, Inter regular and bold, are inside the program
// (fonts/), so text needs no file and looks the same on every computer. Measuring
// text needs no GPU; drawing it is the renderer's (typeset.odin).
package gfx

import "base:runtime"
import "core:os"
import "core:strings"
import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

INTER_REGULAR :: #load("fonts/Inter-Regular.ttf")
INTER_BOLD :: #load("fonts/Inter-Bold.ttf")

// Face numbers a sketch can always use.
FACE_DEFAULT :: u16(0) // Inter regular
FACE_BOLD :: u16(1)

DEFAULT_FONT_SIZE :: f32(20)

Align :: enum u8 {
	Left,
	Center,
	Right,
}

Face :: struct {
	name:  string,
	index: int, // which font of the file this is, 0 unless the file is a collection
	data:  []u8, // kept alive for as long as the face is open
	io:    ^sdl.IOStream,
	base:  ^ttf.Font,
}

Font_Key :: struct {
	face:  u16,
	pixels: u32, // the size as a whole number of 64ths of a pixel
	align: Align,
	leading: u32, // the line spacing as a whole number of thousandths of the size; 0 is the font's own
}

// Fonts the system may have, tried in order to draw characters Inter has not (other
// scripts, emoji). They are used where they are installed and never copied, so a
// sketch shows those characters on the computers that have such a font and the
// empty box of a missing character on the ones that do not.
FALLBACK_FONT_FILES := [?]string{
	// macOS
	"/System/Library/Fonts/Hiragino Sans GB.ttc", "/System/Library/Fonts/AppleSDGothicNeo.ttc", "/System/Library/Fonts/GeezaPro.ttc",
	"/System/Library/Fonts/Kohinoor.ttc", "/System/Library/Fonts/Apple Color Emoji.ttc", "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
	// Windows
	"C:/Windows/Fonts/YuGothR.ttc", "C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/segoeui.ttf", "C:/Windows/Fonts/seguiemj.ttf",
	// Linux and the BSDs
	"/usr/share/fonts/noto/NotoSansCJK-Regular.ttc", "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
	"/usr/share/fonts/google-noto-cjk/NotoSansCJK-Regular.ttc", "/usr/local/share/fonts/noto/NotoSansCJK-Regular.ttc",
	"/usr/share/fonts/noto/NotoSansArabic-Regular.ttf", "/usr/share/fonts/noto/NotoSansDevanagari-Regular.ttf",
	"/usr/share/fonts/noto/NotoColorEmoji.ttf", "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf", "/usr/share/fonts/TTF/DejaVuSans.ttf",
	"/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
}

Fonts :: struct {
	started: bool,
	faces:   [dynamic]Face,
	fallbacks: [dynamic]^ttf.Font, // the system fonts added to the fonts made so far; closed with them
	fallback_paths: [dynamic]cstring,
	opened:  map[Font_Key]^ttf.Font,
}

// Fonts are not thread-safe in SDL_ttf, and tests run in parallel threads, so each
// thread has its own set. The app loop runs on one thread.
@(thread_local) fonts: Fonts

// Starts SDL_ttf and loads the two built-in faces, once for this thread. Gives
// false when SDL_ttf will not start.
fonts_start :: proc() -> bool {
	context.allocator = runtime.heap_allocator()
	if fonts.started {
		return len(fonts.faces) > 0
	}
	fonts.started = true
	if !ttf.Init() {
		return false
	}
	fonts.opened = make(map[Font_Key]^ttf.Font)
	find_fallbacks()
	ok := add_face_memory("Inter", INTER_REGULAR) && add_face_memory("Inter Bold", INTER_BOLD)
	if !ok {
		fonts_stop()
		fonts.started = true // not tried again
	}
	return ok
}

// Closes every font. The renderer's text cache must be dropped first.
fonts_stop :: proc() {
	context.allocator = runtime.heap_allocator()
	if !fonts.started {
		return
	}
	for _, font in fonts.opened {
		ttf.CloseFont(font)
	}
	delete(fonts.opened)
	for face in fonts.faces {
		ttf.CloseFont(face.base)
		sdl.CloseIO(face.io)
		if face.data != nil && raw_data(face.data) != raw_data(INTER_REGULAR) && raw_data(face.data) != raw_data(INTER_BOLD) {
			delete(face.data)
		}
		delete(face.name)
	}
	for fallback in fonts.fallbacks {
		ttf.CloseFont(fallback)
	}
	delete(fonts.fallbacks)
	for path in fonts.fallback_paths {
		delete(path)
	}
	delete(fonts.fallback_paths)
	delete(fonts.faces)
	fonts = {}
	ttf.Quit()
}

// Adds a face from bytes that stay alive (the built-in ones) or that this package
// now owns. Gives false when SDL_ttf cannot read them.
add_face_memory :: proc(name: string, data: []u8, index := 0) -> bool {
	context.allocator = runtime.heap_allocator()
	io := sdl.IOFromConstMem(raw_data(data), uint(len(data)))
	if io == nil {
		return false
	}
	base: ^ttf.Font
	if index == 0 {
		base = ttf.OpenFontIO(io, false, DEFAULT_FONT_SIZE)
	} else {
		// the font a collection holds at that place, which only the properties can ask for
		props := sdl.CreateProperties()
		defer sdl.DestroyProperties(props)
		sdl.SetPointerProperty(props, ttf.PROP_FONT_CREATE_IOSTREAM_POINTER, io)
		sdl.SetFloatProperty(props, ttf.PROP_FONT_CREATE_SIZE_FLOAT, DEFAULT_FONT_SIZE)
		sdl.SetNumberProperty(props, ttf.PROP_FONT_CREATE_FACE_NUMBER, i64(index))
		base = ttf.OpenFontWithProperties(props)
	}
	if base == nil {
		sdl.CloseIO(io)
		return false
	}
	append(&fonts.faces, Face{name = strings.clone(name), index = index, data = data, io = io, base = base})
	return true
}

// Adds a face from font file bytes (a sketch's `assets/fonts` file) and gives its
// number, or false when the bytes are not a font. The bytes are copied. `index` is which
// font of a collection to take (0 for the first, or for a plain font).
add_face :: proc(name: string, bytes: []u8, index := 0) -> (face: u16, ok: bool) {
	context.allocator = runtime.heap_allocator()
	if !fonts_start() {
		return 0, false
	}
	data := make([]u8, len(bytes))
	copy(data, bytes)
	if !add_face_memory(name, data, index) {
		delete(data)
		return 0, false
	}
	return u16(len(fonts.faces) - 1), true
}

// The number of the face with this name, or false. Names compare as written.
find_face :: proc(name: string) -> (face: u16, ok: bool) {
	if !fonts_start() {
		return 0, false
	}
	for f, i in fonts.faces {
		if f.name == name {
			return u16(i), true
		}
	}
	return 0, false
}

// The font for a face, a size in pixels and a line alignment, opened on first use.
font_for :: proc(face: u16, pixels: f32, align: Align, leading: f32 = 0) -> ^ttf.Font {
	context.allocator = runtime.heap_allocator()
	if !fonts_start() || int(face) >= len(fonts.faces) {
		return nil
	}
	key := Font_Key{face, u32(max(pixels, 1) * 64), align, u32(max(leading, 0) * 1000)}
	if font, found := fonts.opened[key]; found {
		return font
	}
	font := ttf.CopyFont(fonts.faces[face].base)
	if font == nil {
		return nil
	}
	ttf.SetFontSize(font, max(pixels, 1))
	ttf.SetFontWrapAlignment(font, ttf.HorizontalAlignment(int(align)))
	if leading > 0 {
		ttf.SetFontLineSkip(font, i32(max(leading * max(pixels, 1), 1) + 0.5))
	}
	add_fallbacks(font, max(pixels, 1))
	fonts.opened[key] = font
	return font
}

// How big a text is, in logical pixels, at a size, with lines broken where `wrap`
// says (0 for only where the text has line breaks). A text nobody can show gives 0.
measure_typeset :: proc(face: u16, size: f32, align: Align, text: string, wrap: f32 = 0, leading: f32 = 0) -> (width, height: f32) {
	font := font_for(face, size, align, leading)
	if font == nil || len(text) == 0 {
		return 0, 0
	}
	// The wrapped measure is the one that breaks lines at line breaks too, and with
	// a wrap width of 0 it breaks nowhere else.
	// emoji count as the em space they are drawn in place of (emoji.odin)
	swapped, _ := split_emoji(text, context.temp_allocator)
	w, h: i32
	if !ttf.GetStringSizeWrapped(font, raw_data(swapped), uint(len(swapped)), i32(max(wrap, 0)), &w, &h) {
		return 0, 0
	}
	return f32(w), f32(h)
}

// The fallback files this computer has, found once.
@(private)
find_fallbacks :: proc() {
	for file in FALLBACK_FONT_FILES {
		if os.exists(file) {
			append(&fonts.fallback_paths, strings.clone_to_cstring(file))
		}
	}
}

// Adds the system's fallback fonts to a font just made at a size. A fallback has to be
// the same size as the font it serves, so each font gets its own.
@(private)
add_fallbacks :: proc(font: ^ttf.Font, pixels: f32) {
	for path in fonts.fallback_paths {
		fallback := ttf.OpenFont(path, pixels)
		if fallback == nil {
			continue
		}
		if !ttf.AddFallbackFont(font, fallback) {
			ttf.CloseFont(fallback)
			continue
		}
		append(&fonts.fallbacks, fallback)
	}
}
