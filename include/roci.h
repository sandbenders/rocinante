/* SPDX-License-Identifier: 0BSD
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
	ROCI_MIDI_DOWN = 9, ROCI_MIDI_UP, ROCI_MIDI_CONTROL, ROCI_OSC } roci_event_kind;

/* A key or controller of a MIDI keyboard: the note (60 is middle C) and its velocity (0 to 100) for a key,
 * the controller and its value (0 to 100) for a knob or fader, and the channel (1 to 16). */
typedef struct { double note, velocity, channel, control, value; } roci_midi;

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

/* Opens a window of the given size, optionally at a position, and gives it back. */
roci_window_id roci_window(double width, double height);

/* Opens a window at a position on the screen and gives it back. */
roci_window_id roci_window_at(double width, double height, double x, double y);

/* Sets the title of the window the code runs in. Another window is changed with `set`. */
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

/* Sets the color, gradient or picture behind everything in the window, wherever it is written: `background photo as cover`. */
void roci_background(roci_color color);

/* Sets the color, gradient or picture behind everything in the window, wherever it is written: `background photo as cover`. */
void roci_background_image(roci_image_id picture);

/* Paints the whole window with a picture, behind everything. `fit` is 0 cover, 1 fit, 2 stretch, 3 tile or 4 center; `tile` is the width of one copy for tile (0 is the picture's own size); `at_x` and `at_y` shift the picture for tile and center. */
void roci_background_image_as(roci_image_id picture, int fit, double tile, double at_x, double at_y);

/* Paints the whole window a gray, 0 to 255. */
void roci_background_gray(double value);

/* Empties the window, leaving it transparent. */
void roci_clear(void);

/* Draws a circle around a point. */
void roci_circle(double x, double y, double radius);

/* Draws a circle around a point. */
void roci_circle_v(roci_vec2 position, double radius);

/* Draws text with its top at a point, in the current font. */
void roci_text(const char *words, double x, double y);

/* Draws text with its top at a point, in the current font. */
void roci_text_v(const char *words, roci_vec2 position);

/* Sets the font, and its size, for the text drawn from now on: Inter or Inter Bold, a font file in assets/fonts, or a font installed on the computer, which is copied into assets/fonts. */
void roci_font(const char *name);

/* Sets where a text sits against its point from now on: left, center or right. */
void roci_align(const char *side);

/* Sets the space between the lines of a text from now on, as a multiple of its size: 1.5 puts the lines one and a half sizes apart, and 0 is the font's own spacing. */
void roci_leading(double multiple);

/* How big a text is in the current font, as a vector of its width and height. */
roci_vec2 roci_measure(const char *text);

/* Decodes the bytes of a picture file (PNG, JPEG, BMP, TGA or QOI) and gives its number, or 0 when they are not a picture. */
roci_image_id roci_load_image(const unsigned char *bytes, int length);

/* How wide a picture is, in pixels (0 for no picture). */
double roci_image_width(roci_image_id picture);

/* How high a picture is, in pixels (0 for no picture). */
double roci_image_height(roci_image_id picture);

/* Draws a loaded picture with its top left at a point, at its own size, or at a width or height (the other side follows) or a size. */
void roci_image(roci_image_id picture, double x, double y);

/* Draws a loaded picture with its top left at a point, at its own size, or at a width or height (the other side follows) or a size. */
void roci_image_v(roci_image_id picture, roci_vec2 position);

/* Draws a loaded picture with its top left at a point, at its own size, or at a width or height (the other side follows) or a size. */
void roci_image_sized(roci_image_id picture, double x, double y, double width, double height);

/* Draws a loaded picture with its top left at a point, at its own size, or at a width or height (the other side follows) or a size. */
void roci_image_sized_v(roci_image_id picture, roci_vec2 position, roci_vec2 size);

/* Makes a canvas: a picture you draw into with `draw into`. It keeps what is drawn on it from frame to frame, and is shown with `image`. Make it once, not every frame. */
roci_image_id roci_canvas(double width, double height);

/* Draws onto a canvas from now on, until roci_end_into; gives 1, or 0 when the picture is not a canvas or one is being drawn into already. */
int roci_begin_into(roci_image_id canvas);

/* Goes back to drawing into the window. */
void roci_end_into(void);

/* Sets the color pictures are drawn through from now on: white leaves them as they are, and its alpha makes them see-through. */
void roci_tint(roci_color color);

/* Sets the size of the text drawn from now on, in pixels. */
void roci_font_size(double pixels);

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

/* Text in the built-in overlay font, in the fill color; whole-number scales look best. */
void roci_debug_text(const char *text, double x, double y, double scale);

/* Sets the color of areas from now on, or fills them with a picture: each shape is a mask the picture shows through. */
void roci_fill(roci_color color);

/* Sets the color of areas from now on, or fills them with a picture: each shape is a mask the picture shows through. */
void roci_fill_image(roci_image_id picture);

/* Fills with a picture. `fit` is 0 cover, 1 fit, 2 stretch, 3 tile or 4 center; `tile` is the width of one copy for tile (0 is the picture's own size); `at_x` and `at_y` shift the picture for tile and center. */
void roci_fill_image_as(roci_image_id picture, int fit, double tile, double at_x, double at_y);

/* Fills with a gray, 0 to 255, from now on. */
void roci_fill_gray(double value);

/* Turns area color off from now on. */
void roci_no_fill(void);

/* Sets the color of outlines and lines from now on, or draws them with a picture: each outline is a mask the picture shows through. */
void roci_stroke(roci_color color);

/* Sets the color of outlines and lines from now on, or draws them with a picture: each outline is a mask the picture shows through. */
void roci_stroke_image(roci_image_id picture);

/* Outlines with a picture. `fit` is 0 cover, 1 fit, 2 stretch, 3 tile or 4 center; `tile` is the width of one copy for tile (0 is the picture's own size); `at_x` and `at_y` shift the picture for tile and center. */
void roci_stroke_image_as(roci_image_id picture, int fit, double tile, double at_x, double at_y);

/* Outlines with a gray, 0 to 255, from now on. */
void roci_stroke_gray(double value);

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

/* Sets how what is drawn from now on mixes with what is behind it: normal (the default), add, multiply, screen, subtract or lighten. It lasts like fill does, and one shape can say it too: `circle at 100 100 radius 50 blend add`. */
void roci_blend(const char *mode);

/* Keeps drawing from now on inside a box, in the transform of the moment: `clip at 20 20 size 200 100`. A turned box clips to the upright box round it. A new clip replaces the old one, and `no clip` takes it away. */
void roci_clip(double x, double y, double width, double height);

/* Keeps drawing from now on inside a box, in the transform of the moment: `clip at 20 20 size 200 100`. A turned box clips to the upright box round it. A new clip replaces the old one, and `no clip` takes it away. */
void roci_clip_v(roci_vec2 position, roci_vec2 size);

