// A tunnel made of twisting, glowing rings, drawn from nothing by marching a ray through a
// distance function for every pixel. What the sketch drew (`scene`) is laid over it, shifted
// a little by the tunnel's own motion, as if seen through water. The sketch gives it `look`,
// where the camera turns, and `glow`, how bright the rings are. Written for rocinante, so the
// names `scene`, `size` and `time` come with the shader.
float2 look;
float glow;

float2x2 turn(float a)
{
    float c = cos(a);
    float s = sin(a);
    return float2x2(c, -s, s, c);
}

// A color that slides through the rainbow as `t` grows (a cosine palette).
float3 palette(float t)
{
    return 0.5 + 0.5 * cos(6.28318 * (float3(1.0, 1.0, 1.0) * t + float3(0.0, 0.33, 0.67)));
}

// How far p is from the nearest surface: the tunnel wall, with a ring in every cell of the
// way and a twist that grows with the distance.
float map(float3 p)
{
    p.xy = mul(turn(p.z * 0.12 + time * 0.15), p.xy);
    float wall = 2.6 - length(p.xy) + sin(p.z * 1.7 + atan2(p.y, p.x) * 3.0) * 0.18;
    float3 q = p;
    q.z = frac(p.z / 4.0 + 0.5) * 4.0 - 2.0;
    float2 t = float2(length(q.xy) - 1.9, q.z);
    float ring = length(t) - 0.16;
    return min(wall, ring + 0.0);
}

float3 normal_at(float3 p)
{
    float2 e = float2(0.002, 0.0);
    return normalize(float3(map(p + e.xyy) - map(p - e.xyy),
                            map(p + e.yxy) - map(p - e.yxy),
                            map(p + e.yyx) - map(p - e.yyx)));
}

float4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    float2 screen = (uv - 0.5) * float2(size.x / size.y, 1.0);
    float3 ro = float3(0.0, 0.0, time * 2.2);
    float3 rd = normalize(float3(screen, 1.1));
    rd.xz = mul(turn(look.x), rd.xz);
    rd.yz = mul(turn(look.y), rd.yz);
    rd.xy = mul(turn(sin(time * 0.2) * 0.3), rd.xy);

    float t = 0.0;
    float steps = 0.0;
    float hit = 0.0;
    for (int i = 0; i < 64; i++)
    {
        float d = map(ro + rd * t);
        if (d < 0.003)
        {
            hit = 1.0;
            break;
        }
        t += d * 0.9;
        steps += 1.0;
        if (t > 40.0)
        {
            break;
        }
    }

    float3 p = ro + rd * t;
    float3 n = normal_at(p);
    float3 light = normalize(float3(0.3, 0.6, -0.5));
    float diffuse = saturate(dot(n, light)) * 0.7 + 0.45;
    float3 base = palette(p.z * 0.05 + time * 0.05 + length(p.xy) * 0.08);
    float fog = exp(-t * 0.045);
    float3 color = base * diffuse * fog * hit;
    // the glow around anything the ray passed close to: the more steps it took, the closer it went
    color += palette(time * 0.1 + t * 0.03) * (steps / 64.0) * glow * (0.4 + 0.6 * fog);

    // the sketch's own drawing over it, a little wavering, premultiplied so it lays on top
    float2 wobble = float2(sin(uv.y * 24.0 + time * 2.0), cos(uv.x * 24.0 + time * 1.7)) * 0.004;
    float4 sketch = scene.Sample(scene_sampler, uv + wobble);
    color = sketch.rgb + color * (1.0 - sketch.a);
    return float4(color, 1.0);
}
