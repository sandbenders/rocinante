// SPDX-License-Identifier: 0BSD
//
// Colours. A colour is four numbers, red, green, blue
// and alpha, every one from 0 to 255 (decided 2026-10-23); values outside that
// are clamped. Because a colour is an Odin array, `c * 0.5` and `a + b` work
// element by element, as section 5.2 promises. `hsb` also uses 0-255 for all
// three channels; `oklch` follows its CSS notation (lightness 0-1, chroma,
// hue in degrees). Mixing is done in Oklab by default, which keeps gradients
// even and avoids muddy middles (Ottosson, https://bottosson.github.io/posts/oklab/).
package maths

import "core:math"

Colour :: [4]f32

Mix_Space :: enum {
	Oklab, // the default
	Rgb,   // Processing's look
	Oklch, // along the hue, taking the shorter way round
}

clamp_channel :: proc "contextless" (v: f64) -> f32 {
	if math.is_nan(v) {
		return 0
	}
	return f32(clamp(v, 0, 255))
}

grey :: proc "contextless" (v: f64, alpha: f64 = 255) -> Colour {
	g := clamp_channel(v)
	return {g, g, g, clamp_channel(alpha)}
}

rgb :: proc "contextless" (r, g, b: f64, alpha: f64 = 255) -> Colour {
	return {clamp_channel(r), clamp_channel(g), clamp_channel(b), clamp_channel(alpha)}
}

// Hue, saturation and brightness, each 0-255. Hue 0 and 255 are both red.
hsb :: proc "contextless" (h, s, b: f64, alpha: f64 = 255) -> Colour {
	hue := f64(clamp_channel(h)) / 255 * 6
	sat := f64(clamp_channel(s)) / 255
	val := f64(clamp_channel(b)) / 255
	sector := math.floor(hue)
	f := hue - sector
	p := val * (1 - sat)
	q := val * (1 - sat * f)
	t := val * (1 - sat * (1 - f))
	r, g, bl: f64
	switch int(sector) % 6 {
	case 0: r, g, bl = val, t, p
	case 1: r, g, bl = q, val, p
	case 2: r, g, bl = p, val, t
	case 3: r, g, bl = p, q, val
	case 4: r, g, bl = t, p, val
	case 5: r, g, bl = val, p, q
	}
	return rgb(r * 255, g * 255, bl * 255, alpha)
}

// Lightness 0-1, chroma (about 0-0.4), hue in degrees. Colours outside what a
// screen can show are clamped.
oklch :: proc "contextless" (l, c, h: f64, alpha: f64 = 255) -> Colour {
	radians := h * math.PI / 180
	return oklab_to_colour(l, c * math.cos(radians), c * math.sin(radians), alpha)
}

// Reads "#rrggbb" or "#rrggbbaa" (any case). Anything else is not a colour.
hex_parse :: proc "contextless" (text: string) -> (colour: Colour, ok: bool) {
	if len(text) != 7 && len(text) != 9 || text[0] != '#' {
		return {}, false
	}
	values: [4]u8 = {0, 0, 0, 255}
	for i in 0 ..< (len(text) - 1) / 2 {
		hi, hi_ok := hex_digit(text[1 + 2 * i])
		lo, lo_ok := hex_digit(text[2 + 2 * i])
		if !hi_ok || !lo_ok {
			return {}, false
		}
		values[i] = hi * 16 + lo
	}
	return {f32(values[0]), f32(values[1]), f32(values[2]), f32(values[3])}, true
}

@(private)
hex_digit :: proc "contextless" (c: u8) -> (value: u8, ok: bool) {
	switch c {
	case '0' ..= '9': return c - '0', true
	case 'a' ..= 'f': return c - 'a' + 10, true
	case 'A' ..= 'F': return c - 'A' + 10, true
	}
	return 0, false
}

// A CSS colour name such as "orange" or "rebeccapurple", lowercase as in the language.
name_lookup :: proc "contextless" (name: string) -> (colour: Colour, ok: bool) {
	for entry in NAMED_COLOURS {
		if entry.name == name {
			v := entry.rgb
			return {f32(v >> 16 & 255), f32(v >> 8 & 255), f32(v & 255), 255}, true
		}
	}
	return {}, false
}

