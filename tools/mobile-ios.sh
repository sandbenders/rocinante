#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Puts a compiled sketch on an iPhone: builds the Odin program `roci run --compile --target ios` made as a static
# library, links it with SDL3 and the libraries roci uses, wraps it with the sketch's `assets` in an app that Xcode
# signs with the development team (free accounts work: the signature lasts 7 days and the developer must be
# trusted on the phone once), installs it and starts it. Needs a Mac with Xcode, and the phone's libraries,
# which `tools/mobile-sdl.sh ios` and `spikes/mobile/ios/libs.sh` build.
#
#     tools/mobile-ios.sh <source folder> <sketch folder> <name>
# Environment: TEAM_ID (else the team Xcode knows), DEVICE (else the one iPhone that is connected), BUNDLE_ID
# (default org.rocinante.sketch, so a new sketch replaces the last), MIN_IOS (default 15.0), ROCI_ROOT (the source
# of rocinante, default the folder above this one), NO_INSTALL (build the app and stop).
#
# `roci package ios` runs this script too, to make an app people can be given instead of a test build: it sets APP_PLIST (the
# app's own Info.plist), APP_CATALOG (a folder holding Assets.xcassets: the icon and the launch colour), APP_PRODUCT (the
# program's and the app's file name), APP_OUT (the folder the build is made in) and APP_IPA (where the .ipa goes).
set -eu

source_folder="${1:?the folder with the program roci made}"
sketch_folder="${2:?the sketch folder, for its assets}"
name="${3:-sketch}"
root="${ROCI_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
out="$sketch_folder/artifacts/ios"
[ -z "${APP_OUT:-}" ] || out="$APP_OUT"
product="${APP_PRODUCT:-RocinanteSketch}"
SDL_IOS_LIB="${SDL_IOS_LIB:-$root/.cache/mobile/ios}"
BUNDLE_ID="${BUNDLE_ID:-org.rocinante.sketch}"
MIN_IOS="${MIN_IOS:-15.0}"

