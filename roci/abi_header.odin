// SPDX-License-Identifier: 0BSD
//
// The C header (include/roci.h), generated from the verb registry. ABI_TABLE lists
// every C function and which registry verb and shape it is; the prototype of each
// is written from the registry's own parameter names and kinds, so a verb's
// signature lives in one place. Functions that are not a registry verb (the loop,
// messages, values, the `_grey` forms) carry their prototype here. Tests check the
// table against the registry and against the types of the exported procedures in
// abi.odin, and that the committed header is exactly what this generates;
// `odin run tools/header -- include/roci.h` writes it again.
package roci

import "base:runtime"
import "core:fmt"
import "core:strings"
import "registry"

Abi_Entry :: struct {
	c_name:    string,
	verb:      string, // the registry verb this is, or "" for a function of ours
	shape:     int,    // which of the verb's shapes
	procedure: typeid, // the type of the exported Odin procedure, for the checks
	prototype: string, // for a function of ours: its C parameters and result, "double (double x)"
	doc:       string, // for a function of ours
}

// Registry shapes that have no C function, and why.
Abi_Skip :: struct {
	verb:   string,
	shape:  int,
	reason: string,
}

ABI_NOT_IN_C := [?]Abi_Skip{
	{"gradient", 0, "takes a list of colors; C has roci_gradient, which gives a gradient number for roci_fill_gradient, roci_stroke_gradient and roci_background_gradient"},
	{"pick", 0, "takes a list; C has roci_pick_index, the place of a random item"},
	{"push", 0, "takes a block; C has roci_push and roci_pop"},
	{"random", 1, "`random from 1 to 3` is roci_random_between"},
	{"draw into", 0, "takes a block; C has roci_begin_into and roci_end_into"},
	{"light", 0, "takes a kind word and options; C has roci_light_ambient, roci_light_sun, roci_light_point and roci_light_spot"},
	{"material", 0, "takes optional words; C has roci_material with all three numbers"},
	{"model", 0, "takes a file name; C has roci_load_model, roci_model and roci_model_v"},
	{"model", 1, "takes a file name; C has roci_load_model, roci_model and roci_model_v"},
	{"forward", 1, "moves a sound by the seconds after `by`; C has roci_forward_sound"},
	{"synth", 1, "takes a file found in the assets; C has roci_soundfont and roci_soundfont_named, which read the file by its path"},
	{"bands", 0, "gives a list; C has roci_bands, which writes the numbers into the caller's array"},
	{"bands", 1, "gives a list; C has roci_bands, which writes the numbers into the caller's array"},
	{"bands", 2, "gives a list; C has roci_bands_of, which writes the numbers into the caller's array"},
	{"bands", 3, "gives a list; C has roci_bands_of, which writes the numbers into the caller's array"},
}

// The verbs only the language has (registry.LANGUAGE_VERBS) and the C functions that do their job; a verb with no function is one whose
// job C does with its own arrays and loops, and says so. A new language verb has to be listed here, so none is left out of C unnoticed.
Abi_Language :: struct {
	verb:      string,
	functions: string, // the C functions, separated by spaces, or ""
	reason:    string, // for a verb with none
}

ABI_LANGUAGE := [?]Abi_Language{
	{"add", "", "a list is a C array: C appends to its own"},
	{"remove", "", "a list is a C array: C removes from its own"},
	{"count", "", "a list is a C array: C knows its length"},
	{"item", "roci_item", ""},
	{"keep", "", "takes a block over a list: C has its own loops"},
	{"skip", "", "takes a block over a list: C has its own loops"},
	{"collect", "", "takes a block over a list: C has its own loops"},
	{"combine", "", "takes a block over a list: C has its own loops"},
	{"find", "", "takes a block over a list: C has its own loops"},
	{"sort", "", "takes a block over a list: C has qsort"},
	{"shuffle", "roci_shuffle", ""},
	{"copy", "", "a record or list is C's own memory: C copies it"},
	{"table", "", "a table is a map of text to values: C has its own"},
	{"put", "", "a table is a map of text to values: C has its own"},
	{"get", "", "a table is a map of text to values: C has its own"},
	{"keys", "", "a table is a map of text to values: C has its own"},
	{"effect", "roci_effect roci_builtin_effect roci_add_shader roci_update_shader roci_sound_effect roci_sound_effect_set roci_sound_effect_word", ""},
	{"no effect", "roci_no_sound_effect", ""},
	{"shade", "roci_shade roci_add_shader", ""},
	{"save", "roci_save", ""},
	{"record", "roci_record roci_record_sound roci_no_record", ""},
	{"no record", "roci_no_record roci_no_record_sound", ""},
	{"load", "roci_load_image roci_load_image_file roci_load_model roci_load_svg roci_load_sound roci_load_sound_file", ""},
	{"pixel", "roci_pixel", ""},
	{"pixels", "roci_pixels", ""},
	{"picture", "roci_picture_from_colors roci_picture_of_window", ""},
	{"crop", "roci_crop", ""},
	{"resize", "roci_resize", ""},
	{"filter", "roci_filter", ""},
	{"mask", "roci_mask", ""},
	{"outline", "roci_outline", ""},
	{"label", "roci_label", ""},
	{"button", "roci_button", ""},
	{"toggle", "roci_toggle", ""},
	{"slider", "roci_slider", ""},
	{"number", "roci_number", ""},
	{"textbox", "roci_textbox", ""},
	{"dropdown", "roci_dropdown", ""},
	{"choice", "roci_choice", ""},
	{"progress", "roci_progress", ""},
	{"separator", "roci_separator", ""},
	{"tip", "roci_tip", ""},
	{"colorpicker", "roci_colorpicker", ""},
	{"knob", "roci_knob", ""},
	{"range", "roci_range", ""},
	{"xypad", "roci_xypad", ""},
	{"image button", "roci_image_button", ""},
	{"ui hide", "roci_ui_hide", ""},
	{"ui show", "roci_ui_show", ""},
	{"ui key", "roci_ui_key", ""},
	{"ui theme", "roci_ui_theme", ""},
	{"forget ui", "roci_forget_ui", ""},
	{"panel", "roci_panel_begin roci_panel_end", ""},
	{"row", "roci_row_begin roci_row_end", ""},
	{"column", "roci_column_begin roci_column_end", ""},
	{"tabs", "roci_tabs_begin roci_tabs_end", ""},
	{"tab", "roci_tab_begin roci_tab_end", ""},
	{"menu", "roci_menu_begin roci_menu_end", ""},
	{"list", "roci_list", ""},
	{"set", "roci_set_title roci_set_size roci_set_position roci_set_window_flag roci_set_cursor roci_set_parent roci_set_sound_at roci_set_sound_volume roci_set_sound_pan roci_set_sound_speed roci_set_sound_loop roci_set_sound_pitch roci_play_note", ""},
	{"osc send", "roci_osc_send roci_osc_send_bundle", ""},
	{"midi note", "roci_midi_note", ""},
	{"midi release", "roci_midi_release", ""},
	{"midi set", "roci_midi_set", ""},
	{"midi bend", "roci_midi_bend", ""},
	{"midi program", "roci_midi_program", ""},
	{"midi to", "roci_midi_to", ""},
	{"midi outputs", "roci_midi_output_count roci_midi_output_name", ""},
	{"midi clock", "roci_midi_clock", ""},
	{"midi stop", "roci_midi_stop", ""},
	{"send", "roci_send roci_send_number roci_send_text roci_send_vec2 roci_send_boolean", ""},
	{"print", "roci_print", ""},
	{"held", "roci_held", ""},
	{"tween", "roci_tween roci_tween_vec2 roci_tween_vec3 roci_tween_color", ""},
	{"touching", "roci_touching", ""},
	{"contact", "roci_contact", ""},
	{"hits", "roci_hits roci_tree_hits", ""},
	{"inside", "roci_inside", ""},
	{"cast", "roci_cast roci_tree_cast", ""},
	{"ray", "roci_ray roci_ray_v", ""},
	{"triangles", "roci_triangles roci_triangles_v", ""},
	{"mesh", "roci_mesh", ""},
	{"svg", "roci_svg roci_svg_v roci_svg_sized roci_svg_sized_v roci_load_svg", ""},
}

