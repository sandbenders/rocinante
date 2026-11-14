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

// A model's pictures, which a part that has none is given a stand-in for (see renderer_scene.odin): the color, the
// normal map, metal and roughness (roughness in green, metal in blue) and the light the surface gives.
Texture2D<float4> colour_map : register(t1, space2);
SamplerState colour_sampler : register(s1, space2);
Texture2D<float4> normal_map : register(t2, space2);
SamplerState normal_sampler : register(s2, space2);
Texture2D<float4> metal_map : register(t3, space2);
SamplerState metal_sampler : register(s3, space2);
Texture2D<float4> emissive_map : register(t4, space2);
SamplerState emissive_sampler : register(s4, space2);

// A point light's shadow map: six faces (+x, -x, +y, -y, +z, -z of the world) in a texture three faces wide and two high
Texture2D<float4> point_map : register(t5, space2);
SamplerState point_sampler : register(s5, space2);

cbuffer Part : register(b1, space3)
{
    float4 part;     // x: how strongly the normal map bends the surface (0: there is none), y: 1 when the light comes from a picture, z: the alpha below which a pixel is not drawn (0: none), w: how much a non-metal reflects looked at straight on
    float4 sets;     // for each picture, 0 or 1: the set of coordinates it is read with
    float4 xform[8]; // for each picture two rows, (a b tx) and (c d ty), that move its coordinates
};

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
    float4 point_rows[24]; // the four rows of the matrix of each face of the point light's map
    float4 point_at;     // xyz: where the point light that casts shadows is, w: its number among the lights plus 1 (0: none casts)
    float4 point_info;   // x, y: the near and far distance of the faces, z: how far across a texel of a face is at a distance of 1, w: one over a face's size in texels
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
    float2 uv : TEXCOORD9;
    float2 uv1 : TEXCOORD10;
    float4 vcolour : TEXCOORD11;
};