# What it says is read by roci, which draws the steps: `step <kind> <words>` starts one (kinds: libraries, phone, compile,
# bundle, sign, install, start), `result <name> <detail>` is something made, `finished <words>` the last word and
# `problem <words>` what went wrong; any other line is what a tool said, kept in a log.
step() { printf "step %s %s\n" "$1" "$2"; }
result() { printf "result %s %s\n" "$1" "$2"; }
finished() { printf "finished %s\n" "$*"; }
fail() { printf "problem %s\n" "$*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || fail "An iPhone app can only be built on a Mac, because Apple's tools only run there."
[ -f "$SDL_IOS_LIB/libSDL3.a" ] || fail "SDL for the iPhone is not built yet. Run: tools/mobile-sdl.sh ios"
# The phone's libraries, built when one is missing or what it is made from changed (the first time takes a while); its
# output goes to a log, shown only when it fails.
step libraries "Getting the phone's libraries ready"
mkdir -p "$sketch_folder/artifacts"
libs_log="$sketch_folder/artifacts/phone-libs.log"
if ! MIN_IOS="$MIN_IOS" SDL_IOS_LIB="$SDL_IOS_LIB" SDL_IOS_SRC="${SDL_IOS_SRC:-$root/.cache/mobile/SDL3-3.4.18}" \
  sh "$root/spikes/mobile/ios/libs.sh" > "$libs_log" 2>&1; then
  tail -n 20 "$libs_log" >&2
  fail "The iPhone's libraries could not be built; the whole of it is in $libs_log."
fi
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"

if [ -z "${TEAM_ID:-}" ]; then
  TEAM_ID="$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null | sed -n 's/.*teamID = \([A-Z0-9]*\);.*/\1/p' | head -n 1)"
fi
[ -n "${TEAM_ID:-}" ] || fail "I need your Apple development team to sign the app. Open Xcode, Settings, Accounts, and add your Apple ID, or set TEAM_ID."

if [ -z "${NO_INSTALL:-}" ] && [ -z "${DEVICE:-}" ]; then
  step phone "Finding the iPhone"
  DEVICE="$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && (/available/ || /connected/) { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]+-[0-9A-F]+$/) { print $i; exit } }')"
  [ -n "${DEVICE:-}" ] || fail "I cannot find an iPhone. Connect it with its cable, unlock it and trust this computer, or set DEVICE (xcrun devicectl list devices)."
fi

rm -rf "$out"
mkdir -p "$out/proj"

step compile "Compiling the sketch for the iPhone"
odin build "$source_folder" -collection:rocinante="$root" -target:darwin_arm64 -subtarget:iphone -build-mode:lib \
  -out:"$out/libsketch.a" -minimum-os-version:"$MIN_IOS" -o:speed

step bundle "Making the app"
lib="$root/.cache/ios/lib"
libs="$lib/libroci_ui.a $lib/libroci_sound.a $lib/libcurl.a $lib/libmbedtls.a $lib/libmbedx509.a $lib/libmbedcrypto.a $lib/libtfpsacrypto.a $lib/libSDL3_ttf.a $(ls "$lib"/libfreetype*.a "$lib"/libharfbuzz*.a) $lib/libshaderc_combined.a $(ls "$lib"/libspirv-cross-*.a)"
xcrun --sdk iphoneos clang -target "arm64-apple-ios$MIN_IOS" -isysroot "$sdk" \
  "$out/libsketch.a" "$SDL_IOS_LIB/libSDL3.a" $libs \
  -framework CoreMedia -framework CoreVideo -framework CoreAudio \
  -framework AudioToolbox -framework AVFoundation -framework CoreBluetooth \
  -framework CoreGraphics -framework CoreText -framework CoreFoundation -framework CoreMIDI -framework CoreMotion -framework Foundation \
  -framework GameController -framework Metal -framework OpenGLES \
  -framework QuartzCore -framework SystemConfiguration -framework UIKit -weak_framework CoreHaptics \
  -lc++ -lm -lpthread -o "$out/proj/sketch"
mkdir -p "$out/proj/resources"
if [ -n "${APP_PLIST:-}" ]; then
  cp "$APP_PLIST" "$out/proj/Info.plist"
else
  sed "s/rocinante spike/$name/g" "$root/spikes/mobile/ios/Info.plist" > "$out/proj/Info.plist"
fi
if [ -n "${APP_CATALOG:-}" ]; then
  # the icon and the launch colour: compiled to Assets.car and the icon's pictures, whose names go into the Info.plist
  xcrun actool "$APP_CATALOG/Assets.xcassets" --compile "$out/proj/resources" --platform iphoneos \
    --minimum-deployment-target "$MIN_IOS" --target-device iphone --app-icon AppIcon \
    --output-partial-info-plist "$out/proj/partial.plist" > "$out/actool.log" 2>&1 \
    || { tail -15 "$out/actool.log" >&2; fail "The icon and the launch colour could not be made into the app's pictures. The whole of it is in $out/actool.log."; }
  /usr/libexec/PlistBuddy -c "Merge $out/proj/partial.plist" "$out/proj/Info.plist"
fi
if [ -d "$sketch_folder/assets" ]; then
  cp -R "$sketch_folder/assets" "$out/proj/assets"
fi

step sign "Signing the app"
mkdir -p "$out/proj/Sketch.xcodeproj"
cat > "$out/proj/Sketch.xcodeproj/project.pbxproj" <<PBX
// !\$*UTF8*\$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {
		A0000001 /* Project object */ = {
			isa = PBXProject;
			attributes = {
				LastUpgradeCheck = 2700;
				TargetAttributes = {
					A0000002 = {
						DevelopmentTeam = $TEAM_ID;
					};
				};
			};
			buildConfigurationList = A0000003;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
			);
			mainGroup = A0000004;
			productRefGroup = A0000005;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				A0000002,
			);
		};
		A0000002 /* RocinanteSketch */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = A0000006;
			buildPhases = (
				A0000007,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = RocinanteSketch;
			productName = RocinanteSketch;
			productReference = A0000008;
			productType = "com.apple.product-type.application";
		};
		A0000003 /* Project build configurations */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				A0000009,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Debug;
		};
		A0000006 /* Target build configurations */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				A000000A,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Debug;
		};
		A0000009 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				SDKROOT = iphoneos;
				IPHONEOS_DEPLOYMENT_TARGET = $MIN_IOS;
				ENABLE_USER_SCRIPT_SANDBOXING = NO;
			};
			name = Debug;
		};
		A000000A /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ARCHS = arm64;
				CODE_SIGN_STYLE = Automatic;
				DEVELOPMENT_TEAM = $TEAM_ID;
				INFOPLIST_FILE = Info.plist;
				PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_ID;
				PRODUCT_NAME = $product;
				GENERATE_INFOPLIST_FILE = NO;
				SUPPORTED_PLATFORMS = "iphoneos";
				TARGETED_DEVICE_FAMILY = 1;
			};
			name = Debug;
		};
		A0000004 = {
			isa = PBXGroup;
			children = (
				A0000005,
			);
			sourceTree = "<group>";
		};
		A0000005 /* Products */ = {
			isa = PBXGroup;
			children = (
				A0000008,
			);
			name = Products;
			sourceTree = "<group>";
		};
		A0000008 /* RocinanteSketch.app */ = {
			isa = PBXFileReference;
			explicitFileType = wrapper.application;
			includeInIndex = 0;
			path = RocinanteSketch.app;
			sourceTree = BUILT_PRODUCTS_DIR;
		};
		A0000007 /* Put the prebuilt executable in the app */ = {
			isa = PBXShellScriptBuildPhase;
			alwaysOutOfDate = 1;
			buildActionMask = 2147483647;
			files = (
			);
			inputPaths = (
			);
			name = "Put the prebuilt executable in the app";
			outputPaths = (
			);
			runOnlyForDeploymentPostprocessing = 0;
			shellPath = /bin/sh;
			shellScript = "mkdir -p \"\$TARGET_BUILD_DIR/\$EXECUTABLE_FOLDER_PATH\"\ncp \"\$SRCROOT/sketch\" \"\$TARGET_BUILD_DIR/\$EXECUTABLE_PATH\"\nif [ -d \"\$SRCROOT/assets\" ]; then rm -rf \"\$TARGET_BUILD_DIR/\$WRAPPER_NAME/assets\"; cp -R \"\$SRCROOT/assets\" \"\$TARGET_BUILD_DIR/\$WRAPPER_NAME/assets\"; fi\nif [ -d \"\$SRCROOT/resources\" ]; then cp -R \"\$SRCROOT/resources/.\" \"\$TARGET_BUILD_DIR/\$WRAPPER_NAME/\"; fi\n# codesign refuses extended attributes (provenance, quarantine) on the bundle\nxattr -cr \"\$TARGET_BUILD_DIR/\$WRAPPER_NAME\"\n";
		};
	};
	rootObject = A0000001;
}
PBX
(cd "$out/proj" && xcodebuild -project Sketch.xcodeproj -target RocinanteSketch \
  -configuration Debug -sdk iphoneos -allowProvisioningUpdates \
  CONFIGURATION_BUILD_DIR="$out/app" build > "$out/xcode.log" 2>&1) || { tail -25 "$out/xcode.log" >&2; fail "Xcode could not sign the app. The whole of it is in $out/xcode.log."; }
