# Reading questions

Print the three sketches of the participant's group (`A/` or `B/`, never both) and this page without the answers. The participant reads each sketch and answers aloud or in writing, without running anything. The observer times each sketch from the moment it is turned over until the last answer, and notes every answer word for word.

Say before starting: "These are three short programs in a language you have never seen. Tell me what you think each one does. Guessing is fine: we are testing the language, not you."

## Sketch 1 (`1_dots.roci`)

1. How many circles does it draw?
2. Where in the window are they?
3. What decides how big each circle is?

## Sketch 2 (`2_wave.roci`)

4. Does the circle move? Which way?
5. What does its height do over time?
6. On the line that starts with `y =`, what is multiplied by 50?

## Sketch 3 (`3_points.roci`)

7. How many circles does it draw?
8. How big is each one?
9. What do you think `{ 100, 100 }` is? And `[ ... ]` around the two of them?

---

## Answer key (for the observer only)

| Question | Answer | What a wrong answer suggests |
|---|---|---|
| 1 | 30 | `repeat` not understood |
| 2 | anywhere: a random place in the window | `random width` not understood (group B: the arguments ran together) |
| 3 | a random radius up to 20 | the call boundaries were misread (group B: `radius random 20 fill rgb ...`) |
| 4 | yes, to the right, 2 pixels a frame | `draw` running every frame not understood |
| 5 | it goes up and down smoothly, 50 pixels either side of the middle | `sin` of time not understood |
| 6 | the sine (`sin (time * 90)`), not `time` or `90` | **the nesting question**: group B's `sin time * 90 * 50` reads several ways; this is where the two styles should differ |
| 7 | **3**: `b = a` makes one list, so adding to `b` adds to `a` | **trap 3, sharing** (an answer of 2 is the classic `b = a` mistake) |
| 8 | radius 15 (3 items, times 5) | `count a` read after the sharing mistake gives 10 |
| 9 | a point or position (a vector); the square brackets make a list of them | **trap 1, `[ ]` against `{ , }`** |

Score each answer right, partly right or wrong, and note the time per sketch. Do not correct a wrong answer during the session: the making part afterwards should start from what the participant understood.