/* Takes the clip away, so drawing reaches the whole window again. */
void roci_no_clip(void);

/* Makes a color from red, green and blue, each 0 to 255. */
roci_color roci_rgb(double red, double green, double blue);

/* Makes a color with its own transparency, each channel 0 to 255. */
roci_color roci_rgba(double red, double green, double blue, double alpha);

/* Makes a color from hue, saturation and brightness, each 0 to 255. */
roci_color roci_hsb(double hue, double saturation, double brightness);

/* Makes a color from lightness 0 to 1, chroma and hue in degrees. */
roci_color roci_oklch(double lightness, double chroma, double hue);

/* Blends two colors, or two numbers; amount 0 gives the first and 1 the second. */
roci_color roci_mix(roci_color first, roci_color second, double amount);

/* Blends two colors, or two numbers; amount 0 gives the first and 1 the second. */
double roci_mix_numbers(double first, double second, double amount);

/* Moves everything drawn after it; with three numbers, or a vector of three, it moves the 3D shapes. */
void roci_move(double x, double y);

/* Moves everything drawn after it; with three numbers, or a vector of three, it moves the 3D shapes. */
void roci_move_v(roci_vec2 offset);

/* Turns everything drawn after it: the canvas, or with `around x`, `around y` or `around z` the 3D shapes about that axis. */
void roci_turn(double degrees);

/* Scales everything drawn after it. */
void roci_grow(double factor);

/* Scales everything drawn after it. */
void roci_grow_xy(double x, double y);

/* Slants everything drawn after it, by angles in degrees. */
void roci_shear(double x, double y);

/* Saves the style, the transform and the turtle until the matching roci_pop. */
void roci_push(void);

/* Puts back what the matching roci_push saved. Gives 0 for a pop without a push. */
int roci_pop(void);

/* Walks the turtle forward, drawing a line while its pen is down; with a sound, moves it ahead: `forward rain by 10` (seconds). */
void roci_forward(double distance);

/* Walks the turtle backwards, without turning it round. */
void roci_back(double distance);

/* Turns the turtle anticlockwise, in degrees. */
void roci_left(double degrees);

/* Turns the turtle clockwise, in degrees. */
void roci_right(double degrees);

/* Lifts the turtle's pen: it moves without drawing. */
void roci_pen_up(void);

/* Puts the turtle's pen down: it draws as it moves, in the stroke, or in black while there is none. */
void roci_pen_down(void);

/* Sends the turtle back to the middle of the window, facing up, without drawing. */
void roci_home(void);

/* Draws the turtle itself where it is: a small triangle pointing the way it faces, solid while its pen is down and an outline while it is up. */
void roci_show_turtle(void);

/* Moves a number from one range to another. */
double roci_map(double value, double from_low, double from_high, double to_low, double to_high);

/* Keeps a number between a low and a high. */
double roci_clamp(double value, double low, double high);

/* The distance between two points. */
double roci_dist(double x1, double y1, double x2, double y2);

/* The distance between two points. */
double roci_dist_v(roci_vec2 a, roci_vec2 b);

/* The angle in degrees of a point, clockwise from straight right as the screen turns, from -180 to 180: `atan y x`, or `atan v` for the direction of a vector. */
double roci_atan(double y, double x);

/* The angle in degrees of a point, clockwise from straight right as the screen turns, from -180 to 180: `atan y x`, or `atan v` for the direction of a vector. */
double roci_atan_v(roci_vec2 v);

/* The vector in the same direction with a length of 1; a vector with no length stays the zero vector. */
roci_vec2 roci_normalize(roci_vec2 v);

/* The vector shortened to at most a length, in the same direction: `limit speed 3`. */
roci_vec2 roci_limit(roci_vec2 v, double most);

/* A number without its sign. */
double roci_abs(double value);

/* The square root. */
double roci_sqrt(double value);

/* The whole number at or below a number: floor 2.7 is 2, floor -2.1 is -3. */
double roci_floor(double value);

/* The nearest whole number; halves go away from zero: round 2.5 is 3. */
double roci_round(double value);

/* The whole number at or above a number: ceil 2.1 is 3, ceil -2.7 is -2. */
double roci_ceil(double value);

/* The sine of an angle in degrees. */
double roci_sin(double degrees);

/* The cosine of an angle in degrees. */
double roci_cos(double degrees);

/* How far along a movement is when an amount (0 to 1) of its time has passed, on a curve: `ease t as out`. Smooth unless `as` says linear, in, out, back, elastic or bounce. */
double roci_ease(double amount);

/* The same on a named curve: smooth, linear, in, out, back, elastic or bounce (any other name is smooth). */
double roci_ease_as(double amount, const char *curve);

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

/* Draws a box in 3D about a point: with one side for a cube, or a width, height and depth. The window gets a camera that the mouse turns. */
void roci_box(double x, double y, double z, double side);

/* Draws a box in 3D about a point: with one side for a cube, or a width, height and depth. The window gets a camera that the mouse turns. */
void roci_box_sized(double x, double y, double z, double width, double height, double depth);

/* Draws a box in 3D about a point: with one side for a cube, or a width, height and depth. The window gets a camera that the mouse turns. */
void roci_box_v(roci_vec3 position, double side);

/* Draws a box in 3D about a point: with one side for a cube, or a width, height and depth. The window gets a camera that the mouse turns. */
void roci_box_sized_v(roci_vec3 position, roci_vec3 size);

/* Draws a sphere in 3D about a point. */
void roci_sphere(double x, double y, double z, double radius);

/* Draws a sphere in 3D about a point. */
void roci_sphere_v(roci_vec3 position, double radius);

/* Draws a flat square in 3D, lying in the plane of x and z like a floor, about a point. */
void roci_plane(double x, double y, double z, double width, double depth);

/* Draws a flat square in 3D, lying in the plane of x and z like a floor, about a point. */
void roci_plane_v(roci_vec3 position, roci_vec2 size);

/* Draws a cone in 3D about a point, its tip up. */
void roci_cone(double x, double y, double z, double radius, double height);

/* Draws a cone in 3D about a point, its tip up. */
void roci_cone_v(roci_vec3 position, double radius, double height);

/* Draws a cylinder in 3D about a point, standing on its end. */
void roci_cylinder(double x, double y, double z, double radius, double height);

/* Draws a cylinder in 3D about a point, standing on its end. */
void roci_cylinder_v(roci_vec3 position, double radius, double height);

/* Draws a capsule in 3D about a point: a cylinder with a half sphere on each end, the height counting both. */
void roci_capsule(double x, double y, double z, double radius, double height);

/* Draws a capsule in 3D about a point: a cylinder with a half sphere on each end, the height counting both. */
void roci_capsule_v(roci_vec3 position, double radius, double height);

