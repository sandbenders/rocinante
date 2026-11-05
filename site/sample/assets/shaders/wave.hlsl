// Waves the picture sideways. `phase` and `amount` are given by the sketch with `by`.
float amount;
float phase;

float4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    float2 p = uv;
    p.x += sin(p.y * 30.0 + phase) * amount;
    return scene.Sample(scene_sampler, p);
}
