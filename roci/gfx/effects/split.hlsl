// What a cheap lens does to colors: red and blue drift apart toward the edges, `amount`
// pixels at the corners.
float amount;

float4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    float2 shift = (uv - 0.5) * 2.0 * amount / size;
    float4 g = scene.SampleLevel(scene_sampler, uv, 0);
    float r = scene.SampleLevel(scene_sampler, uv + shift, 0).r;
    float b = scene.SampleLevel(scene_sampler, uv - shift, 0).b;
    return float4(r, g.g, b, g.a);
}
