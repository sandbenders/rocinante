// SPDX-License-Identifier: 0BSD
//
// The mesh shader (CLAUDE.md section 4.3): draws the triangles that package geom
// makes on the CPU for quads, arcs and outlines with mitred or bevelled corners.
// Each vertex has a position on the canvas (logical pixels, origin top left) and
// a colour with straight alpha; the output is premultiplied, like shapes.hlsl.
// Edges are smoothed by multisampling, not here. The vertex layout is
// Mesh_Vertex in roci/gfx/mesh.odin: TEXCOORD0 is the position, TEXCOORD1 the colour.

cbuffer Frame : register(b0, space1)
{
    float2 canvas_size;
    float2 unused;
};

struct VSInput
{
    float2 position : TEXCOORD0;
    float4 colour : TEXCOORD1;
};

struct VSOutput
{
    float4 position : SV_Position;
    float4 colour : TEXCOORD0;
};

VSOutput vs_main(VSInput input)
{
    VSOutput output;
    output.position = float4(input.position.x / canvas_size.x * 2.0 - 1.0,
                             1.0 - input.position.y / canvas_size.y * 2.0, 0.0, 1.0);
    output.colour = input.colour;
    return output;
}

float4 ps_main(VSOutput input) : SV_Target0
{
    return float4(input.colour.rgb * input.colour.a, input.colour.a);
}
