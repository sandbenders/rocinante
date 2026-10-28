/* SPDX-License-Identifier: 0BSD
 *
 * rocinante's C API. Generated from the verb registry (roci/registry) and
 * ABI_TABLE (roci/abi_header.odin) by 'odin run tools/header -- include/roci.h';
 * do not edit it by hand.
 *
 * Numbers are double, text is a NUL-terminated const char *, colours are
 * roci_colour (four floats, each 0 to 255), points are roci_vec2, windows are
 * roci_window_id (an int; 0 is none) and true and false are int. A verb with
 * several shapes has one function per shape: the first keeps the verb's name and
 * the others add a suffix (_v is the form that takes points).
 */
#ifndef ROCI_H
#define ROCI_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct { float r, g, b, a; } roci_colour;
typedef struct { double x, y; } roci_vec2;
typedef int roci_window_id;

typedef enum { ROCI_NUMBER, ROCI_TEXT, ROCI_BOOLEAN, ROCI_VEC2 } roci_value_kind;

/* A message: read the field that goes with kind. The text is valid only while
 * the handler runs. */
typedef struct {
	roci_value_kind kind;
	double number;
	const char *text;
	roci_vec2 vec;
} roci_value;

typedef void (*roci_draw_fn)(void);
typedef void (*roci_receive_fn)(roci_value *value);

/* Opens a window of the given size, optionally at a position, and gives it back. */
roci_window_id roci_window(double width, double height);

/* Opens a window at a position on the screen and gives it back. */
roci_window_id roci_window_at(double width, double height, double x, double y);

/* Sets the window's title. */
void roci_title(const char *text);

/* Makes the window fill the screen. */
void roci_fullscreen(void);

/* Closes the sketch. */
void roci_quit(void);

/* The window the verbs are drawing into now. */
roci_window_id roci_current_window(void);

/* The width of the current window in logical pixels. */
double roci_width(void);

/* The height of the current window in logical pixels. */
double roci_height(void);

/* Runs `block` every frame for a window (0 for the current one). */
void roci_draw(roci_window_id window, roci_draw_fn block);

/* Runs `handler` for each message the window receives, on its next frame. */
void roci_on_receive(roci_window_id window, roci_receive_fn handler);

/* Sends a number to a window; it arrives on that window's next frame. */
void roci_send_number(roci_window_id to, double number);

/* Sends text to a window; the text is copied. */
void roci_send_text(roci_window_id to, const char *text);

/* Sends a point to a window. */
void roci_send_vec2(roci_window_id to, roci_vec2 point);

/* Shows the sketch until every window is closed, or for `frames` frames when that is more than 0. Gives 1 when it ran and 0 when the graphics could not start. */
int roci_run(int frames);

/* Fills the whole window with a colour or a gradient. */
void roci_background(roci_colour colour);

/* Paints the whole window a grey, 0 to 255. */
void roci_background_grey(double value);

/* Empties the window, leaving it transparent. */
void roci_clear(void);

/* Draws a circle around a point. */
void roci_circle(double x, double y, double radius);

/* Draws a circle around a point. */
void roci_circle_v(roci_vec2 position, double radius);

/* Draws an ellipse. */
void roci_ellipse(double x, double y, double width, double height);

/* Draws an ellipse. */
void roci_ellipse_v(roci_vec2 position, roci_vec2 size);

/* Draws a rectangle. */
void roci_rect(double x, double y, double width, double height);

/* Draws a rectangle. */
void roci_rect_v(roci_vec2 position, roci_vec2 size);

/* Draws a square. */
void roci_square(double x, double y, double side);

/* Draws a square. */
void roci_square_v(roci_vec2 position, double side);

/* Draws a line between two points. */
void roci_line(double x1, double y1, double x2, double y2);

/* Draws a line between two points. */
void roci_line_v(roci_vec2 from, roci_vec2 to);

/* Draws a single point. */
void roci_point(double x, double y);

/* Draws a single point. */
void roci_point_v(roci_vec2 position);

/* Draws a triangle through three points. */
void roci_triangle(double x1, double y1, double x2, double y2, double x3, double y3);

/* Draws a triangle through three points. */
void roci_triangle_v(roci_vec2 a, roci_vec2 b, roci_vec2 c);

/* Draws a four-sided shape through four points. */
void roci_quad(double x1, double y1, double x2, double y2, double x3, double y3, double x4, double y4);

/* Draws a four-sided shape through four points. */
void roci_quad_v(roci_vec2 a, roci_vec2 b, roci_vec2 c, roci_vec2 d);

/* Draws part of an ellipse, between two angles in degrees. */
void roci_arc(double x, double y, double width, double height, double start, double stop);

/* Text in the built-in overlay font, in the fill colour; whole-number scales look best. */
void roci_debug_text(const char *text, double x, double y, double scale);

