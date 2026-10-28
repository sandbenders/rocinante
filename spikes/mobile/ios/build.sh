#!/bin/sh
# SPDX-License-Identifier: 0BSD
#
# Spike 2, iOS: builds the Odin code as a static library, links it with SDL3
# into an executable for the iPhone, and wraps it in a tiny Xcode project whose
# only job is to make the .app and sign it (Xcode creates and renews the
# development certificate and provisioning profile for a free Apple ID). Needs
# a Mac with full Xcode. `roci package ios` will do this itself.
#
# Environment:
#   SDL_IOS_LIB   folder holding libSDL3.a built for the iPhone (arm64)
#   TEAM_ID       the Apple development team id (see Xcode, Settings, Accounts)
#   DEVICE        the iPhone's identifier from `xcrun devicectl list devices` (for --install)
# Optional: BUNDLE_ID (default org.rocinante.spike), MIN_IOS (default 15.0).
#
#     SDL_IOS_LIB=... TEAM_ID=... DEVICE=... spikes/mobile/ios/build.sh [--install]
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
out="$root/output/ios"
: "${SDL_IOS_LIB:?set SDL_IOS_LIB to the folder with libSDL3.a for the iPhone}"
: "${TEAM_ID:?set TEAM_ID to your Apple development team id}"
BUNDLE_ID="${BUNDLE_ID:-org.rocinante.spike}"
MIN_IOS="${MIN_IOS:-15.0}"
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"

rm -rf "$out"
mkdir -p "$out/proj"

echo "== odin: static library"
odin build "$here" -target:darwin_arm64 -subtarget:iphone -build-mode:lib \
  -out:"$out/libspike.a" -minimum-os-version:"$MIN_IOS" -vet -strict-style

# Odin links the executable itself, but it puts Homebrew's macOS libSDL3 ahead
# of ours, so the final link is done here.
echo "== link"
xcrun --sdk iphoneos clang -target "arm64-apple-ios$MIN_IOS" -isysroot "$sdk" \
  "$out/libspike.a" "$SDL_IOS_LIB/libSDL3.a" \
  -framework CoreMedia -framework CoreVideo -framework CoreAudio \
  -framework AudioToolbox -framework AVFoundation -framework CoreBluetooth \
  -framework CoreGraphics -framework CoreMotion -framework Foundation \
  -framework GameController -framework Metal -framework OpenGLES \
  -framework QuartzCore -framework UIKit -weak_framework CoreHaptics \
  -lm -lpthread -o "$out/proj/spike"
cp "$here/Info.plist" "$out/proj/Info.plist"

echo "== xcode: wrap, sign"
mkdir -p "$out/proj/Spike.xcodeproj"
cat > "$out/proj/Spike.xcodeproj/project.pbxproj" <<PBX
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
		A0000002 /* RocinanteSpike */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = A0000006;
			buildPhases = (
				A0000007,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = RocinanteSpike;
			productName = RocinanteSpike;
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
				PRODUCT_NAME = RocinanteSpike;
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
		A0000008 /* RocinanteSpike.app */ = {
			isa = PBXFileReference;
			explicitFileType = wrapper.application;
			includeInIndex = 0;
			path = RocinanteSpike.app;
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
			shellScript = "mkdir -p \"\$TARGET_BUILD_DIR/\$EXECUTABLE_FOLDER_PATH\"\ncp \"\$SRCROOT/spike\" \"\$TARGET_BUILD_DIR/\$EXECUTABLE_PATH\"\n# codesign refuses extended attributes (provenance, quarantine) on the bundle\nxattr -cr \"\$TARGET_BUILD_DIR/\$WRAPPER_NAME\"\n";
		};
	};
	rootObject = A0000001;
}
PBX
(cd "$out/proj" && xcodebuild -project Spike.xcodeproj -target RocinanteSpike \
  -configuration Debug -sdk iphoneos -allowProvisioningUpdates \
  CONFIGURATION_BUILD_DIR="$out/app" build 2>&1 | tail -25)
echo "built $out/app/RocinanteSpike.app"

if [ "${1:-}" = "--install" ]; then
  : "${DEVICE:?set DEVICE to the identifier of the iPhone}"
  xcrun devicectl device install app --device "$DEVICE" "$out/app/RocinanteSpike.app"
  xcrun devicectl device process launch --device "$DEVICE" --terminate-existing --console "$BUNDLE_ID"
fi
