# The newcomer test

Phase 2's last exit criterion: someone who has never seen rocinante makes a moving sketch in 15 minutes, observed and written up, with two groups that read the same sketches in two styles, and three traps from Logo's history watched for. How it is run was decided on 2026-10-30:

- **Two groups, eight people.** Group A reads the sketches with one thing per argument (`circle at (random width) (random height) radius 5`), group B the same sketches in bare Logo nesting (`circle at random width random height radius 5`). Bare nesting is an error in rocinante, so only the reading differs: everyone then builds in the real `roci run`. In each group, two people who have never programmed and two with a little experience (Scratch, Processing, spreadsheet formulas).
- **In person, one at a time, thinking aloud**, at the observer's computer, about 30 minutes each. Screen and voice are recorded only with written consent.
- **In English**, with people comfortable reading it, since rocinante's words and messages are English.

## What is here

| File | For | |
|---|---|---|
| `consent.md` | the participant | signed before anything starts |
| `reading/A/*.roci`, `reading/B/*.roci` | the participant | the three sketches, printed, of their group only |
| `reading/questions.md` | both | the questions (print without the answer key) and the observer's answer key |
| `task-card.md` | the participant | the making task |
| `cheatsheet.md` | the participant | one page of words, the same for both groups |
| `results.md` | the observer | one sheet per participant |

Two tests keep these honest: every `B` sketch must be its `A` sketch with the round brackets taken out, and every example on the handout must check with no message (`roci/lang/check_files_test.odin`).

## Before the sessions

- Build `roci` and put it on the path: `odin build cli -o:speed -out:output/roci`, then `export PATH="$PWD/output:$PATH"` in the session's terminal.
- Assign participants to groups before meeting them, alternating A, B, A, B within each background, so the groups stay balanced.
- Print, per participant: the consent form, their group's three sketches, the questions without the answer key, the task card, the handout and a results sheet.
- Pick an editor the participant can use without help (Kate, gedit or VS Code; not nvim), with autosave off so a save is a deliberate act, and line numbers on, since messages give line numbers.
- Check the consent form against the rules where the sessions take place before the first one.

## Each session (about 30 minutes)

**Setup (2 minutes, before they arrive).** In a fresh folder: `roci new p1` (the participant's number), then `cd p1`. Open `sketch.roci` in the editor on the left half of the screen. Start `roci run 2>&1 | tee ../p1.log` in a terminal along the bottom; the window opens on the right. Start the recording if they agreed to it.

**Welcome (3 minutes).** Consent form. Say: "We're testing a programming language, not you. Please think aloud the whole time: what you're trying, what you expect, what surprises you. I'll mostly stay quiet, because I want to see where the language gets in your way."

**Reading (about 5 minutes, paper, no tool).** Follow `reading/questions.md`. Time each sketch, write every answer down word for word, and do not correct anything.

**Making (15 minutes, timed).** Hand over the task card and the handout. Start the clock when they first touch the keyboard. Note the minute of the first visible change and of the first thing that moves, every message they meet (its title from the log or the screen, whether they read it, whether its suggested line fixed things), and any of the three traps.

How to help:

- Stay quiet while they are making progress, even slowly.
- After two minutes stuck, give the first hint and note it: "What does the window or the terminal say?"
- After two more: "Which line do you think it means?"
- Only after that, a direct hint, written down word for word. Every hint counts against "made it in 15 minutes unaided".
- Never touch the keyboard.

**Debrief (5 minutes).** The three questions at the end of `results.md`. For the last one, show the other group's version of sketch 2 next to theirs.

**After.** Copy their `sketch.roci` and the log next to the results sheet. Fill in the sheet the same day, while you remember. Keep the sheets and recordings outside the repository; delete recordings once the write-up is done.

## Writing it up

When all eight are done, summarise in CLAUDE.md, §8, Phase 2, as the exit criterion asks:

- how many made something move in 15 minutes unaided, per group and per background, and the median minute of the first moving thing;
- reading: right answers per question per group, and the time per sketch. Question 6 is where the two styles should differ most;
- the messages people met most, and the ones that did not help: each of those is a catalogue fix (§5.7);
- each trap: how many met it, and what they did;
- what the debrief said about the two styles.

Then decide with what it shows: whether "one thing per argument" stands, which messages and words change, and whether Phase 2 is closed. A change that comes out of the test is recorded as a dated decision in §10, like any other.
