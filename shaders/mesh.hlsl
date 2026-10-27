// SPDX-License-Identifier: 0BSD
//
// The mesh shader (CLAUDE.md section 4.3): draws the triangles that package geom
// makes on the CPU for quads, arcs and outlines with mitred or bevelled corners.
// Each vertex has a position on the canvas (logical pixels, origin top left) and
// a colour with straight alpha (or a gradient, see gradient.hlsli); the output is
// premultiplied, like shapes.hlsl.
// Edges are smoothed by multisampling, not here. The vertex layout is
// Mesh_Vertex in roci/gfx/mesh.odin: TEXCOORD0 is the position, TEXCOORD1 the colour.

#include "gradient.hlsli"

cbuffer Frame : register(b0, space1)
{
    float2 canvas_size;
    float2 unused;
};

struct VSInput
{
    float2 position : TEXCOORD0;
    float4 colour : TEXCOORD1;
    float2 local : TEXCOORD2;   // measured from the middle of the shape's box
    float2 box_half : TEXCOORD3;
    uint gradient : TEXCOORD4;  // 1 and up, or 0 for the plain colour
};

struct VSOutput
{
    float4 position : SV_Position;
    float4 colour : TEXCOORD0;
    float2 local : TEXCOORD1;
    nointerpolation float2 box_half : TEXCOORD2;
    nointerpolation uint gradient : TEXCOORD3;
};

VSOutput vs_main(VSInput input)
{
    VSOutput output;
    output.position = float4(input.position.x / canvas_size.x * 2.0 - 1.0,
                             1.0 - input.position.y / canvas_size.y * 2.0, 0.0, 1.0);
    output.colour = input.colour;
    output.local = input.local;
    output.box_half = input.box_half;
    output.gradient = input.gradient;
    return output;
}

float4 ps_main(VSOutput input) : SV_Target0
{
    float4 colour = input.colour;
    if (input.gradient != 0)
    {
        // The vertex colour then holds only the style's alpha.
        float4 g = gradient_colour(input.gradient, input.local, input.box_half);
        colour = float4(g.rgb, g.a * input.colour.a);
    }
    return float4(colour.rgb * colour.a, colour.a);
}
