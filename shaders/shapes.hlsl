// SPDX-License-Identifier: 0BSD
//
// The shapes shader (CLAUDE.md section 4.3): one instanced quad per shape, with
// the shape worked out from a signed distance in the fragment shader. Circles,
// ellipses, rectangles, lines and triangles all go through here, so any number of
// them in a row is one draw. The instance layout is Instance in roci/gfx/batch.odin.
//
// Resource layout follows SDL's GPU rules (SDL_CreateGPUShader): the vertex
// stage's uniform buffer is register b0 in space1 (set 1 in SPIR-V), and vertex
// inputs are TEXCOORD0, 1, 2 ... in order.
//
// Colour is not converted: values go to the screen as written, like Processing,
// and the output is premultiplied (the pipeline blends with ONE, ONE_MINUS_SRC_ALPHA).

#include "gradient.hlsli"

static const uint FLAG_FILL = 1;
static const uint FLAG_STROKE = 2;

// Margin the CPU adds around a shape for smoothing, in the shape's own units
// (AA_MARGIN in roci/gfx/batch.odin).
static const float AA_MARGIN = 1.0;

cbuffer Frame : register(b0, space1)
{
    float2 canvas_size; // the window in logical pixels, as sketches see it
    float2 unused;
};

struct VSInput
{
    float4 transform_ab_cd : TEXCOORD0; // a b c d
    float4 transform_ef_half : TEXCOORD1; // e f half.x half.y
    float4 shape_0123 : TEXCOORD2;
    float2 shape_45 : TEXCOORD3;
    float4 fill : TEXCOORD4;
    float4 stroke : TEXCOORD5;
    float thickness : TEXCOORD6;
    uint kind : TEXCOORD7;
    uint flags : TEXCOORD8;
    uint fill_gradient : TEXCOORD9;
    uint stroke_gradient : TEXCOORD10;
    uint vertex_id : SV_VertexID;
};

struct VSOutput
{
    float4 position : SV_Position;
    float2 local : TEXCOORD0;
    nointerpolation float4 shape_0123 : TEXCOORD1;
    nointerpolation float2 shape_45 : TEXCOORD2;
    nointerpolation float4 fill : TEXCOORD3;
    nointerpolation float4 stroke : TEXCOORD4;
    nointerpolation float thickness : TEXCOORD5;
    nointerpolation uint kind : TEXCOORD6;
    nointerpolation uint flags : TEXCOORD7;
    nointerpolation uint2 gradients : TEXCOORD8; // fill, stroke
    nointerpolation float2 box_half : TEXCOORD9; // the shape's box, without margin
};

VSOutput vs_main(VSInput input)
{
    // Two triangles make the quad: corners (-1,-1) (1,-1) (-1,1) (-1,1) (1,-1) (1,1).
    float2 corners[6] = {
        float2(-1, -1), float2(1, -1), float2(-1, 1),
        float2(-1, 1), float2(1, -1), float2(1, 1)
    };
    float2 half_size = input.transform_ef_half.zw;
    float2 p = corners[input.vertex_id] * half_size;

    float a = input.transform_ab_cd.x;
    float b = input.transform_ab_cd.y;
    float c = input.transform_ab_cd.z;
    float d = input.transform_ab_cd.w;
    float2 canvas = float2(a * p.x + c * p.y + input.transform_ef_half.x,
                           b * p.x + d * p.y + input.transform_ef_half.y);

    VSOutput output;
    // The canvas has its origin at the top left with y down; clip space has y up.
    output.position = float4(canvas.x / canvas_size.x * 2.0 - 1.0,
                             1.0 - canvas.y / canvas_size.y * 2.0, 0.0, 1.0);
    output.local = p;
    output.shape_0123 = input.shape_0123;
    output.shape_45 = input.shape_45;
    output.fill = input.fill;
    output.stroke = input.stroke;
    output.thickness = input.thickness;
    output.kind = input.kind;
    output.flags = input.flags;
    output.gradients = uint2(input.fill_gradient, input.stroke_gradient);
    float pad = AA_MARGIN + ((input.flags & FLAG_STROKE) != 0 ? input.thickness * 0.5 : 0.0);
    output.box_half = max(half_size - pad, 0.0);
    return output;
}

