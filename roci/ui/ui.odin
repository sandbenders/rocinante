// SPDX-License-Identifier: 0BSD
//
// The user interface of one window: a Dear ImGui context, the widgets rocinante offers
// as procedures, and a record of every widget a frame made (its role, label, value and
// place) for screen readers and tests. No sketch language here, and no window: a frame is
// built from the size, the density and the input events it is given, so everything but
// the drawing at the end runs headless. One window, one `State`; Dear ImGui keeps a
// current context of its own, so every procedure here makes its own current first.
package ui

import "core:os"
import "core:strings"

import imgui "../../vendor/imgui"
import sdl "vendor:sdl3"

import "../gfx"

Theme :: enum {
	Dark,
	Light,
}

Role :: enum {
	Label,
	Button,
	Toggle,
	Slider,
	Panel,
	Number,
	Textbox,
	Dropdown,
	Choice,
	Progress,
	Tab,
	Menu,
	Item,
	List,
	Colorpicker,
	Knob,
	Range,
	Xypad,
	Image_Button,
}

Rect :: struct {
	min, max: [2]f32, // logical pixels, from the window's top left
}

// What a widget was, for a screen reader or a test.
Record :: struct {
	role:     Role,
	label:    string, // owned by the state
	value:    f32,    // a slider's number, a toggle's 0 or 1
	text:     string, // a slider's number as shown, a text box's text, the item a dropdown shows; owned by the state
	tip:      string, // what `tip` says about it; owned by the state
	rect:     Rect,
	id:       u32,
	focused:  bool,
	hovered:  bool,
	active:   bool,   // held down
	changed:  bool,   // this frame
}

State :: struct {
	ctx:            ^imgui.Context,
	theme:          Theme,
	size:           [2]f32,
	density:        f32,
	in_frame:       bool,
	drawn:          bool, // the last finished frame has something to draw
	problems:       [dynamic]string, // said once each, for the sketch's writer
	records:        [dynamic]Record, // the frame being built
	finished:       [dynamic]Record, // the last frame built
	seen:           map[u32]bool,    // identities used this frame
	kinds:          map[string]Kept_Kind, // what each kept value is, for ui.toml (keyed like the kept maps)
	names:          map[string]string,    // the item a drop-down, radio group or list had chosen, by its text
	loaded:         map[string]Stored,    // what ui.toml said, taken as a widget is first made
	kept_vec:       map[string][4]f32, // what the colour, range and pad widgets hold, by their text
	kept_text:      map[string][]u8, // the text boxes' text, by their text: a zero-ended buffer of TEXT_BYTES
	path:           [dynamic]string, // the panels, tabs and menus the widgets being made are inside
	salt:           int,             // which time this call in the sketch has been made this frame (a loop), 0 for the first
	in_row:         bool,            // widgets go side by side
	row_first:      bool,            // the next widget is the first of its row
	bar_depth:      int,             // tab bars open
	bar_count:      int,             // tab bars made this frame
	fallbacks_added: bool,           // the system's fonts for other scripts have been added to the atlas
	target_scale:   f32,             // when above 0: device pixels to a logical pixel of the picture being made, whatever the density was
	kept:           map[string]f64,  // what the widgets that keep a value hold, by their text (a check box is 0 or 1)
	panel_open:     bool,
	panel_visible:  bool,
	panel_count:    int,
	// the SDL_GPU renderer backend, made when something is first drawn
	device:         ^sdl.GPUDevice,
	format:         sdl.GPUTextureFormat,
	backend_ready:  bool,
	themed:         bool, // the colors have been set for `theme`
}

BASE_FONT_SIZE :: 15

// Whether a text has anything outside ASCII, which Inter may not draw.
@(private)
beyond_ascii :: proc(text: string) -> bool {
	for b in transmute([]u8)text {
		if b >= 0x80 {
			return true
		}
	}
	return false
}

// Adds the system's fonts for other scripts (Chinese, Japanese, Korean, Arabic, Devanagari) to the
// font the interface draws with, once, the first time a text with anything but ASCII in it is typed
// or shown: they are big files, and most sketches never need them. Colour emoji fonts are left out,
// because Dear ImGui draws one colour only. The glyphs come from a font as they are first drawn.
@(private)
add_fallback_fonts :: proc(s: ^State) {
	if s.fallbacks_added {
		return
	}
	s.fallbacks_added = true
	use(s)
	atlas := imgui.get_io().fonts
	for file in gfx.FALLBACK_FONT_FILES {
		if strings.contains(file, "Emoji") || !os.exists(file) {
			continue
		}
		config := imgui.FontConfig {
			font_data_owned_by_atlas = true,
			extra_size_scale         = 1,
			glyph_max_advance_x      = 3.4028235e38,
			rasterizer_multiply      = 1,
			rasterizer_density       = 1,
			ellipsis_char            = 0xFFFF,
			merge_mode               = true,
		}
		imgui.font_atlas_add_font_from_file_ttf(atlas, cstr(file), BASE_FONT_SIZE, &config, nil)
	}
}

// Called with the text of every widget and everything typed.
@(private)
see_text :: proc(s: ^State, text: string) {
	if !s.fallbacks_added && beyond_ascii(text) {
		add_fallback_fonts(s)
	}
}

