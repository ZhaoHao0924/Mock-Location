# Development Progress

Last updated: 2026-08-10 (Asia/Shanghai)

## Completed

- Created the iOS MockLocation app for TrollStore-capable devices.
- Added map selection, coordinate entry, Apple Maps search/share handoff,
  favorites, recent locations, route interpolation, and start/stop controls.
- Added the Objective-C `CLSimulationManager` bridge and the private
  `com.apple.locationd.simulation` entitlement configuration.
- Added `Scripts/build-trollstore-ipa.sh` and the macOS GitHub Actions workflow
  `.github/workflows/build-ios.yml`.
- Added CI build diagnostics, pinned XcodeGen to the Xcode 15.3 project format,
  and fixed Swift's `NSError**` bridge calls.
- Pushed the project to `https://github.com/ZhaoHao0924/Mock-Location.git` on
  `master`.

## Commits on remote

- `efb39ed` Add TrollStore iOS location simulator
- `bb88ca7` Fix macOS CI XcodeGen installation
- `67bcfbc` Fix XcodeGen project output path
- `c16391d` Add CI build diagnostics
- `3d041f2` Fix XcodeGen project generation
- `be95217` Improve XcodeGen diagnostics
- `014e0f8` Pin Xcode project format
- `8232b4e` Fix Swift bridge error handling
- `b2fbf77` Correct Swift bridge argument label

## Current CI state

The validation run is [31355541330](https://github.com/ZhaoHao0924/Mock-Location/actions/runs/31355541330)
for commit `c251687` (run #38) and completed successfully. XcodeGen
generation, the unsigned device build, IPA layout validation, AMap resource
validation, and artifact upload all passed. The `MockLocation-TrollStore-IPA`
artifact (ID `9050543427`, about 20.7 MB) is available until 2026-09-09.

## Current debugging status

The nullable factory prevents the startup crash on iOS 15.6.1 with TrollStore
2.1.1. The first fixed builds reported that the AMap SDK could not create a
map view; the current build initializes the required privacy state, sets the
AMap resource bundle path and language before creation, uses a non-empty
screen frame, and synchronizes the real container bounds after SwiftUI layout.
The map view now waits for a visible nonzero container before it applies its
configuration, forces a refresh, and emits loading lifecycle diagnostics when
the map remains blank.

## Crash fix implementation

The AMap startup crash, zero-frame, privacy, resource, and display-lifecycle fixes are implemented and passed CI:

- `MockLocation/MockLocation-Bridging-Header.h` imports the Objective-C map
  view factory.
- `MockLocation/Services/AMapMapViewFactory.h` and `.m` expose nullable
  `MAMapView` creation without Swift's non-optional initializer bridge, set
  the required privacy state, and explicitly configure AMap resources.
- `MockLocation/Views/LocationAMapSDKView.swift` now hosts the optional map
  view in an `AMapMapContainerView`, keeps a non-empty initialization frame,
  refreshes after UIKit visibility, and reports creation and loading failures
  in the UI.

## Validation status

- `git diff --check` passes.
- The XcodeGen `MockLocation` source root recursively contains both factory
  files, so they will be included in the generated target.

## Next session

1. Download artifact `9050543427` and install the generated IPA with TrollStore.
2. Delete the old app before installing the new IPA, then verify that the app
   opens and that AMap tiles load on the iOS 15.6.1 test device.

Local development cannot run the iOS build because this workstation is Windows
and has no Xcode, `xcodebuild`, or XcodeGen toolchain.
