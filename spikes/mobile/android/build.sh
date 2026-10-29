#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Spike 2, Android: builds the Odin library, compiles SDL's Java glue, and
# assembles, signs and (with --install) installs an APK. Written for the spike;
# `roci package android` will do this itself.
#
# Needs, as environment variables:
#   SDL_ANDROID_LIB   folder holding libSDL3.so built for arm64-v8a with the NDK
#   SDL_ANDROID_JAVA  folder holding SDL's org/libsdl/app/*.java
#                     (android-project/app/src/main/java in SDL's source)
# Optional: ANDROID_HOME, NDK_VERSION, API_LEVEL, TARGET_API_LEVEL.
#
#     SDL_ANDROID_LIB=... SDL_ANDROID_JAVA=... spikes/mobile/android/build.sh [--install]
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
out="$root/output/android"

# Android Studio's own places: ~/Library/Android/sdk on a Mac, ~/Android/Sdk on Linux.
case "$(uname -s)" in
  Darwin) default_home="$HOME/Library/Android/sdk" ;;
  *) default_home="$HOME/Android/Sdk" ;;
esac
ANDROID_HOME="${ANDROID_HOME:-$default_home}"
NDK_VERSION="${NDK_VERSION:-29.0.14206865}"
API_LEVEL="${API_LEVEL:-24}"
TARGET_API_LEVEL="${TARGET_API_LEVEL:-34}"
: "${SDL_ANDROID_LIB:?set SDL_ANDROID_LIB to the folder with libSDL3.so}"
: "${SDL_ANDROID_JAVA:?set SDL_ANDROID_JAVA to the android-project/app/src/main/java}"

ndk="$ANDROID_HOME/ndk/$NDK_VERSION"
build_tools="$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -n 1)"
android_jar="$(ls -d "$ANDROID_HOME"/platforms/android-* | sort -V | tail -n 1)/android.jar"
# The NDK's macOS toolchain is x86_64 even on Apple Silicon, and Odin guesses
# the folder from the CPU, so it is named here.
case "$(uname -s)" in
  Darwin) host=darwin-x86_64 ;;
  Linux) host=linux-x86_64 ;;
  *) echo "build.sh: untested on $(uname -s)" >&2; exit 1 ;;
esac

rm -rf "$out"
mkdir -p "$out/lib/arm64-v8a" "$out/classes" "$out/dex"
# The debug key lives outside $out: a new key on every build would make the
# phone refuse to update the app.
keystore="$root/output/spike-debug.keystore"

echo "== odin: libmain.so"
ODIN_ANDROID_SDK="$ANDROID_HOME/" ODIN_ANDROID_NDK="$ndk/" \
ODIN_ANDROID_NDK_TOOLCHAIN="$ndk/toolchains/llvm/prebuilt/$host/" \
  odin build "$here" -target:linux_arm64 -subtarget:android -build-mode:shared \
    -out:"$out/lib/arm64-v8a/libmain.so" -extra-linker-flags:"-L$SDL_ANDROID_LIB" \
    -vet -strict-style
cp "$SDL_ANDROID_LIB/libSDL3.so" "$out/lib/arm64-v8a/"

echo "== java: SDL glue and the activity"
javac --release 11 -classpath "$android_jar" -d "$out/classes" \
  $(find "$SDL_ANDROID_JAVA" "$here/java" -name '*.java')
"$build_tools/d8" --lib "$android_jar" --min-api "$API_LEVEL" --output "$out/dex" \
  $(find "$out/classes" -name '*.class')

echo "== apk"
"$build_tools/aapt" package -f -M "$here/AndroidManifest.xml" -I "$android_jar" \
  --min-sdk-version "$API_LEVEL" --target-sdk-version "$TARGET_API_LEVEL" \
  -F "$out/spike-unaligned.apk"
cp "$out/dex/classes.dex" "$out/classes.dex"
(cd "$out" && "$build_tools/aapt" add spike-unaligned.apk classes.dex \
  lib/arm64-v8a/libmain.so lib/arm64-v8a/libSDL3.so > /dev/null)
"$build_tools/zipalign" -f -p 4 "$out/spike-unaligned.apk" "$out/spike-aligned.apk"

if [ ! -f "$keystore" ]; then
  keytool -genkeypair -keystore "$keystore" -storepass android -keypass android \
    -alias spike -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=rocinante spike, O=rocinante" > /dev/null 2>&1
fi
"$build_tools/apksigner" sign --ks "$keystore" --ks-pass pass:android \
  --key-pass pass:android --out "$out/spike.apk" "$out/spike-aligned.apk"
echo "built $out/spike.apk"

if [ "${1:-}" = "--install" ]; then
  adb="$ANDROID_HOME/platform-tools/adb"
  "$adb" install -r "$out/spike.apk"
  "$adb" logcat -c
  "$adb" shell am start -n org.rocinante.spike/.SpikeActivity
  echo "logs: $adb logcat -s SDL"
fi