// A window's interface. `font` is a TrueType font that outlives the state (it is not copied).
create :: proc(font: []u8, theme := Theme.Dark) -> ^State {
	s := new(State)
	s.ctx = imgui.create_context()
	use(s)
	io := imgui.get_io()
	io.ini_filename = nil // no imgui.ini: remembered values are ui.toml's job
	io.config_flags |= imgui.ConfigFlags_NavEnableKeyboard
	// the renderer (if there is one) takes the font textures; without one, a frame still lays out
	io.backend_flags |= imgui.BackendFlags_RendererHasTextures
	config := imgui.FontConfig {
		font_data_owned_by_atlas = false,
		extra_size_scale         = 1,
		glyph_max_advance_x      = 3.4028235e38,
		rasterizer_multiply      = 1,
		rasterizer_density       = 1,
		ellipsis_char            = 0xFFFF,
	}
	copy(config.name[:], "Inter")
	imgui.font_atlas_add_font_from_memory_ttf(io.fonts, raw_data(font), i32(len(font)), BASE_FONT_SIZE, &config)
	platform_io := imgui.get_platform_io()
	platform_io.platform_get_clipboard_text_fn = clipboard_get
	platform_io.platform_set_clipboard_text_fn = clipboard_set
	s.theme = theme
	apply_theme(s)
	return s
}

destroy :: proc(s: ^State) {
	if s == nil {
		return
	}
	use(s)
	if s.backend_ready {
		imgui.gpu3_shutdown()
	}
	imgui.destroy_context(s.ctx)
	for r in s.records {
		free_record(r)
	}
	delete(s.records)
	for r in s.finished {
		free_record(r)
	}
	delete(s.finished)
	for p in s.problems {
		delete(p)
	}
	delete(s.problems)
	delete(s.seen)
	for key in s.kept {
		delete(key)
	}
	delete(s.kept)
	for key in s.kept_vec {
		delete(key)
	}
	delete(s.kept_vec)
	clear_persistence(s)
	delete(s.kinds)
	delete(s.names)
	delete(s.loaded)
	for part in s.path {
		delete(part)
	}
	delete(s.path)
	for key, buffer in s.kept_text {
		delete(key)
		delete(buffer)
	}
	delete(s.kept_text)
	free(s)
}

@(private)
free_record :: proc(r: Record) {
	delete(r.label)
	delete(r.text)
	delete(r.tip)
}

// Makes this window's context the one Dear ImGui's calls act on.
use :: proc(s: ^State) {
	imgui.set_current_context(s.ctx)
}

// The colors and shapes of rocinante's interface: Dear ImGui's own palettes with a rounder, quieter
// shape and one accent.
apply_theme :: proc(s: ^State) {
	use(s)
	style := imgui.get_style()
	if s.theme == .Dark {
		imgui.style_colors_dark(style)
	} else {
		imgui.style_colors_light(style)
	}
	style.window_rounding = 8
	style.frame_rounding = 6
	style.grab_rounding = 6
	style.popup_rounding = 6
	style.tab_rounding = 6
	style.window_border_size = 0
	style.frame_border_size = 0
	style.window_padding = {12, 10}
	style.frame_padding = {10, 6}
	style.item_spacing = {10, 8}
	style.font_size_base = BASE_FONT_SIZE
	s.themed = true
}

set_theme :: proc(s: ^State, theme: Theme) {
	if s.theme != theme || !s.themed {
		s.theme = theme
		apply_theme(s)
	}
}

// Said by the sketch's writer's own problems (two widgets with one identity); each is kept once.
problem :: proc(s: ^State, message: string) {
	for p in s.problems {
		if p == message {
			return
		}
	}
	append(&s.problems, strings.clone(message))
}

// Starts a frame for a window `size` logical pixels across, drawn at `density` device pixels
// to a logical one, `dt` seconds after the last. Widgets called before this are not allowed;
// `ensure_frame` is how they get a frame.
begin_frame :: proc(s: ^State, size: [2]f32, density, dt: f32) {
	use(s)
	if s.in_frame {
		end_frame(s)
	}
	s.size = size
	s.density = density
	io := imgui.get_io()
	io.display_size = size
	io.display_framebuffer_scale = {density, density}
	io.delta_time = max(dt, 1.0 / 1000)
	imgui.new_frame()
	s.in_frame = true
	s.panel_open = false
	s.panel_count = 0
	s.bar_count = 0
	s.in_row, s.row_first = false, false
	for part in s.path {
		delete(part)
	}
	clear(&s.path)
	clear(&s.seen)
	for r in s.records {
		free_record(r)
	}
	clear(&s.records)
}

// Finishes the frame: what it made is kept as `records` and its triangles are ready for `draw`.
end_frame :: proc(s: ^State) {
	if !s.in_frame {
		return
	}
	use(s)
	if s.panel_open {
		panel_end(s)
	}
	imgui.render()
	s.in_frame = false
	data := imgui.get_draw_data()
	s.drawn = data != nil && data.valid && data.cmd_lists_count > 0 && len(s.records) > 0
	// the finished frame's records replace the last ones
	for r in s.finished {
		free_record(r)
	}
	clear(&s.finished)
	append(&s.finished, ..s.records[:])
	clear(&s.records)
}

// Forgets what the last frame drew: used when a window's frame ran and made no widgets.
skip :: proc(s: ^State) {
	if s.in_frame {
		end_frame(s)
	}
	s.drawn = false
	for r in s.finished {
		free_record(r)
	}
	clear(&s.finished)
}

// The widgets of the last finished frame, in the order they were made.
records :: proc(s: ^State) -> []Record {
	return s.finished[:]
}
