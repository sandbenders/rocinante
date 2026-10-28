# Release checklist

Work through this before tagging `vYYYY.MINOR.MICRO`. Record the results in the table at the bottom, one row per version. The Linux artefact comes from the tag pipeline; the other platforms are built and checked locally.

## Before the tag

- [ ] `main` is green on GitLab (Arch) and GitHub (Ubuntu).
- [ ] `ODIN_VERSION` is the Odin release this version was built and tested with.
- [ ] `README.md` status and build instructions are current.
- [ ] Anything that breaks existing sketches, the stable verb ABI or `ui.toml` is written down for the top of the release notes, with the fix for each.

## On each platform

For FreeBSD, macOS and Windows: build on that system, run every example, run the golden-image suite and the back-end equivalence suite, and build the platform's artefact. For iOS and Android, which are targets only: package from a host that can (a Mac for iOS; macOS, Linux x86-64 or Windows for Android), install on a real device, and run every example there.

Where someone has a mid-range laptop, run `examples/benchmark` on it and note the frame rate (Phase 1 used an older desktop as a stand-in).

## Results

| Version | FreeBSD | macOS | Windows | iOS | Android | Notes |
|---|---|---|---|---|---|---|