// Filled when the program starts: `typeid_of` is not a constant, and a table this
// size built as a global initialiser makes LLVM unhappy.
ABI_TABLE: []Abi_Entry

@(init)
abi_table_init :: proc "contextless" () {
	context = runtime.default_context()
	entries := [?]Abi_Entry{
	{"roci_window", "window", 0, typeid_of(type_of(abi_window)), "", ""},
	{"roci_window_at", "", 0, typeid_of(type_of(abi_window_at)), "roci_window_id roci_window_at(double width, double height, double x, double y)", "Opens a window at a position on the screen and gives it back."},
	{"roci_title", "title", 0, typeid_of(type_of(abi_title)), "", ""},
	{"roci_fullscreen", "fullscreen", 0, typeid_of(type_of(abi_fullscreen)), "", ""},
	{"roci_quit", "quit", 0, typeid_of(type_of(abi_quit)), "", ""},
	{"roci_current_window", "", 0, typeid_of(type_of(abi_current_window)), "roci_window_id roci_current_window(void)", "The window the verbs are drawing into now."},
	{"roci_width", "", 0, typeid_of(type_of(abi_width)), "double roci_width(void)", "The width of the current window in logical pixels."},
	{"roci_height", "", 0, typeid_of(type_of(abi_height)), "double roci_height(void)", "The height of the current window in logical pixels."},
	{"roci_draw", "", 0, typeid_of(type_of(abi_draw)), "void roci_draw(roci_window_id window, roci_draw_fn block)", "Runs `block` every frame for a window (0 for the current one)."},
	{"roci_on_receive", "", 0, typeid_of(type_of(abi_on_receive)), "void roci_on_receive(roci_window_id window, roci_receive_fn handler)", "Runs `handler` for each message the window receives, on its next frame."},
	{"roci_send_number", "", 0, typeid_of(type_of(abi_send_number)), "void roci_send_number(roci_window_id to, double number)", "Sends a number to a window; it arrives on that window's next frame."},
	{"roci_send_text", "", 0, typeid_of(type_of(abi_send_text)), "void roci_send_text(roci_window_id to, const char *text)", "Sends text to a window; the text is copied."},
	{"roci_send_vec2", "", 0, typeid_of(type_of(abi_send_vec2)), "void roci_send_vec2(roci_window_id to, roci_vec2 point)", "Sends a point to a window."},
	{"roci_run", "", 0, typeid_of(type_of(abi_run)), "int roci_run(int frames)", "Shows the sketch until every window is closed, or for `frames` frames when that is more than 0. Gives 1 when it ran and 0 when the graphics could not start."},
	{"roci_background", "background", 0, typeid_of(type_of(abi_background)), "", ""},
	{"roci_background_image", "background", 1, typeid_of(type_of(abi_background_image)), "", ""},
	{"roci_background_image_as", "", 0, typeid_of(type_of(abi_background_image_as)), "void roci_background_image_as(roci_image_id picture, int fit, double tile, double at_x, double at_y)", "Paints the whole window with a picture, behind everything. `fit` is 0 cover, 1 fit, 2 stretch, 3 tile or 4 center; `tile` is the width of one copy for tile (0 is the picture's own size); `at_x` and `at_y` shift the picture for tile and center."},
	{"roci_background_gray", "", 0, typeid_of(type_of(abi_background_gray)), "void roci_background_gray(double value)", "Paints the whole window a gray, 0 to 255."},
	{"roci_clear", "clear", 0, typeid_of(type_of(abi_clear)), "", ""},
	{"roci_circle", "circle", 0, typeid_of(type_of(abi_circle)), "", ""},
	{"roci_circle_v", "circle", 1, typeid_of(type_of(abi_circle_v)), "", ""},
	{"roci_text", "text", 0, typeid_of(type_of(abi_text)), "", ""},
	{"roci_text_v", "text", 1, typeid_of(type_of(abi_text_v)), "", ""},
	{"roci_font", "font", 0, typeid_of(type_of(abi_font)), "", ""},
	{"roci_align", "align", 0, typeid_of(type_of(abi_align)), "", ""},
	{"roci_leading", "leading", 0, typeid_of(type_of(abi_leading)), "", ""},
	{"roci_measure", "measure", 0, typeid_of(type_of(abi_measure)), "", ""},
	{"roci_load_image", "", 0, typeid_of(type_of(abi_load_image)), "roci_image_id roci_load_image(const unsigned char *bytes, int length)", "Decodes the bytes of a picture file (PNG, JPEG, BMP, TGA or QOI) and gives its number, or 0 when they are not a picture."},
	{"roci_image_width", "", 0, typeid_of(type_of(abi_image_width)), "double roci_image_width(roci_image_id picture)", "How wide a picture is, in pixels (0 for no picture)."},
	{"roci_image_height", "", 0, typeid_of(type_of(abi_image_height)), "double roci_image_height(roci_image_id picture)", "How high a picture is, in pixels (0 for no picture)."},
	{"roci_image", "image", 0, typeid_of(type_of(abi_image)), "", ""},
	{"roci_image_v", "image", 1, typeid_of(type_of(abi_image_v)), "", ""},
	{"roci_image_sized", "image", 2, typeid_of(type_of(abi_image_sized)), "", ""},
	{"roci_image_sized_v", "image", 3, typeid_of(type_of(abi_image_sized_v)), "", ""},
	{"roci_canvas", "canvas", 0, typeid_of(type_of(abi_canvas)), "", ""},
	{"roci_begin_into", "", 0, typeid_of(type_of(abi_begin_into)), "int roci_begin_into(roci_image_id canvas)", "Draws onto a canvas from now on, until roci_end_into; gives 1, or 0 when the picture is not a canvas or one is being drawn into already."},
	{"roci_end_into", "", 0, typeid_of(type_of(abi_end_into)), "void roci_end_into(void)", "Goes back to drawing into the window."},
	{"roci_tint", "tint", 0, typeid_of(type_of(abi_tint)), "", ""},
	{"roci_font_size", "", 0, typeid_of(type_of(abi_font_size)), "void roci_font_size(double pixels)", "Sets the size of the text drawn from now on, in pixels."},
	{"roci_ellipse", "ellipse", 0, typeid_of(type_of(abi_ellipse)), "", ""},
	{"roci_ellipse_v", "ellipse", 1, typeid_of(type_of(abi_ellipse_v)), "", ""},
	{"roci_rect", "rect", 0, typeid_of(type_of(abi_rect)), "", ""},
	{"roci_rect_v", "rect", 1, typeid_of(type_of(abi_rect_v)), "", ""},
	{"roci_square", "square", 0, typeid_of(type_of(abi_square)), "", ""},
	{"roci_square_v", "square", 1, typeid_of(type_of(abi_square_v)), "", ""},
	{"roci_line", "line", 0, typeid_of(type_of(abi_line)), "", ""},
	{"roci_line_v", "line", 1, typeid_of(type_of(abi_line_v)), "", ""},
	{"roci_point", "point", 0, typeid_of(type_of(abi_point)), "", ""},
	{"roci_point_v", "point", 1, typeid_of(type_of(abi_point_v)), "", ""},
	{"roci_triangle", "triangle", 0, typeid_of(type_of(abi_triangle)), "", ""},
	{"roci_triangle_v", "triangle", 1, typeid_of(type_of(abi_triangle_v)), "", ""},
	{"roci_quad", "quad", 0, typeid_of(type_of(abi_quad)), "", ""},
	{"roci_quad_v", "quad", 1, typeid_of(type_of(abi_quad_v)), "", ""},
	{"roci_arc", "arc", 0, typeid_of(type_of(abi_arc)), "", ""},
	{"roci_debug_text", "", 0, typeid_of(type_of(abi_debug_text)), "void roci_debug_text(const char *text, double x, double y, double scale)", "Text in the built-in overlay font, in the fill color; whole-number scales look best."},
	{"roci_fill", "fill", 0, typeid_of(type_of(abi_fill)), "", ""},
	{"roci_fill_image", "fill", 1, typeid_of(type_of(abi_fill_image)), "", ""},
	{"roci_fill_image_as", "", 0, typeid_of(type_of(abi_fill_image_as)), "void roci_fill_image_as(roci_image_id picture, int fit, double tile, double at_x, double at_y)", "Fills with a picture. `fit` is 0 cover, 1 fit, 2 stretch, 3 tile or 4 center; `tile` is the width of one copy for tile (0 is the picture's own size); `at_x` and `at_y` shift the picture for tile and center."},
	{"roci_fill_gray", "", 0, typeid_of(type_of(abi_fill_gray)), "void roci_fill_gray(double value)", "Fills with a gray, 0 to 255, from now on."},
	{"roci_no_fill", "no fill", 0, typeid_of(type_of(abi_no_fill)), "", ""},
	{"roci_stroke", "stroke", 0, typeid_of(type_of(abi_stroke)), "", ""},
	{"roci_stroke_image", "stroke", 1, typeid_of(type_of(abi_stroke_image)), "", ""},
	{"roci_stroke_image_as", "", 0, typeid_of(type_of(abi_stroke_image_as)), "void roci_stroke_image_as(roci_image_id picture, int fit, double tile, double at_x, double at_y)", "Outlines with a picture. `fit` is 0 cover, 1 fit, 2 stretch, 3 tile or 4 center; `tile` is the width of one copy for tile (0 is the picture's own size); `at_x` and `at_y` shift the picture for tile and center."},
	{"roci_stroke_gray", "", 0, typeid_of(type_of(abi_stroke_gray)), "void roci_stroke_gray(double value)", "Outlines with a gray, 0 to 255, from now on."},
	{"roci_no_stroke", "no stroke", 0, typeid_of(type_of(abi_no_stroke)), "", ""},
	{"roci_thickness", "thickness", 0, typeid_of(type_of(abi_thickness)), "", ""},
	{"roci_alpha", "alpha", 0, typeid_of(type_of(abi_alpha)), "", ""},
	{"roci_caps", "caps", 0, typeid_of(type_of(abi_caps)), "", ""},
	{"roci_joins", "joins", 0, typeid_of(type_of(abi_joins)), "", ""},
	{"roci_blend", "blend", 0, typeid_of(type_of(abi_blend)), "", ""},
	{"roci_clip", "clip", 0, typeid_of(type_of(abi_clip)), "", ""},
	{"roci_clip_v", "clip", 1, typeid_of(type_of(abi_clip_v)), "", ""},
	{"roci_no_clip", "no clip", 0, typeid_of(type_of(abi_no_clip)), "", ""},
	{"roci_rgb", "rgb", 0, typeid_of(type_of(abi_rgb)), "", ""},
	{"roci_rgba", "", 0, typeid_of(type_of(abi_rgba)), "roci_color roci_rgba(double red, double green, double blue, double alpha)", "Makes a color with its own transparency, each channel 0 to 255."},
	{"roci_hsb", "hsb", 0, typeid_of(type_of(abi_hsb)), "", ""},
	{"roci_oklch", "oklch", 0, typeid_of(type_of(abi_oklch)), "", ""},
	{"roci_mix", "mix", 0, typeid_of(type_of(abi_mix)), "", ""},
	{"roci_mix_numbers", "mix", 1, typeid_of(type_of(abi_mix_numbers)), "", ""},
	{"roci_move", "move", 0, typeid_of(type_of(abi_move)), "", ""},
	{"roci_move_v", "move", 1, typeid_of(type_of(abi_move_v)), "", ""},
	{"roci_turn", "turn", 0, typeid_of(type_of(abi_turn)), "", ""},
	{"roci_grow", "grow", 0, typeid_of(type_of(abi_grow)), "", ""},
	{"roci_grow_xy", "grow", 1, typeid_of(type_of(abi_grow_xy)), "", ""},
	{"roci_shear", "shear", 0, typeid_of(type_of(abi_shear)), "", ""},
	{"roci_push", "", 0, typeid_of(type_of(abi_push)), "void roci_push(void)", "Saves the style, the transform and the turtle until the matching roci_pop."},
	{"roci_pop", "", 0, typeid_of(type_of(abi_pop)), "int roci_pop(void)", "Puts back what the matching roci_push saved. Gives 0 for a pop without a push."},
	{"roci_forward", "forward", 0, typeid_of(type_of(abi_forward)), "", ""},
	{"roci_back", "back", 0, typeid_of(type_of(abi_back)), "", ""},
	{"roci_left", "left", 0, typeid_of(type_of(abi_left)), "", ""},
	{"roci_right", "right", 0, typeid_of(type_of(abi_right)), "", ""},
	{"roci_pen_up", "pen up", 0, typeid_of(type_of(abi_pen_up)), "", ""},
	{"roci_pen_down", "pen down", 0, typeid_of(type_of(abi_pen_down)), "", ""},
	{"roci_home", "home", 0, typeid_of(type_of(abi_home)), "", ""},
	{"roci_show_turtle", "show turtle", 0, typeid_of(type_of(abi_show_turtle)), "", ""},
	{"roci_map", "map", 0, typeid_of(type_of(abi_map)), "", ""},
	{"roci_clamp", "clamp", 0, typeid_of(type_of(abi_clamp)), "", ""},
	{"roci_dist", "dist", 0, typeid_of(type_of(abi_dist)), "", ""},
	{"roci_dist_v", "dist", 1, typeid_of(type_of(abi_dist_v)), "", ""},
	{"roci_atan", "atan", 0, typeid_of(type_of(abi_atan)), "", ""},
	{"roci_atan_v", "atan", 1, typeid_of(type_of(abi_atan_v)), "", ""},
	{"roci_normalize", "normalize", 0, typeid_of(type_of(abi_normalize)), "", ""},
	{"roci_limit", "limit", 0, typeid_of(type_of(abi_limit)), "", ""},
	{"roci_abs", "abs", 0, typeid_of(type_of(abi_abs)), "", ""},
	{"roci_sqrt", "sqrt", 0, typeid_of(type_of(abi_sqrt)), "", ""},
	{"roci_floor", "floor", 0, typeid_of(type_of(abi_floor)), "", ""},
	{"roci_round", "round", 0, typeid_of(type_of(abi_round)), "", ""},
	{"roci_ceil", "ceil", 0, typeid_of(type_of(abi_ceil)), "", ""},
	{"roci_sin", "sin", 0, typeid_of(type_of(abi_sin)), "", ""},
	{"roci_cos", "cos", 0, typeid_of(type_of(abi_cos)), "", ""},
	{"roci_ease", "ease", 0, typeid_of(type_of(abi_ease)), "", ""},
	{"roci_ease_as", "", 0, typeid_of(type_of(abi_ease_as)), "double roci_ease_as(double amount, const char *curve)", "The same on a named curve: smooth, linear, in, out, back, elastic or bounce (any other name is smooth)."},
	{"roci_random", "random", 0, typeid_of(type_of(abi_random)), "", ""},
	{"roci_random_between", "", 0, typeid_of(type_of(abi_random_between)), "double roci_random_between(double low, double high)", "A random number from `low` up to `high`."},
	{"roci_gaussian", "gaussian", 0, typeid_of(type_of(abi_gaussian)), "", ""},
	{"roci_seed", "seed", 0, typeid_of(type_of(abi_seed)), "", ""},
	{"roci_noise", "noise", 0, typeid_of(type_of(abi_noise)), "", ""},
	{"roci_noise2", "noise", 1, typeid_of(type_of(abi_noise2)), "", ""},
	{"roci_noise3", "noise", 2, typeid_of(type_of(abi_noise3)), "", ""},
	{"roci_noise4", "noise", 3, typeid_of(type_of(abi_noise4)), "", ""},
	{"roci_fbm", "fbm", 0, typeid_of(type_of(abi_fbm)), "", ""},
	{"roci_box", "box", 0, typeid_of(type_of(abi_box)), "", ""},
	{"roci_box_sized", "box", 1, typeid_of(type_of(abi_box_sized)), "", ""},
	{"roci_box_v", "box", 2, typeid_of(type_of(abi_box_v)), "", ""},
	{"roci_box_sized_v", "box", 3, typeid_of(type_of(abi_box_sized_v)), "", ""},
	{"roci_sphere", "sphere", 0, typeid_of(type_of(abi_sphere)), "", ""},
	{"roci_sphere_v", "sphere", 1, typeid_of(type_of(abi_sphere_v)), "", ""},
	{"roci_plane", "plane", 0, typeid_of(type_of(abi_plane)), "", ""},
	{"roci_plane_v", "plane", 1, typeid_of(type_of(abi_plane_v)), "", ""},
	{"roci_cone", "cone", 0, typeid_of(type_of(abi_cone)), "", ""},
	{"roci_cone_v", "cone", 1, typeid_of(type_of(abi_cone_v)), "", ""},
	{"roci_cylinder", "cylinder", 0, typeid_of(type_of(abi_cylinder)), "", ""},
	{"roci_cylinder_v", "cylinder", 1, typeid_of(type_of(abi_cylinder_v)), "", ""},
	{"roci_capsule", "capsule", 0, typeid_of(type_of(abi_capsule)), "", ""},
	{"roci_capsule_v", "capsule", 1, typeid_of(type_of(abi_capsule_v)), "", ""},
	{"roci_torus", "torus", 0, typeid_of(type_of(abi_torus)), "", ""},
	{"roci_torus_v", "torus", 1, typeid_of(type_of(abi_torus_v)), "", ""},
	{"roci_icosphere", "icosphere", 0, typeid_of(type_of(abi_icosphere)), "", ""},
	{"roci_icosphere_v", "icosphere", 1, typeid_of(type_of(abi_icosphere_v)), "", ""},
	{"roci_grid", "grid", 0, typeid_of(type_of(abi_grid)), "", ""},
	{"roci_axes", "axes", 0, typeid_of(type_of(abi_axes)), "", ""},
	{"roci_arrow", "arrow", 0, typeid_of(type_of(abi_arrow)), "", ""},
	{"roci_arrow_v", "arrow", 1, typeid_of(type_of(abi_arrow_v)), "", ""},
	{"roci_mesh", "", 0, typeid_of(type_of(abi_mesh)), "void roci_mesh(const char *key, const roci_vec3 *corners, int count, int wireframe)", "Draws a mesh of triangles: `corners` holds `count` corners, three for each triangle, in the coordinates of the moment, flat shaded in the fill; with `wireframe` 1 only the feature edges are drawn, as tubes as wide as the thickness. `key` names the call that draws it, so a list drawn again unchanged is sent to the graphics card once."},
	{"roci_load_model", "", 0, typeid_of(type_of(abi_load_model)), "roci_model_id roci_load_model(const char *path)", "Reads a glTF (.glb or .gltf) or OBJ model from a file, with the pictures and data it names beside it, and gives its number, or 0 when it cannot be read. The same file read again, unchanged, gives the same number."},
	{"roci_model", "", 0, typeid_of(type_of(abi_model)), "void roci_model(roci_model_id model, double x, double y, double z, double size)", "Draws a loaded model with its middle at a point and its longest side `size` long, in the colors and pictures of its own materials."},
	{"roci_model_v", "", 0, typeid_of(type_of(abi_model_v)), "void roci_model_v(roci_model_id model, roci_vec3 position, double size)", "The same at a point given as a vector."},
	{"roci_camera", "camera", 0, typeid_of(type_of(abi_camera)), "", ""},
	{"roci_camera_v", "camera", 1, typeid_of(type_of(abi_camera_v)), "", ""},
	{"roci_camera_fov", "", 0, typeid_of(type_of(abi_camera_fov)), "void roci_camera_fov(double x, double y, double z, double fov)", "Puts the eye of the 3D camera at a point, as roci_camera does, seeing `fov` degrees wide (50 to start with)."},
	{"roci_look_at", "look at", 0, typeid_of(type_of(abi_look_at)), "", ""},
	{"roci_look_at_v", "look at", 1, typeid_of(type_of(abi_look_at_v)), "", ""},
	{"roci_ortho", "ortho", 0, typeid_of(type_of(abi_ortho)), "", ""},
	{"roci_perspective", "perspective", 0, typeid_of(type_of(abi_perspective)), "", ""},
	{"roci_perspective_fov", "", 0, typeid_of(type_of(abi_perspective_fov)), "void roci_perspective_fov(double fov)", "Draws the 3D scene with perspective again, seeing `fov` degrees wide."},
	{"roci_screen_point", "screen point", 0, typeid_of(type_of(abi_screen_point)), "", ""},
	{"roci_screen_point_v", "screen point", 1, typeid_of(type_of(abi_screen_point_v)), "", ""},
	{"roci_world_point", "world point", 0, typeid_of(type_of(abi_world_point)), "", ""},
	{"roci_world_point_v", "world point", 1, typeid_of(type_of(abi_world_point_v)), "", ""},
	{"roci_light_ambient", "", 0, typeid_of(type_of(abi_light_ambient)), "int roci_light_ambient(roci_color color)", "Adds an ambient light of a color to the 3D scene. The first light of a frame takes the usual lights away. Gives 0 when the scene already has as many lights as it can hold."},
	{"roci_light_sun", "", 0, typeid_of(type_of(abi_light_sun)), "int roci_light_sun(double x, double y, double z, roci_color color)", "Adds a sun: light from the direction x, y, z (the direction towards the sun, in the world, y down). Gives 0 when the scene has no room."},
	{"roci_light_point", "", 0, typeid_of(type_of(abi_light_point)), "int roci_light_point(double x, double y, double z, roci_color color, double falloff)", "Adds a point light at a place, weaker the further away: `falloff` is the distance at which it has dropped to half (500 is usual). Gives 0 when the scene has no room."},
	{"roci_light_spot", "", 0, typeid_of(type_of(abi_light_spot)), "int roci_light_spot(double x, double y, double z, double to_x, double to_y, double to_z, double angle, roci_color color, double falloff)", "Adds a spot light at a place, aimed at another, inside a cone of half `angle` degrees (30 is usual). Gives 0 when the scene has no room."},
	{"roci_no_lights", "no lights", 0, typeid_of(type_of(abi_no_lights)), "", ""},
	{"roci_material", "", 0, typeid_of(type_of(abi_material)), "void roci_material(double metallic, double roughness, double emissive)", "Sets what the 3D shapes drawn from now on are made of: `metallic` 0 for paint up to 1 for metal, `roughness` 0 for a mirror up to 1 for chalk, and `emissive` how much of their color they give off by themselves."},
	{"roci_shadows", "shadows", 0, typeid_of(type_of(abi_shadows)), "", ""},
	{"roci_move_xyz", "move", 2, typeid_of(type_of(abi_move_xyz)), "", ""},
	{"roci_move_v3", "", 0, typeid_of(type_of(abi_move_v3)), "void roci_move_v3(roci_vec3 offset)", "Moves the 3D shapes drawn after it, by a vector of three numbers."},
	{"roci_grow_xyz", "grow", 2, typeid_of(type_of(abi_grow_xyz)), "", ""},
	{"roci_turn_about", "", 0, typeid_of(type_of(abi_turn_about)), "void roci_turn_about(double degrees, const char *axis)", "Turns the 3D shapes drawn after it about an axis, \"x\", \"y\" or \"z\", in degrees: clockwise seen from the end of the axis."},
	{"roci_turtle_space", "turtle space", 0, typeid_of(type_of(abi_turtle_space)), "", ""},
	{"roci_up", "up", 0, typeid_of(type_of(abi_up)), "", ""},
	{"roci_down", "down", 0, typeid_of(type_of(abi_down)), "", ""},
	{"roci_roll", "roll", 0, typeid_of(type_of(abi_roll)), "", ""},
	{"roci_play", "play", 0, typeid_of(type_of(abi_play)), "", ""},
	{"roci_loop", "loop", 0, typeid_of(type_of(abi_loop)), "", ""},
	{"roci_pause", "pause", 0, typeid_of(type_of(abi_pause)), "", ""},
	{"roci_rewind", "rewind", 0, typeid_of(type_of(abi_rewind)), "", ""},
	{"roci_level", "level", 0, typeid_of(type_of(abi_level)), "", ""},
	{"roci_synth", "synth", 0, typeid_of(type_of(abi_synth)), "", ""},
	{"roci_midi_control", "midi control", 0, typeid_of(type_of(abi_midi_control)), "", ""},
	{"roci_midi_tempo", "midi tempo", 0, typeid_of(type_of(abi_midi_tempo)), "", ""},
	{"roci_osc_listen", "osc listen", 0, typeid_of(type_of(abi_osc_listen)), "", ""},
	{"roci_osc_value", "osc value", 0, typeid_of(type_of(abi_osc_value)), "", ""},
	{"roci_level_of", "level", 1, typeid_of(type_of(abi_level_of)), "", ""},
	{"roci_ray", "", 0, typeid_of(type_of(abi_ray)), "roci_line3 roci_ray(double x, double y)", "The line from the eye of the 3D camera through a pixel of the window: `from` is the eye and `to` is far along the way the pixel looks, in the world."},
	{"roci_ray_v", "", 0, typeid_of(type_of(abi_ray_v)), "roci_line3 roci_ray_v(roci_vec2 pixel)", "The same for a pixel given as a point, such as the mouse."},
	{"roci_triangles", "", 0, typeid_of(type_of(abi_triangles)), "int roci_triangles(roci_model_id model, double x, double y, double z, double size, roci_vec3 *corners, int capacity)", "The corners of a loaded model's triangles, three for each, placed and sized as roci_model draws it. Copies up to `capacity` corners into `corners` (which may be NULL) and gives how many there are in all, so a first call with capacity 0 says how big an array to make."},
	{"roci_triangles_v", "", 0, typeid_of(type_of(abi_triangles_v)), "int roci_triangles_v(roci_model_id model, roci_vec3 position, double size, roci_vec3 *corners, int capacity)", "The same at a point given as a vector."},
	{"roci_load_svg", "", 0, typeid_of(type_of(abi_load_svg)), "roci_svg_id roci_load_svg(const char *path)", "Reads an SVG drawing from a file and gives its number, or 0 when it cannot be read. The same file read again, unchanged, gives the same number; saved again, it is read again under it."},
	{"roci_svg", "", 0, typeid_of(type_of(abi_svg)), "void roci_svg(roci_svg_id drawing, double x, double y)", "Draws an SVG drawing with its top left at a point, at its own size, in its own colors, under the current transform."},
	{"roci_svg_v", "", 0, typeid_of(type_of(abi_svg_v)), "void roci_svg_v(roci_svg_id drawing, roci_vec2 position)", "The same at a point given as a vector."},
	{"roci_svg_sized", "", 0, typeid_of(type_of(abi_svg_sized)), "void roci_svg_sized(roci_svg_id drawing, double x, double y, double width, double height)", "Draws an SVG drawing stretched to a width and a height."},
	{"roci_svg_sized_v", "", 0, typeid_of(type_of(abi_svg_sized_v)), "void roci_svg_sized_v(roci_svg_id drawing, roci_vec2 position, roci_vec2 size)", "The same with the point and the size given as vectors."},
	{"roci_svg_width", "", 0, typeid_of(type_of(abi_svg_width)), "double roci_svg_width(roci_svg_id drawing)", "How wide a drawing is in its own units (0 for no drawing)."},
	{"roci_svg_height", "", 0, typeid_of(type_of(abi_svg_height)), "double roci_svg_height(roci_svg_id drawing)", "How high a drawing is in its own units (0 for no drawing)."},
	{"roci_svg_lost", "", 0, typeid_of(type_of(abi_svg_lost)), "int roci_svg_lost(roci_svg_id drawing)", "What the drawing has that cannot be drawn, as bits: 1 text, 2 pictures, 4 gradients (drawn in the first color of their stops), 8 clips, 16 masks, 32 filters, 64 patterns, 128 markers."},
	{"roci_mouse", "", 0, typeid_of(type_of(abi_mouse)), "roci_vec2 roci_mouse(void)", "Where the mouse is in the current window, in logical pixels."},
	{"roci_pmouse", "", 0, typeid_of(type_of(abi_pmouse)), "roci_vec2 roci_pmouse(void)", "Where the mouse was one frame ago."},
	{"roci_mouse_down", "", 0, typeid_of(type_of(abi_mouse_down)), "int roci_mouse_down(void)", "1 while the left mouse button is down, in the current window."},
	{"roci_key_down", "", 0, typeid_of(type_of(abi_key_down)), "int roci_key_down(const char *name)", "1 while the key with this lowercase name (\"a\", \"space\", \"left\", \"f5\", ...) is held."},
	{"roci_time", "", 0, typeid_of(type_of(abi_time)), "double roci_time(void)", "Seconds since the sketch began."},
	{"roci_frame_count", "", 0, typeid_of(type_of(abi_frame_count)), "int roci_frame_count(void)", "How many frames have been drawn."},
}
	all := make([dynamic]Abi_Entry, 0, 512)
	append(&all, ..entries[:])
	abi_window_group(&all)
	abi_pictures_group(&all)
	abi_collide_group(&all)
	abi_ui_group(&all)
	abi_misc_group(&all)
	abi_sound_group(&all)
	ABI_TABLE = all[:]
}