// "grey" is the British spelling of "gray", also inside longer names such as
// "darkslategrey". Gives the US word to suggest, or false when `name` has no
// British spelling or its US form is not a colour.
us_spelling :: proc(name: string, allocator := context.allocator) -> (us: string, ok: bool) {
	for i := 0; i + 4 <= len(name); i += 1 {
		if name[i:i + 4] == "grey" {
			bytes := make([]byte, len(name), allocator)
			copy(bytes, name)
			copy(bytes[i:], "gray")
			candidate := string(bytes)
			if _, found := name_lookup(candidate); found {
				return candidate, true
			}
			delete(bytes, allocator)
			return "", false
		}
	}
	return "", false
}

// sRGB to linear light, for one channel in 0-1.
@(private)
to_linear :: proc "contextless" (c: f64) -> f64 {
	if c <= 0.04045 {
		return c / 12.92
	}
	return math.pow((c + 0.055) / 1.055, 2.4)
}

@(private)
from_linear :: proc "contextless" (c: f64) -> f64 {
	if c <= 0.0031308 {
		return c * 12.92
	}
	return 1.055 * math.pow(c, 1 / 2.4) - 0.055
}

@(private)
cube_root :: proc "contextless" (x: f64) -> f64 {
	if x < 0 {
		return -math.pow(-x, 1.0 / 3.0)
	}
	return math.pow(x, 1.0 / 3.0)
}

Oklab :: struct {
	l, a, b: f64,
	alpha:   f64, // 0-255, as in Colour
}

colour_to_oklab :: proc "contextless" (c: Colour) -> Oklab {
	r := to_linear(f64(c.r) / 255)
	g := to_linear(f64(c.g) / 255)
	b := to_linear(f64(c.b) / 255)
	l := cube_root(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
	m := cube_root(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
	s := cube_root(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
	return Oklab{
		l     = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		a     = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		b     = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
		alpha = f64(c.a),
	}
}

oklab_to_colour :: proc "contextless" (l, a, b: f64, alpha: f64 = 255) -> Colour {
	l_ := l + 0.3963377774 * a + 0.2158037573 * b
	m_ := l - 0.1055613458 * a - 0.0638541728 * b
	s_ := l - 0.0894841775 * a - 1.2914855480 * b
	x, y, z := l_ * l_ * l_, m_ * m_ * m_, s_ * s_ * s_
	r := +4.0767416621 * x - 3.3077115913 * y + 0.2309699292 * z
	g := -1.2684380046 * x + 2.6097574011 * y - 0.3413193965 * z
	bl := -0.0041960863 * x - 0.7034186147 * y + 1.7076147010 * z
	// Clamp in linear light first, so out-of-gamut colours land on the edge.
	return rgb(
		from_linear(clamp(r, 0, 1)) * 255,
		from_linear(clamp(g, 0, 1)) * 255,
		from_linear(clamp(bl, 0, 1)) * 255,
		alpha,
	)
}

// A colour between `a` (amount 0) and `b` (amount 1). Amounts outside 0-1 are
// clamped, and not-a-number counts as 0.
mix :: proc "contextless" (a, b: Colour, amount: f64, space := Mix_Space.Oklab) -> Colour {
	t := clamp(amount, 0, 1)
	if math.is_nan(amount) {
		t = 0
	}
	alpha := math.lerp(f64(a.a), f64(b.a), t)
	switch space {
	case .Rgb:
		return rgb(
			math.lerp(f64(a.r), f64(b.r), t),
			math.lerp(f64(a.g), f64(b.g), t),
			math.lerp(f64(a.b), f64(b.b), t),
			alpha,
		)
	case .Oklab:
		x, y := colour_to_oklab(a), colour_to_oklab(b)
		return oklab_to_colour(math.lerp(x.l, y.l, t), math.lerp(x.a, y.a, t), math.lerp(x.b, y.b, t), alpha)
	case .Oklch:
		x, y := colour_to_oklab(a), colour_to_oklab(b)
		c1, c2 := math.sqrt(x.a * x.a + x.b * x.b), math.sqrt(y.a * y.a + y.b * y.b)
		// A grey has no hue, so it takes the other colour's.
		h1, h2 := math.atan2(x.b, x.a), math.atan2(y.b, y.a)
		if c1 < 1e-6 {h1 = h2}
		if c2 < 1e-6 {h2 = h1}
		dh := h2 - h1
		if dh > math.PI {dh -= math.TAU}
		if dh < -math.PI {dh += math.TAU}
		c, h := math.lerp(c1, c2, t), h1 + dh * t
		return oklab_to_colour(math.lerp(x.l, y.l, t), c * math.cos(h), c * math.sin(h), alpha)
	}
	return a
}
