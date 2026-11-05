// Darkens the corners, more where `strength` is bigger. The middle of the vignette is the
// mouse (`mouse` is in pixels, `size` is the window's size).
float strength;

float4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    float4 c = scene.Sample(scene_sampler, uv);
    float d = distance(uv * size, mouse) / length(size);
    return c * (1.0 - smoothstep(0.2, 0.8, d) * strength);
}
