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
- Pushed the project to `https://github.com/ZhaoHao0924/Mock-Location.git` on
  `master`.

## Commits on remote

- `efb39ed` Add TrollStore iOS location simulator
- `bb88ca7` Fix macOS CI XcodeGen installation
- `67bcfbc` Fix XcodeGen project output path

## Current CI state

The latest run is [31268915373](https://github.com/ZhaoHao0924/Mock-Location/actions/runs/31268915373)
for commit `67bcfbc`. The macOS runner and XcodeGen installation succeeded,
but the `Build TrollStore IPA` step failed before the IPA validation/upload
steps. GitHub's public API does not allow downloading the detailed job log
without repository admin authentication, so the exact compiler error still
needs to be read from the Actions UI or an authenticated API request.

## Next session

1. Open the failed job and capture the output from `Build TrollStore IPA`.
2. Fix the reported XcodeGen, Swift, Objective-C, entitlement, or packaging
   issue and push a new commit.
3. Repeat until `MockLocation-TrollStore-IPA` is uploaded successfully.
4. Download `MockLocation.ipa` from the successful Actions artifact and install
   it with TrollStore on a compatible device.

Local development cannot run the iOS build because this workstation is Windows
and has no Xcode, `xcodebuild`, or XcodeGen toolchain.
