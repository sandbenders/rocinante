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
#
# `roci package android` runs this script too, to make an app people can be given instead of a test build: it sets APP_MANIFEST
# (the app's own AndroidManifest.xml), APP_RES (the folder of its icons, `res`), APP_PACKAGE (its id), APP_OUT (the folder the
# build is made in), APP_APK (where the signed APK goes), APP_KEYSTORE and APP_KEYPASS (its release key and the file with the
# key's password: made here when the key is not there yet) and NO_INSTALL=1. The sketch's `assets`, `libs` and starting files
# are then carried inside the APK, which the activity unpacks into the app's own folder the first time it runs.
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
PACKAGE="${APP_PACKAGE:-org.rocinante.sketch}"
[ -z "${APP_OUT:-}" ] || out="$APP_OUT"

# What it says is read by roci, which draws the steps: `step <kind> <words>` starts one (kinds: libraries, phone, compile,
# bundle, sign, install, start), `result <name> <detail>` is something made, `finished <words>` the last word and
# `problem <words>` what went wrong; any other line is what a tool said, kept in a log.
step() { printf "step %s %s\n" "$1" "$2"; }
result() { printf "result %s %s\n" "$1" "$2"; }
finished() { printf "finished %s\n" "$*"; }
fail() { printf "problem %s\n" "$*" >&2; exit 1; }

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
# The phone's libraries, built when one is missing or what it is made from changed (the first time takes a while); its
# output goes to a log, shown only when it fails.
step libraries "Getting the phone's libraries ready"
mkdir -p "$sketch_folder/artifacts"
libs_log="$sketch_folder/artifacts/phone-libs.log"
if ! ANDROID_HOME="$ANDROID_HOME" NDK_VERSION="$NDK_VERSION" API_LEVEL="$API_LEVEL" SDL_ANDROID_LIB="$SDL_ANDROID_LIB" \
  SDL_ANDROID_SRC="${SDL_ANDROID_SRC:-$root/.cache/mobile/SDL3-3.4.18}" sh "$root/spikes/mobile/android/libs.sh" > "$libs_log" 2>&1; then
  tail -n 20 "$libs_log" >&2
  fail "Android's libraries could not be built; the whole of it is in $libs_log."
fi
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
  step phone "Starting the emulator $avd"
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
    step phone "Finding the emulator"
    case "${ANDROID_SERIAL:-}" in
      emulator-*) ;;
      *) ANDROID_SERIAL=""; use_emulator ;;
    esac
    export ANDROID_SERIAL
  else
    step phone "Finding the phone"
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

step compile "Compiling the sketch for Android"
ODIN_ANDROID_SDK="$ANDROID_HOME/" ODIN_ANDROID_NDK="$ndk/" \
ODIN_ANDROID_NDK_TOOLCHAIN="$ndk/toolchains/llvm/prebuilt/$host/" \
  odin build "$source_folder" -collection:rocinante="$root" -target:linux_arm64 -subtarget:android -build-mode:shared \
    -out:"$out/lib/arm64-v8a/libmain.so" -extra-linker-flags:"-L$SDL_ANDROID_LIB -L$root/.cache/android/lib" -o:speed
cp "$SDL_ANDROID_LIB/libSDL3.so" "$out/lib/arm64-v8a/"
for so in libSDL3_ttf.so libshaderc_shared.so libspirv-cross-c-shared.so; do
  cp "$root/.cache/android/lib/$so" "$out/lib/arm64-v8a/"
done

step bundle "Making the app"
javac --release 11 -classpath "$android_jar" -d "$out/classes" $(find "$SDL_ANDROID_JAVA" "$here" -name '*.java')
"$build_tools/d8" --lib "$android_jar" --min-api "$API_LEVEL" --output "$out/dex" $(find "$out/classes" -name '*.class')

if [ -n "${APP_MANIFEST:-}" ]; then
  # an app of its own: its manifest and its icons, through aapt2, which knows the adaptive icons of Android 8 and later
  cp "$APP_MANIFEST" "$out/AndroidManifest.xml"
  "$build_tools/aapt2" compile --dir "$APP_RES" -o "$out/res.zip" \
    || fail "The icons could not be read by aapt2: look in $APP_RES."
  "$build_tools/aapt2" link -o "$out/sketch-unaligned.apk" -I "$android_jar" --manifest "$out/AndroidManifest.xml" \
    --min-sdk-version "$API_LEVEL" --target-sdk-version "$TARGET_API_LEVEL" "$out/res.zip" \
    || fail "aapt2 could not put the manifest and the icons together."
else
  sed "s/@NAME@/$name/g" "$here/AndroidManifest.xml" > "$out/AndroidManifest.xml"
  "$build_tools/aapt" package -f -M "$out/AndroidManifest.xml" -I "$android_jar" \
    --min-sdk-version "$API_LEVEL" --target-sdk-version "$TARGET_API_LEVEL" -F "$out/sketch-unaligned.apk"
