# Release checklist

Work through this before tagging `vYYYY.MINOR.MICRO`. Record the results in the table at the bottom, one row per version. A release has a download for each host, FreeBSD, Linux, macOS and Windows, and none for iOS or Android, which are targets only: `roci` never runs on a phone, so a phone gets a sketch as an app its author packaged. The Linux download comes from the tag pipeline; the other hosts' are built and checked locally, and the phones are checked as targets.

## Before the tag

- [ ] `main` is green on GitLab (Arch) and GitHub (Ubuntu).
- [ ] `ODIN_VERSION` is the Odin release this version was built and tested with.
- [ ] `README.md` status and build instructions are current.
- [ ] Anything that breaks existing sketches, the stable verb ABI or `ui.toml` is written down for the top of the release notes, with the fix for each.

## On each platform

For FreeBSD, macOS and Windows: build on that system, run every example, run the golden-image suite and the back-end equivalence suite, and build the platform's download. For iOS and Android, which have no download: package from a host that can (a Mac for iOS; macOS, Linux x86-64 or Windows for Android), install on a real device, and run every example there.

Where someone has a mid-range laptop, run `examples/benchmark` on it and note the frame rate (Phase 1 used an older desktop as a stand-in).

On the iPhone, also play `examples/touch` with several fingers: they should be in the right places, numbered in order and never reused, and gone when they lift (checked on the Pixel 9 in Phase 2; the iPhone was moved here when Phase 2 closed).

## Results

| Version | FreeBSD | macOS | Windows | iOS | Android | Notes |
|---|---|---|---|---|---|---|
