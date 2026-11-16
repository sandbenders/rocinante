// SPDX-License-Identifier: 0BSD
//
// AAC (and the MP4 and M4A files that hold it) is read by each system's own decoder, because no AAC
// decoder under a permissive licence exists to link: AudioToolbox on macOS and iOS (roci_apple.h),
// Media Foundation on Windows (roci_windows.h) and MediaCodec on Android (roci_android.h). Linux,
// FreeBSD and OpenBSD have none, so a sketch there is helped by the user's ffmpeg, which the Odin side
// asks (vendor/sound/ffmpeg.odin). Each of these backends takes only what looks like an AAC file, so
// the other decoders keep every other kind.

// Whether the first bytes of a file are an MP4 or M4A (a `ftyp` box) or an AAC stream in ADTS frames.
static int roci_looks_like_aac(const unsigned char *head, size_t size) {
	if (size >= 12 && memcmp(head + 4, "ftyp", 4) == 0) {
		return 1;
	}
	// ADTS: twelve bits of sync, then the layer, which is 0 for AAC (MP3's is 1 or 2 or 3)
	if (size >= 7 && head[0] == 0xFF && (head[1] & 0xF6) == 0xF0) {
		return 1;
	}
	return 0;
}