struct VSOutput
{
    float4 position : SV_Position;
    float3 world : TEXCOORD0;
    float3 normal : TEXCOORD1;
    float4 colour : TEXCOORD2;
    float4 material : TEXCOORD3;
    float2 uv : TEXCOORD4;
    float2 uv1 : TEXCOORD5;
    float4 vcolour : TEXCOORD6;
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
    output.uv = input.uv;
    output.uv1 = input.uv1;
    output.vcolour = input.vcolour;
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

// The same for a point light: the face the place is in is the one its largest distance from the light points at, and what
// the map holds there is the depth of a perspective that is turned back into a distance along that axis to be compared.
float point_shadow_factor(float3 world, float3 n, float nl)
{
    float3 d0 = world - point_at.xyz;
    float3 a = abs(d0);
    float dist = max(max(a.x, a.y), a.z);
    int face;
    if (a.x >= a.y && a.x >= a.z)
    {
        face = d0.x > 0.0 ? 0 : 1;
    }
    else if (a.y >= a.z)
    {
        face = d0.y > 0.0 ? 2 : 3;
    }
    else
    {
        face = d0.z > 0.0 ? 4 : 5;
    }
    float4 p = float4(world + n * (dist * point_info.z * 1.5), 1.0);
    float4 clip = float4(dot(point_rows[face * 4], p), dot(point_rows[face * 4 + 1], p), dot(point_rows[face * 4 + 2], p), dot(point_rows[face * 4 + 3], p));
    if (clip.w <= 0.0)
    {
        return 1.0;
    }
    float2 ndc = clip.xy / clip.w;
    float2 inside = float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
    float margin = 1.5 * point_info.w;
    inside = clamp(inside, margin, 1.0 - margin);
    float2 origin = float2(face % 3, face / 3);
    float2 uv = (origin + inside) / float2(3.0, 2.0);
    float2 texel = float2(point_info.w / 3.0, point_info.w / 2.0);
    float near = point_info.x;
    float far = point_info.y;
    float ka = far / (near - far);
    float kb = near * far / (near - far);
    float bias = clip.w * (0.003 + 0.01 * (1.0 - nl));
    float lit = 0.0;
    for (int y = -1; y <= 1; y++)
    {
        for (int x = -1; x <= 1; x++)
        {
            float seen = point_map.SampleLevel(point_sampler, uv + float2(x, y) * texel, 0).r;
            float seen_distance = kb / (seen + ka);
            lit += (clip.w - bias > seen_distance) ? 0.0 : 1.0;
        }
    }
    return lit / 9.0;
}

float3 to_linear(float3 c)
{
    return pow(c, 2.2);
}

// Where a picture is read: the set of coordinates it uses, moved by its own transform.
float2 coords(VSOutput input, int slot)
{
    float2 uv = (sets[slot] > 0.5) ? input.uv1 : input.uv;
    float3 p = float3(uv, 1.0);
    return float2(dot(xform[slot * 2].xyz, p), dot(xform[slot * 2 + 1].xyz, p));
}

float4 ps_main(VSOutput input) : SV_Target0
{
    // the pictures are read before anything can leave the shader, so the sizes they are read at (from how fast
    // the coordinates change across neighbouring pixels) are worked out for every pixel
    float4 painted = colour_map.Sample(colour_sampler, coords(input, 0));
    float4 packed = metal_map.Sample(metal_sampler, coords(input, 2));
    float3 bump = normal_map.Sample(normal_sampler, coords(input, 1)).xyz * 2.0 - 1.0;
    float3 glow = emissive_map.Sample(emissive_sampler, coords(input, 3)).rgb;
    float3 dp1 = ddx(input.world);
    float3 dp2 = ddy(input.world);
    float2 bump_uv = coords(input, 1);
    float2 duv1 = ddx(bump_uv);
    float2 duv2 = ddy(bump_uv);
    if (part.z > 0.0 && painted.a * input.colour.a * input.vcolour.a < part.z)
    {
        discard;
    }
    float3 base = input.colour.rgb * painted.rgb * input.vcolour.rgb;
    // flat in its color: no lights
    if (input.material.z > 0.5)
    {
        return float4(base, 1.0);
    }
    float3 n = normalize(input.normal);
    float3 v = normalize(eye.xyz - input.world);
    if (dot(n, v) < 0.0)
    {
        n = -n;
    }
    if (part.x != 0.0)
    {
        // the surface's own sideways directions, from how the picture's coordinates run across it (no tangents are kept
        // in the mesh); the picture's up is where its v gets smaller
        float3 perp2 = cross(dp2, n);
        float3 perp1 = cross(n, dp1);
        float3 tangent = perp2 * duv1.x + perp1 * duv2.x;
        float3 bitangent = -(perp2 * duv1.y + perp1 * duv2.y);
        float scale = rsqrt(max(max(dot(tangent, tangent), dot(bitangent, bitangent)), 1e-12));
        n = normalize(tangent * scale * bump.x * part.x + bitangent * scale * bump.y * part.x + n * bump.z);
    }
    float3 albedo = to_linear(base);
    float metallic = input.material.x * packed.b;
    float rough = clamp(input.material.y * packed.g, 0.04, 1.0);
    float3 f0 = lerp(float3(part.w, part.w, part.w), albedo, metallic);
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
            if (point_at.w > 0.5 && (float)i + 1.0 == point_at.w)
            {
                strength *= point_shadow_factor(input.world, n, nl);
            }
            total += (diffuse_colour + specular * PI) * to_linear(second.rgb) * strength * nl;
        }
    }
    float3 sky = to_linear(ambient.rgb);
    total += sky * (diffuse_colour + f0 * (1.8 - rough));
    float3 given = (part.y > 0.5) ? to_linear(glow) : albedo;
    total += given * input.material.w;
    return float4(pow(saturate(total), 1.0 / 2.2), 1.0);
}