// One table row for a function of ours (one that is not a registry verb).
abi_entry :: proc(c_name: string, procedure: typeid, prototype, doc: string) -> Abi_Entry {
	return {c_name = c_name, procedure = procedure, prototype = prototype, doc = doc}
}

// The C type for a registry kind, or false when C has no form for it.
abi_c_type :: proc(kind: registry.Kind, wide := false) -> (name: string, ok: bool) {
	switch kind {
	case .None:                 return "void", true
	case .Number:               return "double", true
	case .Text, .Name:          return "const char *", true
	case .Colour, .Paint:       return "roci_color", true
	case .Vector:               return "roci_vec3" if wide else "roci_vec2", true
	case .Window:               return "roci_window_id", true
	case .Image:                return "roci_image_id", true
	case .Sound:                return "roci_sound_id", true
	case .List, .Table, .Block, .Gradient, .Any, .Boolean, .Expr_Block, .Record: return "", false
	}
	return "", false
}

// The functions whose vectors are points in space: the vector parameters (counted among all the
// parameters) and the result that have three numbers where the registry only says vector, because
// the language's vector is two to four numbers.
Abi_Wide :: struct {
	c_name: string,
	params: bit_set[0 ..< 8], // which parameters
	result: bool,
}

ABI_WIDE := [?]Abi_Wide{
	{"roci_box_v", {0}, false},
	{"roci_box_sized_v", {0, 1}, false},
	{"roci_sphere_v", {0}, false},
	{"roci_plane_v", {0}, false}, // its size is a vector of two
	{"roci_cone_v", {0}, false},
	{"roci_cylinder_v", {0}, false},
	{"roci_capsule_v", {0}, false},
	{"roci_torus_v", {0}, false},
	{"roci_icosphere_v", {0}, false},
	{"roci_arrow_v", {0, 1}, false},
	{"roci_camera_v", {0}, false},
	{"roci_look_at_v", {0}, false},
	{"roci_screen_point_v", {0}, false}, // it gives a pixel, a vector of two
	{"roci_world_point", {}, true},
	{"roci_world_point_v", {}, true}, // it takes a pixel
}

