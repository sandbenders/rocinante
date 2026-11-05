// Big square pixels, `block` pixels wide.
float block;

float4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    float2 cells = max(size / max(block, 1.0), 1.0);
    float2 middle = (floor(uv * cells) + 0.5) / cells;
    return scene.SampleLevel(scene_sampler, middle, 0);
}
