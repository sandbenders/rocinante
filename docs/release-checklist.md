# Release checklist

Work through this before tagging `vYYYY.MINOR.MICRO` (CLAUDE.md §11). Record the results in the table at the bottom, one row per version. The Linux artefact comes from the tag pipeline; the other platforms are built and checked locally.

## Before the tag

- [ ] `main` is green on GitLab (Arch) and GitHub (Ubuntu).
- [ ] `ODIN_VERSION` is the Odin release this version was built and tested with.
- [ ] `README.md` status and build instructions are current.
- [ ] Anything that breaks existing sketches, the stable verb ABI or `ui.toml` is written down for the top of the release notes, with the fix for each.

## On each platform

For FreeBSD, macOS, Windows, iOS and Android: build, run every example, run the golden-image suite and the back-end equivalence suite, and build the platform's artefact.

## Results

| Version | FreeBSD | macOS | Windows | iOS | Android | Notes |
|---|---|---|---|---|---|---|