/* Draws a ring in 3D lying in the plane of x and z about a point: the radius is to the middle of the tube, and the tube has a radius of its own. */
void roci_torus(double x, double y, double z, double radius, double tube);

/* Draws a ring in 3D lying in the plane of x and z about a point: the radius is to the middle of the tube, and the tube has a radius of its own. */
void roci_torus_v(roci_vec3 position, double radius, double tube);

/* Draws a sphere of 80 flat faces in 3D about a point, which shows how the light falls on each. */
void roci_icosphere(double x, double y, double z, double radius);

/* Draws a sphere of 80 flat faces in 3D about a point, which shows how the light falls on each. */
void roci_icosphere_v(roci_vec3 position, double radius);

/* Draws a grid on the floor of the 3D scene, the plane of x and z: `lines` squares across a size, in the fill. */
void roci_grid(double size, double lines);

/* Draws the three axes of the 3D scene as arrows from the origin: x red, y green and z blue. */
void roci_axes(double size);

/* Draws an arrow in 3D from one point to another, in the fill. */
void roci_arrow(double x1, double y1, double z1, double x2, double y2, double z2);

/* Draws an arrow in 3D from one point to another, in the fill. */
void roci_arrow_v(roci_vec3 from, roci_vec3 to);

/* Draws a mesh of triangles: `corners` holds `count` corners, three for each triangle, in the coordinates of the moment, flat shaded in the fill; with `wireframe` 1 only the feature edges are drawn, as tubes as wide as the thickness. `key` names the call that draws it, so a list drawn again unchanged is sent to the graphics card once. */
void roci_mesh(const char *key, const roci_vec3 *corners, int count, int wireframe);

/* Reads a glTF (.glb or .gltf) or OBJ model from a file, with the pictures and data it names beside it, and gives its number, or 0 when it cannot be read. The same file read again, unchanged, gives the same number. */
roci_model_id roci_load_model(const char *path);

/* Draws a loaded model with its middle at a point and its longest side `size` long, in the colors and pictures of its own materials. */
void roci_model(roci_model_id model, double x, double y, double z, double size);

/* The same at a point given as a vector. */
void roci_model_v(roci_model_id model, roci_vec3 position, double size);

/* Puts the eye of the 3D camera at a point, looking at the middle (or where `look at` says), until the frame ends. The mouse then no longer turns it; `fov` is how wide it sees in degrees, 50 to start with. */
void roci_camera(double x, double y, double z);

/* Puts the eye of the 3D camera at a point, looking at the middle (or where `look at` says), until the frame ends. The mouse then no longer turns it; `fov` is how wide it sees in degrees, 50 to start with. */
void roci_camera_v(roci_vec3 position);

/* Puts the eye of the 3D camera at a point, as roci_camera does, seeing `fov` degrees wide (50 to start with). */
void roci_camera_fov(double x, double y, double z, double fov);

/* Aims the 3D camera at a point. If the camera has not been moved, it stays where it was and turns to look there. */
void roci_look_at(double x, double y, double z);

/* Aims the 3D camera at a point. If the camera has not been moved, it stays where it was and turns to look there. */
void roci_look_at_v(roci_vec3 position);

/* Draws the 3D scene without perspective: things are the same size at every distance, one unit a pixel. */
void roci_ortho(void);

/* Draws the 3D scene with perspective again, after `ortho`; `fov` is how wide it sees in degrees. */
void roci_perspective(void);

/* Draws the 3D scene with perspective again, seeing `fov` degrees wide. */
void roci_perspective_fov(double fov);

/* Where a point of the 3D scene shows in the window, as a pixel from the top left, the point in the coordinates of the moment: `screen point { 0, 0, 0 }`. A point behind the camera gives { 0, 0 }. */
roci_vec2 roci_screen_point(double x, double y, double z);

/* Where a point of the 3D scene shows in the window, as a pixel from the top left, the point in the coordinates of the moment: `screen point { 0, 0, 0 }`. A point behind the camera gives { 0, 0 }. */
roci_vec2 roci_screen_point_v(roci_vec3 position);

/* The point of the floor, the plane where y is 0, that shows at a pixel of the window, as a vector of three numbers: `world point mouse`. A pixel that looks past the floor gives { 0, 0, 0 }. */
roci_vec3 roci_world_point(double x, double y);

/* The point of the floor, the plane where y is 0, that shows at a pixel of the window, as a vector of three numbers: `world point mouse`. A pixel that looks past the floor gives { 0, 0, 0 }. */
roci_vec3 roci_world_point_v(roci_vec2 position);

/* Adds an ambient light of a color to the 3D scene. The first light of a frame takes the usual lights away. Gives 0 when the scene already has as many lights as it can hold. */
int roci_light_ambient(roci_color color);

/* Adds a sun: light from the direction x, y, z (the direction towards the sun, in the world, y down). Gives 0 when the scene has no room. */
int roci_light_sun(double x, double y, double z, roci_color color);

/* Adds a point light at a place, weaker the further away: `falloff` is the distance at which it has dropped to half (500 is usual). Gives 0 when the scene has no room. */
int roci_light_point(double x, double y, double z, roci_color color, double falloff);

/* Adds a spot light at a place, aimed at another, inside a cone of half `angle` degrees (30 is usual). Gives 0 when the scene has no room. */
int roci_light_spot(double x, double y, double z, double to_x, double to_y, double to_z, double angle, roci_color color, double falloff);

/* Draws the 3D shapes that come after it flat in their color, with no light or shade, until the `push` it is in ends or the frame does. */
void roci_no_lights(void);

/* Sets what the 3D shapes drawn from now on are made of: `metallic` 0 for paint up to 1 for metal, `roughness` 0 for a mirror up to 1 for chalk, and `emissive` how much of their color they give off by themselves. */
void roci_material(double metallic, double roughness, double emissive);

/* Turns shadows on for the rest of the frame: the first `sun` or `spot` light casts them (the usual sun, if no light is written), and so does the first `point` light, in every direction, and the 3D shapes are dark where they do not reach. */
void roci_shadows(void);

/* Moves everything drawn after it; with three numbers, or a vector of three, it moves the 3D shapes. */
void roci_move_xyz(double x, double y, double z);

/* Moves the 3D shapes drawn after it, by a vector of three numbers. */
void roci_move_v3(roci_vec3 offset);

/* Scales everything drawn after it. */
void roci_grow_xyz(double x, double y, double z);

/* Turns the 3D shapes drawn after it about an axis, "x", "y" or "z", in degrees: clockwise seen from the end of the axis. */
void roci_turn_about(double degrees, const char *axis);

/* Makes the turtle walk the 3D scene for the rest of the frame, from the origin facing up the screen: `forward`, `back`, `left`, `right`, `pen up`, `pen down`, `home` and `show turtle` then act on it, and it draws thin tubes in the stroke (the thickness is their width), or in black while there is none. */
void roci_turtle_space(void);

