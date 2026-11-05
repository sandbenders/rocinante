// A spiral of wavy black and white bands with a few red ones, that turns slowly, in the box
// of the shape it fills. `uv` is where the pixel is in that box and `size` how big the box
// is; the sketch gives `arms` (how many bands wind out from the middle), `rings` (how close
// together they are), `wobble` (how wavy), `speed` and `accent` (the color of the odd band).
float arms;
float rings;
float wobble;
float speed;
float4 accent;

float4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    float2 p = (uv - 0.5) * 2.0;
    p.x *= size.x / size.y;
    float r = length(p);
    float a = atan2(p.y, p.x);
    float t = time * speed;

    // The bands: a spiral phase that grows with the distance and the angle, bent by two waves.
    float bend = sin(a * 5.0 + t) * 0.35 + sin(r * 16.0 - t * 2.0) * 0.45;
    float phase = r * rings - t * 0.5 + a * arms / 6.28318 + bend * wobble;
    float band = sin(phase * 6.28318);
    float soft = fwidth(band) + 0.02;
    float ink = smoothstep(-soft, soft, band);

    // One arm in every turn of the spiral is the accent color. Counting the bands in units of
    // `arms` keeps this smooth where the angle wraps round, which a fixed count would not.
    float turn = frac(phase / arms) * arms;
    float picked = smoothstep(0.0, 0.03, turn) * (1.0 - smoothstep(0.47, 0.5, turn));

    // Paper that goes from white in the middle to gray at the edge.
    float paper = lerp(1.0, 0.55, smoothstep(0.0, 1.6, r));
    float3 color = lerp(float3(paper, paper, paper), float3(0.02, 0.02, 0.03), ink);
    color = lerp(color, accent.rgb, ink * picked);
    // the very middle is a small dot, so the spiral has somewhere to start
    color = lerp(float3(0.02, 0.02, 0.03), color, smoothstep(0.015, 0.03, r));
    return float4(color, 1.0);
}
