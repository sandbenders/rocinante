// A corridor of glowing glass. Every pixel works out how deep into the corridor it is looking
// (the corridor is a stack of rounded squares, each smaller than the one in front) and lights
// the glass walls that lie at that depth: a bright rim, a soft body and a second, fainter
// frame half a step behind, so the frames look see-through. The corridor repeats sideways, so
// neighbors peek in from the sides, darker and with cool reflections. Moving along it is
// nothing but adding time to the depth.
//   speed   how fast the frames rush toward you
//   glow    how bright the light is
//   look    which way the camera leans, as two numbers around 0
float speed;
float glow;
float2 look;

float rounded(float2 q)
{
    // a square with round corners: the fourth power norm
    float2 a = abs(q);
    return pow(pow(a.x, 4.0) + pow(a.y, 4.0), 0.25);
}

float rim(float t)
{
    // the shape of one frame along the depth: a sharp bright edge that fades into the body
    float f = frac(t);
    return smoothstep(0.0, 0.06, f) * (1.0 - smoothstep(0.06, 0.55, f));
}

float4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    float aspect = size.x / size.y;
    float2 p = (uv - 0.5) * float2(aspect, 1.0) * 2.0;
    float period = 2.3;
    float cell = floor(p.x / period + 0.5);
    float2 q = float2(p.x - cell * period, p.y);
    float side = abs(cell);

    // each corridor leans a little differently and runs at its own phase
    q += look * (0.4 + 0.2 * side) + float2(sin(time * 0.5 + cell * 2.0), cos(time * 0.37 + cell)) * 0.06;

    float d = rounded(q * float2(0.95, 1.1)) + 0.0001;
    float t = -log(d + 0.03) * 1.5 + time * speed * 0.9 + cell * 1.7;

    float edge = rim(t);
    float behind = rim(t + 0.5);
    float body = 0.5 + 0.5 * cos(frac(t) * 6.2832);

    float near = exp(-d * 1.4);
    float3 deep = float3(0.55, 0.04, 0.02);
    float3 flame = float3(1.0, 0.45, 0.06);
    float3 amber = float3(1.0, 0.78, 0.25);

    // the gap between two frames is dark, so each frame stands out as glass
    float gap = 0.18 + 0.82 * smoothstep(0.0, 0.5, frac(t)) * (1.0 - 0.6 * smoothstep(0.5, 1.0, frac(t)));
    float3 color = deep * (0.15 + 0.7 * near) * gap;
    color += flame * edge * (0.45 + 0.8 * near);
    color += flame * behind * 0.28 * (0.5 + near);
    color += float3(0.9, 0.2, 0.04) * body * 0.25 * gap;

    // the glass is brightest on the top and bottom walls, where it catches the light
    float topwall = smoothstep(0.0, 0.7, abs(q.y) - abs(q.x) * 0.6);
    color += amber * edge * topwall * 0.5;

    // the far end of the corridor: a warm light
    color += float3(1.0, 0.8, 0.3) * exp(-d * d * 40.0) * 0.9;

    // neighbors are darker, and their reflections are cool
    float cool = saturate(side);
    float3 teal = float3(0.15, 0.65, 0.75);
    color = lerp(color, color * 0.45 + teal * (edge + behind * 0.5) * 0.35, cool);

    // a red glow where two corridors meet
    float seam = exp(-abs(abs(q.x) - period * 0.5) * 7.0);
    color += float3(0.9, 0.1, 0.05) * seam * 0.35 * cool;

    color *= glow;
    color = 1.0 - exp(-color * 1.3);

    float vignette = 1.0 - smoothstep(0.7, 1.7, length((uv - 0.5) * float2(aspect, 1.0) * 2.0)) * 0.55;
    return float4(color * vignette, 1.0);
}