/* Tips the nose of the turtle in space towards its top, in degrees, which at the start is towards you. It needs `turtle space` first. */
void roci_up(double degrees);

/* Tips the nose of the turtle in space away from its top, in degrees. It needs `turtle space` first. */
void roci_down(double degrees);

/* Rolls the turtle in space about the way it faces, its top going to the right, in degrees. It needs `turtle space` first. */
void roci_roll(double degrees);

/* Plays a sound once, from where it is, or from its start when it had come to its end: `play click`. `volume` is 0 to 100, `pan` -100 (left) to 100 (right) and `speed` 1 as recorded. */
void roci_play(roci_sound_id sound);

/* Plays a sound over and over, from where it is: `loop rain volume 40`. `set rain loop false` lets it finish. */
void roci_loop(roci_sound_id sound);

/* Holds a sound where it is; `play` or `loop` goes on from there. An instrument's notes fade out, all of them or one: `pause piano note 60`. */
void roci_pause(roci_sound_id sound);

/* Puts a sound back to its start, or some seconds back: `rewind rain by 10`. A sound that plays goes on playing. */
void roci_rewind(roci_sound_id sound);

/* How loud everything that plays is now, 0 (silent) to 100: `circle at 200 200 radius (level * 2)`. `level rain` is one sound, `level mic` the microphone. */
double roci_level(void);

/* Makes an instrument, a sound of the sketch's own: `piano = synth triangle` (or `sine`, `square`, `saw`, `noise`), or from a SoundFont in the assets, `piano = synth "upright.sf2"`, with `preset` naming one of its instruments by number (General MIDI's 0 is a piano, 48 strings) or by name. `play piano note 60` plays middle C until `pause piano note 60`, or `for 0.5` seconds, and several notes sound together. */
roci_sound_id roci_synth(const char *wave);

/* The latest value of a MIDI controller, 0 to 100, 0 until it first moves: `midi control 1` is the mod wheel, and the knobs and faders of a controller have numbers of their own (its manual says which, or `on midi control [ print midi.control ]`). */
double roci_midi_control(double number);

/* Starts listening for OSC messages on a port: `osc listen 8000`. Without it the first `on osc` or `osc value` listens on port 9000. If another program has the port, a message says so and the sketch goes on without listening; asking again for the port in use changes nothing. */
void roci_osc_listen(double port);

/* The latest first number sent to an OSC address, 0 until one arrives: `osc value "/fader/1"`. The first call starts listening, as `on osc` does. */
double roci_osc_value(const char *address);

/* How loud everything that plays is now, 0 (silent) to 100: `circle at 200 200 radius (level * 2)`. `level rain` is one sound, `level mic` the microphone. */
double roci_level_of(roci_sound_id sound);

/* The line from the eye of the 3D camera through a pixel of the window: `from` is the eye and `to` is far along the way the pixel looks, in the world. */
roci_line3 roci_ray(double x, double y);

/* The same for a pixel given as a point, such as the mouse. */
roci_line3 roci_ray_v(roci_vec2 pixel);

/* The corners of a loaded model's triangles, three for each, placed and sized as roci_model draws it. Copies up to `capacity` corners into `corners` (which may be NULL) and gives how many there are in all, so a first call with capacity 0 says how big an array to make. */
int roci_triangles(roci_model_id model, double x, double y, double z, double size, roci_vec3 *corners, int capacity);

/* The same at a point given as a vector. */
int roci_triangles_v(roci_model_id model, roci_vec3 position, double size, roci_vec3 *corners, int capacity);

/* Reads an SVG drawing from a file and gives its number, or 0 when it cannot be read. The same file read again, unchanged, gives the same number; saved again, it is read again under it. */
roci_svg_id roci_load_svg(const char *path);

/* Draws an SVG drawing with its top left at a point, at its own size, in its own colors, under the current transform. */
void roci_svg(roci_svg_id drawing, double x, double y);

/* The same at a point given as a vector. */
void roci_svg_v(roci_svg_id drawing, roci_vec2 position);

/* Draws an SVG drawing stretched to a width and a height. */
void roci_svg_sized(roci_svg_id drawing, double x, double y, double width, double height);

/* The same with the point and the size given as vectors. */
void roci_svg_sized_v(roci_svg_id drawing, roci_vec2 position, roci_vec2 size);

/* How wide a drawing is in its own units (0 for no drawing). */
double roci_svg_width(roci_svg_id drawing);

/* How high a drawing is in its own units (0 for no drawing). */
double roci_svg_height(roci_svg_id drawing);

/* What the drawing has that cannot be drawn, as bits: 1 text, 2 pictures, 4 gradients (drawn in the first color of their stops), 8 clips, 16 masks, 32 filters, 64 patterns, 128 markers. */
int roci_svg_lost(roci_svg_id drawing);

/* Where the mouse is in the current window, in logical pixels. */
roci_vec2 roci_mouse(void);

/* Where the mouse was one frame ago. */
roci_vec2 roci_pmouse(void);

/* 1 while the left mouse button is down, in the current window. */
int roci_mouse_down(void);

/* 1 while the key with this lowercase name ("a", "space", "left", "f5", ...) is held. */
int roci_key_down(const char *name);

/* Seconds since the sketch began. */
double roci_time(void);

/* How many frames have been drawn. */
int roci_frame_count(void);

/* Copies the open windows into `windows` as far as `capacity` allows (it may be NULL) and gives how many are open. */
int roci_open_windows(roci_window_id *windows, int capacity);

/* Sets the title in a window's bar. */
void roci_set_title(roci_window_id window, const char *text);

/* Sets the size of a window in logical pixels. */
void roci_set_size(roci_window_id window, double width, double height);

/* Moves a window to a place on the screen. */
void roci_set_position(roci_window_id window, double x, double y);

/* Sets the smallest size a window can be dragged to; 0 and 0 for no limit. */
void roci_set_smallest(roci_window_id window, double width, double height);

/* Sets the largest size a window can be dragged to; 0 and 0 for no limit. */
void roci_set_largest(roci_window_id window, double width, double height);

/* Sets the shape (width over height) a window keeps when it is resized; 0 for any. */
void roci_set_ratio(roci_window_id window, double ratio);

/* Sets how solid the whole window is, 0 (gone) to 255 (solid). */
void roci_set_window_alpha(roci_window_id window, double alpha);

/* Makes a window belong to another. */
void roci_set_parent(roci_window_id window, roci_window_id parent);

/* Sets the mouse cursor over a window: "arrow" or "none". */
void roci_set_cursor(roci_window_id window, const char *name);

