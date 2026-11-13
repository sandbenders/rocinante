// SPDX-License-Identifier: 0BSD
//
// The shadow shader: draws the solids of a scene (roci/gfx/scene3.odin) as a light sees them,
// into a texture that holds how far from the light the nearest surface is at each pixel. The
// scene's shader reads that to tell what the light does not reach. The instance layout is the
// scene shader's (Instance3), and the matrix is the light's, as four rows.

#include "scene3_shape.hlsli"

cbuffer Light : register(b0, space1)
{
    float4 clip_x;
    float4 clip_y;
    float4 clip_z;
    float4 clip_w;
};

struct VSInput
{
    float3 position : TEXCOORD0;
    float3 normal : TEXCOORD1;
    float stretch : TEXCOORD2;
    float4 row0 : TEXCOORD3;
    float4 row1 : TEXCOORD4;
    float4 row2 : TEXCOORD5;
    float4 colour : TEXCOORD6;
    float4 params : TEXCOORD7;
    float4 material : TEXCOORD8;
};

struct VSOutput
{
    float4 position : SV_Position;
};

VSOutput vs_main(VSInput input)
{
    VSOutput output;
    float4 w = float4(shape_world(input.position, input.normal, input.stretch, input.row0, input.row1, input.row2, input.params), 1.0);
    output.position = float4(dot(clip_x, w), dot(clip_y, w), dot(clip_z, w), dot(clip_w, w));
    return output;
}

// The depth, as a color, because a color texture can be read by every system and a depth texture cannot.
float4 ps_main(VSOutput input) : SV_Target0
{
    return float4(input.position.z, 0.0, 0.0, 1.0);
}
