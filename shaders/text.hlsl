// SPDX-License-Identifier: 0BSD
//
// The text shader (CLAUDE.md section 8, Phase 1): draws the overlay font, one
// instanced quad per character, from a texture that holds the glyphs in a grid
// (roci/gfx/font.odin). The instance is Glyph_Instance in roci/gfx/batch.odin: a
// transform from glyph pixels (a glyph is 8 x 8) to canvas pixels, a colour and a
// glyph number. Sampling is nearest, so the pixels of the font stay crisp. The
// output is premultiplied, like the other shaders.

cbuffer Frame : register(b0, space1)
{
    float2 canvas_size; // the window in logical pixels, as sketches see it
    float2 unused;
};

Texture2D<float> font_texture : register(t0, space2);
SamplerState font_sampler : register(s0, space2);

static const float GLYPH_SIZE = 8.0;
static const uint ATLAS_COLUMNS = 16;
static const float2 ATLAS_SIZE = float2(128.0, 48.0);

struct VSInput
{
    float4 transform_abcd : TEXCOORD0;
    float2 transform_ef : TEXCOORD1;
    float4 colour : TEXCOORD2;
    uint glyph : TEXCOORD3;
    uint vertex_id : SV_VertexID;
};

struct VSOutput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    nointerpolation float4 colour : TEXCOORD1;
};

VSOutput vs_main(VSInput input)
{
    float2 corners[6] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(0, 1), float2(1, 0), float2(1, 1)
    };
    float2 p = corners[input.vertex_id] * GLYPH_SIZE; // in glyph pixels
    float2 canvas = float2(input.transform_abcd.x * p.x + input.transform_abcd.z * p.y + input.transform_ef.x,
                           input.transform_abcd.y * p.x + input.transform_abcd.w * p.y + input.transform_ef.y);

    VSOutput output;
    output.position = float4(canvas.x / canvas_size.x * 2.0 - 1.0,
                             1.0 - canvas.y / canvas_size.y * 2.0, 0.0, 1.0);
    float2 cell = float2(input.glyph % ATLAS_COLUMNS, input.glyph / ATLAS_COLUMNS) * GLYPH_SIZE;
    output.uv = (cell + p) / ATLAS_SIZE;
    output.colour = input.colour;
    return output;
}

float4 ps_main(VSOutput input) : SV_Target0
{
    float ink = font_texture.Sample(font_sampler, input.uv);
    float alpha = input.colour.a * ink;
    return float4(input.colour.rgb * alpha, alpha);
}