/* Turns a yes-or-no setting of a window on or off, by the name the language uses: "fullscreen", "resizable", "bordered", "topmost", "visible", "focusable", "grab", "modal", "focused" (on brings it to the front), "maximized" or "minimized". */
void roci_set_window_flag(roci_window_id window, const char *name, int on);

/* Whether a yes-or-no fact about a window is true: the names of roci_set_window_flag, and "hovered" and "covered". */
int roci_window_flag(roci_window_id window, const char *name);

/* The width of a window in logical pixels. */
double roci_window_width(roci_window_id window);

/* The height of a window in logical pixels. */
double roci_window_height(roci_window_id window);

/* Where a window is on the screen. */
roci_vec2 roci_window_at_position(roci_window_id window);

/* Where the mouse is in a window. */
roci_vec2 roci_window_mouse(roci_window_id window);

/* How solid a window is, 0 to 255. */
double roci_window_alpha(roci_window_id window);

/* The shape a window keeps when resized; 0 for any. */
double roci_window_ratio(roci_window_id window);

/* The smallest size a window can be dragged to. */
roci_vec2 roci_window_smallest(roci_window_id window);

/* The largest size a window can be dragged to. */
roci_vec2 roci_window_largest(roci_window_id window);

/* The window a window belongs to, 0 for none. */
roci_window_id roci_window_parent(roci_window_id window);

/* The title of a window. The text stays valid until the next function that gives text back. */
const char *roci_window_title(roci_window_id window);

/* The name of the cursor over a window. The text stays valid until the next function that gives text back. */
const char *roci_window_cursor(roci_window_id window);

/* Turns waiting for the display's refresh on or off for the current window (on to start with). */
void roci_vsync(int on);

/* How many frames a second the sketch is drawing. */
double roci_fps(void);

/* The seed of this run, chosen at random unless roci_seed set it. */
unsigned long long roci_current_seed(void);

/* How far the wheel turned during the last frame: x to the right, y up. */
roci_vec2 roci_wheel(void);

/* 1 while any mouse button is held down in the current window. */
int roci_pressed(void);

/* 1 while the mouse button with this name ("left", "middle", "right", "back" or "forward") is down in the current window. */
int roci_mouse_button_down(const char *name);

/* The name of the key pressed last, or an empty text before any. The text stays valid until the next function that gives text back. */
const char *roci_last_key(void);

/* 1 while "shift", "ctrl" or "alt" is held, on either side. */
int roci_modifier_down(const char *name);

/* How many fingers are down in the current window. */
int roci_touch_count(void);

/* The finger at a place (from 0) in the order the fingers went down, every field 0 past the last. */
roci_finger roci_touch(int index);

/* Runs `handler` when something happens in a window (0 for whichever it happens in): `event` is "key", "mouse down", "mouse up", "touch down", "touch up", "resize", "move", "focus", "midi down", "midi up" or "midi control" (the first MIDI handler starts reading every MIDI device), and `argument` the key or mouse button it is for ("space", "right"), or NULL for any. */
void roci_on(roci_window_id window, const char *event, const char *argument, roci_event_fn handler);

/* Runs `handler` again and again in the current window, every `count` seconds, or frames when `unit` is "frames". */
void roci_every(double count, const char *unit, roci_draw_fn handler);

/* Makes a gradient from one to 16 colors and gives its number, or 0 when they do not fit. `kind` is 0 linear, 1 radial or 2 conic; `angle` is in degrees (0 runs left to right, clockwise); `space` is the color space the colors are mixed in, 0 Oklab, 1 RGB or 2 Oklch; `stops` is one percentage along the way for each color, or NULL to spread them evenly; `at_x` and `at_y` are the middle in percent of the shape for radial and conic (50 and 50 is the middle). */
roci_gradient_id roci_gradient(const roci_color *colors, int count, int kind, double angle, int space, const float *stops, double at_x, double at_y);

/* Fills with a gradient from now on. */
void roci_fill_gradient(roci_gradient_id gradient);

/* Outlines with a gradient from now on. */
void roci_stroke_gradient(roci_gradient_id gradient);

/* Paints the whole window with a gradient, behind everything. */
void roci_background_gradient(roci_gradient_id gradient);

/* A color by its CSS name ("orange", "teal"); clear black for a name that is not one. */
roci_color roci_named(const char *name);

/* A color from "#rgb", "#rgba", "#rrggbb" or "#rrggbbaa"; clear black for text that is not one. */
roci_color roci_hex(const char *text);

/* Blends two colors in a color space: 0 Oklab, 1 RGB or 2 Oklch. roci_mix is the Oklab one. */
roci_color roci_mix_in(roci_color first, roci_color second, double amount, int space);

/* Reads a picture file (PNG, JPEG, BMP, TGA or QOI) and gives its number, or 0 when it cannot be read. */
roci_image_id roci_load_image_file(const char *path);

/* The last frame of a window as a picture, `scale` times its logical size (1 or more), or 0 when there are no graphics to draw it. */
roci_image_id roci_picture_of_window(roci_window_id window, int scale);

/* The color of a pixel of a picture; clear black outside it. */
roci_color roci_pixel(roci_image_id picture, double x, double y);

/* Copies the colors of a picture, left to right and top to bottom, into `colors` as far as `capacity` allows (it may be NULL) and gives how many there are, or 0 for no picture or one of more than a million pixels. */
int roci_pixels(roci_image_id picture, roci_color *colors, int capacity);

/* Makes a picture of `width` by `height` from exactly that many colors, left to right and top to bottom, and gives it, or 0. */
roci_image_id roci_picture_from_colors(const roci_color *colors, int count, int width, int height);

/* A new picture of the part of a picture in a box from its top left, in pixels; the picture is left as it was. */
roci_image_id roci_crop(roci_image_id picture, double x, double y, double width, double height);

/* A new picture of a size (a side of 0 follows the picture's shape); `smooth` 0 keeps hard edges. */
roci_image_id roci_resize(roci_image_id picture, double width, double height, int smooth);

/* A new picture with a filter applied: "gray", "invert", "threshold", "posterize", "blur", "edges" or "pixelate". `amount` is what the filter uses (a brightness, a number of steps, a radius or a block size), or NaN for its usual. 0 for an unknown filter. */
roci_image_id roci_filter(roci_image_id picture, const char *name, double amount);

/* A new picture whose alpha is multiplied by how much of the stencil shows at each place, the stencil stretched over it. */
roci_image_id roci_mask(roci_image_id picture, roci_image_id stencil);

/* The corners of the solid part of a picture (its biggest piece, without holes), copied into `points` as far as `capacity` allows (it may be NULL), and how many there are. `alpha` is how solid a pixel has to be in percent (below 0 for 50); `at_x` and `at_y` put the picture where it is drawn, and a `width` and `height` of 0 leave it its own size. */
int roci_outline(roci_image_id picture, double alpha, double at_x, double at_y, double width, double height, roci_vec2 *points, int capacity);

