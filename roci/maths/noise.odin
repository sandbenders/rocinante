// SPDX-License-Identifier: 0BSD
//
// Perlin noise in one to three dimensions, and layered ("fractal") noise built
// on it. This is Perlin's improved noise (Perlin, "Improving Noise", SIGGRAPH
// 2002: the quintic fade curve and the twelve edge gradients). The permutation
// table comes from the seed, so the same seed gives the same landscape, and the
// interpreter and compiled sketches share this one implementation (CLAUDE.md
// section 4.7). Results run from 0 to 1, like Processing's noise().
package maths

import "core:math"

Noise :: struct {
	perm: [512]u8, // 256 shuffled values, repeated so lookups never wrap by hand
}

// A noise field for a seed. Every seed is valid.
noise_make :: proc(seed: u64) -> Noise {
	n: Noise
	for i in 0 ..< 256 {
		n.perm[i] = u8(i)
	}
	r := rng_make(seed)
	// Fisher-Yates shuffle.
	for i := 255; i > 0; i -= 1 {
		j := int(rng_int(&r, 0, i64(i)))
		n.perm[i], n.perm[j] = n.perm[j], n.perm[i]
	}
	for i in 0 ..< 256 {
		n.perm[i + 256] = n.perm[i]
	}
	return n
}

@(private)
fade :: proc "contextless" (t: f64) -> f64 {
	return t * t * t * (t * (t * 6 - 15) + 10)
}

// Dot product of the point's offset with one of twelve gradient directions.
@(private)
grad :: proc "contextless" (hash: u8, x, y, z: f64) -> f64 {
	h := hash & 15
	u := x if h < 8 else y
	v: f64
	switch {
	case h < 4:
		v = y
	case h == 12 || h == 14:
		v = x
	case:
		v = z
	}
	return (u if h & 1 == 0 else -u) + (v if h & 2 == 0 else -v)
}

// Noise from 0 to 1 at a point on a line.
noise1 :: proc "contextless" (n: ^Noise, x: f64) -> f64 {
	return noise3(n, x, 0, 0)
}

// Noise from 0 to 1 at a point on a plane.
noise2 :: proc "contextless" (n: ^Noise, x, y: f64) -> f64 {
	return noise3(n, x, y, 0)
}

// Noise from 0 to 1 at a point in space. At whole-number points it is exactly 0.5.
noise3 :: proc "contextless" (n: ^Noise, x_in, y_in, z_in: f64) -> f64 {
	x, y, z := x_in, y_in, z_in
	fx, fy, fz := math.floor(x_in), math.floor(y_in), math.floor(z_in)
	// The lattice repeats every 256; i64 first so huge or negative values wrap cleanly.
	xi, yi, zi := int(i64(fx) & 255), int(i64(fy) & 255), int(i64(fz) & 255)
	x, y, z = x - fx, y - fy, z - fz
	u, v, w := fade(x), fade(y), fade(z)

	p := &n.perm
	a := int(p[xi]) + yi
	aa := int(p[a]) + zi
	ab := int(p[a + 1]) + zi
	b := int(p[xi + 1]) + yi
	ba := int(p[b]) + zi
	bb := int(p[b + 1]) + zi

	x1 := math.lerp(grad(p[aa], x, y, z), grad(p[ba], x - 1, y, z), u)
	x2 := math.lerp(grad(p[ab], x, y - 1, z), grad(p[bb], x - 1, y - 1, z), u)
	y1 := math.lerp(x1, x2, v)
	x3 := math.lerp(grad(p[aa + 1], x, y, z - 1), grad(p[ba + 1], x - 1, y, z - 1), u)
	x4 := math.lerp(grad(p[ab + 1], x, y - 1, z - 1), grad(p[bb + 1], x - 1, y - 1, z - 1), u)
	y2 := math.lerp(x3, x4, v)
	return 0.5 + 0.5 * math.lerp(y1, y2, w)
}

// Layers of noise, each `lacunarity` times finer and `gain` times quieter than
// the one before, added up and scaled back to 0 to 1. Processing's noiseDetail
// uses 4 octaves, a lacunarity of 2 and a gain of 0.5, and so do the defaults.
noise_fbm :: proc "contextless" (n: ^Noise, x, y, z: f64, octaves := 4, lacunarity := 2.0, gain := 0.5) -> f64 {
	total, amplitude, frequency, norm := 0.0, 1.0, 1.0, 0.0
	for _ in 0 ..< max(octaves, 1) {
		total += amplitude * noise3(n, x * frequency, y * frequency, z * frequency)
		norm += amplitude
		amplitude *= gain
		frequency *= lacunarity
	}
	return total / norm
}
