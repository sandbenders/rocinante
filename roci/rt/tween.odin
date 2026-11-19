// SPDX-License-Identifier: 0BSD
//
// Tweens: `tween ball.pos to mouse over 0.5 as out` moves a number, a vector or a color from where it is to a
// value, a little each frame, on an ease curve, and the last step lands exactly on the value. The place is a pointer
// taken once, when the tween starts: a name of the sketch, or a field of a record (which the collector is told
// to keep while the tween lasts). A new tween of the same place replaces the old one.
package rt

import "../"
import "../maths"

@(private)
Tween :: struct {
	place:    rawptr,
	kind:     int, // 0 a number, 1 a vector, 2 a color
	n:        int, // the parts of a vector
	from, to: [4]f64,
	start:    f64,
	duration: f64,
	curve:    maths.Ease,
	owner:    ^Header, // the record the place is in, kept alive while the tween lasts
}

@(thread_local) @(private) tweens: [dynamic]Tween
@(thread_local) @(private) tweened_frame: int

@(private)
begin :: proc(t: Tween, name: string) {
	t := t
	t.start = roci.time_now()
	if name != "" {
		t.curve, _ = maths.ease_by_name(name)
	}
	for old, i in tweens {
		if old.place == t.place {
			unordered_remove(&tweens, i)
			break
		}
	}
	append(&tweens, t)
}

tween_number :: proc(place: ^f64, to, over: f64, curve: string, owner: ^Header = nil) {
	begin(Tween{place = place, kind = 0, n = 1, from = {place^, 0, 0, 0}, to = {to, 0, 0, 0}, duration = over, owner = owner}, curve)
}

tween_vector :: proc(place: ^[$N]f64, to: [N]f64, over: f64, curve: string, owner: ^Header = nil) {
	t := Tween{place = place, kind = 1, n = N, duration = over, owner = owner}
	for i in 0 ..< N {
		t.from[i], t.to[i] = place[i], to[i]
	}
	begin(t, curve)
}

tween_colour :: proc(place: ^maths.Colour, to: maths.Colour, over: f64, curve: string, owner: ^Header = nil) {
	t := Tween{place = place, kind = 2, n = 4, duration = over, owner = owner}
	for i in 0 ..< 4 {
		t.from[i], t.to[i] = f64(place[i]), f64(to[i])
	}
	begin(t, curve)
}

@(private)
write :: proc(t: Tween, values: [4]f64) {
	switch t.kind {
	case 0:
		(^f64)(t.place)^ = values[0]
	case 1:
		for i in 0 ..< t.n { // the parts of a vector lie one after another
			(^f64)(uintptr(t.place) + uintptr(i * size_of(f64)))^ = values[i]
		}
	case 2:
		c := (^maths.Colour)(t.place)
		for i in 0 ..< 4 {
			c[i] = f32(values[i])
		}
	}
}

// Moves every tween to where it should be now, once a frame; the finished ones land on their value and go.
step_tweens :: proc() {
	frame := roci.frame_count()
	if frame == tweened_frame && frame != 0 {
		return
	}
	tweened_frame = frame
	now := roci.time_now()
	for i := 0; i < len(tweens); {
		t := tweens[i]
		amount := (now - t.start) / t.duration if t.duration > 0 else 1
		if amount >= 1 {
			write(t, t.to)
			unordered_remove(&tweens, i)
			continue
		}
		along := maths.ease(amount, t.curve)
		out: [4]f64
		if t.kind == 2 {
			// colors mix in the way the language mixes them (Oklab), not channel by channel
			from := maths.Colour{f32(t.from[0]), f32(t.from[1]), f32(t.from[2]), f32(t.from[3])}
			to := maths.Colour{f32(t.to[0]), f32(t.to[1]), f32(t.to[2]), f32(t.to[3])}
			mixed := maths.mix(from, to, along)
			out = {f64(mixed[0]), f64(mixed[1]), f64(mixed[2]), f64(mixed[3])}
		} else {
			for k in 0 ..< t.n {
				out[k] = t.from[k] + (t.to[k] - t.from[k]) * along
			}
		}
		write(t, out)
		i += 1
	}
}

// Marks the records the places of the tweens are in, so a record only a tween holds is not freed under it.
mark_tweens :: proc() {
	for t in tweens {
		if t.owner != nil {
			mark(t.owner)
		}
	}
}