/* Saves the current window as a PNG, SVG or PDF once the frame is drawn; a run of # in the name is the frame number. Gives 0 for a name that is none of those. What goes wrong later comes from roci_next_message. */
int roci_save(const char *path);

/* Starts recording the current window into a movie: ".apng", or ".mp4", ".mov", ".webm", ".mkv" or ".gif" through the user's ffmpeg. Gives 1, or 0 with the reason in roci_record_problem. */
int roci_record(const char *path);

/* Ends the current window's recording and writes the file. */
void roci_no_record(void);

/* Why the last roci_record gave 0, or an empty text. The text stays valid until the next function that gives text back. */
const char *roci_record_problem(void);

/* What saving and recording have to say, one message at a time (a file that could not be written, one not quite what the window shows, a recording that ended), or NULL when there is nothing more. The text stays valid until the next function that gives text back. */
const char *roci_next_message(void);

/* Translates the HLSL source of a shader and keeps it: `fill` 0 for an effect over a window or canvas, 1 for a shader that fills shapes; `file` names it in messages. Gives its number, or 0 when it is not a good shader, with what the translator said in roci_shader_message. */
roci_shader_id roci_add_shader(const char *source, const char *file, int fill);

/* Translates a changed source into a shader again. Gives 1 when it is good, or 0 with the message in roci_shader_message. */
int roci_update_shader(roci_shader_id shader, const char *source, const char *file);

/* What the translator said of the last shader that was not good, or an empty text. The text stays valid until the next function that gives text back. */
const char *roci_shader_message(void);

/* Runs a shader over the current window's frame once it is drawn, or over the canvas being drawn into. The shader's globals are given by name: `count` names, and in `values` the numbers of each one after the other, `counts` of each (1 to 4). Gives 0 for a shader that is not good. */
int roci_effect(roci_shader_id shader, const char *const *names, const double *values, const int *counts, int count);

/* Fills the shapes drawn from now on with a fill shader, until another fill is chosen; the values as for roci_effect. Gives 0 for a shader that is not good or is an effect. */
int roci_shade(roci_shader_id shader, const char *const *names, const double *values, const int *counts, int count);

/* Runs one of the effects that come with rocinante ("blur", "glow", "pixelate", "vignette", "split", "grain", "gray", "invert") over the frame, the values given by name as for roci_effect over the effect's own. Gives 0 for a name that is not one. */
int roci_builtin_effect(const char *name, const char *const *names, const double *values, const int *counts, int count);

/* How many effects come with rocinante. */
int roci_builtin_effect_count(void);

/* The name of a built-in effect (from 0), or NULL past the last. The text stays valid until the next function that gives text back. */
const char *roci_builtin_effect_name(int index);

/* Adds a font from the bytes of its file (a face of a collection by `face`) under a name, so roci_font finds it. Gives 1 when the bytes are a font. */
int roci_add_font(const char *name, const unsigned char *bytes, int length, int face);

/* Whether a font of this name is known. */
int roci_has_font(const char *name);

/* Whether two shapes touch, edges included. A flat shape and a shape in space never touch. */
int roci_touching(const roci_shape *a, const roci_shape *b);

/* Where two shapes touch: `normal` is the direction to move `a` to part them, `depth` how far, `point` a place where they touch. `touching` is 0, and every field 0, when they are apart. */
roci_contact_info roci_contact(const roci_shape *a, const roci_shape *b);

/* Whether a point is inside a shape, edges included. The point's z is not used for a flat shape. */
int roci_inside(roci_vec3 point, const roci_shape *shape);

/* Which items of a list a shape touches: copies their places in the list (from 0, in list order) into `out` as far as `capacity` allows (it may be NULL) and gives how many there are. A flat shape touches only flat items, and one in space only items in space. */
int roci_hits(const roci_shape *shape, const roci_shape *list, int count, int *out, int capacity);

/* The first item of a list a line from `from` to `to` meets: its place in the list, the point, the normal out of the shape and how far along the line. `index` is -1 (and the rest 0) when it meets nothing. The line is flat when the first item is. */
roci_cast_hit roci_cast(roci_vec3 from, roci_vec3 to, const roci_shape *list, int count);

/* Builds a tree of boxes for a list of shapes to ask about again and again; it answers what checking every shape answers, much faster for a long list. The shapes are copied. The tree is flat when the first shape is, and items of the other kind touch nothing. Gives the tree's number, or 0 for an empty list. */
roci_tree_id roci_collision_tree(const roci_shape *list, int count);

/* Lets a tree go. */
void roci_tree_free(roci_tree_id tree);

/* The items of a tree a shape touches, in list order, as roci_hits gives them. */
int roci_tree_hits(roci_tree_id tree, const roci_shape *shape, int *out, int capacity);

/* The first item of a tree a line meets, as roci_cast gives it. */
roci_cast_hit roci_tree_cast(roci_tree_id tree, roci_vec3 from, roci_vec3 to);

/* Runs `block` every frame after a window's draw (0 for the current window): the widgets of the window are made in it. They can also be made inside a draw function. */
void roci_ui(roci_window_id window, roci_draw_fn block);

/* A line of text in the interface. */
void roci_label(const char *text);

/* A button: gives 1 on the frame it is clicked. */
int roci_button(const char *text);

/* A check box that keeps its own value, `start` the first time its text is seen: gives 1 while it is ticked. */
int roci_toggle(const char *text, int start);

/* A slider that keeps its own value, `start` the first time its text is seen: gives its number. */
double roci_slider(const char *text, double low, double high, double start);

/* A number box with steppers that keeps its own value: gives it, inside `low` and `high`. */
double roci_number(const char *text, double low, double high, double start);

/* A box of text (`lines` high) that keeps its own text, `start` the first time its text is seen: copies what it holds into `out` (NUL-terminated, cut to `capacity`; it may be NULL) and gives the length of the whole text. */
int roci_textbox(const char *text, const char *start, int lines, char *out, int capacity);

/* A drop-down list of the items that keeps which is chosen (`start` the first time): gives its place, from 0, or -1 for no items. */
int roci_dropdown(const char *text, const char *const *items, int count, int start);

/* Radio buttons for the items; gives the place of the chosen one as roci_dropdown does. */
int roci_choice(const char *text, const char *const *items, int count, int start);

/* A selectable list of the items; gives the place of the chosen one as roci_dropdown does. */
int roci_list(const char *text, const char *const *items, int count, int start);

/* A color box that keeps its own color, `start` the first time its text is seen: gives it. */
roci_color roci_colorpicker(const char *text, roci_color start);

/* A rotary knob that keeps its own value: gives it, inside `low` and `high`. */
double roci_knob(const char *text, double low, double high, double start);

/* A two-handled range that keeps its own ends: gives them, the low one as x and the high one as y. */
roci_vec2 roci_range(const char *text, double low, double high, double start_low, double start_high);

