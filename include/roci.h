/* SPDX-License-Identifier: 0BSD
 *
 * rocinante's C API. Generated from the verb registry (roci/registry) and
 * ABI_TABLE (roci/abi_header.odin) by 'odin run tools/header -- include/roci.h';
 * do not edit it by hand.
 *
 * Numbers are double, text is a NUL-terminated const char *, colors are
 * roci_color (four floats, each 0 to 255), points are roci_vec2 (roci_vec3 in space), windows are
 * roci_window_id, pictures roci_image_id and models roci_model_id and drawings roci_svg_id (ints; 0 is none) and true and false are int. A verb with
 * several shapes has one function per shape: the first keeps the verb's name and
 * the others add a suffix (_v is the form that takes points; sized takes a size for each side).
 */
#ifndef ROCI_H
#define ROCI_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct { float r, g, b, a; } roci_color;
typedef struct { double x, y; } roci_vec2;
typedef struct { double x, y, z; } roci_vec3;
typedef int roci_window_id;
typedef int roci_image_id;
typedef int roci_model_id;
typedef int roci_svg_id;
typedef struct { roci_vec3 from, to; } roci_line3;

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

/* Walks the turtle forward, drawing a line while its pen is down. */
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

#ifdef __cplusplus
}
#endif

#endif /* ROCI_H */
