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
- `5c5e434` Improve AMap tile loading fallback
- `7c77250` Fix AMap 3D resources and key initialization
- `0144fc5` Make AMap resource check portable on macOS

## Current CI state

The latest validation run is [31372572757](https://github.com/ZhaoHao0924/Mock-Location/actions/runs/31372572757)
for commit `0144fc5` (run #44) and completed successfully. XcodeGen
generation, the unsigned device build, IPA layout validation, AMap resource
validation, and artifact upload all passed. The `MockLocation-TrollStore-IPA`
artifact (ID `9056743891`, about 21.3 MB) is available until 2026-09-09.

The downloadable artifact is:
`https://nightly.link/ZhaoHao0924/Mock-Location/actions/runs/31372572757/MockLocation-TrollStore-IPA.zip`

The final IPA was unpacked independently. It contains `AMap.bundle` with
`bundleVersion.txt = 11.2.100`, `res.ck`, `res.zip`, `AMap3D.bundle`, and a
standard base-map style resource.

## Blank base map: diagnosis and fix

Device testing returned the banner "SDK 已完成初始化，但没有收到任何底图瓦片"
with Bundle ID `com.personal.mocklocation`, a 32-character Key ending `e9af`
reported as applied, and 3D resource 11.2.100.

That banner is one specific watchdog branch. Reaching it requires
`didFinishLoadingMap == true`, `successfulTileCount == 0` **and**
`failedTileCount == 0`. So the engine completed its load cycle and the
`tileLoadCallback` never fired even once — not a single tile request was
issued, let alone failed. That rules out the network path (failed requests
would increment `failedTileCount`), the renderer (`didChangeOpenGLESDisabled`
never fired and `mapViewDidFinishLoadingMap` did), the 3D resources
(`prepareSDK()` returned 0 and the version matched), and layout (the 高德 logo
draws in a non-empty frame).

Key authentication was the first hypothesis. The 高德 console screenshots
disprove it: the Key ending `e9af` matches what the app reports, its 服务平台
is iOS平台, iOS地图SDK is among the enabled services, and 安全码Bundle ID is
`com.personal.mocklocation`. 安全密钥 showing `—` is expected on iOS, where the
Bundle ID is the binding.

One flaw in the reasoning above survived two rounds and has to be retired: a
zero `tileLoadCallback` count was read as proof that no tile request was ever
issued. That property is not confirmed to be wired to the base map's internal
tile pipeline, so it can legitimately read zero on a completely healthy map.
Nothing about authentication follows from it, and the earlier Key conclusion
rested on exactly that step.

What the delegate callbacks do establish is narrower and more useful.
`mapViewDidFinishLoadingMap` fired, so the engine considers its map data
loaded. Loaded data plus a blank screen points at the render surface never
producing a frame — not at the network, and not at the Key.

The 高德 logo is a UIKit subview of `MAMapView`. It draws through the normal
view hierarchy no matter what the renderer does, so its presence was never
evidence that rendering worked. Two candidates remain, ranked:

1. Metal device creation or GPU userclient access fails under the ad-hoc
   TrollStore signature. The entitlements already carry `AGXDeviceUserClient`
   and `IOSurfaceRootUserClient`, added by an earlier session when the GPU was
   suspected, and `setMetalEnabled:YES` forced the Metal path with no fallback.
2. The 3D resource path was never actually applied. `setBundlePath:` had its
   return value treated as `0 == success`, which the SDK headers do not
   document. If 0 means failure there, the `resourceStatus == 0` guard in
   `LocationAMapSDKView` was passing precisely when the path had not been set.

Rather than guess a third time, the build now instruments this.
`AMapMapViewFactory.isMetalAvailable` probes `MTLCreateSystemDefaultDevice()`,
the renderer is switchable at runtime under Settings > 高德地图, and the
diagnostic banner reports both. `Metal 设备 不可用` there would be conclusive.

Device confirmation: the key-free 高德 raster path and 百度 both render correctly
on the target device. That isolates the fault to the native SDK's interior. The
network, tile transport, ATS configuration, the GCJ-02/BD-09 projection code,
and the SwiftUI/UIKit view hierarchy are all proven good by the working raster
maps, and candidate 1 is what remains.

`prepareSDK` therefore no longer hands Metal to the SDK when
`MTLCreateSystemDefaultDevice()` returns nil. The GLES fallback engages on its
own rather than depending on the user finding the Settings toggle. This is a
correctness fix independent of the diagnosis: forcing a renderer the process
cannot create was wrong regardless of what the device reports.

`AMapSDKConfiguration.isApplied` is misleading independent of all this: it only
compares `AMapServices.shared().apiKey` against the stored string, proving a
local property assignment and nothing about the server's answer. Its label now
reads 已写入 SDK.

The fix routes 高德 to the key-free raster tile pipeline by default. That code
already existed in `LocationMapProviderView` (`MapSource.amap` projections,
`webrd`/`webst` `appmaptile` URLs, `AMapWebMercator`) but was unreachable
because the dashboard hardcoded `source: .baidu`. The native SDK is retained as
an explicit opt-in.

`AMapMapViewFactory.resourceBundleStatus` no longer gates on the undocumented
`setBundlePath:` return value. It still validates bundle contents and the
version against `MAMapKitVersion`, but it now only overrides the SDK's own
lookup when `AMap.bundle` is missing from the main bundle, and ignores the
return value. This removes candidate 2 above as a silent failure mode.

## Previous debugging status

The nullable factory prevents the startup crash on iOS 15.6.1 with TrollStore
2.1.1. The map view now initializes the required privacy state, sets the AMap
resource bundle path and language before creation, uses a non-empty screen
frame, and synchronizes the real container bounds after SwiftUI layout.

The previous run #42 IPA contained a complete 11.2.000 3D resource bundle, so
the blank base map was not explained by a missing top-level resource alone.
The latest build upgrades the 3D SDK to 11.2.100, validates the resource
contents and version at build/runtime, and applies the stored iOS Key before
AMap engine initialization. This ordering is important because setting the Key
after the SDK starts can leave markers visible while all base-map tiles fail.

The app deliberately does not embed a user's Key. It stores the user-provided
Key in `UserDefaults`, shows the exact runtime Bundle ID in Settings, and
reports only the Key length/last four characters in the map diagnostic banner.

## Crash fix implementation

The AMap startup crash, zero-frame, privacy, resource, display-lifecycle, and
user-key configuration fixes are implemented and passed CI:

- `MockLocation/MockLocation-Bridging-Header.h` imports the Objective-C map
  view factory.
- `MockLocation/Services/AMapMapViewFactory.h` and `.m` expose nullable
  `MAMapView` creation without Swift's non-optional initializer bridge, prepare
  the required privacy state, validate the 3D resource bundle/version, and set
  the validated resource path before map creation.
- `MockLocation/Services/AMapSDKConfiguration.swift` applies the stored iOS
  Key during app startup and immediately before map preparation, enables the
  required privacy agreements, and provides runtime diagnostics.
- `MockLocation/Views/LocationAMapSDKView.swift` now hosts the optional map
  view in an `AMapMapContainerView`, keeps a non-empty initialization frame,
  refreshes after UIKit visibility, and reports creation/loading/resource/Key
  failures in the UI.
- `MockLocation/Views/SettingsView.swift` displays the exact Bundle ID and
  provides the key-entry workflow.
- `Podfile` pins `AMap3DMap-NO-IDFA` to 11.2.100. The build script rejects a
  missing, incomplete, non-3D, or version-mismatched `AMap.bundle`.

## Validation status

- `git diff --check` passes.
- `bash -n Scripts/build-trollstore-ipa.sh` passes.
- GitHub Actions run #44 completed successfully.
- The final IPA resource bundle was independently checked after extraction.
- The XcodeGen `MockLocation` source root recursively contains both factory
  files, so they will be included in the generated target.
- Device-side map rendering with the new artifact is still pending; local
  iOS compilation cannot run because this workstation is Windows and has no
  Xcode, `xcodebuild`, or XcodeGen toolchain.

## Next session

1. Push the raster-default change so GitHub Actions can compile it. Local
   compilation is still impossible on this Windows workstation.
2. Install the resulting IPA and open the 地图 tab. 高德 should now render
   without any Key, with 标准 and 卫星 both selectable.
3. If that raster map renders, the blank-base-map issue is resolved for normal
   use and the native SDK path is optional.
4. The native SDK is now optional and the raster path covers real use. To settle
   it anyway, enable Settings > 高德地图 > 使用高德原生 SDK and read the
   diagnostic banner. `Metal 设备 不可用` confirms candidate 1 outright. If it
   reads 可用 while the map is still blank, the automatic fallback did not apply,
   so turn the Metal toggle off, fully quit, and reopen. If GLES also renders
   nothing, the remaining step is the device console: 高德 logs authentication
   and resource-load errors to stderr, and TrollStore permits a console reader.

Local development cannot run the iOS build because this workstation is Windows
and has no Xcode, `xcodebuild`, or XcodeGen toolchain.
