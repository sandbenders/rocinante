<h1 align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/logo/rocinante-wordmark-dark.svg">
    <img src="docs/logo/rocinante-wordmark.svg" alt="rocinante" width="360">
  </picture>
</h1>

> _Y así, después de muchos nombres que formó, borró y quitó, añadió, deshizo y tornó a hacer en su memoria e imaginación, al fin le vino a llamar Rocinante: nombre, a su parecer, alto, sonoro y significativo de lo que había sido cuando fue rocín, antes de lo que ahora era, que era antes y primero de todos los rocines del mundo._
>
> Miguel de Cervantes, _El ingenioso hidalgo don Quijote de la Mancha_, Part I, Chapter 1 (1605)[^expanse]

```
circle at 100 100 radius 50
```

That line is a complete rocinante sketch. Run it and a window opens with a circle in it.

rocinante is an open-source creative coding framework with its own easy to learn and powerful language. It comes out of years of working with [Processing](https://processing.org/), [openFrameworks](https://openframeworks.cc/) and [Cinder](https://libcinder.org/), and it borrows the turtle, ideas and also some syntax from [Logo](https://el.media.mit.edu/logo-foundation/). You write a line and get a picture, mistakes come with a plain explanation, and when you save the file the running sketch updates.

## Documentation

All of it is at <https://rocinante-lang.org/>, built from this repository.

- [Getting started](https://rocinante-lang.org/guides/01-getting-started/): install, run a first sketch, the `roci` command.
- [Guides](https://rocinante-lang.org/guides/): shapes and color, movement, input, lists, your own verbs, text, widgets, 3D, sound and more, one topic at a time.
- [Reference](https://rocinante-lang.org/reference/): every word, with an example and the picture it draws.
- [Examples](https://rocinante-lang.org/examples/): every sketch in `examples/`, running, with its code.
- [Errors](https://rocinante-lang.org/messages/): every message rocinante can give, and how to fix it.
- [FAQ](https://rocinante-lang.org/faq/): why not Processing, Python or OpenGL, why Logo, where the objects are, and who is behind it.
- [MANIFESTO.md](MANIFESTO.md): why it exists.

## Status

An alpha. The language, the `roci` command (`run`, `check`, `fmt`, `man`, `test`, `new`, `get`), 2D and 3D drawing, text, pictures, shaders, widgets with screen readers, sound, MIDI and OSC all work, on macOS, Linux, FreeBSD, OpenBSD and Windows, and on an iPhone and an Android phone (`roci run --compile --target ios|android` puts a compiled sketch on a phone that is plugged in). Packaging a sketch into an app (`roci package`) is not written yet. What each phase built and measured is in [docs/phases.md](docs/phases.md).

## Building and contributing

You need git, the Odin release named in `ODIN_VERSION` and SDL3; [docs/building.md](docs/building.md) has the packages for every system and the commands for trying it. Then:

```
git config core.hooksPath tools/hooks   # once, after cloning
odin run build -- ci --fast             # what the pre-push hook runs
odin run cli -- run examples/garden     # a first sketch
```

Issues and pull requests are welcome here on GitHub, and everyone taking part is asked to follow the [code of conduct](CODE_OF_CONDUCT.md). Day-to-day development happens in a self-hosted GitLab and this repository is a mirror, so an accepted pull request may show as closed rather than merged; your commits keep your name. History is linear, commits are small with a message prefixed by the area they touch (`gfx: batch circles with instancing`), and the name is always lowercase. The design and the plan are in [CLAUDE.md](CLAUDE.md) and [docs/design.md](docs/design.md).

## Roadmap

Wanted, but not planned for the first stable release: a shader language of rocinante's own style, a web target, arm64 desktops and Intel Macs, 3D physics, training models inside rocinante, MIDI and the microphone on the phones, HE-AAC files, a sketch-writing skill and an MCP server for AI assistants, editor tools in the source (inline sliders, a frame scrubber), turtle export to plotters and embroidery, and translated keywords and messages.

## Versions

Calendar versioning, `YYYY.MINOR.MICRO`; releases before the first stable one carry their stage, `2026.1.0-alpha` being the first.

## License

[Zero-Clause BSD](LICENSE) (0BSD). Use it for anything, with or without credit.

## Credits

rocinante is designed and built by Fabrizio Poltronieri (sandbenders) [fabrizio@fabriziopoltronieri.com], with help from Claude, Anthropic's AI assistant.

[^expanse]: Four centuries later the name went to a ship. In _The Expanse_, the novel series by James S. A. Corey (the pen name of Daniel Abraham and Ty Franck) that began with _Leviathan Wakes_ in 2011, the Rocinante starts out as the _Tachi_, a Martian navy gunship. The survivors of the ice freighter _Canterbury_ take it over and rename it Rocinante, and it carries them through all nine novels and the television series (Syfy from 2015, then Amazon Prime Video). It is a small ship that keeps flying when it has no business doing so.
