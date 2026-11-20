#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Puts a compiled sketch on an Android phone: builds the Odin program `roci run --compile --target android` made as
# a shared library, compiles SDL's Java glue and the activity, assembles and signs an APK with a debug key, copies the
# sketch's `assets` into the app's own folder, installs the app and starts it. Needs the Android SDK
# and NDK (Android Studio's), a phone connected with USB debugging on, and the phone's libraries, which
# `tools/mobile-sdl.sh android` and `spikes/mobile/android/libs.sh` build. The screen must be on and unlocked.
#
#     tools/mobile-android.sh <source folder> <sketch folder> <name>
# Environment: ANDROID_HOME, NDK_VERSION, API_LEVEL (default 28), ANDROID_SERIAL (else the one phone connected),
# ROCI_ROOT (the source of rocinante, default the folder above this one), NO_INSTALL (build the APK and stop).
# EMULATOR=1 puts the app on Android's emulator instead of a phone: a running one if there is one, else the virtual
# device named by AVD (else the first `emulator -list-avds` gives), started and waited for. The APK is the same
# arm64 one, which an arm64 virtual device runs as it is; the emulator is for seeing layouts, not for speed.
set -eu

source_folder="${1:?the folder with the program roci made}"
sketch_folder="${2:?the sketch folder, for its assets}"
name="${3:-sketch}"
root="${ROCI_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
here="$root/tools/mobile/android"
out="$sketch_folder/artifacts/android"
[ -z "${EMULATOR:-}" ] || out="$sketch_folder/artifacts/android-emulator"
SDL_ANDROID_LIB="${SDL_ANDROID_LIB:-$root/.cache/mobile/android}"
SDL_ANDROID_JAVA="${SDL_ANDROID_JAVA:-$root/.cache/mobile/SDL3-3.4.18/android-project/app/src/main/java}"
PACKAGE=org.rocinante.sketch

say() { printf '%s\n' "$*"; }
fail() { printf '%s\n' "$*" >&2; exit 1; }

case "$(uname -s)" in
  Darwin) default_home="$HOME/Library/Android/sdk"; host=darwin-x86_64 ;;
  Linux) default_home="$HOME/Android/Sdk"; host=linux-x86_64 ;;
  *) fail "Android apps are built on a Mac, a Linux x86-64 computer or a Windows computer, because Google's Android tools run nowhere else." ;;
esac
ANDROID_HOME="${ANDROID_HOME:-$default_home}"
NDK_VERSION="${NDK_VERSION:-29.0.14206865}"
API_LEVEL="${API_LEVEL:-28}"
TARGET_API_LEVEL="${TARGET_API_LEVEL:-34}"
ndk="$ANDROID_HOME/ndk/$NDK_VERSION"
adb="$ANDROID_HOME/platform-tools/adb"
[ -d "$ndk" ] || fail "I need the Android NDK $NDK_VERSION in $ANDROID_HOME (Android Studio, SDK Manager, SDK Tools, NDK), or set ANDROID_HOME."
[ -f "$SDL_ANDROID_LIB/libSDL3.so" ] || fail "SDL for Android is not built yet. Run: tools/mobile-sdl.sh android"
[ -f "$root/.cache/android/lib/libSDL3_ttf.so" ] || fail "Android's libraries are not built yet. Run: SDL_ANDROID_LIB=$SDL_ANDROID_LIB SDL_ANDROID_SRC=$root/.cache/mobile/SDL3-3.4.18 spikes/mobile/android/libs.sh"
[ -d "$SDL_ANDROID_JAVA" ] || fail "SDL's Java glue is not where I looked ($SDL_ANDROID_JAVA)."
build_tools="$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -n 1)"
android_jar="$(ls -d "$ANDROID_HOME"/platforms/android-* | sort -V | tail -n 1)/android.jar"

# The emulator to put the app on: one that is running, or a virtual device started now.
use_emulator() {
  running="$("$adb" devices | awk 'NR > 1 && $1 ~ /^emulator-/ && $2 == "device" { print $1; exit }')"
  if [ -n "$running" ]; then
    ANDROID_SERIAL="$running"
    return 0
  fi
  emulator="$ANDROID_HOME/emulator/emulator"
  [ -x "$emulator" ] || fail "I need Android's emulator in $ANDROID_HOME (Android Studio, SDK Manager, SDK Tools, Android Emulator)."
  avd="${AVD:-$("$emulator" -list-avds | head -n 1)}"
  [ -n "$avd" ] || fail "There is no virtual device. Make one in Android Studio (Device Manager), with an arm64 image."
  say "== starting the emulator $avd"
  mkdir -p "$out"
  nohup "$emulator" -avd "$avd" -no-snapshot-save -no-boot-anim > "$out/emulator.log" 2>&1 &
  waited=0
  until [ "$("$adb" -e shell getprop sys.boot_completed 2> /dev/null | tr -d '\r')" = 1 ]; do
    sleep 3
    waited=$((waited + 3))
    [ "$waited" -lt 240 ] || fail "The emulator did not finish starting in four minutes. Its messages are in $out/emulator.log."
  done
  ANDROID_SERIAL="$("$adb" devices | awk 'NR > 1 && $1 ~ /^emulator-/ && $2 == "device" { print $1; exit }')"
  [ -n "$ANDROID_SERIAL" ] || fail "The emulator started and I cannot see it in adb devices."
}