fi
cp "$out/dex/classes.dex" "$out/classes.dex"
(cd "$out" && "$build_tools/aapt" add sketch-unaligned.apk classes.dex \
  lib/arm64-v8a/libmain.so lib/arm64-v8a/libSDL3.so lib/arm64-v8a/libSDL3_ttf.so \
  lib/arm64-v8a/libshaderc_shared.so lib/arm64-v8a/libspirv-cross-c-shared.so > /dev/null)
if [ -n "${APP_MANIFEST:-}" ]; then
  # the sketch's own files go inside the APK, under assets/sketch/, for the activity to unpack into the app's folder: `assets` and
  # `libs` as they are, and the files a sketch starts from (what it remembers, its vault, what its widgets were set to) apart
  stage="$out/assets/sketch"
  mkdir -p "$stage/seed"
  for part in assets libs; do
    if [ -d "$sketch_folder/$part" ]; then
      cp -R "$sketch_folder/$part" "$stage/$part"
    fi
  done
  find "$stage" -name .git -prune -exec rm -rf {} + 2> /dev/null || true
  find "$stage" \( -name .DS_Store -o -name .keep \) -type f -delete 2> /dev/null || true
  for seed in ui.toml memory.toml vault.bin vault.key; do
    [ ! -f "$sketch_folder/$seed" ] || cp "$sketch_folder/$seed" "$stage/seed/$seed"
  done
  # a file for the activity to find even when the sketch has none, so `sketch` is always there to list
  printf 'rocinante\n' > "$stage/seed/.sketch"
  (cd "$out" && find assets -type f -print0 | xargs -0 "$build_tools/aapt" add sketch-unaligned.apk > /dev/null)
fi
"$build_tools/zipalign" -f -p 4 "$out/sketch-unaligned.apk" "$out/sketch-aligned.apk"
if [ -n "${APP_MANIFEST:-}" ]; then
  # the app's release key: made once for the id, kept outside the sketch's folder, and the only thing that can sign an update
  [ -n "${APP_KEYSTORE:-}" ] && [ -n "${APP_KEYPASS:-}" ] || fail "The app's release key was not named."
  if [ ! -f "$APP_KEYSTORE" ]; then
    mkdir -p "$(dirname "$APP_KEYSTORE")"
    (umask 077; LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32 > "$APP_KEYPASS")
    keytool -genkeypair -keystore "$APP_KEYSTORE" -storepass:file "$APP_KEYPASS" -keypass:file "$APP_KEYPASS" \
      -alias app -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=$PACKAGE" > "$out/keytool.log" 2>&1 \
      || { tail -5 "$out/keytool.log" >&2; fail "The app's release key could not be made."; }
    result newkey "$APP_KEYSTORE"
  fi
  apk="${APP_APK:-$out/sketch.apk}"
  mkdir -p "$(dirname "$apk")"
  # the key has the keystore's password, so it is given once: apksigner reads a second `file:` password from the next line of the
  # same file, and the file has the one line
  "$build_tools/apksigner" sign --ks "$APP_KEYSTORE" --ks-pass file:"$APP_KEYPASS" --ks-key-alias app \
    --out "$apk" "$out/sketch-aligned.apk" || fail "The APK could not be signed with the app's release key."
  "$build_tools/apksigner" verify "$apk" > /dev/null 2>&1 || fail "The signature of the APK did not check."
  result app "$apk"
else
  if [ ! -f "$keystore" ]; then
    keytool -genkeypair -keystore "$keystore" -storepass android -keypass android \
      -alias spike -keyalg RSA -keysize 2048 -validity 10000 \
      -dname "CN=rocinante, O=rocinante" > /dev/null 2>&1
  fi
  "$build_tools/apksigner" sign --ks "$keystore" --ks-pass pass:android --key-pass pass:android \
    --out "$out/sketch.apk" "$out/sketch-aligned.apk"
  result app "$out/sketch.apk"
fi

[ -z "${NO_INSTALL:-}" ] || exit 0
step install "Installing the app"
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
  step install "Copying the sketch's files"
  (cd "$sketch_folder" && COPYFILE_DISABLE=1 tar --no-xattrs -cf - assets) | "$adb" shell run-as "$PACKAGE" tar -xf - -C "$files" > "$out/push.log" 2>&1 || { tail -5 "$out/push.log" >&2; fail "I could not copy the assets to the phone."; }
fi
step start "Starting the sketch"
"$adb" shell input keyevent KEYCODE_WAKEUP > /dev/null 2>&1 || true
"$adb" logcat -c > /dev/null 2>&1 || true
"$adb" shell am start -n "$PACKAGE/.SketchActivity" > "$out/launch.log" 2>&1 || { tail -5 "$out/launch.log" >&2; fail "The app is on the phone and would not start."; }
if [ -n "${EMULATOR:-}" ]; then
  finished "$name is running on the emulator ($ANDROID_SERIAL). A picture of it: $adb -s $ANDROID_SERIAL exec-out screencap -p > shot.png"
else
  finished "$name is running on the phone. Its messages: $adb logcat -s SDL"
fi
