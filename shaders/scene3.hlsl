// SPDX-License-Identifier: 0BSD
//
// The 3D shader: draws the boxes, spheres and planes of a scene (roci/gfx/scene3.odin)
// with a depth buffer. Each instance is one shape: three rows of the transform from the
// shape's own space to the world (the last row is always 0 0 0 1) and a color. The
// matrices are passed as rows and multiplied out with dot products, so no system's idea
// of how a matrix is laid out matters. The shading is one light and a little ambient light,
// worked out per pixel, and a surface is lit on whichever side faces the eye.
// The vertex layout is Vertex3 and Instance3 in scene3.odin: TEXCOORD0 to 2 are per vertex,
// TEXCOORD3 to 7 per instance.

cbuffer Scene : register(b0, space1)
{
    float4 clip_x;  // the rows of the matrix from the world to the screen
    float4 clip_y;
    float4 clip_z;
    float4 clip_w;
    float4 eye;     // where the eye is, in the world
    float4 light;   // the direction to the light, in the world
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
};

struct VSOutput
{
    float4 position : SV_Position;
    float3 world : TEXCOORD0;
    float3 normal : TEXCOORD1;
    float4 colour : TEXCOORD2;
    float3 eye : TEXCOORD3;    // the fragment stage cannot read the vertex stage's uniform block, so these two ride along
    float3 light : TEXCOORD4;
};

VSOutput vs_main(VSInput input)
{
    VSOutput output;
    // A capsule's two halves move apart by params.x, and a torus's ring grows a tube params.y thick.
    float3 shaped = input.position + input.normal * input.params.y;
    shaped.y += input.stretch * input.params.x;
    float4 p = float4(shaped, 1.0);
    float4 w = float4(dot(input.row0, p), dot(input.row1, p), dot(input.row2, p), 1.0);
    output.position = float4(dot(clip_x, w), dot(clip_y, w), dot(clip_z, w), dot(clip_w, w));
    output.world = w.xyz;
    // The normal goes through the cofactor matrix, which keeps it square to the surface
    // when the shape is stretched.
    float3 a0 = input.row0.xyz;
    float3 a1 = input.row1.xyz;
    float3 a2 = input.row2.xyz;
    float3 c0 = cross(a1, a2);
    float3 c1 = cross(a2, a0);
    float3 c2 = cross(a0, a1);
    output.normal = float3(dot(c0, input.normal), dot(c1, input.normal), dot(c2, input.normal));
    output.colour = input.colour;
    output.eye = eye.xyz;
    output.light = light.xyz;
    return output;
}

float4 ps_main(VSOutput input) : SV_Target0
{
    float3 n = normalize(input.normal);
    float3 v = normalize(input.eye - input.world);
    if (dot(n, v) < 0.0)
    {
        n = -n;
    }
    float lit = saturate(dot(n, normalize(input.light)));
    float shade = 0.28 + 0.72 * lit;
    return float4(input.colour.rgb * shade, 1.0);
}
