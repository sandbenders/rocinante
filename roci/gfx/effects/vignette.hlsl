// Dark corners: `amount` is how dark, 0 to 1.
float amount;

float4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    float4 c = scene.SampleLevel(scene_sampler, uv, 0);
    float2 centered = (uv - 0.5) * float2(size.x / size.y, 1.0);
    float dark = smoothstep(0.35, 1.0, length(centered) * 1.3) * amount;
    return float4(c.rgb * (1.0 - dark), c.a);
}