abi_wide_of :: proc(c_name: string) -> Abi_Wide {
	for wide in ABI_WIDE {
		if wide.c_name == c_name {
			return wide
		}
	}
	return {}
}

// A C identifier for a registry parameter name.
@(private)
c_identifier :: proc(name: string, allocator := context.allocator) -> string {
	out := make([]u8, len(name), allocator)
	for c, i in transmute([]u8)name {
		out[i] = c if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') else '_'
	}
	return string(out)
}

// The prototype of a function that is a registry verb, written from its shape.
// Gives false when the shape has a kind C cannot express.
abi_prototype_for :: proc(entry: Abi_Entry, allocator := context.allocator) -> (prototype, doc: string, ok: bool) {
	verb, found := registry.find_verb(entry.verb)
	if !found || entry.shape < 0 || entry.shape >= len(verb.shapes) {
		return "", "", false
	}
	shape := verb.shapes[entry.shape]
	wide := abi_wide_of(entry.c_name)
	ret, ret_ok := abi_c_type(shape.gives, wide.result)
	if !ret_ok {
		return "", "", false
	}
	b := strings.builder_make(allocator)
	fmt.sbprintf(&b, "%s %s(", ret, entry.c_name)
	if len(shape.params) == 0 {
		strings.write_string(&b, "void")
	}
	for param, i in shape.params {
		c_type, type_ok := abi_c_type(param.kind, i in wide.params)
		if !type_ok {
			strings.builder_destroy(&b)
			return "", "", false
		}
		if i > 0 {
			strings.write_string(&b, ", ")
		}
		name := c_identifier(param.name, context.temp_allocator)
		fmt.sbprintf(&b, "%s%s%s", c_type, "" if strings.has_suffix(c_type, "*") else " ", name)
	}
	strings.write_string(&b, ")")
	return strings.to_string(b), verb.doc, true
}