if [ -z "${NO_INSTALL:-}" ]; then
  if [ -n "${EMULATOR:-}" ]; then
    case "${ANDROID_SERIAL:-}" in
      emulator-*) ;;
      *) ANDROID_SERIAL=""; use_emulator ;;
    esac
    export ANDROID_SERIAL
  else
    count="$("$adb" devices | awk 'NR > 1 && $2 == "device" { n++ } END { print n + 0 }')"
    [ "$count" -ge 1 ] || fail "I cannot find an Android phone. Connect it with its cable, turn on USB debugging (Settings, Developer options), unlock it and accept the computer."
    if [ -z "${ANDROID_SERIAL:-}" ] && [ "$count" -gt 1 ]; then
      fail "More than one phone is connected: set ANDROID_SERIAL to the one (adb devices)."
    fi
  fi
fi

rm -rf "$out"
mkdir -p "$out/lib/arm64-v8a" "$out/classes" "$out/dex"
keystore="$root/output/spike-debug.keystore"
mkdir -p "$root/output"

say "== odin: the sketch as a shared library"
ODIN_ANDROID_SDK="$ANDROID_HOME/" ODIN_ANDROID_NDK="$ndk/" \
ODIN_ANDROID_NDK_TOOLCHAIN="$ndk/toolchains/llvm/prebuilt/$host/" \
  odin build "$source_folder" -collection:rocinante="$root" -target:linux_arm64 -subtarget:android -build-mode:shared \
    -out:"$out/lib/arm64-v8a/libmain.so" -extra-linker-flags:"-L$SDL_ANDROID_LIB -L$root/.cache/android/lib" -o:speed
cp "$SDL_ANDROID_LIB/libSDL3.so" "$out/lib/arm64-v8a/"
for so in libSDL3_ttf.so libshaderc_shared.so libspirv-cross-c-shared.so; do
  cp "$root/.cache/android/lib/$so" "$out/lib/arm64-v8a/"
done

say "== java: SDL's glue and the activity"
javac --release 11 -classpath "$android_jar" -d "$out/classes" $(find "$SDL_ANDROID_JAVA" "$here" -name '*.java')
"$build_tools/d8" --lib "$android_jar" --min-api "$API_LEVEL" --output "$out/dex" $(find "$out/classes" -name '*.class')

say "== apk"
sed "s/@NAME@/$name/g" "$here/AndroidManifest.xml" > "$out/AndroidManifest.xml"
"$build_tools/aapt" package -f -M "$out/AndroidManifest.xml" -I "$android_jar" \
  --min-sdk-version "$API_LEVEL" --target-sdk-version "$TARGET_API_LEVEL" -F "$out/sketch-unaligned.apk"
cp "$out/dex/classes.dex" "$out/classes.dex"
(cd "$out" && "$build_tools/aapt" add sketch-unaligned.apk classes.dex \
  lib/arm64-v8a/libmain.so lib/arm64-v8a/libSDL3.so lib/arm64-v8a/libSDL3_ttf.so \
  lib/arm64-v8a/libshaderc_shared.so lib/arm64-v8a/libspirv-cross-c-shared.so > /dev/null)
"$build_tools/zipalign" -f -p 4 "$out/sketch-unaligned.apk" "$out/sketch-aligned.apk"
if [ ! -f "$keystore" ]; then
  keytool -genkeypair -keystore "$keystore" -storepass android -keypass android \
    -alias spike -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=rocinante, O=rocinante" > /dev/null 2>&1
fi
"$build_tools/apksigner" sign --ks "$keystore" --ks-pass pass:android --key-pass pass:android \
  --out "$out/sketch.apk" "$out/sketch-aligned.apk"
say "built $out/sketch.apk"

[ -z "${NO_INSTALL:-}" ] || exit 0
say "== install"
"$adb" install -r "$out/sketch.apk" > "$out/install.log" 2>&1 || {
  if grep -q INSTALL_FAILED_UPDATE_INCOMPATIBLE "$out/install.log"; then
    "$adb" uninstall "$PACKAGE" > /dev/null 2>&1 || true
    "$adb" install -r "$out/sketch.apk" > "$out/install.log" 2>&1 || { tail -5 "$out/install.log" >&2; fail "The phone would not take the app."; }
  else
    tail -5 "$out/install.log" >&2
    fail "The phone would not take the app."
  fi
}
# The assets go into the app's own folder (`run-as` works because the debug app is debuggable): files `adb push`
# puts on the shared storage belong to the shell user, and the app is not let read them.
files="files"
"$adb" shell run-as "$PACKAGE" sh -c "'rm -rf $files/assets; mkdir -p $files'" > /dev/null 2>&1 || true
if [ -d "$sketch_folder/assets" ]; then
  say "== assets"
  (cd "$sketch_folder" && COPYFILE_DISABLE=1 tar --no-xattrs -cf - assets) | "$adb" shell run-as "$PACKAGE" tar -xf - -C "$files" > "$out/push.log" 2>&1 || { tail -5 "$out/push.log" >&2; fail "I could not copy the assets to the phone."; }
fi
say "== start"
"$adb" shell input keyevent KEYCODE_WAKEUP > /dev/null 2>&1 || true
"$adb" logcat -c > /dev/null 2>&1 || true
"$adb" shell am start -n "$PACKAGE/.SketchActivity" > "$out/launch.log" 2>&1 || { tail -5 "$out/launch.log" >&2; fail "The app is on the phone and would not start."; }
if [ -n "${EMULATOR:-}" ]; then
  say "$name is running on the emulator ($ANDROID_SERIAL). A picture of it: $adb -s $ANDROID_SERIAL exec-out screencap -p > shot.png"
else
  say "$name is running on the phone. Its messages: $adb logcat -s SDL"
fi
