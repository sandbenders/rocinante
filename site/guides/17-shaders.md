---
title: "Shaders"
summary: "Effects: shaders of your own, written in HLSL, that run over the finished picture of the window, with values from the sketch and live reloading."
weight: 17
---

A shader is a small program the graphics card runs for every pixel. In rocinante it is a file in your sketch's `assets` folder, written in HLSL, and `effect` runs it over the finished picture of the window, so it can warp, tint, blur or darken everything that was drawn. Here `wave.hlsl` sways the stripes sideways:

```roci picture
background 235
colors = [ tomato gold seagreen steelblue orchid ]
for i from 1 to 5 [
  fill (item i of colors)
  rect at (20 + (i - 1) * 74) 40 size 60 220
]
effect "wave.hlsl" by { amount: 0.02, phase: time * 3 }
```

The shader is found by its file name, like a picture or a font. This is `assets/shaders/wave.hlsl`:

```
float amount;
float phase;

float4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    float2 p = uv;
    p.x += sin(p.y * 30.0 + phase) * amount;
    return scene.Sample(scene_sampler, p);
}
```

## What a shader is given

You write one function, `ps_main`. It runs for every pixel of the window and gives back that pixel's color. These come with every shader, so you never declare them:

- `scene` and `scene_sampler`: the picture the sketch drew. `scene.Sample(scene_sampler, uv)` is its color at `uv`.
- `uv`, the argument of `ps_main`: where this pixel is, from 0 to 1 across and down from the top left. `position` is the same place in pixels.
- `size`: the window's size in pixels, `mouse`: where the mouse is, `time`: seconds since the sketch began and `frame`: the frame number.

The colors are 0 to 1, as in every shader, and a pixel's color is `float4(red, green, blue, alpha)`.

## Giving it values

Any other global at the top of the shader, such as `float amount;`, is a value the sketch gives it by name after `by`. A value is a number, a vector of two to four numbers or a color, and one a sketch leaves out is 0:

```roci
effect "tint.hlsl" by { strength: 0.4, spot: { 120, 80 }, color: teal }
```

A color arrives as 0 to 1, ready for the shader's math. A name the shader does not have is said, with the names it has, and the others still go.

## Several effects, and where they run

Effects run in the order they are written, each over the picture the one before it made, so a wave and then a vignette is two lines. An effect belongs to the window it is written for and runs once the whole frame is drawn: it cannot be written inside `draw into`, because a canvas is not a window. Everything the window shows, including `image` of a canvas, goes through it.

## Editing while it runs

A shader is read again every time its file is saved, in the running sketch, with nothing else restarting. Change a number, save, and the picture changes. A mistake in a shader is said in the shader's own words, with its line, and the picture is drawn without the effect until the next save mends it:

```message
── There is a mistake in the shader `broken.hlsl` ────── sketch.roci:1:1

1 │ effect "broken.hlsl"
  │ ^^^^^^^^^^^^^^^^^^^^

broken.hlsl:1: error: 'oops' : unknown variable
broken.hlsl:1: error: 'return' : type does not match, or is not convertible to, the function's return type

The effect is left out until it is mended, and the sketch carries on. The shader is read again when you save it.
```

## A shader that draws everything itself

A shader does not have to use `scene`. It can make the whole picture from the numbers it is given, as the shaders on Shadertoy do, and lay what the sketch drew over it. Start the frame with `clear` instead of `background`, so the empty parts of what the sketch drew are see-through, and let the shader put `scene` on top where its alpha is not 0.

`examples/effects` has two shaders, a wave and a vignette that follows the mouse. `examples/tunnel` has a tunnel made from nothing by one shader, with the sketch's dots and word laid over it, and a lens effect over both.