result app "$out/app/$product.app"

if [ -n "${APP_IPA:-}" ]; then
  # an .ipa is a zip with the app in a folder called Payload
  rm -rf "$out/ipa" && mkdir -p "$out/ipa/Payload"
  cp -R "$out/app/$product.app" "$out/ipa/Payload/"
  rm -f "$APP_IPA"
  (cd "$out/ipa" && zip -qry "$APP_IPA" Payload) || fail "The .ipa could not be zipped."
  result ipa "$APP_IPA"
fi
[ -z "${NO_INSTALL:-}" ] || exit 0
step install "Installing the app"
xcrun devicectl device install app --device "$DEVICE" "$out/app/$product.app" > "$out/install.log" 2>&1 \
  || xcrun devicectl device install app --device "$DEVICE" "$out/app/$product.app" > "$out/install.log" 2>&1 \
  || { tail -15 "$out/install.log" >&2; fail "The iPhone would not take the app. If it says the developer is not trusted: on the phone, Settings, General, VPN & Device Management, trust your Apple ID, and run this again."; }
step start "Starting the sketch"
xcrun devicectl device process launch --device "$DEVICE" --terminate-existing "$BUNDLE_ID" > "$out/launch.log" 2>&1 \
  || { tail -10 "$out/launch.log" >&2; fail "The app is on the phone and would not start: unlock the phone, and trust the developer (Settings, General, VPN & Device Management)."; }
finished "$name is running on the iPhone."