/* A pad that keeps the place pressed on it, 0 to 1 across and down, starting at `start`: gives it. */
roci_vec2 roci_xypad(const char *text, roci_vec2 start);

/* A button that shows a picture, `width` by `height` across and down (0 and 0 for the picture's own size, down to 64 pixels on the longer side): gives 1 on the frame it is clicked. */
int roci_image_button(const char *text, roci_image_id picture, double width, double height);

/* A progress bar, from 0 to 1. */
void roci_progress(double fraction);

/* A line between widgets. */
void roci_separator(void);

/* Words that show beside the widget made just before, when the mouse rests on it. */
void roci_tip(const char *text);

/* An entry of a menu: gives 1 on the frame it is chosen. */
int roci_item(const char *text);

/* Opens a titled panel that folds up. Gives 1 when the widgets inside are to be made (it is open), and has to be closed with roci_panel_end either way. */
int roci_panel_begin(const char *text);

/* Closes the panel opened last. */
void roci_panel_end(void);

/* Opens a row: the widgets inside sit side by side. Close it with roci_row_end. */
int roci_row_begin(void);

/* Closes the row opened last. */
void roci_row_end(void);

/* Opens a column of widgets. Close it with roci_column_end. */
int roci_column_begin(void);

/* Closes the column opened last. */
void roci_column_end(void);

/* Opens a group of tabs, which holds roci_tab_begin groups. Close it with roci_tabs_end. */
int roci_tabs_begin(void);

/* Closes the group of tabs opened last. */
void roci_tabs_end(void);

/* Opens a tab of a group of tabs. Gives 1 when it is the one showing; close it with roci_tab_end either way. */
int roci_tab_begin(const char *text);

/* Closes the tab opened last. */
void roci_tab_end(void);

/* Opens a menu. Gives 1 when it is open, and its entries (roci_item) are made; close it with roci_menu_end either way. */
int roci_menu_begin(const char *text);

/* Closes the menu opened last. */
void roci_menu_end(void);

/* Says where the next widget or group goes (`has_at` 1: at x and y in the window's pixels, or, inside a draw function, on the canvas so it follows what is drawn) and how wide it is (`width` above 0). `name` is the widget's text, empty for a group with none. Call it just before the widget. */
void roci_place(const char *name, int has_at, double x, double y, double width);

/* Says that this call has made a widget `n` times already this frame (0 the first time), so widgets made in a loop that say the same keep apart. */
void roci_salt(int n);

/* Hides the current window's interface: its widgets are still made and read, but nothing is drawn and no input reaches them. */
void roci_ui_hide(void);

/* Shows the interface again, with the keyboard on its first widget. */
void roci_ui_show(void);

/* Changes the key that hides and shows the interface (the backtick to start with) to the key with this name ("f1"). Gives 0 for a name no key has. */
int roci_ui_key(const char *name);

/* Chooses the colors of the widgets: "dark", "light" or "system" (the computer's own, to start with). Any other word does nothing. */
void roci_ui_theme(const char *name);

/* Puts every widget of the window back to the value it starts with. */
void roci_forget_ui(void);

/* Remembers the widgets' values in this TOML file (such as "ui.toml") from now on, taking what it already says, and writes it when the sketch ends and after a pause in changes. */
void roci_ui_remember(const char *path);

/* Whether the window's interface drew anything in its last finished frame (nothing while it is hidden). */
int roci_ui_drawn(roci_window_id window);

/* How many mistakes the window's widgets have (two with one text), each said once. */
int roci_ui_problem_count(roci_window_id window);

/* One of those mistakes by its place (from 0), or NULL. The text stays valid until the next function that gives text back. */
const char *roci_ui_problem(roci_window_id window, int index);

/* Sends a message of any kind: a number, text, true or false, a point or a list of messages (which can hold lists in turn). It arrives on that window's next frame, and what is sent is copied. */
void roci_send(roci_window_id to, const roci_value *message);

/* Sends true or false to a window. */
void roci_send_boolean(roci_window_id to, int on);

/* Moves a number from where it is to `to` over `seconds`, a little each frame, on a curve ("smooth", the usual, "linear", "in", "out", "back", "elastic" or "bounce"), landing exactly on it. The place has to stay where it is until the tween ends. A new tween of the same place replaces the old one. */
void roci_tween(double *place, double to, double seconds, const char *curve);

/* The same for a point. */
void roci_tween_vec2(roci_vec2 *place, roci_vec2 to, double seconds, const char *curve);

/* The same for a point in space. */
void roci_tween_vec3(roci_vec3 *place, roci_vec3 to, double seconds, const char *curve);

/* The same for a color, mixed in Oklab on the way. */
void roci_tween_color(roci_color *place, roci_color to, double seconds, const char *curve);

/* Ends every tween where it is, without landing. */
void roci_stop_tweens(void);

/* A random place in the current window. */
roci_vec2 roci_anywhere(void);

/* A random place in a list of `count` items, from 0, by the sketch's own random numbers (so a seed repeats it); -1 for an empty list. */
int roci_pick_index(int count);

/* Mixes the `count` items of an array, each `size` bytes, by the sketch's own random numbers, so a seed repeats it. */
void roci_shuffle(void *items, int count, size_t size);

/* Writes a line to the console. */
void roci_print(const char *text);

/* 1 while a key is held, by its name ("space", "a", "left"), or a mouse button of the current window, as "mouse right". */
int roci_held(const char *name);

/* Saves the style (fill, stroke, thickness, font and the rest, not the transform) until the matching roci_pop_style: what is set in between is for the shapes in between only, as the language's `with` is. */
void roci_push_style(void);

/* Puts back the style roci_push_style saved. Gives 0 for a pop without a push. */
int roci_pop_style(void);

/* Says what the position of the next shape means: "center" or "corner" ("default" for the shape's usual), as the language's `as center` and `as corner`. It is for the next circle, ellipse, rectangle, square, arc or picture only. */
void roci_origin(const char *word);

/* Draws text with its top at a point, broken into lines of at most `width` pixels. */
void roci_text_wrapped(const char *text, double x, double y, double width);

/* The same at a point given as a vector. */
void roci_text_wrapped_v(const char *text, roci_vec2 position, double width);

/* How big a text is in the current font when it is broken into lines of at most `width` pixels: its width and height. */
roci_vec2 roci_measure_wrapped(const char *text, double width);

/* Starts a sketch with no windows and no graphics, so that the verbs record and roci_step runs a frame at a time: for tests of a program, and for pictures made with roci_picture_of_window. */
void roci_start_headless(unsigned long long seed);

/* Runs one frame of a sketch started with roci_start_headless, or of one that is showing, which is how a program can drive it itself. */
void roci_step(void);