static const uint KIND_CIRCLE = 0;
static const uint KIND_ELLIPSE = 1;
static const uint KIND_RECT = 2;
static const uint KIND_LINE = 3;
static const uint KIND_TRIANGLE = 4;

float distance_to_segment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-12), 0.0, 1.0);
    return length(pa - ba * h);
}

// Signed distance to a triangle, negative inside (Inigo Quilez, MIT).
float triangle_distance(float2 p, float2 p0, float2 p1, float2 p2)
{
    float2 e0 = p1 - p0;
    float2 e1 = p2 - p1;
    float2 e2 = p0 - p2;
    float2 v0 = p - p0;
    float2 v1 = p - p1;
    float2 v2 = p - p2;
    float2 pq0 = v0 - e0 * clamp(dot(v0, e0) / max(dot(e0, e0), 1e-12), 0.0, 1.0);
    float2 pq1 = v1 - e1 * clamp(dot(v1, e1) / max(dot(e1, e1), 1e-12), 0.0, 1.0);
    float2 pq2 = v2 - e2 * clamp(dot(v2, e2) / max(dot(e2, e2), 1e-12), 0.0, 1.0);
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    float2 d = min(min(float2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                       float2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
                   float2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
    return -sqrt(d.x) * sign(d.y);
}

// Distance to the shape's edge in its own units, negative inside. The ellipse's
// is a close estimate, exact on the axes.
float shape_distance(VSOutput input)
{
    float2 p = input.local;
    switch (input.kind)
    {
    case KIND_CIRCLE:
        return length(p) - input.shape_0123.x;
    case KIND_ELLIPSE:
    {
        float2 r = max(input.shape_0123.xy, 1e-6);
        float k0 = length(p / r);
        float k1 = length(p / (r * r));
        return k1 > 1e-12 ? k0 * (k0 - 1.0) / k1 : -min(r.x, r.y);
    }
    case KIND_RECT:
    {
        float2 q = abs(p) - input.shape_0123.xy;
        return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
    }
    case KIND_LINE:
        return distance_to_segment(p, input.shape_0123.xy, input.shape_0123.zw);
    default:
        return triangle_distance(p, input.shape_0123.xy, input.shape_0123.zw, input.shape_45);
    }
}

// How much of a pixel is on the inside of an edge `d` units away, given how
// many units a pixel covers.
float coverage(float d, float pixel)
{
    return saturate(0.5 - d / pixel);
}

float4 ps_main(VSOutput input) : SV_Target0
{
    float d = shape_distance(input);
    float pixel = max(fwidth(d), 1e-6);

    // A gradient replaces the colour; the colour's alpha then holds the style's alpha.
    float4 fill = input.fill;
    if (input.gradients.x != 0)
    {
        float4 g = gradient_colour(input.gradients.x, input.local, input.box_half);
        fill = float4(g.rgb, g.a * input.fill.a);
    }
    float4 stroke = input.stroke;
    if (input.gradients.y != 0)
    {
        float4 g = gradient_colour(input.gradients.y, input.local, input.box_half);
        stroke = float4(g.rgb, g.a * input.stroke.a);
    }

    float fill_alpha = 0.0;
    float stroke_alpha = 0.0;
    if (input.kind == KIND_LINE)
    {
        // A line has no inside: its stroke is the band around the segment.
        stroke_alpha = stroke.a * coverage(d - input.thickness * 0.5, pixel);
    }
    else
    {
        if ((input.flags & FLAG_FILL) != 0)
        {
            fill_alpha = fill.a * coverage(d, pixel);
        }
        if ((input.flags & FLAG_STROKE) != 0)
        {
            // The outline is centred on the edge, half inside and half outside.
            stroke_alpha = stroke.a * coverage(abs(d) - input.thickness * 0.5, pixel);
        }
    }

    // Stroke over fill, premultiplied.
    float3 colour = stroke.rgb * stroke_alpha + fill.rgb * fill_alpha * (1.0 - stroke_alpha);
    float alpha = stroke_alpha + fill_alpha * (1.0 - stroke_alpha);
    return float4(colour, alpha);
}
