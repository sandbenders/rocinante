// SPDX-License-Identifier: 0BSD
//
// The typeset text shader: draws real text, the triangles SDL_ttf's GPU text engine
// makes for a text, with positions already on the canvas (roci/gfx/typeset.odin does
// the layout and the transform). Each corner holds its colour and whether its atlas
// holds plain glyphs (the colour of the text takes their coverage) or colour glyphs
// such as emoji (the glyph's own colours). A picture is drawn through the same
// shader with 2: its own colours multiplied by the tint. Beyond 2 the number is a set of
// flags added to it: 1 for a picture whose colours are already multiplied by its alpha (a
// canvas, which the renderer drew into), 2 to show nothing where the corner's place falls
// outside the picture (a shape filled with a picture that does not reach it), and 4 to
// repeat the picture (a tiled fill).
// The output is premultiplied, like the other shaders.

cbuffer Frame : register(b0, space1)
{
    float2 canvas_size; // the window in logical pixels, as sketches see it
    float2 unused;
};

Texture2D<float4> atlas_texture : register(t0, space2);
SamplerState atlas_sampler : register(s0, space2);

struct VSInput
{
    float2 position : TEXCOORD0; // canvas pixels
    float2 uv : TEXCOORD1;
    float4 colour : TEXCOORD2;
    float coloured : TEXCOORD3; // 0 for plain glyphs, 1 for colour glyphs, 2 for a picture, 3 for a premultiplied one
};

struct VSOutput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    nointerpolation float4 colour : TEXCOORD1;
    nointerpolation float coloured : TEXCOORD2;
};

VSOutput vs_main(VSInput input)
{
    VSOutput output;
    output.position = float4(input.position.x / canvas_size.x * 2.0 - 1.0,
                             1.0 - input.position.y / canvas_size.y * 2.0, 0.0, 1.0);
    output.uv = input.uv;
    output.colour = input.colour;
    output.coloured = input.coloured;
    return output;
}

float4 ps_main(VSOutput input) : SV_Target0
{
    int mode = (int)(input.coloured + 0.5);
    int flags = mode >= 2 ? mode - 2 : 0;
    float2 uv = input.uv;
    if ((flags & 4) != 0)
    {
        uv = frac(uv);
    }
    float4 glyph = atlas_texture.SampleLevel(atlas_sampler, uv, 0);
    if ((flags & 2) != 0 && (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0))
    {
        return float4(0.0, 0.0, 0.0, 0.0);
    }
    if ((flags & 1) != 0)
    {
        // already premultiplied: the tint scales every part of it by its colour and alpha
        return float4(glyph.rgb * input.colour.rgb * input.colour.a, glyph.a * input.colour.a);
    }
    float alpha = input.colour.a * glyph.a;
    float3 rgb = mode >= 2 ? glyph.rgb * input.colour.rgb
                                      : lerp(input.colour.rgb, glyph.rgb, input.coloured);
    return float4(rgb * alpha, alpha);
}