/* Closes every window and gives everything back. The sketch can be started again. */
void roci_shutdown(void);

/* What went wrong when the graphics could not start, or an empty text. The text stays valid until the next function that gives text back. */
const char *roci_last_error(void);

/* Sets the size of the window a sketch gets when it never calls roci_window. */
void roci_default_window_size(double width, double height);

/* A number that is the same for two frames that look the same, for a window's last frame: what tests compare. */
unsigned long long roci_frame_hash(roci_window_id window);

/* Sends an OSC message to another program, a phone or another sketch: `args` holds `count` values, each a number (a whole number goes as an integer, any other as a float), text, a boolean, or a list of numbers, which goes as a blob of bytes. `host` is a name or an address (NULL for this computer) and `port` the port (0 for 9000). Gives 1 when it was sent, and 0 when the address does not begin with a slash, the host is unknown or the system would not send it. */
int roci_osc_send(const char *address, const roci_value *args, int count, const char *host, int port);

/* Sends several OSC messages together as one bundle, which the receiver reads as a group: `messages` holds `count` values of kind ROCI_LIST, each a message whose first item is its address (text) and whose other items are its arguments, as for roci_osc_send. Gives 1 when it was sent, and 0 when an address does not begin with a slash, the host is unknown or the system would not send it. */
int roci_osc_send_bundle(const roci_value *messages, int count, const char *host, int port);

/* Decodes the bytes of a sound file (WAV, FLAC, MP3 or Ogg Vorbis) and gives its number, or 0 when they are not a sound. A sound is stopped at its start, at volume 100, in the middle and at speed 1. */
roci_sound_id roci_load_sound(const unsigned char *bytes, int length);

/* Opens a sound file (WAV, FLAC, MP3 or Ogg Vorbis) and gives its number, or 0 when it cannot be read. A file longer than 30 seconds is not decoded whole: it is read from the disk as it plays, so a long song costs little memory (roci_load_sound, from bytes, always decodes whole). */
roci_sound_id roci_load_sound_file(const char *path);

/* Moves a sound some seconds back, no further than its start. */
void roci_rewind_by(roci_sound_id sound, double seconds);

/* Moves a sound some seconds ahead; past its end, a sound that does not loop has ended and one that loops goes on from its start. */
void roci_forward_sound(roci_sound_id sound, double seconds);

/* Puts a sound that many seconds from its start, kept between its start and its end. */
void roci_set_sound_at(roci_sound_id sound, double seconds);

/* How loud a sound plays, 0 to 100. */
void roci_set_sound_volume(roci_sound_id sound, double volume);

/* Where a sound is between the speakers, -100 (left) to 100 (right): in the middle both play it at full volume, towards one side the other fades. */
void roci_set_sound_pan(roci_sound_id sound, double pan);

/* How fast a sound plays, 1 as recorded, 0 (held still) to 8; faster is higher, as on a record player. */
void roci_set_sound_speed(roci_sound_id sound, double speed);

/* Whether a sound starts again at its end: 0 lets a looping sound finish where it is. */
void roci_set_sound_loop(roci_sound_id sound, int on);

/* 1 while a sound is playing. */
int roci_sound_playing(roci_sound_id sound);

/* 1 when a sound starts again at its end. */
int roci_sound_loops(roci_sound_id sound);

/* Where a sound is, in seconds from its start. */
double roci_sound_at(roci_sound_id sound);

/* How long a sound is, in seconds (0 for no sound). */
double roci_sound_length(roci_sound_id sound);

/* How loud a sound plays, 0 to 100. */
double roci_sound_volume(roci_sound_id sound);

/* Where a sound is between the speakers, -100 to 100. */
double roci_sound_pan(roci_sound_id sound);

/* Plays a note (60 is middle C, each step a semitone) for some seconds, or held until roci_pause_note when `seconds` is 0. An instrument's notes sound together; a sound from a file plays as if it were middle C, faster for a higher note. */
void roci_play_note(roci_sound_id sound, double note, double seconds);

/* Lets an instrument's notes of that number go; they fade out. roci_pause lets all of them go. */
void roci_pause_note(roci_sound_id sound, double note);

/* Sets an instrument's pitch: its sounding notes slide there, and a note played with none takes it. A sound from a file plays at the speed that makes it that pitch, taking it to be middle C. */
void roci_set_sound_pitch(roci_sound_id sound, double hertz);

/* An instrument's pitch in hertz, or middle C at the speed of a sound from a file. */
double roci_sound_pitch(roci_sound_id sound);

/* Reads a SoundFont (.sf2) and makes an instrument of one of its presets, by number (General MIDI's 0 is a piano), or the first one for -1 or a number it does not have; 0 when the file cannot be read. Its notes are played with roci_play_note. */
roci_sound_id roci_soundfont(const char *path, int preset);

/* The same, the preset found by its name in any case (the first one when no preset has it). */
roci_sound_id roci_soundfont_named(const char *path, const char *preset);

/* The whole mix, as a sound for roci_sound_effect (its effects run over everything that plays, last) and roci_level_of. */
roci_sound_id roci_speakers(void);

/* Puts a sound effect on a sound or the speakers ("overdrive", "fuzz", "delay", "reverb", "chorus", "flanger", "phaser", "tremolo", "compressor", "eq", "rotary", "filter", "bitcrush", "ring", "wah" or "limiter"), at the end of its effects, with its start values; 1 when it is on, 0 for a name no effect has or no sound. */
int roci_sound_effect(roci_sound_id sound, const char *name);

/* Sets a setting of a sound's effect, putting the effect on first if it has none: amounts 0 to 100, times in seconds, rates in times a second, pitches in hertz, eq bands -100 to 100. 0 for a setting the effect has not. */
int roci_sound_effect_set(roci_sound_id sound, const char *name, const char *setting, double value);

/* The same for a setting that is a word: the filter's kind, "low", "high" or "band". */
int roci_sound_effect_word(roci_sound_id sound, const char *name, const char *setting, const char *word);

/* Takes a sound effect off a sound or the speakers; 0 when it had none of that name. */
int roci_no_sound_effect(roci_sound_id sound, const char *name);

/* The microphone, as a sound for roci_level_of and roci_bands_of. The first call in a program with a window opens the computer's default recording device (the system may ask first). Playing it does nothing. */
roci_sound_id roci_mic(void);

/* How much of each pitch everything that plays holds now: writes `count` numbers 0 to 100 (at most 256), the lowest pitches first, into `out`, and gives how many it wrote. */
int roci_bands(int count, double *out);

/* The same for one sound, or the microphone (roci_mic). */
int roci_bands_of(roci_sound_id sound, int count, double *out);

/* How fast a sound plays, 1 as recorded. */
double roci_sound_speed(roci_sound_id sound);

#ifdef __cplusplus
}
#endif

#endif /* ROCI_H */
