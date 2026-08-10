# MockLocation

MockLocation is a personal-use iOS location simulator for TrollStore-capable
devices. It is an original implementation of the common workflow used by
TrollStore location tools: choose a point on a map, receive a point from an
Apple Maps share action, and control the system location-simulation queue.

## What is included

- Map long-press selection, coordinate entry, and Apple Maps search
- Start and stop controls backed by `CLSimulationManager`
- Saved places, recent locations, and JSON persistence
- Route waypoints with distance-based interpolation and configurable speed
- An Apple Maps Share extension for handoff into the app
- A status/settings view and a small unit-test target for route math

## Important platform boundary

Global location simulation is not available to normal App Store applications.
The live bridge in this project requires the private
`com.apple.locationd.simulation` entitlement, which is why it is intended for
installation through TrollStore on a device you control. A standard Xcode or
App Store signature will compile the UI but cannot grant this capability.

The app deliberately uses its own name and assets; it does not copy TrollLoc
branding, source code, or binaries.

## Build on macOS

1. Install Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and [CocoaPods](https://cocoapods.org/).
2. Run `bash Scripts/build-trollstore-ipa.sh` in this directory.
3. Install the generated `MockLocation.ipa` with TrollStore.

The build script compiles without a developer signature because Apple-issued
development profiles cannot carry the private location-simulation entitlement.
TrollStore applies its own installation signature. The development target is
iOS 15. The private bridge checks for the required runtime selectors before it
changes any location state, so unsupported OS versions fail closed.

## Map rendering

Both the 高德 and 百度 tabs render through a built-in raster tile view that
needs no API Key. This is the default and is unaffected by SDK authentication,
private entitlements, or the 3D resource bundle.

The native AMap 3D SDK is opt-in under Settings > 高德地图 > 使用高德原生 SDK.
It requires an API Key whose platform is iOS and whose bound Bundle ID is
exactly `com.personal.mocklocation`. A Web Service Key, or a Key bound to a
different Bundle ID, fails authentication; the SDK then issues no tile requests
at all and the base map stays blank while the 高德 logo still draws.

## Project layout

- `MockLocation/` - main SwiftUI application and Objective-C runtime bridge
- `ShareExtension/` - Apple Maps / URL share action
- `Shared/` - app-group payload shared by both targets
- `Tests/` - route interpolation tests
- `project.yml` - XcodeGen project definition
- `Scripts/` - unsigned TrollStore IPA build script
