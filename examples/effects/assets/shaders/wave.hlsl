// Waves the picture sideways. `amount` and `speed` are given by the sketch with `by`;
// `tint` mixes a color in. `scene` is what the sketch drew, `uv` where this pixel is
// (0 to 1 from the top left), and `time` and `size` come with every shader.
float amount;
float speed;
float4 tint;

float4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    float2 p = uv;
    p.x += sin(p.y * 30.0 + time * speed) * amount;
    float4 c = scene.Sample(scene_sampler, p);
    return lerp(c, tint * c.a, 0.2);
}
