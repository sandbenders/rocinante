// SPDX-License-Identifier: 0BSD
//
// The typeset text shader: draws real text, the triangles SDL_ttf's GPU text engine
// makes for a text, with positions already on the canvas (roci/gfx/typeset.odin does
// the layout and the transform). Each corner holds its colour and whether its atlas
// holds plain glyphs (the colour of the text takes their coverage) or colour glyphs
// such as emoji (the glyph's own colours). The output is premultiplied, like the
// other shaders.

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
    float coloured : TEXCOORD3; // 0 for plain glyphs, 1 for colour glyphs
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
    float4 glyph = atlas_texture.Sample(atlas_sampler, input.uv);
    float alpha = input.colour.a * glyph.a;
    float3 rgb = lerp(input.colour.rgb, glyph.rgb, input.coloured);
    return float4(rgb * alpha, alpha);
}