/* Sets the colour of areas from now on. */
void roci_fill(roci_colour colour);

/* Fills with a grey, 0 to 255, from now on. */
void roci_fill_grey(double value);

/* Turns area colour off from now on. */
void roci_no_fill(void);

/* Sets the colour of outlines and lines from now on. */
void roci_stroke(roci_colour colour);

/* Outlines with a grey, 0 to 255, from now on. */
void roci_stroke_grey(double value);

/* Turns outlines off from now on. */
void roci_no_stroke(void);

/* Sets the width of outlines and lines, in pixels. */
void roci_thickness(double pixels);

/* Sets how solid fill and stroke are: 0 (gone) to 100 (solid) in the language, 0 to 255 in the Odin and C APIs. */
void roci_alpha(double amount);

/* Sets how lines and points end from now on: butt, round or square. */
void roci_caps(const char *style);

/* Sets how outlines turn corners from now on: miter, round or bevel. */
void roci_joins(const char *style);

/* Makes a colour from red, green and blue, each 0 to 255. */
roci_colour roci_rgb(double red, double green, double blue);

/* Makes a colour with its own transparency, each channel 0 to 255. */
roci_colour roci_rgba(double red, double green, double blue, double alpha);

/* Makes a colour from hue, saturation and brightness, each 0 to 255. */
roci_colour roci_hsb(double hue, double saturation, double brightness);

/* Makes a colour from lightness 0 to 1, chroma and hue in degrees. */
roci_colour roci_oklch(double lightness, double chroma, double hue);

/* Blends two colours, or two numbers; amount 0 gives the first and 1 the second. */
roci_colour roci_mix(roci_colour first, roci_colour second, double amount);

/* Blends two colours, or two numbers; amount 0 gives the first and 1 the second. */
double roci_mix_numbers(double first, double second, double amount);

/* Moves everything drawn after it. */
void roci_move(double x, double y);

/* Moves everything drawn after it. */
void roci_move_v(roci_vec2 offset);

/* Turns everything drawn after it. */
void roci_turn(double degrees);

/* Scales everything drawn after it. */
void roci_grow(double factor);

/* Scales everything drawn after it. */
void roci_grow_xy(double x, double y);

/* Slants everything drawn after it, by angles in degrees. */
void roci_shear(double x, double y);

/* Saves the style and the transform until the matching roci_pop. */
void roci_push(void);

/* Puts back what the matching roci_push saved. Gives 0 for a pop without a push. */
int roci_pop(void);

/* Moves a number from one range to another. */
double roci_map(double value, double from_low, double from_high, double to_low, double to_high);

/* Keeps a number between a low and a high. */
double roci_clamp(double value, double low, double high);

/* The distance between two points. */
double roci_dist(double x1, double y1, double x2, double y2);

/* The distance between two points. */
double roci_dist_v(roci_vec2 a, roci_vec2 b);

/* A number without its sign. */
double roci_abs(double value);

/* The square root. */
double roci_sqrt(double value);

/* The sine of an angle in degrees. */
double roci_sin(double degrees);

/* The cosine of an angle in degrees. */
double roci_cos(double degrees);

/* A random number from 0 up to a limit, or `random from 1 to 3` between two numbers. */
double roci_random(double limit);

/* A random number from `low` up to `high`. */
double roci_random_between(double low, double high);

/* A random number clustered around a mean. */
double roci_gaussian(double mean, double spread);

/* Makes every random number from now on repeat the same way. */
void roci_seed(double value);

/* Smooth random noise from 0 to 1 in one to four dimensions; add `as simplex` for simplex noise. */
double roci_noise(double x);

/* Smooth random noise from 0 to 1 in one to four dimensions; add `as simplex` for simplex noise. */
double roci_noise2(double x, double y);

/* Smooth random noise from 0 to 1 in one to four dimensions; add `as simplex` for simplex noise. */
double roci_noise3(double x, double y, double z);

/* Smooth random noise from 0 to 1 in one to four dimensions; add `as simplex` for simplex noise. */
double roci_noise4(double x, double y, double z, double w);

/* Layers of noise from 0 to 1, with finer detail added on top. */
double roci_fbm(double x, double y, double z);

/* Where the mouse is in the current window, in logical pixels. */
roci_vec2 roci_mouse(void);

/* Where the mouse was one frame ago. */
roci_vec2 roci_pmouse(void);

/* 1 while the left mouse button is down. */
int roci_mouse_down(void);

/* 1 while the key with this lowercase name ("a", "space", "left", "f5", ...) is held. */
int roci_key_down(const char *name);

/* Seconds since the sketch began. */
double roci_time(void);

/* How many frames have been drawn. */
int roci_frame_count(void);

#ifdef __cplusplus
}
#endif

#endif /* ROCI_H */
