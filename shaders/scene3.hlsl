// SPDX-License-Identifier: 0BSD
//
// The 3D shader: draws the solids of a scene (roci/gfx/scene3.odin) with a depth buffer. Each
// instance is one shape: three rows of the transform from the shape's own space to the world
// (the last row is always 0 0 0 1), a color, two numbers that stretch it and its material. The
// matrices are passed as rows and multiplied out with dot products, so no system's idea of how
// a matrix is laid out matters.
//
// The light is worked out per pixel from up to 64 lights (ambient, sun, point and spot) with
// the usual physically based answer: a diffuse part tinted by the color and, for a metal, a
// shine tinted by it, from a microfacet model (GGX for the highlight, Smith's shadowing and
// Schlick's Fresnel). Colors are mixed in linear light and written back with the gamma curve,
// and a surface is lit on whichever side faces the eye.
#include "scene3_shape.hlsli"

// The vertex layout is Vertex3 and Instance3 in scene3.odin: TEXCOORD0 to 2 are per vertex,
// TEXCOORD3 to 8 per instance. The fragment stage has its own uniform block (Scene_Lights),
// because it cannot read the vertex stage's.

cbuffer Scene : register(b0, space1)
{
    float4 clip_x;  // the rows of the matrix from the world to the screen
    float4 clip_y;
    float4 clip_z;
    float4 clip_w;
    float4 eye_unused;
};

Texture2D<float4> shadow_map : register(t0, space2);
SamplerState shadow_sampler : register(s0, space2);

cbuffer Lights : register(b0, space3)
{
    float4 eye;      // where the eye is, in the world
    float4 ambient;  // the ambient color, and in w how many lights there are
    float4 lights[192]; // three for each light: (place or direction, kind), (color, falloff), (spot axis, cosine of its half angle)
    float4 shadow_x;     // the rows of the matrix from the world to the shadow-casting light's view
    float4 shadow_y;
    float4 shadow_z;
    float4 shadow_w;
    float4 shadow;       // x: 1 when there is a shadow map, y: which light casts it, z: how far to push a surface out along its normal, w: the size of a texel of the map
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
    float3 world : TEXCOORD0;
    float3 normal : TEXCOORD1;
    float4 colour : TEXCOORD2;
    float4 material : TEXCOORD3;
};

VSOutput vs_main(VSInput input)
{
    VSOutput output;
    float4 w = float4(shape_world(input.position, input.normal, input.stretch, input.row0, input.row1, input.row2, input.params), 1.0);
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
    output.material = input.material;
    return output;
}

static const float PI = 3.14159265;

// How much of a light reaches a place: 1 for all of it, 0 for none, from the depths the light saw, looked up
// over a three by three block of texels so an edge is soft rather than stepped.
float shadow_factor(float3 world, float3 n, float nl)
{
    float3 pushed = world + n * shadow.z;
    float4 p = float4(pushed, 1.0);
    float4 clip = float4(dot(shadow_x, p), dot(shadow_y, p), dot(shadow_z, p), dot(shadow_w, p));
    float3 ndc = clip.xyz / clip.w;
    float2 uv = float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
    if (clip.w <= 0.0 || uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0 || ndc.z > 1.0)
    {
        return 1.0;
    }
    float bias = 0.0008 + 0.002 * (1.0 - nl);
    float lit = 0.0;
    for (int y = -1; y <= 1; y++)
    {
        for (int x = -1; x <= 1; x++)
        {
            float seen = shadow_map.SampleLevel(shadow_sampler, uv + float2(x, y) * shadow.w, 0).r;
            lit += (ndc.z - bias > seen) ? 0.0 : 1.0;
        }
    }
    return lit / 9.0;
}

float3 to_linear(float3 c)
{
    return pow(c, 2.2);
}

float4 ps_main(VSOutput input) : SV_Target0
{
    // flat in its color: no lights
    if (input.material.z > 0.5)
    {
        return float4(input.colour.rgb, 1.0);
    }
    float3 n = normalize(input.normal);
    float3 v = normalize(eye.xyz - input.world);
    if (dot(n, v) < 0.0)
    {
        n = -n;
    }
    float3 albedo = to_linear(input.colour.rgb);
    float metallic = input.material.x;
    float rough = clamp(input.material.y, 0.04, 1.0);
    float3 f0 = lerp(float3(0.04, 0.04, 0.04), albedo, metallic);
    float3 diffuse_colour = albedo * (1.0 - metallic);
    float a = rough * rough;
    float a2 = a * a;
    float k = (rough + 1.0) * (rough + 1.0) / 8.0;
    float nv = max(dot(n, v), 1e-3);

    float3 total = float3(0.0, 0.0, 0.0);
    int count = (int)ambient.w;
    [loop]
    for (int i = 0; i < count; i++)
    {
        float4 first = lights[i * 3];
        float4 second = lights[i * 3 + 1];
        float4 third = lights[i * 3 + 2];
        float3 l;
        float strength = 1.0;
        if (first.w < 1.5)
        {
            l = normalize(first.xyz);
        }
        else
        {
            float3 d = first.xyz - input.world;
            float dist = max(length(d), 1e-3);
            l = d / dist;
            float ratio = dist / second.w;
            strength = 1.0 / (1.0 + ratio * ratio);
            if (first.w > 2.5)
            {
                // a spot light: full inside the cone and fading over the last fifth of it
                float across = dot(-l, normalize(third.xyz));
                strength *= smoothstep(third.w, lerp(third.w, 1.0, 0.2), across);
            }
        }
        float nl = saturate(dot(n, l));
        if (nl > 0.0)
        {
            float3 h = normalize(l + v);
            float nh = saturate(dot(n, h));
            float vh = saturate(dot(v, h));
            float denominator = nh * nh * (a2 - 1.0) + 1.0;
            float d_term = a2 / (PI * denominator * denominator);
            float g_term = (nl / (nl * (1.0 - k) + k)) * (nv / (nv * (1.0 - k) + k));
            float3 fresnel = f0 + (1.0 - f0) * pow(1.0 - vh, 5.0);
            float3 specular = d_term * g_term * fresnel / (4.0 * nv * nl + 1e-4);
            // the diffuse part is the color times the light; its 1/pi and the light's pi cancel, so the highlight takes the pi
            if (shadow.x > 0.5 && (float)i == shadow.y)
            {
                strength *= shadow_factor(input.world, n, nl);
            }
            total += (diffuse_colour + specular * PI) * to_linear(second.rgb) * strength * nl;
        }
    }
    float3 sky = to_linear(ambient.rgb);
    total += sky * (diffuse_colour + f0 * (1.8 - rough));
    total += albedo * input.material.w;
    return float4(pow(saturate(total), 1.0 / 2.2), 1.0);
}
