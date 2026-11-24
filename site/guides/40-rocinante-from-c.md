---
title: "rocinante from C"
summary: "Use rocinante as a C library: one header, one library and a draw function give you a window, and any other C library joins in with an include. Three examples: a kaleidoscope, a reaction-diffusion library of its own, and an stb header."
weight: 40
---

Everything a sketch can do, a C program can do too. rocinante comes as a C library with one header, `include/roci.h`, and the functions in it are the verbs you already know, each with `roci_` in front: `circle at 100 100 radius 50` is `roci_circle(100, 100, 50)`. If you know the language, you already know the C API. A whole program is this short:

```c
#include "roci.h"

static void draw(void) {
	roci_background_gray(30);
	roci_fill(roci_rgb(255, 99, 71));
	roci_circle(roci_mouse().x, roci_mouse().y, 40);
}

int main(void) {
	roci_draw(0, draw);
	return roci_run(0) ? 0 : 1;
}
```

That is `examples/c/circle.c`, nearly. `roci_draw` says what to draw each frame (0 is the window the sketch opens when it opens none) and `roci_run` opens the window and keeps it open until it is closed. Windows, the mouse and keys, text, pictures, sound, MIDI, widgets and 3D are all there in the same way.

## Building it

Build rocinante as a shared library once, from the repository, then build your program against the header and the library:

```
odin build roci -build-mode:shared -no-entry-point -out:output/libroci.dylib
cc examples/c/circle.c -Iinclude -Loutput -lroci -o output/c_circle
DYLD_LIBRARY_PATH=output ./output/c_circle
```

On Linux, FreeBSD and OpenBSD the library is `output/libroci.so` and the last line starts with `LD_LIBRARY_PATH=output`. You need what rocinante itself needs (Odin and SDL3, see [Getting started](../01-getting-started/)) and a C compiler. On Windows the same `odin build` with `-out:output/roci.dll` makes a DLL; building the C examples there has not been tried yet.

`tools/abi-check.sh` builds the library and every program in `examples/c`, and `tools/abi-check.sh --run` runs each one for two seconds.

## Events and the file dialog: a kaleidoscope

`examples/c/kaleidoscope.c` asks you for a picture and turns it into a kaleidoscope you steer with the mouse. It uses events, the file dialog and a picture as a fill.

An event is a function you hand over. A click, a key or a resize calls a function of yours, with the key's or the button's name in the event:

```c
static void more_slices(const roci_event *event) {
	(void)event;
	if (slices < MOST_SLICES) slices += 2;
}

roci_on(0, "key", "up", more_slices);
roci_on(0, "mouse down", "left", choose_picture);
```

The system's file dialog does not stop the program. `roci_ask` opens it and gives a number; each frame, `roci_answer` with that number says whether there is an answer yet: `NULL` while the dialog is open, an empty text when it was closed, and the path when a file was chosen:

```c
request = roci_ask("file", "png jpg jpeg bmp tga qoi", "");
...
const char *path = roci_answer(request);
if (path != NULL && path[0] != '\0') picture = roci_load_image_file(path);
```

And the kaleidoscope itself is a picture used as the fill of a thin triangle, drawn again for each slice, turned a little more each time and mirrored every other time, exactly as you would write it in a sketch with `push`, `turn` and `grow`:

```c
roci_fill_image_as(picture, 3, zoom, offset_x, offset_y);  /* 3: as tile */
for (int i = 0; i < slices; i++) {
	roci_push();
	roci_move(middle.x, middle.y);
	roci_turn(spin + i * 360.0 / slices);
	if (i % 2 == 1) roci_grow_xy(1, -1);
	roci_triangle(0, 0, left.x, left.y, right.x, right.y);
	roci_pop();
}
```

The mouse slides the picture under the slices, the wheel zooms it, the up and down arrows give more or fewer slices, and a click asks for another picture.

## A C library of your own: reaction-diffusion

Often you write C because there is a C library you want to use, your own or someone else's. The library does not have to know about rocinante. Your program calls both.

`examples/c/gray_scott.c` is a small library written for this guide, the kind you might already have: it runs the Gray-Scott model of two chemicals that react and spread over a grid, and knows nothing about windows or drawing. Its header is seven functions (`gray_scott_create`, `gray_scott_step`, `gray_scott_b` and a few more). `examples/c/reaction.c` moves the reaction on each frame, turns each cell into a color, and hands the colors to rocinante as a picture that fills the window:

```c
gray_scott_step(grid, STEPS_A_FRAME);
for (int y = 0; y < GRID; y++) {
	for (int x = 0; x < GRID; x++) {
		colors[y * GRID + x] = color_of(gray_scott_b(grid, x, y));
	}
}
roci_image_id frame = roci_picture_from_colors(colors, GRID * GRID, GRID, GRID);
roci_image_sized(frame, 0, 0, width, height);
```

A picture made from the same colors again is the same picture, and those not drawn for a while are let go, so making one each frame is fine. Building it only adds the library's file to the line:

```
cc examples/c/reaction.c examples/c/gray_scott.c -Iinclude -Loutput -lroci -o output/c_reaction
```

Hold the mouse down to pour in more of the reaction, 1 and 2 choose two well-known patterns (coral, and cells that split), and the arrows change the two rates the patterns come from.

## A single-file library: stb_rect_pack

Many C libraries are a single header. Sean Barrett's [stb libraries](https://github.com/nothings/stb) are the best known (MIT or public domain, as you prefer). `examples/c/packing.c` uses `stb_rect_pack.h`, copied beside it as it is, which packs rectangles into a space as tightly as it can, for sprite sheets and font atlases. Bringing it in is the two lines its own instructions ask for, in one file of your program:

```c
#define STB_RECT_PACK_IMPLEMENTATION
#include "stb_rect_pack.h"
```

After that you call stb's functions next to rocinante's. Each frame the program asks stb to pack a few hundred rectangles into the window and draws them where stb put them:

```c
stbrp_init_target(&context, space_w, space_h, nodes, space_w);
stbrp_pack_rects(&context, rects, count);
for (int i = 0; i < count; i++) {
	if (!rects[i].was_packed) continue;
	roci_fill(roci_hsb((i * 37) % 255, 150, 230));
	roci_rect(MARGIN + rects[i].x, MARGIN + rects[i].y, rects[i].w, rects[i].h);
}
```

Moving the mouse changes how many rectangles there are and how big, and the packing changes with it. h switches between stb's two ways of choosing a place, and the bottom line says how much of the space is used.

## What comes next

Here C uses rocinante. The other way round, a sketch calling C (a library of verbs written in C or Odin that a `.roci` file brings in with `use`), is planned and not built yet; when it comes, a C library like `gray_scott` will be able to give its functions to sketches as verbs.