// The whole header, as text. The caller frees it.
abi_header :: proc(allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	strings.write_string(&b, `/* SPDX-License-Identifier: 0BSD
 *
 * rocinante's C API. Generated from the verb registry (roci/registry) and
 * ABI_TABLE (roci/abi_header.odin) by 'odin run tools/header -- include/roci.h';
 * do not edit it by hand.
 *
 * Numbers are double, text is a NUL-terminated const char *, colors are
 * roci_color (four floats, each 0 to 255), points are roci_vec2 (roci_vec3 in space), windows are
 * roci_window_id, pictures roci_image_id and models roci_model_id, drawings roci_svg_id, gradients roci_gradient_id and shaders roci_shader_id (ints; 0 is none) and true and false are int. A verb with
 * several shapes has one function per shape: the first keeps the verb's name and
 * the others add a suffix (_v is the form that takes points; sized takes a size for each side).
 */
#ifndef ROCI_H
#define ROCI_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct { float r, g, b, a; } roci_color;
typedef struct { double x, y; } roci_vec2;
typedef struct { double x, y, z; } roci_vec3;
typedef int roci_window_id;
typedef int roci_image_id;
typedef int roci_sound_id;
typedef int roci_model_id;
typedef int roci_svg_id;
typedef int roci_gradient_id;
typedef int roci_shader_id;
typedef int roci_tree_id;
typedef struct { roci_vec3 from, to; } roci_line3;

typedef enum { ROCI_NUMBER, ROCI_TEXT, ROCI_BOOLEAN, ROCI_VEC2, ROCI_LIST } roci_value_kind;

/* A message: read the field that goes with kind (a boolean is number 0 or 1, a list has count items). The
 * text and the items are valid only while the handler runs. */
typedef struct roci_value {
	roci_value_kind kind;
	double number;
	const char *text;
	roci_vec2 vec;
	const struct roci_value *items;
	int count;
} roci_value;

typedef struct { int id; roci_vec2 pos, start; double pressure; } roci_finger;

typedef enum { ROCI_KEY_DOWN, ROCI_MOUSE_DOWN, ROCI_MOUSE_UP, ROCI_TOUCH_DOWN, ROCI_TOUCH_UP, ROCI_RESIZE, ROCI_MOVE, ROCI_FOCUS,
	ROCI_MIDI_DOWN = 9, ROCI_MIDI_UP, ROCI_MIDI_CONTROL, ROCI_OSC, ROCI_MIDI_BEND, ROCI_MIDI_PROGRAM, ROCI_MIDI_PRESSURE, ROCI_MIDI_START, ROCI_MIDI_STOP } roci_event_kind;

/* What a MIDI event says: the note (60 is middle C) and its velocity (0 to 100) for a key, the controller and its
 * value (0 to 100) for a knob or fader, the pitch wheel (bend, -100 to 100), the instrument chosen (program, 0 to
 * 127), how hard a key is held (pressure, 0 to 100, with note the key or 0 for the whole keyboard), and the
 * channel (1 to 16) for all of them. A field that does not belong to the event is 0. */
typedef struct { double note, velocity, channel, control, value, bend, program, pressure; } roci_midi;

/* A message that arrived over the network: its address and sender as text, the first text argument (empty when
 * none), the first number argument (0 when none; true is 1, false is 0) and every argument in order as roci_values:
 * a number, text, a boolean, or for a blob of bytes a list of numbers. The text and the values are valid only while
 * the handler runs. */
typedef struct { const char *address, *from, *text; double value; const roci_value *args; int arg_count; } roci_osc;

/* What happened: kind, the window it happened in, the key's or the mouse button's name (for key and
 * mouse events; valid only while the handler runs), the finger (for touch events) and the key or
 * controller (for MIDI events) and the message (for an osc event). */
typedef struct {
	int kind;
	roci_window_id window;
	const char *name;
	roci_finger finger;
	roci_midi midi;
	roci_osc osc;
} roci_event;

/* A shape for the collision functions. Kinds: ROCI_POINT, ROCI_CIRCLE, ROCI_BOX, ROCI_SEGMENT and ROCI_POLYGON are flat;
 * ROCI_POINT3, ROCI_SPHERE, ROCI_BOX3, ROCI_SEGMENT3 and ROCI_MESH are in space. pos is a point, a circle's or sphere's middle, a flat
 * box's top left corner or a box's middle in space; radius a circle's or sphere's; size a box's; angle.x a flat box's turn in degrees
 * and angle a box's turns about x, y and z in space; from and to a segment's ends; points and count a polygon's corners (x and y)
 * or a mesh's triangles (three corners for each). Fields a kind does not use are ignored. */
typedef enum { ROCI_POINT, ROCI_CIRCLE, ROCI_BOX, ROCI_SEGMENT, ROCI_POLYGON, ROCI_POINT3, ROCI_SPHERE, ROCI_BOX3, ROCI_SEGMENT3, ROCI_MESH } roci_shape_kind;

typedef struct {
	int kind;
	roci_vec3 pos;
	double radius;
	roci_vec3 size;
	roci_vec3 angle;
	roci_vec3 from, to;
	const roci_vec3 *points;
	int count;
} roci_shape;

typedef struct { int touching; roci_vec3 point, normal; double depth; } roci_contact_info;
typedef struct { int index; roci_vec3 point, normal; double distance; } roci_cast_hit;

typedef void (*roci_event_fn)(const roci_event *event);
typedef void (*roci_draw_fn)(void);
typedef void (*roci_receive_fn)(roci_value *value);

`)
	for entry in ABI_TABLE {
		prototype, doc: string
		if entry.verb != "" {
			ok: bool
			prototype, doc, ok = abi_prototype_for(entry, context.temp_allocator)
			if !ok {
				continue
			}
		} else {
			prototype, doc = entry.prototype, entry.doc
		}
		fmt.sbprintf(&b, "/* %s */\n%s;\n\n", doc, prototype)
	}
	strings.write_string(&b, `#ifdef __cplusplus
}
#endif

#endif /* ROCI_H */
`)
	return strings.to_string(b)
}
