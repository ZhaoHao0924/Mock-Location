# Development Progress

Last updated: 2026-08-09 (Asia/Shanghai)

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

The validation run is [31296238424](https://github.com/ZhaoHao0924/Mock-Location/actions/runs/31296238424)
for commit `b2fbf77` and completed successfully. XcodeGen generation,
the unsigned device build, IPA layout validation, and artifact upload all
passed. The `MockLocation-TrollStore-IPA` artifact (ID `9033025525`) is
available for 30 days.

## Next session

1. Download `MockLocation.ipa` from the successful Actions artifact.
2. Install it with TrollStore on a compatible device.
3. Validate point and route simulation behavior on-device.

Local development cannot run the iOS build because this workstation is Windows
and has no Xcode, `xcodebuild`, or XcodeGen toolchain.
